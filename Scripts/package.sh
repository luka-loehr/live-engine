#!/bin/bash

set -e

APP_NAME="LiveEngine"
DISPLAY_NAME="Live Engine"
BUILD_DIR=".build/release"
APP_BUNDLE="$DISPLAY_NAME.app"
DMG_NAME="Live-Engine.dmg"

echo "Building release..."
swift build -c release

echo "Creating .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Copy Info.plist
cp Assets/Info.plist "$APP_BUNDLE/Contents/"

# Copy app icon
if [ -f "Assets/Icons/AppIcon.icns" ]; then
    cp Assets/Icons/AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
    echo "App icon copied"
fi

echo "Signing app (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Creating DMG..."
rm -f "$DMG_NAME"

# Check if create-dmg is installed
if command -v create-dmg &> /dev/null; then
    create-dmg \
      --volname "$DISPLAY_NAME Installer" \
      --window-pos 200 120 \
      --window-size 800 400 \
      --icon-size 100 \
      --icon "$DISPLAY_NAME.app" 200 190 \
      --hide-extension "$DISPLAY_NAME.app" \
      --app-drop-link 600 185 \
      "$DMG_NAME" \
      "$APP_BUNDLE"
else
    echo "create-dmg not found. Falling back to hdiutil..."
    hdiutil create -volname "$DISPLAY_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_NAME"
fi

echo "Done! DMG created at $DMG_NAME"
