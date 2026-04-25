#!/usr/bin/env bash
# Build an unsigned iOS archive (.ipa-shaped zip). Not installable on device until signed.
# Requires: macOS, Xcode, CocoaPods, Flutter.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILD_NAME="${FLUTTER_BUILD_NAME:-1.6.0}"
BUILD_NUMBER="${FLUTTER_BUILD_NUMBER:-1}"
OUT_NAME="${1:-build/ios/fireball_unsigned.ipa}"

echo "==> flutter pub get"
flutter pub get

echo "==> patch audiotags iOS podspec (CI safeguard)"
AUDIO_PODSPEC_PATH="$(python3 - <<'PY'
import json
from pathlib import Path

plugins_path = Path(".flutter-plugins-dependencies")
if not plugins_path.exists():
    raise SystemExit(0)

data = json.loads(plugins_path.read_text())
for plugin in data.get("plugins", {}).get("ios", []):
    if plugin.get("name") == "audiotags":
        print(Path(plugin["path"]) / "ios" / "audiotags.podspec")
        break
PY
)"

if [[ -n "${AUDIO_PODSPEC_PATH:-}" && -f "$AUDIO_PODSPEC_PATH" ]]; then
  # audiotags 1.4.5 has a malformed shell condition that can skip xcframework download.
  perl -0pi -e 's/if \[ ! -d ios\.zip \]d/if [ ! -f ios.zip ]/g' "$AUDIO_PODSPEC_PATH"
fi

echo "==> pod install"
( cd ios && pod install )

echo "==> flutter build ios --release --no-codesign"
flutter build ios --release --no-codesign \
  --build-name="$BUILD_NAME" \
  --build-number="$BUILD_NUMBER"

APP="build/ios/iphoneos/Runner.app"
if [[ ! -d "$APP" ]]; then
  APP="build/ios/Release-iphoneos/Runner.app"
fi
if [[ ! -d "$APP" ]]; then
  echo "Runner.app not found under build/ios (expected iphoneos or Release-iphoneos)." >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/Payload"
cp -R "$APP" "$TMP/Payload/"

mkdir -p "$(dirname "$OUT_NAME")"
( cd "$TMP" && zip -qr "$ROOT/$OUT_NAME" Payload )

echo "==> Wrote $OUT_NAME"
echo "    (Unsigned — resign with your provisioning profile / certificate to install on devices.)"
