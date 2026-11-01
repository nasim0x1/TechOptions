#!/usr/bin/env bash
# ==============================================================================
# Build Release APKs for Angan Kids Android & Angan Parents (Flutter)
# and Deploy to <root>/TechOptions (Single-commit release, no bloated git history)
#
# Usage:
#   ./build_release_apk.sh                     # Interactive mode: asks target app and build only vs release
#   ./build_release_apk.sh build               # Build all apps locally (TechOptions untouched)
#   ./build_release_apk.sh kids build          # Build only Kids app locally
#   ./build_release_apk.sh parents build       # Build only Parents app locally
#   ./build_release_apk.sh release             # Official release: auto-bump, stage to TechOptions & push
#   ./build_release_apk.sh release --no-push   # Release locally: auto-bump & stage to TechOptions, skip push
#   ./build_release_apk.sh all --stage         # Build all apps and stage to TechOptions locally (no push)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

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

# Helper function to read input safely in interactive and non-interactive shells
ask_prompt() {
  local prompt_text="$1"
  local default_value="$2"
  local result_var="$3"
  local user_input=""

  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    eval "$result_var=\"$default_value\""
    return
  fi

  if read -r -p "$prompt_text" user_input; then
    user_input="$(echo "$user_input" | xargs)"
  else
    user_input=""
  fi

  if [[ -z "$user_input" ]]; then
    user_input="$default_value"
  fi
  eval "$result_var=\"$user_input\""
}

# Configuration variables
TARGET_APP=""
IS_RELEASE=false
MODE_SPECIFIED=false
UPDATE_TECHOPTIONS=""
NO_PUSH=true           # Default: safe local build only (no remote push)
AUTO_BUMP=false        # Default: keep current version for local test builds
NON_INTERACTIVE=false
DRY_RUN=false
CUSTOM_VERSION=""
CUSTOM_NOTES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|dry-run)
      DRY_RUN=true
      shift
      ;;
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
      MODE_SPECIFIED=true
      AUTO_BUMP=true
      NO_PUSH=false
      UPDATE_TECHOPTIONS="true"
      shift
      ;;
    build|--build|build-only|--build-only)
      IS_RELEASE=false
      MODE_SPECIFIED=true
      AUTO_BUMP=false
      NO_PUSH=true
      UPDATE_TECHOPTIONS="false"
      shift
      ;;
    stage|--stage|techoptions|--techoptions|--update-techoptions)
      UPDATE_TECHOPTIONS="true"
      MODE_SPECIFIED=true
      shift
      ;;
    --no-stage|--no-techoptions)
      UPDATE_TECHOPTIONS="false"
      shift
      ;;
    auto|--auto|auth|--auth)
      AUTO_BUMP=true
      shift
      ;;
    --push)
      NO_PUSH=false
      UPDATE_TECHOPTIONS="true"
      shift
      ;;
    --no-push|no-push)
      NO_PUSH=true
      UPDATE_TECHOPTIONS="true"
      MODE_SPECIFIED=true
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
    -y|--yes|--non-interactive|--batch)
      NON_INTERACTIVE=true
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
      echo "Usage: $SCRIPT_NAME [all|kids|parents] [build|release] [options]"
      echo ""
      echo "Modes:"
      echo "  1. Interactive (default when run in terminal without mode):"
      echo "     $SCRIPT_NAME                   # Prompts for target app and action (Build only vs Release also)"
      echo ""
      echo "  2. Build Only (local compile, keeps TechOptions untouched, no push):"
      echo "     $SCRIPT_NAME build             # Builds all APKs locally"
      echo "     $SCRIPT_NAME kids build        # Builds only Kids APK locally"
      echo "     $SCRIPT_NAME parents build     # Builds only Parents APK locally"
      echo ""
      echo "  3. Build & Stage to TechOptions (local staging, no push):"
      echo "     $SCRIPT_NAME --stage           # Builds all APKs and copies to TechOptions locally"
      echo "     $SCRIPT_NAME kids --no-push    # Builds Kids APK and copies to TechOptions locally"
      echo ""
      echo "  4. Official Release (auto-versioning & push to TechOptions):"
      echo "     $SCRIPT_NAME release           # Auto-increments versions, stages to TechOptions & pushes"
      echo "     $SCRIPT_NAME kids release      # Release only Kids app with auto-bump & push"
      echo "     $SCRIPT_NAME release --no-push # Auto-bump and stage to TechOptions locally without git push"
      echo ""
      echo "Options:"
      echo "  --build, build-only               Build APKs locally without updating TechOptions"
      echo "  --release                         Release mode (bumps version, updates TechOptions, pushes)"
      echo "  --stage, --techoptions            Copy built APKs to TechOptions repository"
      echo "  --no-stage, --no-techoptions      Do not touch TechOptions repository"
      echo "  --version <X.Y.Z>                 Explicitly set versionName (auto-increments versionCode)"
      echo "  --notes <description>             Custom notes for update popup (auto-stamped with current date)"
      echo "  --push                            Push release commit to TechOptions remote (origin/angan)"
      echo "  --no-push                         Build APKs and update TechOptions locally without git push"
      echo "  --bump / --no-bump                Force enable or disable version auto-increment"
      echo "  -y, --non-interactive             Skip interactive prompts and use defaults"
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

IS_TTY=false
if [[ "$NON_INTERACTIVE" != "true" ]] && { [[ -t 0 ]] || [[ -r /dev/tty ]]; }; then
  IS_TTY=true
fi

# ------------------------------------------------------------------------------
# Interactive Prompts (when options were not explicitly provided on CLI)
# ------------------------------------------------------------------------------
# 1. Target application
if [[ -z "$TARGET_APP" ]]; then
  if $IS_TTY; then
    echo "=========================================================="
    echo " Angan Multi-App Build & Release"
    echo "=========================================================="
    echo ""
    echo "Select target application:"
    echo "  1) All (Kids Android + Parents Flutter) [Default]"
    echo "  2) Kids Android only"
    echo "  3) Parents Flutter only"
    ask_prompt "Enter choice [1-3] (Default: 1): " "1" APP_CHOICE
    case "$APP_CHOICE" in
      2|kids|kid)
        TARGET_APP="kids"
        ;;
      3|parents|parent)
        TARGET_APP="parents"
        ;;
      *)
        TARGET_APP="all"
        ;;
    esac
    echo ""
  else
    TARGET_APP="all"
  fi
fi

# 2. Action: Build only vs Release also
if ! $MODE_SPECIFIED; then
  if $IS_TTY; then
    echo "Select action:"
    echo "  1) Build only   (Compile APK locally, keep current version, skip git push) [Default]"
    echo "  2) Release also (Auto-bump version, stage to TechOptions, commit & push)"
    ask_prompt "Enter choice [1-2] (Default: 1): " "1" MODE_CHOICE
    case "$MODE_CHOICE" in
      2|release|r|R)
        IS_RELEASE=true
        AUTO_BUMP=true
        UPDATE_TECHOPTIONS="true"
        NO_PUSH=false
        ;;
      *)
        IS_RELEASE=false
        AUTO_BUMP=false
        NO_PUSH=true
        ;;
    esac
    echo ""
  else
    IS_RELEASE=false
    AUTO_BUMP=false
    NO_PUSH=true
  fi
fi

# 3. TechOptions staging & Release confirmation
if ! $IS_RELEASE; then
  if [[ -z "$UPDATE_TECHOPTIONS" ]]; then
    if $IS_TTY; then
      ask_prompt "Also update/stage APKs in TechOptions locally? [y/N] (Default: n): " "n" STAGE_CHOICE
      case "$STAGE_CHOICE" in
        y|Y|yes|YES)
          UPDATE_TECHOPTIONS="true"
          ;;
        *)
          UPDATE_TECHOPTIONS="false"
          ;;
      esac
      echo ""
    else
      UPDATE_TECHOPTIONS="false"
    fi
  fi
else
  # Official release always updates TechOptions
  UPDATE_TECHOPTIONS="true"

  # Confirm Git Push for Release if in interactive mode
  if $IS_TTY && ! $NO_PUSH; then
    ask_prompt "Push release commit to TechOptions remote (origin/angan)? [Y/n] (Default: y): " "y" PUSH_CHOICE
    case "$PUSH_CHOICE" in
      n|N|no|NO)
        NO_PUSH=true
        echo "==> Remote push skipped; changes will stay local in TechOptions."
        ;;
      *)
        NO_PUSH=false
        ;;
    esac
    echo ""
  fi

  # Prompt for custom release notes if not provided
  if $IS_TTY && [[ -z "$CUSTOM_NOTES" ]]; then
    ask_prompt "Custom release notes (Optional - press Enter to use default): " "" NOTES_INPUT
    if [[ -n "$NOTES_INPUT" ]]; then
      CUSTOM_NOTES="$NOTES_INPUT"
    fi
    echo ""
  fi
fi

if [[ "$UPDATE_TECHOPTIONS" == "true" ]]; then
  SHOULD_UPDATE_TECHOPTIONS=true
else
  SHOULD_UPDATE_TECHOPTIONS=false
fi

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

    if $DRY_RUN; then
      echo "✓ [Dry-run] Would bump Kids Android: v${CURR_KIDS_NAME}+${CURR_KIDS_CODE} -> v${NEW_KIDS_NAME}+${NEW_KIDS_CODE}"
    else
      sed -i "s/versionCode = [0-9]\+/versionCode = $NEW_KIDS_CODE/" "$KIDS_APP_DIR/app/build.gradle.kts"
      sed -i "s/versionName = \"[^\"]\+\"/versionName = \"$NEW_KIDS_NAME\"/" "$KIDS_APP_DIR/app/build.gradle.kts"
      echo "✓ Auto-bumped Kids Android: v${CURR_KIDS_NAME}+${CURR_KIDS_CODE} -> v${NEW_KIDS_NAME}+${NEW_KIDS_CODE}"
    fi
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

    if $DRY_RUN; then
      echo "✓ [Dry-run] Would bump Parents Flutter: v${CURR_P_NAME}+${CURR_P_CODE} -> v${NEW_P_NAME}+${NEW_P_CODE}"
    else
      sed -i "s/^version: .*/version: ${NEW_P_NAME}+${NEW_P_CODE}/" "$PARENTS_APP_DIR/pubspec.yaml"
      echo "✓ Auto-bumped Parents Flutter: v${CURR_P_NAME}+${CURR_P_CODE} -> v${NEW_P_NAME}+${NEW_P_CODE}"
    fi
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
elif $SHOULD_UPDATE_TECHOPTIONS; then
  echo " Angan Multi-App Build & TechOptions Staging (Local)"
else
  echo " Angan Multi-App Build (Local Only)"
fi
echo "=========================================================="
echo "Workspace Root    : $WORKSPACE_ROOT"
echo "Target App(s)     : $TARGET_APP"
echo "Mode              : $(if $IS_RELEASE; then echo "Official Release"; elif $SHOULD_UPDATE_TECHOPTIONS; then echo "Build & Stage to TechOptions"; else echo "Local Build Only"; fi)"
echo "Auto-Bump Version : $(if $AUTO_BUMP; then echo "Enabled (+1)"; else echo "Disabled (Keep current)"; fi)"
echo "Update TechOptions: $(if $SHOULD_UPDATE_TECHOPTIONS; then echo "Yes ($TECHOPTIONS_DIR)"; else echo "No (TechOptions untouched)"; fi)"
echo "Git Push          : $(if $NO_PUSH; then echo "Disabled (Local only)"; else echo "Enabled (origin/angan)"; fi)"
echo "Gateway URL       : $GATEWAY_URL"
echo "Web Base URL      : $WEB_BASE_URL"
echo "=========================================================="

if $SHOULD_UPDATE_TECHOPTIONS; then
  mkdir -p "$TECHOPTIONS_DIR"
fi

if $DRY_RUN; then
  echo ""
  echo ">>> [DRY-RUN] Validation complete. Exiting without compiling APKs or modifying repositories."
  exit 0
fi

# ------------------------------------------------------------------------------
# STEP 1: Build Angan Kids Android Release APK
# ------------------------------------------------------------------------------
KIDS_DEST_APK="$TECHOPTIONS_DIR/angan-kids.apk"
KIDS_DEST_UNIVERSAL="$TECHOPTIONS_DIR/angan-kids-universal.apk"
KIDS_BUILT_APK=""

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
    KIDS_BUILT_APK="$KIDS_ARM64_APK"
  elif [[ -f "$KIDS_STANDARD_APK" ]]; then
    KIDS_BUILT_APK="$KIDS_STANDARD_APK"
  elif [[ -f "$KIDS_UNIVERSAL_APK" ]]; then
    KIDS_BUILT_APK="$KIDS_UNIVERSAL_APK"
  else
    echo "Error: No release APK found in $KIDS_OUT_DIR!" >&2
    exit 1
  fi

  if $SHOULD_UPDATE_TECHOPTIONS; then
    cp "$KIDS_BUILT_APK" "$KIDS_DEST_APK"
    echo "✓ Staged Primary Kids APK to TechOptions: $KIDS_DEST_APK ($(du -h "$KIDS_DEST_APK" | cut -f1))"
    if [[ -f "$KIDS_UNIVERSAL_APK" ]]; then
      cp "$KIDS_UNIVERSAL_APK" "$KIDS_DEST_UNIVERSAL"
      echo "✓ Staged Universal Kids APK to TechOptions: $KIDS_DEST_UNIVERSAL ($(du -h "$KIDS_DEST_UNIVERSAL" | cut -f1))"
    fi
  else
    echo "✓ Built Primary Kids APK: $KIDS_BUILT_APK ($(du -h "$KIDS_BUILT_APK" | cut -f1))"
    if [[ -f "$KIDS_UNIVERSAL_APK" ]]; then
      echo "✓ Built Universal Kids APK: $KIDS_UNIVERSAL_APK ($(du -h "$KIDS_UNIVERSAL_APK" | cut -f1))"
    fi
  fi
fi

# ------------------------------------------------------------------------------
# STEP 2: Build Angan Parents (Flutter) Release APK via Docker
# ------------------------------------------------------------------------------
PARENTS_DEST_APK="$TECHOPTIONS_DIR/angan-parents.apk"
PARENTS_SRC_APK=""

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

  if $SHOULD_UPDATE_TECHOPTIONS; then
    cp "$PARENTS_SRC_APK" "$PARENTS_DEST_APK"
    echo "✓ Staged Parents APK to TechOptions: $PARENTS_DEST_APK ($(du -h "$PARENTS_DEST_APK" | cut -f1))"
  else
    echo "✓ Built Parents APK: $PARENTS_SRC_APK ($(du -h "$PARENTS_SRC_APK" | cut -f1))"
  fi
fi

# ------------------------------------------------------------------------------
# STEP 3: TechOptions Metadata & Scripts Sync (Optional based on mode/choice)
# ------------------------------------------------------------------------------
if $SHOULD_UPDATE_TECHOPTIONS; then
  # Remove obsolete files
  rm -f "$TECHOPTIONS_DIR/app-release.apk"

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
    echo "==> Skipping Git push (--no-push or local staging specified)."
  fi
fi

echo ""
echo "=========================================================="
if $SHOULD_UPDATE_TECHOPTIONS; then
  if ! $NO_PUSH; then
    echo " BUILD & RELEASE COMPLETE (Pushed to TechOptions)!"
  else
    echo " BUILD & TECHOPTIONS STAGING COMPLETE (Local Only)!"
  fi
else
  echo " BUILD COMPLETE (Local Build Only)!"
fi
echo "=========================================================="

if [[ "$TARGET_APP" == "all" || "$TARGET_APP" == "kids" ]]; then
  if $SHOULD_UPDATE_TECHOPTIONS; then
    if [[ -f "$KIDS_DEST_APK" ]]; then
      echo "1. Angan Kids APK (arm64, slim): $KIDS_DEST_APK ($(du -h "$KIDS_DEST_APK" | cut -f1))"
      echo "   Download Link               : https://raw.githubusercontent.com/nasim0x1/TechOptions/refs/heads/angan/angan-kids.apk"
      echo "   SHA-256                     : $(sha256sum "$KIDS_DEST_APK" | awk '{print $1}')"
    fi
    if [[ -f "$KIDS_DEST_UNIVERSAL" ]]; then
      echo "2. Angan Kids Universal APK    : $KIDS_DEST_UNIVERSAL ($(du -h "$KIDS_DEST_UNIVERSAL" | cut -f1))"
      echo "   Download Link               : https://raw.githubusercontent.com/nasim0x1/TechOptions/refs/heads/angan/angan-kids-universal.apk"
    fi
  else
    if [[ -n "${KIDS_BUILT_APK:-}" && -f "$KIDS_BUILT_APK" ]]; then
      echo "1. Angan Kids APK              : $KIDS_BUILT_APK ($(du -h "$KIDS_BUILT_APK" | cut -f1))"
      echo "   SHA-256                     : $(sha256sum "$KIDS_BUILT_APK" | awk '{print $1}')"
    fi
    if [[ -f "$KIDS_UNIVERSAL_APK" ]]; then
      echo "2. Angan Kids Universal APK    : $KIDS_UNIVERSAL_APK ($(du -h "$KIDS_UNIVERSAL_APK" | cut -f1))"
    fi
  fi
fi

if [[ "$TARGET_APP" == "all" || "$TARGET_APP" == "parents" ]]; then
  if $SHOULD_UPDATE_TECHOPTIONS; then
    if [[ -f "$PARENTS_DEST_APK" ]]; then
      echo "3. Angan Parents APK           : $PARENTS_DEST_APK ($(du -h "$PARENTS_DEST_APK" | cut -f1))"
      echo "   Download Link               : https://raw.githubusercontent.com/nasim0x1/TechOptions/refs/heads/angan/angan-parents.apk"
      echo "   SHA-256                     : $(sha256sum "$PARENTS_DEST_APK" | awk '{print $1}')"
    fi
  else
    if [[ -n "${PARENTS_SRC_APK:-}" && -f "$PARENTS_SRC_APK" ]]; then
      echo "3. Angan Parents APK           : $PARENTS_SRC_APK ($(du -h "$PARENTS_SRC_APK" | cut -f1))"
      echo "   SHA-256                     : $(sha256sum "$PARENTS_SRC_APK" | awk '{print $1}')"
    fi
  fi
fi

if ! $SHOULD_UPDATE_TECHOPTIONS; then
  echo ""
  echo "Note: TechOptions repository was not modified."
  echo "      Run with 'release' or enable TechOptions staging to update TechOptions."
fi
echo "=========================================================="
