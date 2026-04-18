# Changelog

All notable changes to **Fireball** are documented here. Release binaries live on [GitHub Releases](https://github.com/just-for-death/fireball/releases).

## [1.5.0] — 2026-04-18

### Sync & library

- **WebDAV live sync**: Pulling a newer remote `library.json` **merges** libraries (history, favorites, playlists, artists, albums) instead of replacing the whole device, so two devices are less likely to wipe each other’s edits.
- **Periodic sync**: Optional background check every few minutes while the app runs (when live sync is enabled).
- **Shared settings merge**: Account-related fields from the remote library merge without overwriting local theme / iPad layout / remote-server preferences.

### Remote control

- **Pairing**: Short **pairing code** (IP + port encoded) plus **QR** for Fireball (`fbremote://…`) and a second QR for plain `http://` scanning.
- **In-app QR scan** (Android/iOS) to connect without typing an IP.
- **LAN IP selection** prefers private IPv4 when multiple interfaces exist.
- **Android**: Cleartext HTTP allowed for LAN remote URLs.
- **Hostname**: Manual entry accepts `host:port` for `.local` / mDNS names, not only IPv4.

### Android

- **Thumbnails**: Protocol-relative artwork URLs (`//…`) normalized for image loading.
- **Mini player**: Extra bottom inset on Android so the bar clears gesture/navigation areas.

### Tooling

- **Codemagic**: Workflows default to marketing version **1.5.0**; `scripts/build_apk.sh` prefers JDK 21 for Gradle compatibility.

### Downloads (v1.5.0)

| Platform | Asset name |
|----------|------------|
| Android | `Fireball-1.5.0-android.apk` |
| iOS | `Fireball-1.5.0-ios-unsigned.ipa` (unsigned — sideload / your signing) |

Verify downloads with `SHA256SUMS.txt` on the release.

---

## [1.0.0] — 2025 (first release)

Initial public release: Invidious playback, library, lyrics, ListenBrainz, Google Drive & WebDAV backup, tablet UI, Material 3 / dynamic color. See GitHub release [v1.0.0](https://github.com/just-for-death/fireball/releases/tag/v1.0.0) for assets and checksums.

[1.5.0]: https://github.com/just-for-death/fireball/releases/tag/v1.5.0
[1.0.0]: https://github.com/just-for-death/fireball/releases/tag/v1.0.0
