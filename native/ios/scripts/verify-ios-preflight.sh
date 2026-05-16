#!/usr/bin/env bash
# Static checks for iOS app sources before Codemagic / xcodebuild (runs on Linux).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/FireballNative"
WIDGETS="$ROOT/FireballWidgets"
TASK_ID="com.fireball.native.artist-releases"
failed=0

err() {
  echo "error: $*" >&2
  failed=1
}

echo "==> iOS preflight (static)"

# Deployment target aligned with project.yml / onChange(of:initial:_:)
if ! grep -q 'iOS: "17.0"' "$ROOT/project.yml" 2>/dev/null; then
  err "project.yml must set deploymentTarget iOS 17.0 (two-parameter onChange)"
fi

# BGTask identifier must match Info.plist + Swift registration
if ! grep -q "$TASK_ID" "$APP/Info.plist"; then
  err "Info.plist missing BGTask identifier $TASK_ID"
fi
if ! grep -q "$TASK_ID" "$APP/App/ArtistReleaseBackgroundRefresh.swift"; then
  err "ArtistReleaseBackgroundRefresh missing taskIdentifier $TASK_ID"
fi

# Widget extension needs explicit Info.plist path (XcodeGen)
if [[ ! -f "$WIDGETS/Info.plist" ]]; then
  err "FireballWidgets/Info.plist missing (XcodeGen info.path)"
fi
if ! grep -q 'FireballWidgets/Info.plist' "$ROOT/project.yml"; then
  err "project.yml must set FireballWidgets info.path"
fi

scan_swift() {
  local label="$1"
  local dir="$2"
  if rg -q '\.onValueChange\(' "$dir" 2>/dev/null; then
    err "$label: deprecated .onValueChange — use .onChange(of:initial:_:)"
  fi
  if rg -q '\.marquee\(' "$dir" 2>/dev/null; then
    err "$label: .marquee() unavailable on Xcode 16.4 — use lineLimit + minimumScaleFactor"
  fi
  if rg -q 'ExtractionMethod' "$dir" 2>/dev/null; then
    err "$label: ExtractionMethod at file scope — use YouTube(videoID:methods: [.local, .remote]) inline"
  fi
  if rg -q 'onChange\(of:[^)]+\) \{ [^_,]' "$dir" --glob '*.swift' 2>/dev/null; then
    err "$label: single-parameter onChange — use { _, newValue in } (iOS 17+)"
  fi
  if rg -q '\bfollowArtist\(\s*[^n]' "$dir" --glob '*.swift' 2>/dev/null; then
    err "$label: followArtist missing name: label"
  fi
  if rg -q 'playTrackUpNext\([^t]|appendTrackToQueue\([^t]' "$dir" --glob '*.swift' 2>/dev/null; then
    err "$label: queue helpers need track: label"
  fi
}

scan_swift "app" "$APP"
scan_swift "widgets" "$WIDGETS"

# Public app views must not expose internal model types in API (WMO / access control)
if rg -q '^public struct (NowPlayingScreen|HomeScreen|LibraryScreen)' "$APP" --glob '*.swift' 2>/dev/null; then
  err "public screen structs with internal Track/FireballSettings break Release builds"
fi

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
echo "OK: iOS preflight static checks"
