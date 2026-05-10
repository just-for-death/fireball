# Fireball Native Runtime Test Checklist

Use this checklist to validate Android and iOS replacements against Fireball behavior contracts.

## Test Environment

- Use a real network connection (required for iTunes/Invidious/LRCLIB/NetEase/integrations).
- Have valid credentials/tokens ready:
  - Invidious instance URL
  - ListenBrainz token
  - WebDAV URL/username/password
  - Gotify URL/token
  - lbdl URL/username/password
  - Google OAuth access token (Drive appData test)

---

## 1) App Boot + Persistence

- [ ] Launch app first time; no crash.
- [ ] Close app and relaunch; settings/history/favorites persist.
- [ ] Confirm persisted file schema remains `fireball_library.json` contract.

Pass criteria:
- No startup crash, previous state restored correctly.

---

## 2) Search Pipeline (Fireball services)

- [ ] Search a popular track; verify results appear (iTunes path).
- [ ] Disable/limit iTunes scenario (or query obscure video-only item) and verify Invidious fallback works.
- [ ] Play a search result and verify now-playing metadata updates.

Pass criteria:
- iTunes-first behavior with Invidious fallback.

---

## 3) Playback Core (OS Native)

- [ ] Play/Pause/Next/Previous from in-app controls.
- [ ] Background app; control playback from notification/lockscreen.
- [ ] Unplug headphones (Android noisy route); playback should pause safely.
- [ ] Verify progress/duration in UI updates while playing.

Pass criteria:
- In-app and OS controls stay synchronized.

---

## 4) Queue Semantics

- [ ] Toggle shuffle and confirm next track randomization.
- [ ] Cycle repeat off -> all -> one and verify behavior at queue end.
- [ ] Enable sleep timer (15m) and verify auto-pause at expiration.
- [ ] Enable sleep-after-current and verify pause at track end.

Pass criteria:
- Queue and timer behavior matches Fireball semantics.

---

## 5) Lyrics Pipeline

- [ ] Play track with known lyrics; verify lyrics are fetched.
- [ ] Confirm LRCLIB used when available.
- [ ] Confirm NetEase fallback when LRCLIB unavailable.
- [ ] Toggle `lyricsPreferEnglishHindi` and verify better candidate preference on mixed-language songs.

Pass criteria:
- LRCLIB -> NetEase fallback works; preference flag influences selection.

---

## 6) AI Queue (Ollama)

- [ ] Enable Ollama in settings with valid URL/model.
- [ ] Play near queue tail and verify AI suggestions append.
- [ ] Verify playback does not reset/restart unexpectedly when AI appends.
- [ ] Verify `AI Queue` playlist persists generated entries.

Pass criteria:
- Queue expands non-disruptively and persists.

---

## 7) ListenBrainz

- [ ] Enable ListenBrainz + token.
- [ ] Confirm `playing_now` is submitted when playback starts (if enabled).
- [ ] Play past scrobble threshold:
  - threshold = min(percent setting, max-seconds setting)
- [ ] Confirm exactly one scrobble per track play.

Pass criteria:
- Threshold timing and one-shot scrobble behavior are correct.

---

## 8) WebDAV Sync

- [ ] Run WebDAV Push; confirm remote file updated.
- [ ] Modify remote file from another client/device.
- [ ] Run WebDAV Pull+Merge; verify merged history/favorites/playlists/artists/albums.

Pass criteria:
- Push/pull complete successfully; merge rules behave as expected.

---

## 9) Google Drive Backup

- [ ] Trigger backup with valid OAuth access token.
- [ ] Confirm upload to Drive `appDataFolder` as `fireball_library.json`.
- [ ] Restore/download manually and inspect JSON shape.

Pass criteria:
- Backup upload succeeds and payload is valid Fireball schema.

---

## 10) Gotify

- [ ] Configure Gotify URL/token.
- [ ] Run Gotify test action.
- [ ] Confirm message arrives in Gotify app/server.

Pass criteria:
- Status shows success and push notification is received.

---

## 11) lbdl

- [ ] Run lbdl auth status check with valid credentials.
- [ ] Queue tracks with URLs and trigger lbdl job creation.
- [ ] Confirm job id is returned and visible in server logs/UI.

Pass criteria:
- Auth and job creation both succeed with proper status messaging.

---

## 12) Remote LAN

- [ ] Set host/port to a compatible Fireball remote server.
- [ ] Send remote toggle command; verify peer playback toggles.
- [ ] Pair with valid code via `/pair` endpoint.

Pass criteria:
- Remote command + pairing both succeed and status text matches.

---

## 13) Cross-Platform UX Consistency

- [ ] Android and iOS settings action labels/order match.
- [ ] Integration status messages match exact wording:
  - `gotify: success|failed`
  - `lbdl auth: success|failed`
  - `lbdl job: success (...)|failed`
  - `remote command: success|failed`
  - `remote pair: success|failed`
  - `gdrive backup: success|failed`

Pass criteria:
- Same semantics and user-visible messaging on both platforms.

---

## 14) Regression Sweep

- [ ] Re-run core flow: Search -> Play -> Lyrics -> Queue ops -> Settings integration actions.
- [ ] Force network failure (disable internet) and verify graceful failure statuses.
- [ ] Relaunch app and verify no data corruption.

Pass criteria:
- No crashes, no silent failures, no corrupted persisted data.
