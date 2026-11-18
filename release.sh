#!/usr/bin/env bash

# ==============================================================================
# Android Packaging & Build Script
# ==============================================================================
# Builds split-per-ABI APKs, a universal APK and an App Bundle (.aab). When the
# project defines github/play Android flavors, the APKs are built as `github`
# and the .aab as `play`. Artifacts land in dist/android/ with a
# SHA256SUMS-v<version>.txt.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

OUTPUT_DIR="dist"
ANDROID_DIST_DIR="$OUTPUT_DIR/android"

BUILD_FLAG=false
CLEAN_FLAG=false
OVERRIDE_APP_NAME="${APP_NAME:-}"

# ABIs produced by `flutter build apk --split-per-abi`; narrow them with e.g. ANDROID_ABIS="arm64-v8a".
ANDROID_ABIS="${ANDROID_ABIS:-arm64-v8a armeabi-v7a x86_64}"
BUILD_MARKER=""          # temp file whose mtime is when this run's build started
ANDROID_PUBLISHED=()     # file names copied into $ANDROID_DIST_DIR by this run
ANDROID_MISSING=()       # expected artifacts that could not be found
PACKAGING_FAILED=false   # set when an expected artifact is missing after a build

show_help() {
    cat <<EOF
Usage: ./release.sh [android] [OPTIONS]

Options:
  --build                 Run 'flutter build' release compilation prior to packaging
  --clean                 Run 'flutter clean' before building
  --project-dir <path>    Path to the Flutter project to package (default: this script's directory)
  --app-name <name>       Override the artifact name prefix (default: from pubspec.yaml)
  --help                  Show this help message

Environment:
  ANDROID_ABIS            Split-APK ABIs to collect (default: "arm64-v8a armeabi-v7a x86_64")

With --build, any missing artifact fails the run (non-zero exit) instead of being skipped.

Example:
  ./release.sh android --build
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        android|all) shift ;;
        --build) BUILD_FLAG=true; shift ;;
        --clean) CLEAN_FLAG=true; shift ;;
        --project-dir) PROJECT_DIR="$(cd "$2" && pwd)"; shift 2 ;;
        --app-name) OVERRIDE_APP_NAME="$2"; shift 2 ;;
        --help|-h) show_help ;;
        *) echo "❌ Unknown argument: $1"; show_help ;;
    esac
done

cd "$PROJECT_DIR"

if [[ ! -f "pubspec.yaml" ]]; then
    echo "❌ Error: No pubspec.yaml found in $PROJECT_DIR — this doesn't look like a Flutter project."
    exit 1
fi

detect_pubspec_field() {
    # $1 = top-level YAML key (e.g. "name", "description", "version")
    grep -m1 -E "^${1}:" pubspec.yaml 2>/dev/null \
        | sed -E "s/^${1}:[[:space:]]*//" \
        | tr -d '\r' \
        | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/'
}

detect_app_name() {
    local raw
    raw=$(detect_pubspec_field "name")
    if [[ -z "$raw" ]]; then
        raw="$(basename "$PROJECT_DIR")"
    fi
    echo "$raw" | tr '_' '-' | tr '[:upper:]' '[:lower:]'
}

APP_NAME="${OVERRIDE_APP_NAME:-$(detect_app_name)}"
RAW_VERSION=$(detect_pubspec_field "version")
VERSION=$(echo "$RAW_VERSION" | cut -d'+' -f1)
BUILD_NUM=$(echo "$RAW_VERSION" | cut -d'+' -f2)
[[ -z "$VERSION" ]] && VERSION="0.0.0"
[[ -z "$BUILD_NUM" ]] && BUILD_NUM="0"

echo "=================================================="
echo "🚀 $APP_NAME Android packaging v$VERSION (Build $BUILD_NUM)"
echo "=================================================="

if ! command -v flutter &> /dev/null; then
    echo "❌ Error: 'flutter' command not found in PATH."
    exit 1
fi

if [[ "$CLEAN_FLAG" == true ]]; then
    echo "🧹 Cleaning Flutter build cache..."
    flutter clean
    flutter pub get
fi

# --- Android Packaging Function ---
# Copies the first existing candidate into $ANDROID_DIST_DIR as <dest_name>,
# verifies the copy, and records the outcome in ANDROID_PUBLISHED / ANDROID_MISSING.
#   usage: publish_android_artifact <label> <dest_name> <candidate-path>...
#
# Several candidates are tried on purpose. Flutter's Gradle plugin writes split
# APKs as app-<abi>-<flavor>-<mode>.apk, while flutter_tools' own lookup list
# uses app-<flavor>-<abi>-<mode>.apk - so never hardcode a single order (an
# earlier version of this script did, and silently skipped every split APK).
publish_android_artifact() {
    local label="$1" dest_name="$2"
    shift 2

    local src="" candidate
    for candidate in "$@"; do
        if [[ -f "$candidate" ]]; then
            src="$candidate"
            break
        fi
    done

    if [[ -z "$src" ]]; then
        ANDROID_MISSING+=("$label")
        echo "  ❌ $label — not found. Looked for:"
        printf '       %s\n' "$@"
        return 0
    fi

    local dest="$ANDROID_DIST_DIR/$dest_name"
    cp -f "$src" "$dest"
    if ! cmp -s "$src" "$dest"; then
        ANDROID_MISSING+=("$label (copy did not match source)")
        echo "  ❌ $label — copy to $dest did not match $src"
        return 0
    fi

    local size built note=""
    size="$(du -h "$dest" | cut -f1)"
    built="$(date -r "$src" '+%Y-%m-%d %H:%M')"
    # Gradle skips repackaging when nothing changed, leaving the previous
    # (identical) file in place - fine to ship, but say so instead of hiding it.
    if [[ -n "$BUILD_MARKER" && ! "$src" -nt "$BUILD_MARKER" ]]; then
        note="  ⚠️ predates this run (Gradle reused an up-to-date build)"
    fi
    echo "  ✅ $label → $dest ($size, built $built)$note"
    ANDROID_PUBLISHED+=("$dest_name")
}

package_android() {
    echo ""
    echo "--------------------------------------------------"
    echo "🤖 Packaging Android Target..."
    echo "--------------------------------------------------"

    if [[ ! -d "android" ]]; then
        echo "⚠️  No 'android/' platform directory found in this project. Skipping Android packaging."
        return
    fi

    mkdir -p "$ANDROID_DIST_DIR"

    # Pick up compile-time secrets (API keys, feature flags, ...) from a
    # gitignored env.json at the project root, if the project uses one (see
    # docs/ADS_ANALYTICS_SETUP.md for this project's case). Without this,
    # String.fromEnvironment()/bool.fromEnvironment() calls in Dart silently
    # compile to their default values instead of erroring, so a build that
    # forgets this flag looks fine but ships with those features inert.
    local dart_define_flag=""
    if [[ -f "env.json" ]]; then
        dart_define_flag="--dart-define-from-file=env.json"
        echo "🔑 Found env.json — compiling with $dart_define_flag"
    fi

    # This app defines `github` and `play` product flavors (see
    # android/app/build.gradle.kts): the APKs are the GitHub-release
    # distribution (checks GitHub for updates, no Google Play code) and the AAB
    # is the Google Play one (Play In-App Updates). Only use them when the
    # target project actually defines both, so this script still works
    # unchanged on a project without flavors.
    local apk_flavor="" aab_flavor=""
    if grep -qsE '(create\("|^\s*)github("\)|\s*\{)' android/app/build.gradle* &&
       grep -qsE '(create\("|^\s*)play("\)|\s*\{)' android/app/build.gradle*; then
        apk_flavor="github"
        aab_flavor="play"
        echo "🏷️  Found github/play flavors — APKs use 'github', the AAB uses 'play'"
    fi
    local apk_flavor_flag="${apk_flavor:+--flavor $apk_flavor}"
    local aab_flavor_flag="${aab_flavor:+--flavor $aab_flavor}"

    if [[ "$BUILD_FLAG" == true ]]; then
        # Anything not newer than this marker wasn't (re)written by this build.
        BUILD_MARKER="$(mktemp)"

        echo "🔨 Building Android Split APKs..."
        flutter build apk --release $apk_flavor_flag --split-per-abi $dart_define_flag

        echo "🔨 Building Android Universal APK..."
        flutter build apk --release $apk_flavor_flag $dart_define_flag

        echo "🔨 Building Android App Bundle (AAB)..."
        flutter build appbundle --release $aab_flavor_flag $dart_define_flag
    fi

    local apk_dir="build/app/outputs/flutter-apk"
    local bundle_dir="build/app/outputs/bundle"
    local apk_flavor_part="${apk_flavor:+-$apk_flavor}"
    local aab_flavor_part="${aab_flavor:+-$aab_flavor}"
    local aab_variant_dir="release"
    [[ -n "$aab_flavor" ]] && aab_variant_dir="${aab_flavor}Release"

    echo "📦 Collecting Android artifacts into $ANDROID_DIST_DIR..."

    # 1. ABI split APKs
    local abi
    for abi in $ANDROID_ABIS; do
        publish_android_artifact "APK ($abi)" "${APP_NAME}-v${VERSION}-${abi}-release.apk" \
            "$apk_dir/app-${abi}${apk_flavor_part}-release.apk" \
            "$apk_dir/app${apk_flavor_part}-${abi}-release.apk"
    done

    # 2. Universal APK
    publish_android_artifact "Universal APK" "${APP_NAME}-v${VERSION}-universal-release.apk" \
        "$apk_dir/app${apk_flavor_part}-release.apk"

    # 3. App Bundle (.aab)
    publish_android_artifact "App Bundle (AAB)" "${APP_NAME}-v${VERSION}-release.aab" \
        "$bundle_dir/$aab_variant_dir/app${aab_flavor_part}-release.aab"

    [[ -n "$BUILD_MARKER" ]] && rm -f "$BUILD_MARKER"
    BUILD_MARKER=""

    # Checksums for what this run published, in `sha256sum -c` format.
    if (( ${#ANDROID_PUBLISHED[@]} > 0 )); then
        local sums_file="SHA256SUMS-v${VERSION}.txt"
        (cd "$ANDROID_DIST_DIR" && sha256sum "${ANDROID_PUBLISHED[@]}" > "$sums_file")
        echo "  🔐 Checksums: $ANDROID_DIST_DIR/$sums_file"
    fi

    if (( ${#ANDROID_MISSING[@]} > 0 )); then
        echo ""
        echo "  Present in $apk_dir:"
        ls -1 "$apk_dir" 2>/dev/null | sed 's/^/       /' || true
        if [[ "$BUILD_FLAG" == true ]]; then
            # A build just ran, so a missing artifact is a real failure - don't
            # let the closing banner claim success.
            PACKAGING_FAILED=true
            echo "❌ ${#ANDROID_MISSING[@]} expected Android artifact(s) missing after the build: ${ANDROID_MISSING[*]}"
        else
            echo "⚠️  ${#ANDROID_MISSING[@]} artifact(s) not found. Nothing was built by this run — pass --build to compile them."
        fi
    fi
}

package_android

echo ""
echo "=================================================="
if [[ "$PACKAGING_FAILED" == true ]]; then
    echo "❌ Packaging finished with errors — see above"
    exit 1
fi
echo "🎉 Build & Packaging Completed Successfully!"
ls -lh "$ANDROID_DIST_DIR" 2>/dev/null || true
