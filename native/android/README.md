# Fireball Android (6.0)

Kotlin + Jetpack Compose · Media3 · `com.fireball.nativeapp`

## Modules

- **`app`** — UI, `MainViewModel`, playback service, navigation  
- **`core-model`** — `Track`, `FireballSettings`, scrobble/advance rules  
- **`core-data`** — API clients, persistence, Invidious, lyrics  

## Build

```bash
./gradlew :app:installDebug
./gradlew :app:assembleRelease
```

From repo root: `../scripts/build_native_apk.sh`

**Version:** `6.0.0` (`versionCode` 600) in `app/build.gradle.kts`.
