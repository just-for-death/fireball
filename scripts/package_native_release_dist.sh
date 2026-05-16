#!/usr/bin/env bash
# Copy native release binaries into dist/ with GitHub Release filenames + SHA256SUMS.txt
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${FIREBALL_VERSION:-6.0.0}"
DIST="$ROOT/dist"
mkdir -p "$DIST"

ANDROID_SRC="$ROOT/native/android/app/build/outputs/apk/release"
if compgen -G "$ANDROID_SRC"/*.apk >/dev/null; then
  APK="$(ls -t "$ANDROID_SRC"/*.apk | head -1)"
  cp "$APK" "$DIST/Fireball-${VERSION}-android.apk"
  echo "==> Android: $DIST/Fireball-${VERSION}-android.apk"
else
  echo "warn: no Android APK in $ANDROID_SRC (run ./scripts/build_native_apk.sh first)" >&2
fi

IPA_GLOB="$DIST/Fireball-${VERSION}-ios-unsigned.ipa"
if [[ -f "$IPA_GLOB" ]]; then
  echo "==> iOS: $IPA_GLOB"
fi

(
  cd "$DIST"
  rm -f SHA256SUMS.txt
  shopt -s nullglob
  files=(Fireball-"${VERSION}"-*)
  if ((${#files[@]})); then
    sha256sum "${files[@]}" >SHA256SUMS.txt
    echo "==> Checksums:"
    cat SHA256SUMS.txt
  else
    echo "warn: nothing to checksum in dist/" >&2
  fi
)
