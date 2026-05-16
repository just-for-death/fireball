# Fireball iOS / iPadOS (6.0)

SwiftUI · AVFoundation · XcodeGen · Live Activity widget extension

## Layout

- **`FireballNative/`** — app target (UI + `MainViewModel`)  
- **`FireballNative/Core/`** — models, repository, API (SwiftPM `FireballNativeCore` on Linux)  
- **`FireballWidgets/`** — Live Activity extension  
- **`project.yml`** — XcodeGen spec (**6.0.0** / build 600)  

## Build (macOS)

```bash
xcodegen generate
open FireballNative.xcodeproj
```

Codemagic: `scripts/build-ios-codemagic.sh` · unsigned IPA: `../../scripts/build_native_unsigned_ipa.sh`

## Linux (CI / dev)

```bash
./scripts/verify-linux.sh   # swift test — no UI target
```
