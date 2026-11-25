"""Exercise release staging without Docker, builds, or remote pushes."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'build_release_apk.sh'


class ReleaseStagingTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.release = self.root / 'TechOptions'
        self.release.mkdir()
        shutil.copy2(SCRIPT, self.release / SCRIPT.name)
        self.parents = self.root / 'angan/angan-app'
        (self.parents / 'scripts').mkdir(parents=True)
        (self.parents / 'pubspec.yaml').write_text('version: 0.1.22+23\n')
        builder = self.parents / 'scripts/build-apk.sh'
        builder.write_text('#!/bin/bash\nset -eu\nmkdir -p build/app/outputs/flutter-apk\nprintf "%s" "${TEST_APK_VERSION:-0.1.22+23}" > build/app/outputs/flutter-apk/app-release.apk\n')
        builder.chmod(0o755)
        kids = self.root / 'angan/angan-kids-android/app'
        kids.mkdir(parents=True)
        # The unbuilt app source is ahead of the staged binary.
        (kids / 'build.gradle.kts').write_text('versionCode = 99\nversionName = "1.0.98"\n')
        (self.release / 'angan-kids.apk').write_text('1.0.19+20')
        (self.release / 'angan-parents.apk').write_text('0.1.21+22')
        (self.release / 'version.json').write_text(json.dumps({
            'kids': {'releaseNotes': 'Keep existing Kids notes'},
            'parents': {'versionName': '0.1.21', 'versionCode': 22},
        }))
        aapt = self.root / 'aapt'
        aapt.write_text('#!/usr/bin/env python3\nfrom pathlib import Path\nimport sys\nname, code = Path(sys.argv[3]).read_text().split("+")\nprint(f"package: name=\'test\' versionCode=\'{code}\' versionName=\'{name}\'")\n')
        aapt.chmod(0o755)
        self.env = dict(os.environ, AAPT_BIN=str(aapt))

    def run_release(self, *args):
        return subprocess.run(
            ['bash', str(self.release / SCRIPT.name), 'parents', '--stage', '--no-push', '-y', *args],
            env=self.env, capture_output=True, text=True,
        )

    def test_staging_uses_binary_versions_and_checksum_urls(self):
        notes = 'Fix "updates"\nবাংলা'
        result = self.run_release('--notes', notes)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        metadata = json.loads((self.release / 'version.json').read_text())
        for app, version, code in [('parents', '0.1.22', 23), ('kids', '1.0.19', 20)]:
            entry = metadata[app]
            sha = hashlib.sha256((self.release / f'angan-{app}.apk').read_bytes()).hexdigest()
            self.assertEqual((entry['versionName'], entry['versionCode']), (version, code))
            self.assertEqual(entry['sha256'], sha)
            self.assertTrue(entry['apkUrl'].endswith(f'?sha256={sha}'))
        self.assertEqual(metadata['kids']['releaseNotes'], 'Keep existing Kids notes')
        self.assertTrue(metadata['parents']['releaseNotes'].startswith(notes))

    def test_stale_binary_is_rejected_before_staging(self):
        before = (self.release / 'version.json').read_bytes()
        self.env['TEST_APK_VERSION'] = '0.1.21+22'
        result = self.run_release()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Refusing to stage stale APK', result.stderr)
        self.assertEqual((self.release / 'angan-parents.apk').read_text(), '0.1.21+22')
        self.assertEqual((self.release / 'version.json').read_bytes(), before)

    def test_missing_unbuilt_app_is_not_advertised(self):
        (self.release / 'angan-kids.apk').unlink()
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        metadata = json.loads((self.release / 'version.json').read_text())
        self.assertNotIn('kids', metadata)

    def test_dry_run_does_not_modify_release(self):
        before = {p.name: p.read_bytes() for p in self.release.iterdir()}
        result = self.run_release('--dry-run')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.release.iterdir()})


if __name__ == '__main__':
    unittest.main()
