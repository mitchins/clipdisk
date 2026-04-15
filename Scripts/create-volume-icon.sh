#!/bin/bash
# Generate AppIcon.icns (app bundle) and VolumeIcon.icns (RAM disk volume)
# from the master app-icon.png (must be 1024x1024).
set -euo pipefail

SOURCE_PNG="app-icon.png"
WORK_DIR="$(mktemp -d /tmp/clipboard-fs-icon.XXXXXX)"

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

if [ ! -f "$SOURCE_PNG" ]; then
    echo "Error: $SOURCE_PNG not found. Run from repo root." >&2
    exit 1
fi

make_icns() {
    local name="$1"
    local output="Resources/${name}.icns"
    local iconset="$WORK_DIR/${name}.iconset"
    mkdir -p "$iconset"

    sips -z 16   16   "$SOURCE_PNG" --out "$iconset/icon_16x16.png"      >/dev/null
    sips -z 32   32   "$SOURCE_PNG" --out "$iconset/icon_16x16@2x.png"   >/dev/null
    sips -z 32   32   "$SOURCE_PNG" --out "$iconset/icon_32x32.png"      >/dev/null
    sips -z 64   64   "$SOURCE_PNG" --out "$iconset/icon_32x32@2x.png"   >/dev/null
    sips -z 128  128  "$SOURCE_PNG" --out "$iconset/icon_128x128.png"    >/dev/null
    sips -z 256  256  "$SOURCE_PNG" --out "$iconset/icon_128x128@2x.png" >/dev/null
    sips -z 256  256  "$SOURCE_PNG" --out "$iconset/icon_256x256.png"    >/dev/null
    sips -z 512  512  "$SOURCE_PNG" --out "$iconset/icon_256x256@2x.png" >/dev/null
    sips -z 512  512  "$SOURCE_PNG" --out "$iconset/icon_512x512.png"    >/dev/null
    cp "$SOURCE_PNG"                     "$iconset/icon_512x512@2x.png"

    iconutil -c icns -o "$output" "$iconset"
    echo "Created $output"
    ls -lh "$output"
}

make_icns AppIcon
make_icns VolumeIcon
