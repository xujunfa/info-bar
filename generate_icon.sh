#!/bin/bash
set -e
ICON_FILE="AppIcon.png"
ICONSET_DIR="AppIcon.iconset"

mkdir -p "$ICONSET_DIR"

# Generate all the necessary sizes for macOS icns
sips -z 16 16     "$ICON_FILE" --out "$ICONSET_DIR/icon_16x16.png"
sips -z 32 32     "$ICON_FILE" --out "$ICONSET_DIR/icon_16x16@2x.png"
sips -z 32 32     "$ICON_FILE" --out "$ICONSET_DIR/icon_32x32.png"
sips -z 64 64     "$ICON_FILE" --out "$ICONSET_DIR/icon_32x32@2x.png"
sips -z 128 128   "$ICON_FILE" --out "$ICONSET_DIR/icon_128x128.png"
sips -z 256 256   "$ICON_FILE" --out "$ICONSET_DIR/icon_128x128@2x.png"
sips -z 256 256   "$ICON_FILE" --out "$ICONSET_DIR/icon_256x256.png"
sips -z 512 512   "$ICON_FILE" --out "$ICONSET_DIR/icon_256x256@2x.png"
sips -z 512 512   "$ICON_FILE" --out "$ICONSET_DIR/icon_512x512.png"
sips -z 1024 1024 "$ICON_FILE" --out "$ICONSET_DIR/icon_512x512@2x.png"

# Convert iconset directory to icns file
iconutil -c icns "$ICONSET_DIR"

# Move icns file to the standard Resources dir and cleanup
mv AppIcon.icns Sources/InfoBar/Resources/AppIcon.icns
rm -rf "$ICONSET_DIR"

echo "Successfully generated AppIcon.icns in Sources/InfoBar/Resources/"
