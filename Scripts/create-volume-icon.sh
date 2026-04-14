#!/bin/bash
set -euo pipefail

SOURCE_SVG="Resources/IconSources/clipboard-drive.svg"
OUTPUT_ICNS="Resources/VolumeIcon.icns"
WORK_DIR="$(mktemp -d /tmp/clipboard-fs-icon.XXXXXX)"
MASTER_PNG="$WORK_DIR/master.png"
ICONSET="$WORK_DIR/VolumeIcon.iconset"

cleanup() {
	rm -rf "$WORK_DIR"
}

trap cleanup EXIT

mkdir -p "$ICONSET"

# Rasterize the SVG source once at 1024x1024, then downscale into the iconset.
sips -s format png "$SOURCE_SVG" --out "$MASTER_PNG" >/dev/null

sips -z 16 16 "$MASTER_PNG" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$MASTER_PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$MASTER_PNG" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$MASTER_PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$MASTER_PNG" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$MASTER_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$MASTER_PNG" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$MASTER_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$MASTER_PNG" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$MASTER_PNG" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns -o "$OUTPUT_ICNS" "$ICONSET"

echo "Created $OUTPUT_ICNS from $SOURCE_SVG"
ls -lh "$OUTPUT_ICNS"
