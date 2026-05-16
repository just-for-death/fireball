#!/usr/bin/env bash
# Build native Fireball iOS app on Codemagic (macOS). No local Mac required.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: iOS app packaging requires macOS (use Codemagic workflow fireball-native-ios)." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "==> Installing XcodeGen…"
  brew install xcodegen
fi

export MARKETING_VERSION="${FIREBALL_VERSION:-6.0.0}"
export CURRENT_PROJECT_VERSION="${FIREBALL_BUILD_NUMBER:-600}"

echo "==> Generating Xcode project (Fireball $MARKETING_VERSION / $CURRENT_PROJECT_VERSION)…"
xcodegen generate

SCHEME="FireballNative"
DEST="${1:-generic/platform=iOS}"

echo "==> Building $SCHEME (+ FireballWidgets extension) for $DEST…"
xcodebuild \
  -project FireballNative.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "$DEST" \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}" \
  build

echo "OK: native iOS app + widget extension built."
