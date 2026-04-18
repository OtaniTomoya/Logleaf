#!/bin/bash
set -euo pipefail

APP_NAME="Logleaf"
BUNDLE_ID="com.tomoya.logleaf"
VERSION="${1:-1.0.0}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/arm64-apple-macosx/release"
RELEASE_DIR="$PROJECT_DIR/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"

echo "=== Building $APP_NAME v$VERSION (Release) ==="

# 1. Release build
swift build -c release --package-path "$PROJECT_DIR" 2>&1

# 2. Create .app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 3. Copy binary
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 4. Copy resources (icon)
RESOURCE_BUNDLE="$BUILD_DIR/Logleaf_Logleaf.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
fi
if [ -f "$PROJECT_DIR/Sources/Logleaf/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Sources/Logleaf/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# 5. Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>ja</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

# 6. Sign (ad-hoc for local use)
codesign --force --deep --sign - "$APP_BUNDLE" 2>&1

echo ""
echo "=== Build complete ==="
echo "App bundle: $APP_BUNDLE"
echo ""

# 7. Create DMG
DMG_PATH="$RELEASE_DIR/${APP_NAME}-${VERSION}.dmg"
rm -f "$DMG_PATH"

DMG_TMP="$RELEASE_DIR/dmg_tmp"
rm -rf "$DMG_TMP"
mkdir -p "$DMG_TMP"
cp -R "$APP_BUNDLE" "$DMG_TMP/"
ln -s /Applications "$DMG_TMP/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_TMP" -ov -format UDZO "$DMG_PATH" 2>&1
rm -rf "$DMG_TMP"

echo "DMG: $DMG_PATH"
echo ""
echo "=== Done ==="
