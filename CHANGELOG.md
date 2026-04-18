# Changelog

All notable changes to **Fireball** are documented here. Release binaries live on [GitHub Releases](https://github.com/just-for-death/fireball/releases).

## [1.6.0] — 2026-04-18

### Remote (LAN)

- **Remote tab**: Bottom navigation (and iPad sidebar) includes a **Remote** destination — pairing, host QR, scan, and control in one place. Settings keeps a shortcut row only.
- **Single QR code** on the host: `http://<ip>:7771` (works with Fireball’s scanner and generic scanners). Pairing code + copy buttons unchanged.
- **Bidirectional pairing**: `POST /pair` on the remote HTTP server registers the caller’s address. After you scan or enter a code, this device saves the peer **and** notifies them so **both** can tap **Control** without typing the other’s IP (both devices should enable the remote server on the same Wi‑Fi).
- **`remotePeerPort`** in settings for non-default ports.
- **Mini player** is hidden on the Remote tab and when **RemoteScreen** (host/control) is open (`remoteScreenCoversShellProvider`), so the strip never covers remote UIs. Full-screen routes use the root navigator where needed.

### Android / iOS UI & polish

- **Scroll insets**: Shared `shellScrollBottomPadding` so Home, Search, Library, and Settings lists clear the bottom nav + mini-player + system gesture inset.
- **Remote hub**: Narrow screens stack **Scan QR** / **Host QR** and control actions; shorter labels + tooltips avoid clipped buttons.
- **Text overflow**: Ellipsis / bounded lines on empty states, settings rows, sync/danger buttons, playlist tiles, queue subtitles, remote error rows, glass tab labels, navigation rail labels, iPad sidebar nav, and search header.
- **Shell mini-player**: **AnimatedSwitcher** fade when hiding/showing; bottom offset uses **`80 + MediaQuery.viewPadding.bottom`** on **iPhone and Android** (aligned with gesture/home indicator). iPad sidebar mini uses the same fade without re-animating on sidebar collapse.

### Downloads (v1.6.0)

| Platform | Asset name |
|----------|------------|
| Android | `Fireball-1.6.0-android.apk` |
| iOS | `Fireball-1.6.0-ios-unsigned.ipa` (unsigned — sideload / your signing) |

**pubspec**: `1.6.0+3`. After building locally, copy artifacts into `dist/` and regenerate checksums:

```bash
cp build/app/outputs/flutter-apk/app-release.apk dist/Fireball-1.6.0-android.apk
cp fireball_unsigned.ipa dist/Fireball-1.6.0-ios-unsigned.ipa   # from scripts/build_unsigned_ipa.sh on macOS
( cd dist && sha256sum Fireball-1.6.0-android.apk Fireball-1.6.0-ios-unsigned.ipa > SHA256SUMS.txt )
```

Verify with `sha256sum -c SHA256SUMS.txt`. Upload **`dist/`** assets + `SHA256SUMS.txt` to [GitHub Releases](https://github.com/just-for-death/fireball/releases) for tag **v1.6.0**.

## [1.5.0] — 2026-04-18

### Sync & library

- **WebDAV live sync**: Pulling a newer remote `library.json` **merges** libraries (history, favorites, playlists, artists, albums) instead of replacing the whole device, so two devices are less likely to wipe each other’s edits.
- **Periodic sync**: Optional background check every few minutes while the app runs (when live sync is enabled).
- **Shared settings merge**: Account-related fields from the remote library merge without overwriting local theme / iPad layout / remote-server preferences.

### Remote control

- **Pairing**: Short **pairing code** (IP + port encoded) plus **QR** for Fireball (`fbremote://…`) and a second QR for plain `http://` scanning.
- **In-app QR scan** (Android/iOS) to connect without typing an IP.
- **LAN IP selection** prefers private IPv4 when multiple interfaces exist.
- **Android**: Cleartext HTTP allowed for LAN remote URLs.
- **Hostname**: Manual entry accepts `host:port` for `.local` / mDNS names, not only IPv4.

### Android

- **Thumbnails**: Protocol-relative artwork URLs (`//…`) normalized for image loading.
- **Mini player**: Extra bottom inset on Android so the bar clears gesture/navigation areas.

### Tooling

- **Codemagic**: Workflows default to marketing version **1.5.0**; `scripts/build_apk.sh` prefers JDK 21 for Gradle compatibility.

### Downloads (v1.5.0)

| Platform | Asset name |
|----------|------------|
| Android | `Fireball-1.5.0-android.apk` |
| iOS | `Fireball-1.5.0-ios-unsigned.ipa` (unsigned — sideload / your signing) |

Verify downloads with `SHA256SUMS.txt` on the release.

---

## [1.0.0] — 2025 (first release)

Initial public release: Invidious playback, library, lyrics, ListenBrainz, Google Drive & WebDAV backup, tablet UI, Material 3 / dynamic color. See GitHub release [v1.0.0](https://github.com/just-for-death/fireball/releases/tag/v1.0.0) for assets and checksums.

[1.6.0]: https://github.com/just-for-death/fireball/releases/tag/v1.6.0
[1.5.0]: https://github.com/just-for-death/fireball/releases/tag/v1.5.0
[1.0.0]: https://github.com/just-for-death/fireball/releases/tag/v1.0.0
