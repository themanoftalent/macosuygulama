#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/TopShelf.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "Building TopShelf (release)..."
cd "$PROJECT_DIR"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/TopShelf"

echo "Generating AppIcon.icns..."
mkdir -p "$BUILD_DIR"
swift "$PROJECT_DIR/scripts/generate_icon.swift" "$BUILD_DIR"
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$BUILD_DIR/AppIcon.icns"
rm -rf "$BUILD_DIR/AppIcon.iconset"

echo "Assembling TopShelf.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/TopShelf"
cp "$BUILD_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>TopShelf</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.topshelf.menubar</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>TopShelf</string>
    <key>CFBundleDisplayName</key>
    <string>TopShelf</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>TopShelf Menu Bar Folder Utility</string>
</dict>
</plist>
EOF

echo "Ad-hoc signing TopShelf.app..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Done! Built: $APP_BUNDLE"
