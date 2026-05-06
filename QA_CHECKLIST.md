# Fireball QA Checklist

Use this checklist after major feature merges.

## Automated

- [ ] `flutter analyze` passes
- [ ] `flutter test` passes

## Settings Persistence

- [ ] Change `Invidious playlist privacy` and restart app -> value persists
- [ ] Change `ListenBrainz scrobble percent` and restart app -> value persists
- [ ] Change `ListenBrainz scrobble max seconds` and restart app -> value persists
- [ ] Change `Queue mode` (`off` / `repeat` / `ai`) and restart app -> value persists

## Queue Mode Behavior

- [ ] `off`: queue ends -> playback stops
- [ ] `repeat`: queue ends -> playback loops to first track
- [ ] `ai`: queue ends -> AI track is appended and playback continues (with valid Ollama config)
- [ ] `ai`: with invalid/missing Ollama config -> graceful failure, no crash

## Follow Artist Flows

- [ ] Artist screen follow/unfollow updates library correctly
- [ ] Player menu follow/unfollow updates library correctly
- [ ] Track options sheet follow/unfollow updates library correctly

## ListenBrainz

- [ ] Valid token: "Submit Playing Now" works
- [ ] Valid token: scrobble fires using configured thresholds
- [ ] Invalid token/offline: no crash, clear error feedback
- [ ] Home "Recently Played" section renders correctly
- [ ] Home "My Top Tracks" section renders correctly

## Invidious Playlist Privacy

- [ ] `private` applies when creating/pushing playlist
- [ ] `unlisted` applies when creating/pushing playlist
- [ ] `public` applies when creating/pushing playlist

## Core Regression Smoke

- [ ] Home loads and plays tracks
- [ ] Search works and plays tracks
- [ ] Artist screen loads and plays tracks
- [ ] Library tabs work (favorites/playlists/artists/albums/downloads/cached)
- [ ] Player controls work (play/pause, prev/next, seek, shuffle/repeat)
- [ ] WebDAV sync still works
- [ ] Remote pairing/control still works
- [ ] Downloads and cache behavior unchanged

## Final Signoff

- [ ] No blocker issues found
- [ ] Any known non-blockers documented
