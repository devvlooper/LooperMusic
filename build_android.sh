#!/usr/bin/env bash
# Builds the 4 release APKs (arm64-v8a, armeabi-v7a, x86_64, universal) the
# same way CI does (.github/workflows/release.yml) and names them
# looper-player-v<version>-<abi>-online-release.apk in dist/android/.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

version=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)
[ -n "$version" ] || { echo "No version in pubspec.yaml" >&2; exit 1; }
[ -f android/key.properties ] || echo "warning: android/key.properties missing, APKs won't use the release key" >&2

defines=()
[ -f env.json ] && defines=(--dart-define-from-file=env.json)

flutter build apk --release --flavor github --split-per-abi "${defines[@]}"
flutter build apk --release --flavor github "${defines[@]}"

src=build/app/outputs/flutter-apk
out=dist/android
mkdir -p "$out"
for abi in arm64-v8a armeabi-v7a x86_64 universal; do
  if [ "$abi" = universal ]; then f="$src/app-github-release.apk"; else f="$src/app-$abi-github-release.apk"; fi
  [ -f "$f" ] || { echo "Missing $f" >&2; exit 1; }
  cp "$f" "$out/looper-player-v$version-$abi-online-release.apk"
done
ls -lh "$out"/looper-player-v"$version"-*-online-release.apk
