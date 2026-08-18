#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_DIR="$PROJECT_DIR/dist-swift/dotenvx GUI.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$PROJECT_DIR"
swift build -c release

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp ".build/release/DotenvxGUI" "$MACOS_DIR/DotenvxGUI"
cp "native/AppInfo.plist" "$CONTENTS_DIR/Info.plist"
cp "native/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
chmod 755 "$MACOS_DIR/DotenvxGUI"

codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"
