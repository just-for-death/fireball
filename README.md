<p align="center">
  <img src="assets/icon.png" alt="Fireball" width="120" height="120">
</p>

# 🔥 Fireball

**Your music, anywhere.** A standalone, server-free music player for iOS and Android built with Flutter.

Fireball streams music through [Invidious](https://invidious.io), discovers lyrics via [LRCLIB](https://lrclib.net), tracks your listening with [ListenBrainz](https://listenbrainz.org), and keeps your library backed up to Google Drive or any WebDAV / Nextcloud server — all without a backend of its own.

---

## Features

| Category | Details |
|---|---|
| **Playback** | Stream audio via any Invidious instance · background playback (lock screen controls) · shuffle, repeat, queue management |
| **Discovery** | iTunes trending charts by country · search across Invidious · AI-generated queue via local Ollama |
| **Lyrics** | Synced (LRC) + plain lyrics from LRCLIB with structured multi-step fallback · NetEase fallback for Asian tracks |
| **Library** | Local-first JSON store (`path_provider`) · favorites, playlists, artists, albums · full play history |
| **Scrobbling** | Direct ListenBrainz scrobbling · Last.fm API key validation |
| **Backup & Sync** | Google Drive (`appDataFolder`) backup/restore · WebDAV / Nextcloud backup/restore · optional **live sync** with merge across devices |
| **Tablet UI** | iPad glass sidebar · Android NavigationRail · two-pane player and library on large screens |
| **Remote** | LAN HTTP remote control (optional) · QR / pairing code · in-app scanner on mobile |
| **Theming** | Material 3 · FlexColorScheme · dynamic color (Android 12+) · true-black dark mode option |

---

## Releases

Official binaries are published on **[GitHub Releases](https://github.com/just-for-death/fireball/releases)** (not stored in git). **Changelog:** [`CHANGELOG.md`](CHANGELOG.md).

| Version | Android | iOS |
|--------|---------|-----|
| **v1.5.0** (current) | `Fireball-1.5.0-android.apk` | `Fireball-1.5.0-ios-unsigned.ipa` — **unsigned** |
| **v1.0.0** | `Fireball-1.0.0-android.apk` | `Fireball-1.0.0-ios-unsigned.ipa` — **unsigned** |

- **Android**: Open the APK on device, or `adb install …`. You may need to allow installs from your file manager or developer options.
- **iOS**: IPAs are **not** signed for App Store distribution. Install with AltStore / Sideloadly, or sign with your Apple Developer account / CI.
- **Integrity**: Each release includes `SHA256SUMS.txt`. Verify with `sha256sum -c SHA256SUMS.txt` after downloading.

---

## Screenshots

> _Coming soon_

---

## Getting Started

### Prerequisites

- Flutter 3.x (stable channel)
- An [Invidious](https://api.invidious.io) instance URL (required for streaming)
- Optional: ListenBrainz user token, Ollama running locally

### Build

```bash
git clone https://github.com/just-for-death/fireball.git
cd fireball
flutter pub get
flutter run                    # attach a device or emulator
flutter build apk --release   # Android APK → build/app/outputs/flutter-apk/app-release.apk
flutter build ipa              # iOS (requires macOS + Xcode)
```

**Android / Gradle:** Use **JDK 17 or 21** for release builds. JDK 26+ can break Gradle’s Kotlin DSL (`IllegalArgumentException` parsing the Java version). On Arch Linux, for example: `export JAVA_HOME=/usr/lib/jvm/java-21-openjdk`. If the NDK error `CXX1101` / missing `source.properties` appears, remove the broken NDK folder under your Android SDK and rebuild so Gradle re-downloads it (see `android/gradle.properties` comments).

### First Run

1. Open **Settings → Invidious** and enter an instance URL (e.g. `https://invidious.snopyta.org`)
2. Optionally add your **ListenBrainz** token to enable scrobbling and personalized top tracks
3. Optionally sign in to **Google Drive** or configure **WebDAV** for library backups
4. Head to **Home** — trending charts load automatically

---

## Architecture

```
lib/
├── core/
│   ├── api/          fireball_api.dart   — direct calls to iTunes, LRCLIB, Invidious, LB, Ollama
│   ├── models/       track, playlist, artist, album, settings
│   ├── store/        local_store.dart (path_provider JSON) + Riverpod providers
│   └── widgets/      GlassCard, GlassPill, PremiumBackground
├── features/
│   ├── home/         trending grid, history, favorites, ListenBrainz sections
│   ├── search/       Invidious + iTunes search
│   ├── library/      favorites, playlists, artists, albums (tablet two-pane)
│   ├── player/       full-screen player, synced lyrics, queue (tablet side-by-side)
│   └── settings/     Invidious, ListenBrainz, Last.fm, Ollama, Backup & Sync
├── sync/
│   ├── gdrive_sync.dart    Google Drive appDataFolder backup/restore
│   └── webdav_sync.dart    WebDAV / Nextcloud PUT/GET
└── widgets/
    ├── shell_scaffold.dart  platform-adaptive nav (glass tab bar / sidebar / rail)
    └── mini_player.dart     floating now-playing bar (tablet-aware)
```

No server required. All data lives in `fireball_library.json` in the app's documents directory.

---

## Dependencies

| Package | Purpose |
|---|---|
| `media_kit` + `audio_service` | Streaming playback + background / lock screen |
| `hooks_riverpod` + `flutter_hooks` | State management |
| `go_router` | Declarative navigation |
| `path_provider` | Local JSON library store |
| `google_sign_in` + `googleapis` | Google Drive backup |
| `webdav_client` | WebDAV / Nextcloud backup |
| `flex_color_scheme` + `dynamic_color` | Theming |
| `cached_network_image` + `shimmer` | Image loading & skeletons |
| `http` | Direct API calls |

---

## License

MIT — see [LICENSE](LICENSE).
