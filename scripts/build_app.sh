#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-debug}"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP_DIR="build/Void.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BIN_DIR/Void" "$MACOS_DIR/Void"
cp "$BIN_DIR/void-mcp" "$MACOS_DIR/void-mcp"
chmod +x "$MACOS_DIR/Void" "$MACOS_DIR/void-mcp"

codesign --force --deep --sign - --identifier "com.voidapp.mac" --entitlements "Resources/Void.entitlements" "$APP_DIR" >/dev/null 2>&1 || true
echo "Built $APP_DIR successfully."
