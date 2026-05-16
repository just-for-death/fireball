#!/usr/bin/env bash
# Generate Android mipmaps + adaptive layers and iOS AppIcon from assets/icon.png.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON="$ROOT/assets/icon.png"
MONO="$ROOT/assets/icon-monochrome.png"
ANDROID_RES="$ROOT/native/android/app/src/main/res"
IOS_SET="$ROOT/native/ios/FireballNative/Assets.xcassets/AppIcon.appiconset"

if ! command -v magick >/dev/null 2>&1; then
  echo "error: ImageMagick 'magick' is required." >&2
  exit 1
fi
if [[ ! -f "$ICON" ]]; then
  echo "error: missing $ICON" >&2
  exit 1
fi

echo "==> Android legacy mipmaps"
gen_mipmap() {
  local dens="$1" size="$2"
  local dir="$ANDROID_RES/mipmap-$dens"
  mkdir -p "$dir"
  magick "$ICON" -resize "${size}x${size}" -background none -gravity center -extent "${size}x${size}" \
    "$dir/ic_launcher.png"
  magick "$ICON" -resize "${size}x${size}^" -gravity center -extent "${size}x${size}" \
    \( +clone -fill black -colorize 100% -draw "circle $((size / 2)),$((size / 2)) $((size / 2)),0" \) \
    -alpha off -compose copy_opacity -composite \
    "$dir/ic_launcher_round.png"
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
  mkdir -p "$dir"
  local inset_px=$(( layer_px * 66 / 100 ))
  magick "$ICON" -resize "${inset_px}x${inset_px}" -background none -gravity center \
    -extent "${layer_px}x${layer_px}" "$dir/ic_launcher_foreground.png"
  if [[ -f "$MONO" ]]; then
    magick "$MONO" -resize "${inset_px}x${inset_px}" -background none -gravity center \
      -extent "${layer_px}x${layer_px}" "$dir/ic_launcher_monochrome.png"
  fi
}

gen_adaptive_layer mdpi 108
gen_adaptive_layer hdpi 162
gen_adaptive_layer xhdpi 216
gen_adaptive_layer xxhdpi 324
gen_adaptive_layer xxxhdpi 432

# nodpi fallback for devices that resolve drawable without density
mkdir -p "$ANDROID_RES/drawable-nodpi"
magick "$ICON" -resize 432x432 -background none -gravity center -extent 432x432 \
  "$ANDROID_RES/drawable-nodpi/ic_launcher_foreground.png"
if [[ -f "$MONO" ]]; then
  magick "$MONO" -resize 285x285 -background none -gravity center -extent 432x432 \
    "$ANDROID_RES/drawable-nodpi/ic_launcher_monochrome.png"
fi

echo "==> iOS AppIcon.appiconset"
mkdir -p "$IOS_SET"

ios_icon() {
  local px="$1" name="$2"
  magick "$ICON" -resize "${px}x${px}" -background none -gravity center -extent "${px}x${px}" \
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
