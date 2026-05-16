<p align="center">
  <img src="assets/icon.png" alt="Fireball" width="120" height="120">
</p>

# Fireball 6.0

**Your music, anywhere.** A standalone, server-free music player for **Android** and **iOS/iPadOS**, built with **Kotlin (Jetpack Compose)** and **Swift (SwiftUI)**.

Fireball streams via [Invidious](https://invidious.io) and on-device YouTube resolution, discovers lyrics through [LRCLIB](https://lrclib.net), scrobbles with [ListenBrainz](https://listenbrainz.org) and [Last.fm](https://www.last.fm), and keeps your library in a portable `fireball_library.json` — with optional WebDAV and Google Drive backup. **No Flutter. No backend of your own.**

The UI and motion language follow patterns from **[SuvMusic](https://github.com/suvojeet-sengupta/SuvMusic)**; playback, contracts, and integrations remain **Fireball-native**.

---

## Features

| Category | Details |
|---|---|
| **Playback** | Invidious + direct stream resolution · ExoPlayer (Android) / AVFoundation (iOS) · shuffle, repeat, queue · session restore **without autoplay** on cold start |
| **Discovery** | iTunes charts by region · search (songs + albums) · artist catalog (iTunes songs/albums) |
| **Lyrics** | LRCLIB + NetEase fallback · synced LRC · **long-press artwork** to toggle lyrics in the art slot · optional pinned lyrics panel |
| **Library** | Favorites, playlists, artists, albums, history · local JSON store |
| **Scrobbling** | ListenBrainz + Last.fm |
| **Integrations** | WebDAV live sync · Google Drive backup · Gotify · lbdl · LAN remote · Ollama AI queue |
| **Tablet / iPad** | Navigation rail / split view · pill mini-player variants · two-column Now Playing |
| **Platform** | Android foreground media service · iOS Now Playing + Live Activity widget extension |

See [`native/MIGRATION_MATRIX.md`](native/MIGRATION_MATRIX.md) for the full parity checklist.

---

## What's new in v6.0.0

- **Native-only:** Flutter app removed; `native/android` and `native/ios` are the product.
- **UI parity:** SuvMusic-inspired motion (`SuvFadeSlideIn`, `SuvPressScale`), pill mini-player, adaptive shell, bottom-sheet track actions.
- **Now Playing:** Long-press album art ↔ lyrics; overflow sheet; artist catalog from player; multi-artist picker.
- **Artist screen:** Songs + Albums tabs (no local Playlists tab — use Library).
- **Reliability:** Lyrics race guards, deduped track-started hooks, pinned-lyrics panel logic, release notifications (optional).

Full notes: [`CHANGELOG.md`](CHANGELOG.md).

---

## Releases

Official binaries: **[GitHub Releases](https://github.com/just-for-death/fireball/releases)**.

| Version | Android | iOS |
|--------|---------|-----|
| **v6.0.0** (current) | `Fireball-6.0.0-android.apk` | `Fireball-6.0.0-ios-unsigned.ipa` (unsigned) |

Verify with `SHA256SUMS.txt` on each release. iOS IPAs must be signed before device install (AltStore, Xcode, etc.).

---

## Getting started

### Prerequisites

| Platform | Tooling |
|----------|---------|
| **Android** | JDK **17 or 21**, Android SDK 36, Gradle (wrapper in `native/android`) |
| **iOS** | macOS + Xcode 15+ for device builds; **Swift 5.9+** on Linux for Core tests only |
| **Optional** | Invidious instance URL, ListenBrainz token, Ollama for AI queue |

### Clone and run

```bash
git clone https://github.com/just-for-death/fireball.git
cd fireball

# Android (device or emulator)
cd native/android && ./gradlew :app:installDebug

# iOS (macOS): generate Xcode project then open
cd native/ios && xcodegen generate && open FireballNative.xcodeproj
```

### Release builds

```bash
# Android APK (from repo root)
./scripts/build_native_apk.sh

# iOS unsigned IPA (macOS only)
./scripts/build_native_unsigned_ipa.sh dist/Fireball-6.0.0-ios-unsigned.ipa

# Automated tests (Linux-friendly for CI)
./scripts/qa.sh
```

**Codemagic:** [`codemagic.yaml`](codemagic.yaml) — workflows `fireball-android-release`, `fireball-native-ios`, `fireball-ios-unsigned-ipa`.

**JDK:** Use 17–21 for Android release builds. JDK 22+ can break Gradle’s Kotlin DSL.

### First run

1. **Settings → Invidious** — instance URL  
2. Optional: ListenBrainz, Last.fm, WebDAV / Google Drive  
3. **Home** — charts load by region  

Smoke test: [`native/SMOKE_TEST_CHECKLIST.md`](native/SMOKE_TEST_CHECKLIST.md).

**App icons:** generated from [`assets/icon.png`](assets/icon.png). After changing artwork, run `./scripts/generate_app_icons.sh`.

---

## Repository layout

```
fireball/
├── native/
│   ├── android/          Kotlin + Jetpack Compose app (:app, :core-model, :core-data)
│   ├── ios/              SwiftUI app + FireballWidgets (XcodeGen)
│   ├── MIGRATION_MATRIX.md
│   └── SMOKE_TEST_CHECKLIST.md
├── assets/               App icon & branding
├── scripts/              build_native_apk.sh, qa.sh, …
├── VERSION               6.0.0
├── codemagic.yaml
└── CHANGELOG.md
```

Data contract: `fireball_library.json` (`version`, `settings`, `history`, `favorites`, `playlists`, `artists`, `albums`, `playbackSession`).

---

## Architecture (native)

| Layer | Android | iOS |
|-------|---------|-----|
| UI | Compose screens, `FireballNativeApp` | SwiftUI `FireballNativeApp`, split/tab shell |
| State | `MainViewModel` + `PlayerManager` | `MainViewModel` + `NativeAudioEngine` |
| Domain | `:core-model` | `FireballNative/Core` |
| Services | `:core-data` (API, Invidious, lyrics, sync) | `FireballRepository`, `FireballAPIClient` |

Playback resolution order (Fireball): downloaded file → disk cache → direct URL → Invidious / InnerTube.

---

## License

MIT — see [LICENSE](LICENSE).

---

## Acknowledgements

Fireball 6.0 combines a **Fireball** backend and library model with **SuvMusic**-inspired UI/UX. We thank the authors of these projects and services:

| Project / service | Role in Fireball | Link |
|-------------------|------------------|------|
| **SuvMusic** | UI shell, motion, player chrome, adaptive layout patterns | [github.com/suvojeet-sengupta/SuvMusic](https://github.com/suvojeet-sengupta/SuvMusic) |
| **Invidious** | Privacy-oriented YouTube front-end / streaming API | [invidious.io](https://invidious.io) · [github.com/iv-org/invidious](https://github.com/iv-org/invidious) |
| **LRCLIB** | Synced and plain lyrics | [lrclib.net](https://lrclib.net) · [github.com/tranxuanthang/lrclib](https://github.com/tranxuanthang/lrclib) |
| **ListenBrainz** | Scrobbling and home feeds | [listenbrainz.org](https://listenbrainz.org) · [github.com/metabrainz/listenbrainz-server](https://github.com/metabrainz/listenbrainz-server) |
| **Last.fm** | Scrobble API | [last.fm](https://www.last.fm) · [last.fm/api](https://www.last.fm/api) |
| **iTunes Search API** | Charts, search, artist/album metadata | [Apple iTunes Search](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/) |
| **YouTubeKit** | Optional iOS stream metadata (Swift package) | [github.com/alexeichhorn/YouTubeKit](https://github.com/alexeichhorn/YouTubeKit) |
| **NewPipe Extractor** | Android YouTube stream extraction patterns | [github.com/TeamNewPipe/NewPipeExtractor](https://github.com/TeamNewPipe/NewPipeExtractor) |
| **Material 3 / Jetpack Compose** | Android design system | [m3.material.io](https://m3.material.io) |
| **SwiftUI** | iOS interface | [developer.apple.com/swiftui](https://developer.apple.com/swiftui/) |
| **ExoPlayer (Media3)** | Android playback engine | [developer.android.com/media/media3](https://developer.android.com/media/media3) |
| **Ollama** | Optional local AI queue generation | [ollama.com](https://ollama.com) · [github.com/ollama/ollama](https://github.com/ollama/ollama) |

NetEase lyrics and other providers are used only where configured in settings and subject to their respective terms.
