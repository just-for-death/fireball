# Fireball Native Rewrite

This folder contains the ground-up native replacement for Fireball:

- `android/`: Kotlin + Jetpack Compose implementation using SuvMusic UI patterns with Fireball backend contracts.
- `ios/`: Swift + SwiftUI implementation mirroring Android features and Fireball service behavior.

## Migration Principles

1. Preserve Fireball data contracts (`fireball_library.json`, settings keys, playback resolution order).
2. Preserve Fireball service providers (Invidious, iTunes, LRCLIB/NetEase, ListenBrainz, WebDAV, etc).
3. Preserve SuvMusic UI/UX architecture and adaptive shell behavior.
4. Keep Android and iOS feature parity.

## Current Scope in this commit

- Core domain models mirrored from Fireball (`Track`, `Playlist`, `Artist`, `Album`, `FireballSettings`).
- Fireball API endpoint client scaffolding for Android + iOS.
- Local library persistence contract skeleton matching `fireball_library.json`.
- Native app shells:
  - Android adaptive navigation shell in Compose.
  - iOS/iPadOS adaptive split-view/tab shell in SwiftUI.

This is the foundation layer for full feature implementation.
