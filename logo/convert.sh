#!/usr/bin/env bash
set -euo pipefail

cd ..

SOURCE="logo/appicon_big.png"
DEST="SilicIA/Assets.xcassets/AppIcon.appiconset"

if command -v magick >/dev/null 2>&1; then
	IM_CMD=(magick)
elif command -v convert >/dev/null 2>&1; then
	IM_CMD=(convert)
else
	echo "ImageMagick is required (magick or convert not found)." >&2
	exit 1
fi

"${IM_CMD[@]}" "$SOURCE" -resize 16x16   "$DEST/icon_16x16.png"
"${IM_CMD[@]}" "$SOURCE" -resize 32x32   "$DEST/icon_16x16@2x.png"
"${IM_CMD[@]}" "$SOURCE" -resize 32x32   "$DEST/icon_32x32.png"
"${IM_CMD[@]}" "$SOURCE" -resize 64x64   "$DEST/icon_32x32@2x.png"
"${IM_CMD[@]}" "$SOURCE" -resize 128x128 "$DEST/icon_128x128.png"
"${IM_CMD[@]}" "$SOURCE" -resize 256x256 "$DEST/icon_128x128@2x.png"
"${IM_CMD[@]}" "$SOURCE" -resize 256x256 "$DEST/icon_256x256.png"
"${IM_CMD[@]}" "$SOURCE" -resize 512x512 "$DEST/icon_256x256@2x.png"
"${IM_CMD[@]}" "$SOURCE" -resize 512x512 "$DEST/icon_512x512.png"
"${IM_CMD[@]}" "$SOURCE" -resize 1024x1024 "$DEST/icon_512x512@2x.png"

# iPhone/iPad + App Store marketing sizes
"${IM_CMD[@]}" "$SOURCE" -resize 20x20   "$DEST/icon_ios_20@1x.png"
"${IM_CMD[@]}" "$SOURCE" -resize 40x40   "$DEST/icon_ios_20@2x.png"
"${IM_CMD[@]}" "$SOURCE" -resize 60x60   "$DEST/icon_ios_20@3x.png"
"${IM_CMD[@]}" "$SOURCE" -resize 29x29   "$DEST/icon_ios_29@1x.png"
"${IM_CMD[@]}" "$SOURCE" -resize 58x58   "$DEST/icon_ios_29@2x.png"
"${IM_CMD[@]}" "$SOURCE" -resize 87x87   "$DEST/icon_ios_29@3x.png"
"${IM_CMD[@]}" "$SOURCE" -resize 40x40   "$DEST/icon_ios_40@1x.png"
"${IM_CMD[@]}" "$SOURCE" -resize 80x80   "$DEST/icon_ios_40@2x.png"
"${IM_CMD[@]}" "$SOURCE" -resize 120x120 "$DEST/icon_ios_40@3x.png"
"${IM_CMD[@]}" "$SOURCE" -resize 76x76   "$DEST/icon_ios_76@1x.png"
"${IM_CMD[@]}" "$SOURCE" -resize 152x152 "$DEST/icon_ios_76@2x.png"
"${IM_CMD[@]}" "$SOURCE" -resize 167x167 "$DEST/icon_ios_83_5@2x.png"
"${IM_CMD[@]}" "$SOURCE" -resize 120x120 "$DEST/icon_ios_60@2x.png"
"${IM_CMD[@]}" "$SOURCE" -resize 180x180 "$DEST/icon_ios_60@3x.png"
"${IM_CMD[@]}" "$SOURCE" -resize 1024x1024 "$DEST/icon_ios_marketing_1024.png"