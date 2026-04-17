# Fireball branding

Use the same mark everywhere:

| Location | File |
|----------|------|
| App bundle / Flutter assets | [`assets/icon.png`](../assets/icon.png) |
| Android 13+ themed / monochrome launcher | [`assets/icon-monochrome.png`](../assets/icon-monochrome.png) (white silhouette; regenerate if you change `icon.png`) |
| GitHub (raw URL, social preview, org avatar) | [`.github/fireball-logo.png`](fireball-logo.png) (copy of `assets/icon.png`) |

**Android adaptive icons:** `flutter_launcher_icons` builds `mipmap-anydpi-v26/launcher_icon.xml` with a **foreground** (`assets/icon.png`), **background** color `#050505`, **22% inset** (safe zone for circle, squircle, rounded-square OEM masks), and optional **monochrome** layer for themed icons.

**Repository social preview:** Settings → General → Social preview → Upload an image. Use `.github/fireball-logo.png` or any 1200×630 banner that includes this mark.

**README:** Centered image points at `assets/icon.png` so it renders on the default GitHub view of the `fireball` folder.

**Regenerate launcher assets after changing the artwork:** `flutter pub run flutter_launcher_icons`
