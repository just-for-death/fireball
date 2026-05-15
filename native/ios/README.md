# Fireball iOS Native

Swift + SwiftUI app with the same playback stack as Android: **Invidious → portable YouTube (InnerTube) → optional YouTubeKit** when built on macOS CI.

You do **not** need a Mac. Develop on Linux; ship the app via **Codemagic** only.

## Stream resolution order

1. Local downloaded file  
2. Direct URL on the track (non–iTunes preview)  
3. Invidious (your instance, then public mirrors)  
4. **Portable InnerTube** (`YoutubeInnerTubeClient`) — works in the Linux-built Core library  
5. **YouTubeKit** (only when the app is built on macOS CI/Xcode with the package linked)

## Develop on Linux (no Xcode)

```bash
cd native/ios
./scripts/verify-linux.sh
```

This compiles `FireballNativeCore` and runs unit tests for Invidious ordering, YouTube search parsing, and InnerTube format selection.

Edit Swift under `FireballNative/` and re-run the script after changes.

## Ship the iOS app without owning a Mac

1. Push this repo to GitHub and connect it to [Codemagic](https://codemagic.io).  
2. Run workflow **`fireball-native-ios`** (see root `codemagic.yaml`).  
3. It runs on a **mac_mini_m2** worker: `xcodegen` → `xcodebuild` → `.app` artifact.  
4. For a device build, configure Apple signing in Codemagic (certificates + provisioning), set `CODE_SIGNING_ALLOWED=YES`, and use destination `generic/platform=iOS`.

`NativeAudioEngine.swift` is included in the Xcode app target via `project.yml` (AVFoundation). It is excluded from the Linux SPM target only.

Enable **Live Activity / Dynamic Island** in Settings; iOS 16.1+ shows now-playing in the island via the embedded `FireballWidgets` extension (built with the app on Codemagic).

## Project layout

| Path | Role |
|------|------|
| `FireballNative/Core/` | Repository, API, **YoutubeInnerTubeClient**, resolver |
| `FireballNative/App/` | SwiftUI shell, ViewModel, screens |
| `FireballNative/Shared/` | Live Activity attributes (app + widget extension) |
| `FireballWidgets/` | WidgetKit extension (Lock Screen + Dynamic Island UI) |
| `project.yml` | XcodeGen spec (generated on CI, not committed) |
| `Package.swift` | Linux-friendly Core library + tests |
| `scripts/verify-linux.sh` | Local verify |
| `scripts/build-ios-codemagic.sh` | macOS CI build |

## Fallback details (no Mac required for logic)

`YoutubeInnerTubeClient` calls YouTube’s `youtubei/v1/player` with several client profiles (Android Music, Android, iOS, Web), then falls back to `ytInitialPlayerResponse` from the watch page. Audio-only streams with direct `url` fields (no cipher) are selected; HLS manifests are used when present.

This is the same responsibility as **NewPipe** on Android, implemented in portable Swift so you can test it on Linux today and ship it in the iOS binary built in the cloud tomorrow.
