# Fireball Native (6.0)

This directory is the **entire** Fireball application for Android and iOS/iPadOS.

| Path | Stack |
|------|--------|
| [`android/`](android/) | Kotlin · Jetpack Compose · Media3 · Gradle multi-module (`app`, `core-model`, `core-data`) |
| [`ios/`](ios/) | Swift · SwiftUI · XcodeGen · `FireballWidgets` extension |

## Principles

1. **Fireball** owns data (`fireball_library.json`), settings keys, playback resolution, and integrations.
2. **SuvMusic** inspires UI layout, motion, and player chrome (see [Acknowledgements](../README.md#acknowledgements)).
3. **Feature parity** between Android and iOS where the platform allows.

## Build

```bash
# Android
cd android && ./gradlew :app:installDebug

# iOS (macOS)
cd ios && xcodegen generate && open FireballNative.xcodeproj

# Tests from repo root
../scripts/qa.sh
```

## Docs

- [`MIGRATION_MATRIX.md`](MIGRATION_MATRIX.md) — parity checklist  
- [`SMOKE_TEST_CHECKLIST.md`](SMOKE_TEST_CHECKLIST.md) — 10-minute device pass  

Version: [`../VERSION`](../VERSION) (currently **6.0.0**).
