# Fireball x SuvMusic Migration Matrix

**Fireball 6.0** — native-only (`native/android`, `native/ios`). Flutter was removed in v6.0.0.

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
  - Target: Fireball ListenBrainz primary + Last.fm scrobble (session via mobile auth)
- Backup/sync:
  - SuvMusic: DataStore/Room local focus
  - Target: Fireball WebDAV live sync + Google Drive appData backup
- Notifications:
  - SuvMusic: Android media + optional Discord
  - Target: Fireball Gotify optional new-release push + optional on-device/OS notifications (`notifyArtistReleasesOnDevice`) for followed artists (same baseline diff as Gotify probe)

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
- [x] Android Picture-in-Picture (settings: Picture-in-Picture)
- [x] iOS Live Activity + Dynamic Island widget extension (`FireballWidgets`)
- [x] Bluetooth autoplay (Android A2DP + iOS route change)
- [x] TTS song announcements (Android + iOS)
- [x] Last.fm validate + connect + scrobble/now-playing (Android + iOS)
- [x] Analytics/logging events gated by settings (Android + iOS)
- [x] Exo disk cache tied to `cacheEnabled` + `localMusicCacheLimit` (Android)
- [x] Flex/theme mode pickers + artwork dynamic color (Android + iOS)
- [x] LRC synced lyrics auto-scroll + reduced motion (Android + iOS)
- [x] Home chart regions, accent seed color, tablet sidebar collapse settings (Android + iOS)
- [x] Split search vs stream cache settings; Exo hot-reconfigure without full app restart (Android)
- [x] Home iTunes top charts by region + Gotify new-release check on boot (Android + iOS)
- [x] Playback/scrobble audit fixes (shuffle-on-end, AI queue append, session persist, scrobble thresholds, previous 3s seek, API 34+ BT receiver)
- [x] Full SuvMusic animation parity (SuvFadeSlideIn, SuvPressScale, PremiumBackground, staggered lists, mini-player + now-playing transitions)
- [x] Full audio engine parity + OS background media service parity (Exo wake lock + engine→UI sync, becoming-noisy; iOS route-change pause, stream disk cache, UIBackgroundModes audio, Now Playing + remote commands)
- [x] ListenBrainz Home feeds (recent + top by range) on Android/iOS
- [x] Follow artist (iTunes resolve) + Gotify release tracking
- [x] Follow-artist new releases — dual channel optional Gotify push + optional on-device local notifications (`notifyArtistReleasesOnDevice`; Android periodic WorkManager + POST_NOTIFICATIONS; iOS foreground refresh + authorization on toggle)
- [x] Appearance chrome source persisted as `appearanceColorSource` (`music` \| `scheme` \| Material You mapped on Android); album-art dynamic colors gated to `music` mode where applicable
- [x] Now Playing lyrics: **long-press artwork** toggles lyrics in art slot; optional extra strip via `alwaysShowLyricsPanel` when art shows cover (Android + iOS)
- [x] Now Playing queue panel + Invidious favorites auto-push playlist ID setting

## Native parity checklist (Android + iOS)

- [x] Search suggestions while typing (debounced, offline + remote)
- [x] Post-search **Songs / Albums** segmented results (iTunes album search)
- [x] **Artist catalog** screen: iTunes songs + albums (no Playlists tab; use Library for playlist browse)
- [x] **Navigate to artist** when name/id known (`requestArtistDetail`); Search prefill as fallback only
- [x] **Playlist detail** navigation (no autoplay on open); Play / Play next / Add to queue
- [x] Mini-player **Close** clears playback session + queue
- [x] Library toolbar: **New playlist** + **Follow artist**
- [x] Track overflow: **Follow artist** + **View artist catalog** (not “Search”)
- [x] **Long-press overflow** on Home rows (incl. saved albums), Search results/suggestions, Library history/favorites (grid + list), Now Playing queue (iOS + Android)
- [x] Overflow sheet stays open for non-current queue tracks (no auto-dismiss on track change)
- [x] **Appearance** `appearanceColorSource`: Android `material_you` \| `music` \| `scheme`; iOS `music` \| `scheme` (`material_you` → scheme)
- [x] Now Playing **⋮ menu**: play next, queue, favorite, view artist, follow, full overflow sheet
- [x] Lyrics: **long-press artwork** to show/hide in art slot; **`alwaysShowLyricsPanel`** adds secondary strip when art shows cover (not while lyrics fill the slot)
- [x] Session restore: **no autoplay** on cold start; lyrics prefetch for restored track (Android + iOS)
- [x] Artist from Now Playing: **immediate** catalog navigation; Follow/Unfollow on artist page + overflow sheet
- [x] Followed-artist **release alerts**: optional Gotify + optional device notifications; Android WorkManager ~15h; iOS foreground + optional `BGAppRefresh`
- [x] Artist screen **Notify on new releases** toggle when artist is followed
- [x] iPad split layout: playlist push, mini-player chrome, Now Playing parity
- [x] Album-only release probe (v1); song-level alerts out of scope
