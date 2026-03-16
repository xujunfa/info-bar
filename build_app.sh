#!/bin/bash
set -e

APP_NAME="InfoBar"
EXECUTABLE_NAME="InfoBarApp"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# Determine version
VERSION_STRING=${1:-$GITHUB_REF_NAME}
VERSION_STRING=${VERSION_STRING:-"1.0.0"}
# Remove 'v' prefix if present (e.g. v1.2.0 -> 1.2.0)
VERSION_STRING=${VERSION_STRING#v}

echo "Building for Release... (Version: $VERSION_STRING)"
# To build a universal binary, you can use: swift build -c release --arch arm64 --arch x86_64
swift build -c release

echo "Creating App Bundle Structure..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

echo "Copying Executable..."
cp ".build/release/${EXECUTABLE_NAME}" "${MACOS_DIR}/"

echo "Copying Resources..."
# Copy the Swift Package resource bundle
if [ -d ".build/release/InfoBar_InfoBar.bundle" ]; then
    cp -R ".build/release/InfoBar_InfoBar.bundle" "${RESOURCES_DIR}/"
fi
# Copy the app icon
if [ -f "Sources/InfoBar/Resources/AppIcon.icns" ]; then
    cp "Sources/InfoBar/Resources/AppIcon.icns" "${RESOURCES_DIR}/"
fi

echo "Creating Info.plist..."
cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.github.infobar</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION_STRING}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION_STRING}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
</dict>
</plist>
EOF

echo "App bundle creation completed at ${APP_DIR}"

echo "Creating DMG..."
DMG_NAME="${APP_NAME}.dmg"
rm -f "${DMG_NAME}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${APP_DIR}" -ov -format UDZO "${DMG_NAME}"

echo "Done! The DMG package is at ${DMG_NAME}"
