#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$PROJECT_DIR/../.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/outputs"
APP_DIR="$OUTPUT_DIR/JazzSON.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUILD_DIR="$PROJECT_DIR/.build"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"

rm -rf "$APP_DIR" "$OUTPUT_DIR/JSON Viewer.app" "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"

cp "$PROJECT_DIR/Assets/AppIcon-1024.png" "$BUILD_DIR/AppIcon-1024.png"
cp "$BUILD_DIR/AppIcon-1024.png" "$OUTPUT_DIR/AppIcon-preview.png"

swiftc \
    -O \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -target arm64-apple-macosx15.0 \
    -module-cache-path "$BUILD_DIR/module-cache" \
    -framework Foundation \
    "$PROJECT_DIR/Sources/ICNSBuilder/main.swift" \
    -o "$BUILD_DIR/ICNSBuilder"

sips -z 32 32 "$BUILD_DIR/AppIcon-1024.png" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 64 64 "$BUILD_DIR/AppIcon-1024.png" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$BUILD_DIR/AppIcon-1024.png" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$BUILD_DIR/AppIcon-1024.png" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$BUILD_DIR/AppIcon-1024.png" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$BUILD_DIR/AppIcon-1024.png" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$BUILD_DIR/AppIcon-1024.png" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null

"$BUILD_DIR/ICNSBuilder" "$RESOURCES_DIR/AppIcon.icns" \
    ic11 "$ICONSET_DIR/icon_16x16@2x.png" \
    ic12 "$ICONSET_DIR/icon_32x32@2x.png" \
    ic07 "$ICONSET_DIR/icon_128x128.png" \
    ic13 "$ICONSET_DIR/icon_128x128@2x.png" \
    ic08 "$ICONSET_DIR/icon_256x256.png" \
    ic14 "$ICONSET_DIR/icon_256x256@2x.png" \
    ic09 "$ICONSET_DIR/icon_512x512.png"

swiftc \
    -O \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -target arm64-apple-macosx15.0 \
    -module-cache-path "$BUILD_DIR/module-cache" \
    -framework AppKit \
    -framework Foundation \
    -framework UniformTypeIdentifiers \
    "$PROJECT_DIR/Sources/SimpleJSONViewer/main.swift" \
    -o "$MACOS_DIR/JazzSON"

cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/docs/JazzSON-PRD-1.2.0.md" "$RESOURCES_DIR/JazzSON-PRD.md"
codesign --force --sign - "$APP_DIR" >/dev/null

echo "Built $APP_DIR"
