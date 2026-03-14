#!/bin/bash
set -e

ICONSET="Resources/VolumeIcon.iconset"
SOURCE="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ClippingPicture.icns"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

sips -z 16 16 "$SOURCE" --out "$ICONSET/icon_16x16.png" &>/dev/null
sips -z 32 32 "$SOURCE" --out "$ICONSET/icon_16x16@2x.png" &>/dev/null
sips -z 32 32 "$SOURCE" --out "$ICONSET/icon_32x32.png" &>/dev/null
sips -z 64 64 "$SOURCE" --out "$ICONSET/icon_32x32@2x.png" &>/dev/null
sips -z 128 128 "$SOURCE" --out "$ICONSET/icon_128x128.png" &>/dev/null
sips -z 256 256 "$SOURCE" --out "$ICONSET/icon_128x128@2x.png" &>/dev/null
sips -z 256 256 "$SOURCE" --out "$ICONSET/icon_256x256.png" &>/dev/null
sips -z 512 512 "$SOURCE" --out "$ICONSET/icon_256x256@2x.png" &>/dev/null
sips -z 512 512 "$SOURCE" --out "$ICONSET/icon_512x512.png" &>/dev/null

iconutil -c icns -o Resources/VolumeIcon.icns "$ICONSET"
rm -rf "$ICONSET"

echo "✓ Created Resources/VolumeIcon.icns"
ls -lh Resources/VolumeIcon.icns
