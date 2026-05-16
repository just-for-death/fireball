# Fireball branding

| Location | File |
|----------|------|
| README / social | [`assets/icon.png`](../assets/icon.png) |
| Monochrome (optional) | [`assets/icon-monochrome.png`](../assets/icon-monochrome.png) |
| GitHub org / preview | [`.github/fireball-logo.png`](fireball-logo.png) |
| Android launcher | `native/android/app/src/main/res/` (vector adaptive icons) |

Regenerate launcher icons for **both platforms** after changing artwork:

```bash
./scripts/generate_app_icons.sh
```

Source: `assets/icon.png` (1024×1024, red mark for README/social) and `assets/icon-monochrome.png` (white mark for launcher foregrounds and Android 13+ themed icon). The generator composites the white mark on `#BF2026` so adaptive icons do not show a black box on a red tile.

**Version:** see [`VERSION`](../VERSION) and `native/android/app/build.gradle.kts` / `native/ios/project.yml`.
