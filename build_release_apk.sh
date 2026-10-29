#!/usr/bin/env bash
# ==============================================================================
# Build Release APKs for Angan Kids Android & Angan Parents (Flutter)
# and Deploy to <root>/TechOptions (Single-commit release, no bloated git history)
#
# Usage:
#   ./build_release_apk.sh                     # Build both Kids & Parents and deploy
#   ./build_release_apk.sh all                 # Same as above
#   ./build_release_apk.sh kids                # Build only Kids app (Android)
#   ./build_release_apk.sh parents             # Build only Parents app (Flutter)
#   ./build_release_apk.sh --no-push           # Build both, copy to TechOptions, skip git push
#   ./build_release_apk.sh kids --no-push      # Build only Kids app without git push
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve workspace root and project directories
if [[ -d "$SCRIPT_DIR/angan/angan-kids-android" ]]; then
  WORKSPACE_ROOT="$SCRIPT_DIR"
elif [[ -d "$SCRIPT_DIR/../angan/angan-kids-android" ]]; then
  WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
elif [[ -f "$SCRIPT_DIR/build.gradle.kts" && -d "$SCRIPT_DIR/app" ]]; then
  WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
else
  WORKSPACE_ROOT="$SCRIPT_DIR"
fi

KIDS_APP_DIR="$WORKSPACE_ROOT/angan/angan-kids-android"
PARENTS_APP_DIR="$WORKSPACE_ROOT/angan/angan-app"
TECHOPTIONS_DIR="$WORKSPACE_ROOT/TechOptions"

# Parse CLI arguments
TARGET_APP="all"
IS_RELEASE=false
NO_PUSH=true           # Default: safe local build only (no remote push)
AUTO_BUMP=false        # Default: keep current version for local test builds
CUSTOM_VERSION=""
CUSTOM_NOTES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    kids|--kids|kid|--kid)
      TARGET_APP="kids"
      shift
      ;;
    parents|--parents|parent|--parent|paernts|--paernts)
      TARGET_APP="parents"
      shift
      ;;
    all|--all)
      TARGET_APP="all"
      shift
      ;;
    release|--release|realese|--realese|relase|--relase)
      IS_RELEASE=true
      AUTO_BUMP=true
      NO_PUSH=false
      shift
      ;;
    auto|--auto|auth|--auth)
      AUTO_BUMP=true
      shift
      ;;
    --push)
      NO_PUSH=false
      shift
      ;;
    --no-push|no-push)
      NO_PUSH=true
      shift
      ;;
    --bump|bump)
      AUTO_BUMP=true
      shift
      ;;
    --no-bump|no-bump)
      AUTO_BUMP=false
      shift
      ;;
    -v|--version)
      CUSTOM_VERSION="$2"
      AUTO_BUMP=true
      shift 2
      ;;
    --version=*)
      CUSTOM_VERSION="${1#*=}"
      AUTO_BUMP=true
      shift
      ;;
    -m|--notes)
      CUSTOM_NOTES="$2"
      shift 2
      ;;
    --notes=*)
      CUSTOM_NOTES="${1#*=}"
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [all|kids|parents] [release] [--auto] [--version <X.Y.Z>] [--notes <text>] [--no-push]"
      echo ""
      echo "Modes:"
      echo "  1. Test Build (default - local only):"
      echo "     $0                             # Builds both APKs locally (no version bump, no push)"
      echo "     $0 kids                        # Builds only Kids APK locally"
      echo "     $0 parents                     # Builds only Parents APK locally"
      echo ""
      echo "  2. Official Release (auto-versioning & push):"
      echo "     $0 release --auto              # Auto-increments versions, stamps date, updates version.json & pushes"
      echo "     $0 release                     # Same as above"
      echo "     $0 kids release                # Release only Kids app with auto-bump & push"
      echo "     $0 release --no-push           # Auto-bump and update version.json locally without git push"
      echo ""
      echo "Options:"
      echo "  --version <X.Y.Z>                 Explicitly set versionName (auto-increments versionCode)"
      echo "  --notes <description>             Custom notes for update popup (auto-stamped with current date)"
      echo "  --no-push                         Build APKs and update TechOptions locally without git push"
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

# Current date string for automated release notes
PRETTY_DATE=$(TZ="Asia/Dhaka" date +"%d %b %Y, %I:%M %p BST" 2>/dev/null || date +"%d %b %Y, %I:%M %p")

# ------------------------------------------------------------------------------
# Auto-incremental Versioning
# ------------------------------------------------------------------------------
if [[ "$TARGET_APP" == "all" || "$TARGET_APP" == "kids" ]]; then
  if $AUTO_BUMP || [[ -n "$CUSTOM_VERSION" ]]; then
    CURR_KIDS_CODE=$(grep -oP 'versionCode\s*=\s*\K[0-9]+' "$KIDS_APP_DIR/app/build.gradle.kts" 2>/dev/null || echo "1")
    CURR_KIDS_NAME=$(grep -oP 'versionName\s*=\s*"\K[^"]+' "$KIDS_APP_DIR/app/build.gradle.kts" 2>/dev/null || echo "1.0")
    NEW_KIDS_CODE=$((CURR_KIDS_CODE + 1))

    if [[ -n "$CUSTOM_VERSION" ]]; then
      NEW_KIDS_NAME="$CUSTOM_VERSION"
    else
      KM_1=$(echo "$CURR_KIDS_NAME" | cut -d. -f1)
      KM_2=$(echo "$CURR_KIDS_NAME" | cut -d. -f2)
      KM_3=$(echo "$CURR_KIDS_NAME" | cut -d. -f3)
      [ -z "$KM_3" ] && KM_3=0
      NEW_KIDS_NAME="${KM_1}.${KM_2}.$((KM_3 + 1))"
    fi

    sed -i "s/versionCode = [0-9]\+/versionCode = $NEW_KIDS_CODE/" "$KIDS_APP_DIR/app/build.gradle.kts"
    sed -i "s/versionName = \"[^\"]\+\"/versionName = \"$NEW_KIDS_NAME\"/" "$KIDS_APP_DIR/app/build.gradle.kts"
    echo "✓ Auto-bumped Kids Android: v${CURR_KIDS_NAME}+${CURR_KIDS_CODE} -> v${NEW_KIDS_NAME}+${NEW_KIDS_CODE}"
  fi
fi

if [[ "$TARGET_APP" == "all" || "$TARGET_APP" == "parents" ]]; then
  if $AUTO_BUMP || [[ -n "$CUSTOM_VERSION" ]]; then
    CURR_P_LINE=$(grep '^version:' "$PARENTS_APP_DIR/pubspec.yaml" 2>/dev/null | awk '{print $2}' || echo "0.1.0+1")
    CURR_P_NAME=$(echo "$CURR_P_LINE" | cut -d'+' -f1)
    CURR_P_CODE=$(echo "$CURR_P_LINE" | cut -d'+' -f2)
    [ -z "$CURR_P_CODE" ] && CURR_P_CODE=1
    NEW_P_CODE=$((CURR_P_CODE + 1))

    if [[ -n "$CUSTOM_VERSION" ]]; then
      NEW_P_NAME="$CUSTOM_VERSION"
    else
      PM_1=$(echo "$CURR_P_NAME" | cut -d. -f1)
      PM_2=$(echo "$CURR_P_NAME" | cut -d. -f2)
      PM_3=$(echo "$CURR_P_NAME" | cut -d. -f3)
      [ -z "$PM_3" ] && PM_3=0
      NEW_P_NAME="${PM_1}.${PM_2}.$((PM_3 + 1))"
    fi

    sed -i "s/^version: .*/version: ${NEW_P_NAME}+${NEW_P_CODE}/" "$PARENTS_APP_DIR/pubspec.yaml"
    echo "✓ Auto-bumped Parents Flutter: v${CURR_P_NAME}+${CURR_P_CODE} -> v${NEW_P_NAME}+${NEW_P_CODE}"
  fi
fi

if [[ "$TARGET_APP" == "all" || "$TARGET_APP" == "kids" ]]; then
  if [[ ! -d "$KIDS_APP_DIR" || ! -f "$KIDS_APP_DIR/gradlew" ]]; then
    echo "Error: Kids Android directory not found at $KIDS_APP_DIR" >&2
    exit 1
  fi
fi

if [[ "$TARGET_APP" == "all" || "$TARGET_APP" == "parents" ]]; then
  if [[ ! -d "$PARENTS_APP_DIR" || ! -f "$PARENTS_APP_DIR/scripts/build-apk.sh" ]]; then
    echo "Error: Parents App directory not found at $PARENTS_APP_DIR" >&2
    exit 1
  fi
fi

# Production Gateway & Web Base URLs
GATEWAY_URL="${GATEWAY_URL:-https://gentliva.com/}"
WEB_BASE_URL="${WEB_BASE_URL:-https://parent.gentliva.com}"

echo "=========================================================="
if $IS_RELEASE; then
  echo " Angan Multi-App Official Release (Auto-Deploy)"
else
  echo " Angan Multi-App Test Build (Local Only)"
fi
echo "=========================================================="
echo "Workspace Root   : $WORKSPACE_ROOT"
echo "Target App(s)    : $TARGET_APP"
echo "Mode             : $(if $IS_RELEASE; then echo "Official Release (Auto)"; else echo "Local Test Build (No Push)"; fi)"
echo "Auto-Bump Version: $(if $AUTO_BUMP; then echo "Enabled (+1)"; else echo "Disabled (Keep current)"; fi)"
echo "Git Push         : $(if $NO_PUSH; then echo "Disabled (Local only)"; else echo "Enabled (origin/angan)"; fi)"
echo "Gateway URL      : $GATEWAY_URL"
echo "Web Base URL     : $WEB_BASE_URL"
echo "=========================================================="

mkdir -p "$TECHOPTIONS_DIR"

# ------------------------------------------------------------------------------
# STEP 1: Build Angan Kids Android Release APK
# ------------------------------------------------------------------------------
KIDS_DEST_APK="$TECHOPTIONS_DIR/angan-kids.apk"
KIDS_DEST_UNIVERSAL="$TECHOPTIONS_DIR/angan-kids-universal.apk"

if [[ "$TARGET_APP" == "all" || "$TARGET_APP" == "kids" ]]; then
  echo ""
  echo ">>> [1/2] Building Angan Kids Android (Optimized ABI Release)..."

  # 1. Resolve JAVA_HOME
  if [[ -z "${JAVA_HOME:-}" || ! -x "${JAVA_HOME:-}/bin/java" ]]; then
    for candidate in \
      "/snap/android-studio/current/jbr" \
      "/opt/android-studio/jbr" \
      "$HOME/android-studio/jbr" \
      "/usr/lib/jvm/java-17-openjdk-amd64" \
      "/usr/lib/jvm/java-21-openjdk-amd64" \
      "/usr/lib/jvm/default-java"; do
      if [[ -x "$candidate/bin/java" ]]; then
        export JAVA_HOME="$candidate"
        break
      fi
    done
  fi

  if [[ -z "${JAVA_HOME:-}" || ! -x "${JAVA_HOME:-}/bin/java" ]]; then
    echo "Error: JAVA_HOME could not be detected. Please set JAVA_HOME explicitly." >&2
    exit 1
  fi
  echo "Using JAVA_HOME  : $JAVA_HOME"
  export PATH="$JAVA_HOME/bin:$PATH"

  # 2. Resolve ANDROID_HOME
  if [[ -z "${ANDROID_HOME:-}" || ! -d "${ANDROID_HOME:-}" ]]; then
    if [[ -f "$KIDS_APP_DIR/local.properties" ]]; then
      sdk_line="$(grep -E '^[[:space:]]*sdk\.dir[[:space:]]*=' "$KIDS_APP_DIR/local.properties" | head -n 1 || true)"
      if [[ -n "$sdk_line" ]]; then
        extracted_sdk="${sdk_line#*=}"
        extracted_sdk="${extracted_sdk//\\/}"
        extracted_sdk="$(echo "$extracted_sdk" | xargs)"
        if [[ -d "$extracted_sdk" ]]; then
          export ANDROID_HOME="$extracted_sdk"
        fi
      fi
    fi
    if [[ -z "${ANDROID_HOME:-}" ]]; then
      for candidate in \
        "$HOME/Android/Sdk" \
        "/usr/lib/android-sdk" \
        "/opt/android-sdk"; do
        if [[ -d "$candidate" ]]; then
          export ANDROID_HOME="$candidate"
          break
        fi
      done
    fi
  fi

  if [[ -z "${ANDROID_HOME:-}" || ! -d "${ANDROID_HOME:-}" ]]; then
    echo "Error: ANDROID_HOME could not be detected. Please set ANDROID_HOME explicitly." >&2
    exit 1
  fi
  echo "Using Android SDK: $ANDROID_HOME"

  (
    cd "$KIDS_APP_DIR"
    ./gradlew assembleRelease -PgatewayUrl="$GATEWAY_URL" --no-daemon
  )

  # Pick the best APK: prefer arm64-v8a (~24MB slim APK for physical phones)
  KIDS_OUT_DIR="$KIDS_APP_DIR/app/build/outputs/apk/release"
  KIDS_ARM64_APK="$KIDS_OUT_DIR/app-arm64-v8a-release.apk"
  KIDS_UNIVERSAL_APK="$KIDS_OUT_DIR/app-universal-release.apk"
  KIDS_STANDARD_APK="$KIDS_OUT_DIR/app-release.apk"

  if [[ -f "$KIDS_ARM64_APK" ]]; then
    cp "$KIDS_ARM64_APK" "$KIDS_DEST_APK"
    echo "✓ Deployed Primary Kids APK (arm64-v8a, slim): $KIDS_DEST_APK ($(du -h "$KIDS_DEST_APK" | cut -f1))"
  elif [[ -f "$KIDS_STANDARD_APK" ]]; then
    cp "$KIDS_STANDARD_APK" "$KIDS_DEST_APK"
    echo "✓ Deployed Primary Kids APK: $KIDS_DEST_APK ($(du -h "$KIDS_DEST_APK" | cut -f1))"
  elif [[ -f "$KIDS_UNIVERSAL_APK" ]]; then
    cp "$KIDS_UNIVERSAL_APK" "$KIDS_DEST_APK"
    echo "✓ Deployed Primary Kids APK: $KIDS_DEST_APK ($(du -h "$KIDS_DEST_APK" | cut -f1))"
  else
    echo "Error: No release APK found in $KIDS_OUT_DIR!" >&2
    exit 1
  fi

  # Deploy universal fallback if generated
  if [[ -f "$KIDS_UNIVERSAL_APK" ]]; then
    cp "$KIDS_UNIVERSAL_APK" "$KIDS_DEST_UNIVERSAL"
    echo "✓ Deployed Universal Kids APK: $KIDS_DEST_UNIVERSAL ($(du -h "$KIDS_DEST_UNIVERSAL" | cut -f1))"
  fi
fi

# ------------------------------------------------------------------------------
# STEP 2: Build Angan Parents (Flutter) Release APK via Docker
# ------------------------------------------------------------------------------
PARENTS_DEST_APK="$TECHOPTIONS_DIR/angan-parents.apk"

if [[ "$TARGET_APP" == "all" || "$TARGET_APP" == "parents" ]]; then
  echo ""
  echo ">>> [2/2] Building Angan Parents App (Flutter Release via Docker)..."

  (
    cd "$PARENTS_APP_DIR"
    ./scripts/build-apk.sh "$GATEWAY_URL" release "$WEB_BASE_URL"
  )

  PARENTS_SRC_APK="$PARENTS_APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
  if [[ ! -f "$PARENTS_SRC_APK" ]]; then
    echo "Error: Parents Release APK was not found at $PARENTS_SRC_APK!" >&2
    exit 1
  fi
  cp "$PARENTS_SRC_APK" "$PARENTS_DEST_APK"
  echo "✓ Deployed Parents APK: $PARENTS_DEST_APK ($(du -h "$PARENTS_DEST_APK" | cut -f1))"
fi

# Remove obsolete files
rm -f "$TECHOPTIONS_DIR/app-release.apk"

# ------------------------------------------------------------------------------
# STEP 3: Generate TechOptions/README.md & TechOptions/version.json
# ------------------------------------------------------------------------------
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S UTC')"
cat <<EOF > "$TECHOPTIONS_DIR/README.md"
# Angan Application Release Downloads

Updated: **$TIMESTAMP**
Gateway Environment: \`$GATEWAY_URL\`

| Application | Target Architecture | File Size | Direct Download Link |
| :--- | :--- | :---: | :--- |
| **Angan Kids** (Recommended) | ARM64 (Modern Phones: ZTE, Samsung, Xiaomi, etc.) | $(du -h "$KIDS_DEST_APK" 2>/dev/null | cut -f1 || echo "N/A") | [angan-kids.apk](https://raw.githubusercontent.com/nasim0x1/TechOptions/refs/heads/angan/angan-kids.apk) |
| **Angan Kids** (Universal) | All CPUs (Universal Fallback) | $(du -h "$KIDS_DEST_UNIVERSAL" 2>/dev/null | cut -f1 || echo "N/A") | [angan-kids-universal.apk](https://raw.githubusercontent.com/nasim0x1/TechOptions/refs/heads/angan/angan-kids-universal.apk) |
| **Angan Parents** | Android (ARM64 Phone Release) | $(du -h "$PARENTS_DEST_APK" 2>/dev/null | cut -f1 || echo "N/A") | [angan-parents.apk](https://raw.githubusercontent.com/nasim0x1/TechOptions/refs/heads/angan/angan-parents.apk) |

### SHA-256 Checksums
\`\`\`text
$(sha256sum "$TECHOPTIONS_DIR"/*.apk 2>/dev/null | awk '{print $1 "  " $2}' | sed "s|$TECHOPTIONS_DIR/||g" || true)
\`\`\`
EOF

# Extract version metadata for version.json (OTA updates)
KIDS_VERSION_CODE=$(grep -oP 'versionCode\s*=\s*\K[0-9]+' "$KIDS_APP_DIR/app/build.gradle.kts" 2>/dev/null || echo "1")
KIDS_VERSION_NAME=$(grep -oP 'versionName\s*=\s*"\K[^"]+' "$KIDS_APP_DIR/app/build.gradle.kts" 2>/dev/null || echo "1.0")

PARENTS_VERSION_LINE=$(grep '^version:' "$PARENTS_APP_DIR/pubspec.yaml" 2>/dev/null | awk '{print $2}' || echo "0.1.0+1")
PARENTS_VERSION_NAME=$(echo "$PARENTS_VERSION_LINE" | cut -d'+' -f1)
PARENTS_VERSION_CODE=$(echo "$PARENTS_VERSION_LINE" | cut -d'+' -f2)
[ -z "$PARENTS_VERSION_CODE" ] && PARENTS_VERSION_CODE="1"

KIDS_SHA=$(sha256sum "$KIDS_DEST_APK" 2>/dev/null | awk '{print $1}' || echo "")
PARENTS_SHA=$(sha256sum "$PARENTS_DEST_APK" 2>/dev/null | awk '{print $1}' || echo "")

if [[ -n "$CUSTOM_NOTES" ]]; then
  KIDS_NOTES="$CUSTOM_NOTES (Released: $PRETTY_DATE)"
  PARENTS_NOTES="$CUSTOM_NOTES (Released: $PRETTY_DATE)"
else
  KIDS_NOTES="Release update ($PRETTY_DATE) with stability and performance improvements."
  PARENTS_NOTES="Release update ($PRETTY_DATE) with stability and performance improvements."
fi

cat <<EOF > "$TECHOPTIONS_DIR/version.json"
{
  "kids": {
    "versionCode": ${KIDS_VERSION_CODE:-1},
    "versionName": "${KIDS_VERSION_NAME:-1.0}",
    "apkUrl": "https://raw.githubusercontent.com/nasim0x1/TechOptions/refs/heads/angan/angan-kids.apk",
    "sha256": "$KIDS_SHA",
    "releaseNotes": "$KIDS_NOTES"
  },
  "parents": {
    "versionCode": ${PARENTS_VERSION_CODE:-1},
    "versionName": "${PARENTS_VERSION_NAME:-0.1.0}",
    "apkUrl": "https://raw.githubusercontent.com/nasim0x1/TechOptions/refs/heads/angan/angan-parents.apk",
    "sha256": "$PARENTS_SHA",
    "releaseNotes": "$PARENTS_NOTES"
  }
}
EOF
echo "✓ Generated TechOptions/version.json (Kids: v${KIDS_VERSION_NAME}+${KIDS_VERSION_CODE}, Parents: v${PARENTS_VERSION_NAME}+${PARENTS_VERSION_CODE})"

# Mirror the release script to TechOptions repository
cp -f "$SCRIPT_DIR/build_release_apk.sh" "$TECHOPTIONS_DIR/build_release_apk.sh"
chmod +x "$TECHOPTIONS_DIR/build_release_apk.sh"

# ------------------------------------------------------------------------------
# STEP 4: Deploy to TechOptions Git (Clean Single Commit, No Git History Bloat)
# ------------------------------------------------------------------------------
if ! $NO_PUSH; then
  echo ""
  echo "=========================================================="
  echo " TECHOPTIONS REPOSITORY SYNC"
  echo "=========================================================="
  if [[ -d "$TECHOPTIONS_DIR/.git" ]]; then
    (
      cd "$TECHOPTIONS_DIR"
      git checkout -B angan
      git add angan-kids.apk angan-parents.apk README.md version.json build_release_apk.sh
      if [[ -f "$KIDS_DEST_UNIVERSAL" ]]; then
        git add angan-kids-universal.apk
      fi
      git rm -f app-release.apk 2>/dev/null || true

      COMMIT_MSG="Release APKs (Target: $TARGET_APP): $TIMESTAMP"

      # Amend the single commit so git history NEVER grows or tracks old binary versions
      if git rev-parse HEAD >/dev/null 2>&1; then
        git commit --amend -m "$COMMIT_MSG"
      else
        git commit -m "$COMMIT_MSG"
      fi

      echo "==> Pushing clean release commit to origin/angan (force update)..."
      git push --force origin angan
      echo "✓ Pushed to https://github.com/nasim0x1/TechOptions/tree/angan"
    )
  else
    echo "Warning: TechOptions is not a git repository. APKs copied but not pushed."
  fi
else
  echo ""
  echo "==> Skipping Git push (--no-push specified)."
fi

echo ""
echo "=========================================================="
echo " BUILD & DEPLOY COMPLETE!"
echo "=========================================================="
if [[ -f "$KIDS_DEST_APK" ]]; then
  echo "1. Angan Kids APK (arm64, slim): $KIDS_DEST_APK ($(du -h "$KIDS_DEST_APK" | cut -f1))"
  echo "   Download Link               : https://raw.githubusercontent.com/nasim0x1/TechOptions/refs/heads/angan/angan-kids.apk"
  echo "   SHA-256                     : $(sha256sum "$KIDS_DEST_APK" | awk '{print $1}')"
fi
if [[ -f "$KIDS_DEST_UNIVERSAL" ]]; then
  echo "2. Angan Kids Universal APK    : $KIDS_DEST_UNIVERSAL ($(du -h "$KIDS_DEST_UNIVERSAL" | cut -f1))"
  echo "   Download Link               : https://raw.githubusercontent.com/nasim0x1/TechOptions/refs/heads/angan/angan-kids-universal.apk"
fi
if [[ -f "$PARENTS_DEST_APK" ]]; then
  echo "3. Angan Parents APK           : $PARENTS_DEST_APK ($(du -h "$PARENTS_DEST_APK" | cut -f1))"
  echo "   Download Link               : https://raw.githubusercontent.com/nasim0x1/TechOptions/refs/heads/angan/angan-parents.apk"
  echo "   SHA-256                     : $(sha256sum "$PARENTS_DEST_APK" | awk '{print $1}')"
fi
echo "=========================================================="
