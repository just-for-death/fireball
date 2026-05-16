# Fireball 6.0 QA Checklist

Use after major merges. Native app only (`native/android`, `native/ios`).

## Automated

- [ ] `./scripts/qa.sh` passes (Android unit tests + iOS Core `swift test` on Linux)
- [ ] `cd native/android && ./gradlew :app:compileDebugKotlin` (optional sanity)

## Settings persistence

- [ ] Invidious instance URL survives restart
- [ ] ListenBrainz scrobble percent / max seconds persist
- [ ] Queue mode (`off` / `repeat` / `ai`) persists
- [ ] `alwaysShowLyricsPanel` and appearance chrome source persist

## Playback

- [ ] Cold start: restored session does **not** autoplay
- [ ] Play / pause / next / previous; lock-screen controls (Android notification, iOS Control Center)
- [ ] Shuffle and repeat modes
- [ ] Sleep timer and sleep-after-current

## Now Playing & lyrics

- [ ] Long-press artwork toggles lyrics in art slot; long-press again shows art
- [ ] With `alwaysShowLyricsPanel`: extra strip when art visible; no duplicate when lyrics in slot
- [ ] ⋮ / ⋯ opens overflow sheet (play next, queue, favorite, playlists, artist)

## Library & artist

- [ ] Artist screen: Songs + Albums only
- [ ] Follow / unfollow artist; optional release notifications
- [ ] Playlist detail: no autoplay on open

## Integrations (smoke)

- [ ] ListenBrainz playing now / scrobble (valid token)
- [ ] WebDAV or Google Drive backup round-trip (if configured)

## Device matrix (recommended)

- [ ] Android phone (API 26+)
- [ ] Android tablet or foldable (rail layout)
- [ ] iPhone
- [ ] iPad (split Now Playing)
