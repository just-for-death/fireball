#!/usr/bin/env bash
# Automated QA for Fireball 6.0 native (Android JVM tests + iOS Core on Linux).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> Android: unit tests + compile"
(
  cd native/android
  ./gradlew :core-model:testDebugUnitTest :app:testDebugUnitTest :app:compileDebugKotlin
)

echo
echo "==> iOS Core: swift test (Linux-friendly; no Xcode UI)"
if command -v swift >/dev/null 2>&1; then
  (
    cd native/ios
    chmod +x scripts/verify-linux.sh
    ./scripts/verify-linux.sh
  )
else
  echo "warn: Swift not installed — skip iOS Core tests"
fi

echo
echo "Native QA automated checks passed."
