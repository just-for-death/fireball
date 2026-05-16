#!/usr/bin/env bash
# Build Fireball native Android release APK (native/android).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/native/android"

if [[ -z "${JAVA_HOME:-}" ]]; then
  for candidate in /usr/lib/jvm/java-21-openjdk /usr/lib/jvm/java-17-openjdk; do
    if [[ -x "$candidate/bin/java" ]]; then
      export JAVA_HOME="$candidate"
      export PATH="$JAVA_HOME/bin:$PATH"
      break
    fi
  done
fi

VERSION="${FIREBALL_VERSION:-6.0.0}"
BUILD_NUM="${FIREBALL_BUILD_NUMBER:-600}"

echo "==> Fireball native Android $VERSION ($BUILD_NUM)"
./gradlew :app:assembleRelease -PfireballVersionName="$VERSION" -PfireballVersionCode="$BUILD_NUM"

APK_DIR="app/build/outputs/apk/release"
echo "==> APK:"
ls -la "$APK_DIR"/*.apk 2>/dev/null || true
