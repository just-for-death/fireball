#!/usr/bin/env bash
# Verify Fireball iOS Core on Linux (no Xcode). Run from repo root or native/ios.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v swift >/dev/null 2>&1; then
  echo "error: Swift toolchain not found. Install Swift 5.9+ (https://www.swift.org/install/linux/)." >&2
  exit 1
fi

echo "==> Swift: $(swift --version | head -1)"
chmod +x scripts/verify-swift-string-literals.sh
./scripts/verify-swift-string-literals.sh
echo "==> Resolving packages…"
swift package resolve

echo "==> Building FireballNativeCore (Linux host, no YouTubeKit)…"
swift build --target FireballNativeCore -c debug

echo "==> Running unit tests…"
swift test --filter FireballNativeCoreTests -c debug

echo "OK: iOS core + InnerTube fallback compile and tests pass on Linux."
echo "Package the .app on Codemagic workflow fireball-native-ios (no local Mac required)."
