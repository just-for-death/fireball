# Fireball Native Smoke Test (10-Minute)

Fast sanity pass for daily verification after code changes.

## 1) Launch + Persistence (1 min)

- [ ] Open app (Android + iOS), confirm no startup crash.
- [ ] Verify previous state exists (history/settings/favorites survive relaunch).

## 2) Search + Play (2 min)

- [ ] Search a known song.
- [ ] Tap Play and confirm audio starts.
- [ ] Confirm now-playing title/artist updates in UI.

## 3) Playback Controls + Background (2 min)

- [ ] Pause/Play/Next/Previous from in-app controls.
- [ ] Background app and control from notification/lockscreen.
- [ ] Confirm controls and UI remain in sync.

## 4) Queue/Timer Logic (1 min)

- [ ] Toggle Shuffle once and Repeat once.
- [ ] Set Sleep 15m then clear it.
- [ ] Enable/disable sleep-after-current toggle.

## 5) Lyrics + AI Queue (1 min)

- [ ] Start a track and confirm lyrics text appears (if available).
- [ ] With Ollama enabled, confirm queue-end AI append occurs (or fails gracefully without crash).

## 6) Core Integrations (2 min)

- [ ] WebDAV Push action returns status (success/fail).
- [ ] Gotify Test returns status.
- [ ] LBDL Status returns status.
- [ ] Remote Toggle returns status.

## 7) Status Message Consistency (1 min)

- [ ] Verify status text format is consistent across Android/iOS:
  - `gotify: success|failed`
  - `lbdl auth: success|failed`
  - `lbdl job: success (...)|failed`
  - `remote command: success|failed`
  - `remote pair: success|failed`
  - `gdrive backup: success|failed`

---

## Smoke Pass Criteria

- No crashes.
- Play/search/control loop works.
- Integration actions show explicit status.
- No obvious desync between UI and actual playback state.
