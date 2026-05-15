# Fireball x SuvMusic Migration Matrix

## Source-of-Truth Rules

- Backend/services/contracts: **Fireball**
- UI/UX patterns/animations/screen architecture: **SuvMusic**
- Conflict resolution: always prefer Fireball providers and behavior

## Service Mapping

- Search/discovery:
  - SuvMusic: YouTube + NewPipe extraction
  - Target: Fireball iTunes + Invidious fallback
- Streaming URL resolution:
  - SuvMusic: YouTube stream repository
  - Target: Fireball resolver order (downloaded -> cache -> direct URL -> Invidious resolution/search)
- Lyrics:
  - SuvMusic: modular providers
  - Target: Fireball LRCLIB first, NetEase fallback, local `.lrc`
- Scrobbling:
  - SuvMusic: Last.fm module
  - Target: Fireball ListenBrainz primary + Last.fm key validation support
- Backup/sync:
  - SuvMusic: DataStore/Room local focus
  - Target: Fireball WebDAV live sync + Google Drive appData backup
- Notifications:
  - SuvMusic: Android media + optional Discord
  - Target: Fireball Gotify new-release notifications

## Data Contract Mapping

- Preserve Fireball `fireball_library.json` envelope:
  - `version`
  - `settings`
  - `history`
  - `favorites`
  - `playlists`
  - `artists`
  - `albums`
- Preserve settings keys and defaults exactly from Fireball.

## Screen Blueprint (SuvMusic UI x Fireball Brain)

- Home: SuvMusic layout/animation; Fireball charts/recommendations/listen history sources.
- Search: SuvMusic search UX; Fireball iTunes + Invidious query pipeline.
- Library: SuvMusic tab/paging UI; Fireball playlist/favorites/artist/album logic.
- Player: SuvMusic player style variants + sheets; Fireball playback/queue/lyrics/scrobble rules.
- Settings: SuvMusic information architecture; Fireball settings semantics and integration toggles.

## Implementation Status

- [x] Native folder + migration docs
- [x] Android domain model mirror of Fireball contracts
- [x] Android Fireball API scaffolding
- [x] Android persistence skeleton for `fireball_library.json`
- [x] Android Compose root shell
- [x] iOS domain model mirror of Fireball contracts
- [x] iOS Fireball API scaffolding
- [x] iOS persistence skeleton for `fireball_library.json`
- [x] iOS adaptive root shell (TabView + NavigationSplitView)
- [x] Android repository + viewmodel + functional Home/Search/Library/Settings flows
- [x] Android playback semantics (shuffle/repeat/sleep controls) foundation
- [x] Android integrations foundation (ListenBrainz, SponsorBlock, WebDAV sync client)
- [x] Android Media3 playback service/controller foundation (media session + foreground playback service wiring)
- [x] Android engine-to-UI playback synchronization (index/play-state/progress) + sleep timer enforcement loop
- [x] Android audio-focus/noisy-route handling baseline + sleep-after-current guardrails
- [x] Android ListenBrainz scrobble threshold timing (percent/max-seconds) baseline
- [x] Android lyrics fallback pipeline baseline (LRCLIB -> NetEase) + surfaced current lyric text
- [x] iOS repository + viewmodel + functional Home/Search/Library/Settings flows
- [x] iOS fallback: portable InnerTube (`YoutubeInnerTubeClient`) + optional YouTubeKit on CI; Linux tests; Codemagic `fireball-native-ios`
- [x] iOS playback semantics (shuffle/repeat/sleep controls) foundation
- [x] iOS integrations foundation (ListenBrainz, SponsorBlock, WebDAV sync client)
- [x] iOS native audio foundation (AVAudioSession + Now Playing + remote transport commands)
- [x] iOS engine-to-UI playback synchronization (index/play-state/progress) + sleep timer enforcement loop
- [x] iOS interruption handling + track-end behavior hooks (sleep-after-current / repeat-one / next)
- [x] iOS ListenBrainz scrobble threshold timing (percent/max-seconds) baseline
- [x] iOS lyrics fallback pipeline baseline (LRCLIB -> NetEase) + surfaced current lyric text
- [x] Queue-end AI append hooks via Ollama settings on Android/iOS
- [x] Gotify integration client hooks on Android/iOS
- [x] lbdl integration client hooks on Android/iOS
- [x] LAN remote command client hooks on Android/iOS
- [x] Google Drive appData backup client scaffolds on Android/iOS
- [x] Lyrics preference scoring baseline (English/Hindi preference) on Android/iOS
- [x] AI queue persistence baseline into local library playlists on Android/iOS
- [x] Integration status/error UX baseline in Settings on Android/iOS
- [x] Remote pairing endpoint hooks on Android/iOS
- [x] Network timeout+retry baseline for integrations on Android/iOS
- [x] Unified integration status messaging across Android/iOS
- [ ] Full SuvMusic animation parity
- [ ] Full audio engine parity + OS background media service parity
