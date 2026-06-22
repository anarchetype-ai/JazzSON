#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$PROJECT_DIR/../.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/outputs"
APP_PATH="$OUTPUT_DIR/JazzSON.app"
DMG_PATH="$OUTPUT_DIR/JazzSON.dmg"
TEMP_DMG_PATH="$OUTPUT_DIR/JazzSON-tmp.dmg"
VOLUME_NAME="JazzSON"
BUILD_DIR="$PROJECT_DIR/.build"
BACKGROUND_TOOL="$BUILD_DIR/DMGBackground"
BACKGROUND_NAME="background.png"
MOUNT_DIR=""

if [[ ! -d "$APP_PATH" ]]; then
    echo "Missing $APP_PATH. Run work/SimpleJSONViewer/build.sh first." >&2
    exit 1
fi

STAGING_DIR="$(mktemp -d)"
cleanup() {
    if [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]]; then
        hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
    fi
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$BUILD_DIR"
swiftc \
    -O \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -target arm64-apple-macosx15.0 \
    -module-cache-path "$BUILD_DIR/module-cache" \
    -framework AppKit \
    -framework Foundation \
    "$PROJECT_DIR/Sources/DMGBackground/main.swift" \
    -o "$BACKGROUND_TOOL"

cp -R "$APP_PATH" "$STAGING_DIR/JazzSON.app"
ln -s /Applications "$STAGING_DIR/Applications"
mkdir -p "$STAGING_DIR/.background"
"$BACKGROUND_TOOL" "$PROJECT_DIR/Assets/AppIcon-1024.png" "$STAGING_DIR/.background/$BACKGROUND_NAME"

rm -f "$DMG_PATH" "$TEMP_DMG_PATH"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDRW \
    -fs APFS \
    "$TEMP_DMG_PATH" >/dev/null

MOUNT_OUTPUT="$(hdiutil attach "$TEMP_DMG_PATH" -readwrite)"
MOUNT_DIR="$(printf '%s\n' "$MOUNT_OUTPUT" | sed -n 's#^.*\(/Volumes/.*\)$#\1#p' | head -n 1)"
if [[ -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
    echo "Could not determine mounted DMG path." >&2
    printf '%s\n' "$MOUNT_OUTPUT" >&2
    exit 1
fi

osascript <<APPLESCRIPT
with timeout of 60 seconds
    tell application "Finder"
        open POSIX file "$MOUNT_DIR"
        delay 1
        set installerWindow to front Finder window
        set current view of installerWindow to icon view
        set toolbar visible of installerWindow to false
        set statusbar visible of installerWindow to false
        set bounds of installerWindow to {160, 120, 800, 568}
        set theViewOptions to the icon view options of installerWindow
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 96
        set background picture of theViewOptions to (POSIX file "$MOUNT_DIR/.background/$BACKGROUND_NAME" as alias)
        set position of item "JazzSON.app" of installerWindow to {174, 196}
        set position of item "Applications" of installerWindow to {464, 196}
        set toolbar visible of installerWindow to false
        set statusbar visible of installerWindow to false
        delay 1
        close installerWindow
    end tell
end timeout
APPLESCRIPT

sync
hdiutil detach "$MOUNT_DIR" >/dev/null
MOUNT_DIR=""

hdiutil convert "$TEMP_DMG_PATH" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH" >/dev/null

rm -f "$TEMP_DMG_PATH"

echo "Built $DMG_PATH"
