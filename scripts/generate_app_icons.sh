#!/usr/bin/env bash
# Generate Android mipmaps + adaptive layers and iOS AppIcon from assets/icon.png.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON="$ROOT/assets/icon.png"
MONO="$ROOT/assets/icon-monochrome.png"
ANDROID_RES="$ROOT/native/android/app/src/main/res"
IOS_SET="$ROOT/native/ios/FireballNative/Assets.xcassets/AppIcon.appiconset"
BRAND_RED="#BF2026"
# Match Android adaptive-icon safe zone (72dp in 108dp layer).
ADAPTIVE_INSET_PERCENT=66
# Legacy / iOS launcher: creature scale inside the square canvas.
LEGACY_INSET_PERCENT=82

if ! command -v magick >/dev/null 2>&1; then
  echo "error: ImageMagick 'magick' is required." >&2
  exit 1
fi
if [[ ! -f "$ICON" ]]; then
  echo "error: missing $ICON" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Preparing foreground (transparent background)"
# Launcher background is brand red; use the white monochrome mark so the creature stays visible.
# (Red-on-black source art disappears when composited on #BF2026.)
if [[ -f "$MONO" ]]; then
  magick "$MONO" -alpha set -fuzz 14% -transparent black "$TMP/creature.png"
else
  magick "$ICON" -alpha set -fuzz 14% -transparent black "$TMP/creature.png"
fi

echo "==> Android legacy mipmaps"
gen_mipmap() {
  local dens="$1" size="$2"
  local dir="$ANDROID_RES/mipmap-$dens"
  local inner=$(( size * LEGACY_INSET_PERCENT / 100 ))
  mkdir -p "$dir"
  magick -size "${size}x${size}" "xc:$BRAND_RED" \
    \( "$TMP/creature.png" -resize "${inner}x${inner}" \) \
    -gravity center -composite \
    "$dir/ic_launcher.png"
  cp "$dir/ic_launcher.png" "$dir/ic_launcher_round.png"
}

gen_mipmap mdpi 48
gen_mipmap hdpi 72
gen_mipmap xhdpi 96
gen_mipmap xxhdpi 144
gen_mipmap xxxhdpi 192

echo "==> Android adaptive foreground + monochrome"
gen_adaptive_layer() {
  local folder="$1" layer_px="$2"
  local dir="$ANDROID_RES/drawable-$folder"
  local inset_px=$(( layer_px * ADAPTIVE_INSET_PERCENT / 100 ))
  mkdir -p "$dir"
  magick "$TMP/creature.png" -resize "${inset_px}x${inset_px}" -background none -gravity center \
    -extent "${layer_px}x${layer_px}" "$dir/ic_launcher_foreground.png"
  if [[ -f "$MONO" ]]; then
    local mono_inset=$(( layer_px * ADAPTIVE_INSET_PERCENT / 100 ))
    magick "$MONO" -resize "${mono_inset}x${mono_inset}" -background none -gravity center \
      -extent "${layer_px}x${layer_px}" "$dir/ic_launcher_monochrome.png"
  fi
}

gen_adaptive_layer mdpi 108
gen_adaptive_layer hdpi 162
gen_adaptive_layer xhdpi 216
gen_adaptive_layer xxhdpi 324
gen_adaptive_layer xxxhdpi 432

mkdir -p "$ANDROID_RES/drawable-nodpi"
magick "$TMP/creature.png" -resize $(( 432 * ADAPTIVE_INSET_PERCENT / 100 ))x$(( 432 * ADAPTIVE_INSET_PERCENT / 100 )) \
  -background none -gravity center -extent 432x432 \
  "$ANDROID_RES/drawable-nodpi/ic_launcher_foreground.png"
if [[ -f "$MONO" ]]; then
  magick "$MONO" -resize $(( 432 * ADAPTIVE_INSET_PERCENT / 100 ))x$(( 432 * ADAPTIVE_INSET_PERCENT / 100 )) \
    -background none -gravity center -extent 432x432 \
    "$ANDROID_RES/drawable-nodpi/ic_launcher_monochrome.png"
fi

echo "==> Android adaptive-icon XML (API 26+)"
mkdir -p "$ANDROID_RES/mipmap-anydpi-v26"
rm -f "$ANDROID_RES/mipmap-anydpi/ic_launcher.xml" "$ANDROID_RES/mipmap-anydpi/ic_launcher_round.xml"
rmdir "$ANDROID_RES/mipmap-anydpi" 2>/dev/null || true

cat > "$ANDROID_RES/mipmap-anydpi-v26/ic_launcher.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
XML

cp "$ANDROID_RES/mipmap-anydpi-v26/ic_launcher.xml" \
  "$ANDROID_RES/mipmap-anydpi-v26/ic_launcher_round.xml"

echo "==> iOS AppIcon.appiconset"
mkdir -p "$IOS_SET"

ios_icon() {
  local px="$1" name="$2"
  local inner=$(( px * LEGACY_INSET_PERCENT / 100 ))
  magick -size "${px}x${px}" "xc:$BRAND_RED" \
    \( "$TMP/creature.png" -resize "${inner}x${inner}" \) \
    -gravity center -composite \
    "$IOS_SET/$name"
}

ios_icon 40 Icon-20@2x.png
ios_icon 60 Icon-20@3x.png
ios_icon 58 Icon-29@2x.png
ios_icon 87 Icon-29@3x.png
ios_icon 80 Icon-40@2x.png
ios_icon 120 Icon-40@3x.png
ios_icon 120 Icon-60@2x.png
ios_icon 180 Icon-60@3x.png
ios_icon 20 Icon-20.png
ios_icon 40 Icon-20@2x-ipad.png
ios_icon 29 Icon-29.png
ios_icon 58 Icon-29@2x-ipad.png
ios_icon 40 Icon-40.png
ios_icon 80 Icon-40@2x-ipad.png
ios_icon 76 Icon-76.png
ios_icon 152 Icon-76@2x.png
ios_icon 167 Icon-83.5@2x.png
ios_icon 1024 Icon-1024.png

cat > "$IOS_SET/Contents.json" <<'JSON'
{
  "images": [
    { "filename": "Icon-20@2x.png", "idiom": "iphone", "scale": "2x", "size": "20x20" },
    { "filename": "Icon-20@3x.png", "idiom": "iphone", "scale": "3x", "size": "20x20" },
    { "filename": "Icon-29@2x.png", "idiom": "iphone", "scale": "2x", "size": "29x29" },
    { "filename": "Icon-29@3x.png", "idiom": "iphone", "scale": "3x", "size": "29x29" },
    { "filename": "Icon-40@2x.png", "idiom": "iphone", "scale": "2x", "size": "40x40" },
    { "filename": "Icon-40@3x.png", "idiom": "iphone", "scale": "3x", "size": "40x40" },
    { "filename": "Icon-60@2x.png", "idiom": "iphone", "scale": "2x", "size": "60x60" },
    { "filename": "Icon-60@3x.png", "idiom": "iphone", "scale": "3x", "size": "60x60" },
    { "filename": "Icon-20.png", "idiom": "ipad", "scale": "1x", "size": "20x20" },
    { "filename": "Icon-20@2x-ipad.png", "idiom": "ipad", "scale": "2x", "size": "20x20" },
    { "filename": "Icon-29.png", "idiom": "ipad", "scale": "1x", "size": "29x29" },
    { "filename": "Icon-29@2x-ipad.png", "idiom": "ipad", "scale": "2x", "size": "29x29" },
    { "filename": "Icon-40.png", "idiom": "ipad", "scale": "1x", "size": "40x40" },
    { "filename": "Icon-40@2x-ipad.png", "idiom": "ipad", "scale": "2x", "size": "40x40" },
    { "filename": "Icon-76.png", "idiom": "ipad", "scale": "1x", "size": "76x76" },
    { "filename": "Icon-76@2x.png", "idiom": "ipad", "scale": "2x", "size": "76x76" },
    { "filename": "Icon-83.5@2x.png", "idiom": "ipad", "scale": "2x", "size": "83.5x83.5" },
    { "filename": "Icon-1024.png", "idiom": "ios-marketing", "scale": "1x", "size": "1024x1024" }
  ],
  "info": { "author": "generate_app_icons.sh", "version": 1 }
}
JSON

mkdir -p "$(dirname "$IOS_SET")"
cat > "$(dirname "$IOS_SET")/Contents.json" <<'JSON'
{
  "info": { "author": "generate_app_icons.sh", "version": 1 }
}
JSON

echo "OK: icons written under native/android/.../res and native/ios/.../AppIcon.appiconset"
