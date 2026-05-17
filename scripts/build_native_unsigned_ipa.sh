#!/usr/bin/env bash
# Build an unsigned Fireball native iOS .ipa (not installable until signed).
# Requires: macOS, Xcode, XcodeGen, Homebrew optional.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS="$ROOT/native/ios"
OUT="${1:-$ROOT/dist/Fireball-${FIREBALL_VERSION:-6.0.0}-ios-unsigned.ipa}"
# Codemagic passes repo-relative dist/…; normalize before any cd (zip runs inside ipa_payload).
if [[ "$OUT" != /* ]]; then
  OUT="$ROOT/$OUT"
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: unsigned IPA requires macOS (use Codemagic workflow fireball-ios-unsigned-ipa)." >&2
  exit 1
fi

export FIREBALL_VERSION="${FIREBALL_VERSION:-6.0.0}"
export FIREBALL_BUILD_NUMBER="${FIREBALL_BUILD_NUMBER:-600}"

cd "$IOS"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "==> Installing XcodeGen…"
  brew install xcodegen
fi

echo "==> XcodeGen (Fireball $FIREBALL_VERSION / $FIREBALL_BUILD_NUMBER)"
MARKETING_VERSION="$FIREBALL_VERSION" CURRENT_PROJECT_VERSION="$FIREBALL_BUILD_NUMBER" xcodegen generate

ARCHIVE_PATH="build/FireballNative.xcarchive"
APP_PATH="build/DerivedData/Build/Products/Release-iphoneos/FireballNative.app"

rm -rf build/FireballNative.xcarchive build/ipa_payload
mkdir -p build

echo "==> xcodebuild archive (unsigned)"
ARCHIVE_LOG="$IOS/build/xcode-archive.log"
rm -f "$ARCHIVE_LOG"
set +e
xcodebuild \
  -project FireballNative.xcodeproj \
  -scheme FireballNative \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  archive 2>&1 | tee "$ARCHIVE_LOG"
ARCHIVE_STATUS=${PIPESTATUS[0]}
set -e
if [[ "$ARCHIVE_STATUS" -ne 0 ]]; then
  echo "==> xcodebuild failed; compiler errors:" >&2
  grep -E 'error:' "$ARCHIVE_LOG" | head -40 >&2 || true
  exit "$ARCHIVE_STATUS"
fi

# Prefer archived .app; fall back to derived data layout if Xcode moves outputs.
if [[ -d "$ARCHIVE_PATH/Products/Applications/FireballNative.app" ]]; then
  APP_SRC="$ARCHIVE_PATH/Products/Applications/FireballNative.app"
else
  xcodebuild \
    -project FireballNative.xcodeproj \
    -scheme FireballNative \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -derivedDataPath build/DerivedData \
    CODE_SIGNING_ALLOWED=NO \
    build
  APP_SRC="$APP_PATH"
fi

mkdir -p build/ipa_payload/Payload
cp -R "$APP_SRC" build/ipa_payload/Payload/FireballNative.app

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
echo "==> Packaging IPA → $OUT"
(cd build/ipa_payload && zip -qr "$OUT" Payload)

echo "OK: $OUT (unsigned — sign with AltStore, Xcode, or your CI certificate before device install)"
