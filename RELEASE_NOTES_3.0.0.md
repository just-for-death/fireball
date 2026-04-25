# Fireball v3.0.0

## Highlights

- Fixed iOS unsigned IPA pipeline reliability in Codemagic (CocoaPods/xcconfig integration hardening).
- Pinned `audiotags` to a known-good iOS build (`1.4.2`) to avoid missing FRB linker symbols.
- Added CI safeguards to `scripts/build_unsigned_ipa.sh` for podspec and xcconfig resilience.
- Fixed multiple race conditions across remote polling, lbdl job polling, and local store restore/init ordering.
- Improved WebDAV live sync safety (skip when remote freshness is unknown, avoid overlapping sync runs).
- Hardened download/cache pipeline with streamed network writes and timeouts to reduce memory pressure.
- Improved search async consistency and URL proxy query handling for signed stream URLs.

## Assets

- Android APK: `Fireball-3.0.0-android.apk`
- iOS unsigned IPA: `Fireball-3.0.0-ios-unsigned.ipa`
- Checksums: `SHA256SUMS.txt`

## Notes

- iOS artifact is unsigned and must be signed/sideloaded by the user.
- Full detailed change history is in `CHANGELOG.md`.
