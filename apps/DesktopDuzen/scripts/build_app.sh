#!/bin/bash
# Builds DesktopDuzen.app into the project folder. Does NOT touch /Applications.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$PROJECT_DIR/DesktopDuzen.app"
CONTENTS_DIR="$APP_DIR/Contents"
VERSION="${DD_VERSION:-1.1.0}"
BUILD="${DD_BUILD:-372}"
# Signing identity: Developer ID if available, else ad-hoc. Override with DD_SIGN_IDENTITY.
IDENTITY="${DD_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Developer ID Application' | sed -E 's/.*"(.*)"/\1/' || true)}"
IDENTITY="${IDENTITY:--}"

cd "$PROJECT_DIR"
echo "==> Building release binary"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/DesktopDuzen"

echo "==> Packaging $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$BIN" "$CONTENTS_DIR/MacOS/DesktopDuzen"
chmod 755 "$CONTENTS_DIR/MacOS/DesktopDuzen"
[ -f "$PROJECT_DIR/Resources/AppIcon.icns" ] && cp "$PROJECT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>DesktopDuzen</string>
    <key>CFBundleIdentifier</key><string>com.desktopduzen.app</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>DesktopDüzen</string>
    <key>CFBundleDisplayName</key><string>DesktopDüzen</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>LSMultipleInstancesProhibited</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSRequiresAquaSystemAppearance</key><false/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Mehmet Akif Çifçi</string>
    <key>NSDesktopFolderUsageDescription</key><string>DesktopDüzen shows and organises your Desktop files in zones and keeps zone folders in ~/Desktop/Zones.</string>
    <key>NSAppleEventsUsageDescription</key><string>DesktopDüzen uses AppleScript to position and lock pinned items on your macOS desktop.</string>
    <key>NSDocumentsFolderUsageDescription</key><string>DesktopDüzen needs access to show Folder Zones that point inside Documents.</string>
    <key>NSDownloadsFolderUsageDescription</key><string>DesktopDüzen needs access to show Folder Zones that point inside Downloads.</string>
    <key>NSRemovableVolumesUsageDescription</key><string>DesktopDüzen needs access to show Folder Zones on external drives.</string>
</dict>
</plist>
EOF
plutil -lint "$CONTENTS_DIR/Info.plist"

echo "==> Signing with: $IDENTITY"
if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP_DIR"
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP_DIR" \
      || codesign --force --options runtime --sign "$IDENTITY" "$APP_DIR"
fi
codesign --verify --strict --verbose=2 "$APP_DIR"
echo "==> Built $APP_DIR"
