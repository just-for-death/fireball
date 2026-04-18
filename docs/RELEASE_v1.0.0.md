# Fireball v1.0.0

First public release of **Fireball** — a standalone, server-free music player for **Android** and **iOS** (Flutter).

## Downloads

| Platform | Asset | Notes |
|----------|--------|--------|
| **Android** | `Fireball-1.0.0-android.apk` | Universal release APK. Install by allowing installs from unknown sources or via `adb install`. |
| **iOS** | `Fireball-1.0.0-ios-unsigned.ipa` | **Unsigned** build. Not for App Store distribution. Install via sideloading (e.g. AltStore, Sideloadly), a developer provisioning profile, or your own signing pipeline. |

Version in app: **1.0.0** (build **1**), matching `pubspec.yaml`.

## Highlights

- **Playback**: Stream via any [Invidious](https://invidious.io) instance; background playback and lock-screen controls (`media_kit` + `audio_service`).
- **Discovery**: Home trending (iTunes RSS), search, optional **Ollama** queue suggestions.
- **Lyrics**: LRCLIB synced/plain lyrics with fallbacks.
- **Library**: Local-first JSON store — favorites, playlists, history, artists, albums.
- **Scrobbling**: ListenBrainz (optional Last.fm key validation).
- **Backup**: Google Drive and WebDAV / Nextcloud.
- **UI**: Material 3, FlexColorScheme, dynamic color (Android 12+), iPad glass sidebar with compact rail, Android NavigationRail on tablets.

## Requirements

- **Android**: 5.0+ (typical Flutter / `minSdk` as per project).
- **iOS**: Version supported by your Flutter SDK (see Flutter iOS deployment target).

Configure an **Invidious instance URL** in Settings on first launch (required for streaming).

## Build from source

See [README.md](../README.md): `flutter build apk --release`, `flutter build ipa` (macOS + Xcode for iOS).

## SHA-256 checksums

```
5ab300c20ba97acd85222f32d20da9beadff29979bab53fd91c2b50cade4cb78  Fireball-1.0.0-android.apk
a42c37b9deff713df19842316d2b16432ba536e6355c4a44381ef75ae2ecdf9c  Fireball-1.0.0-ios-unsigned.ipa
```

A `SHA256SUMS.txt` file is attached to the GitHub release alongside the binaries.

## License

MIT — see [LICENSE](../LICENSE).
