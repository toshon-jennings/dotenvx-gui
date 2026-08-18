#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_PATH="$PROJECT_DIR/dist-swift/dotenvx GUI.app"
BACKGROUND_SVG="$PROJECT_DIR/native/dmg-background.svg"
BACKGROUND_PNG="$PROJECT_DIR/native/dmg-background.png"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/native/AppInfo.plist")
ARCH=$(uname -m)
OUTPUT_PATH="$PROJECT_DIR/dist-swift/dotenvx-gui_${VERSION}_${ARCH}.dmg"
STAGE_DIR=$(mktemp -d /tmp/dotenvx-dmg-stage.XXXXXX)

cleanup() {
  find "$STAGE_DIR" -type f -delete 2>/dev/null || true
  find "$STAGE_DIR" -type l -delete 2>/dev/null || true
  find "$STAGE_DIR" -depth -type d -empty -delete 2>/dev/null || true
}
trap cleanup EXIT

cd "$PROJECT_DIR"
"$PROJECT_DIR/scripts/build-native-app.sh"
"$PROJECT_DIR/scripts/render-dmg-background.sh" "$BACKGROUND_SVG" "$BACKGROUND_PNG"
python3 "$PROJECT_DIR/scripts/check-dmg-background.py" "$BACKGROUND_PNG"

mkdir -p "$STAGE_DIR/.background"
ditto "$APP_PATH" "$STAGE_DIR/dotenvx GUI.app"
cp "$BACKGROUND_PNG" "$STAGE_DIR/.background/background.png"
cp "$PROJECT_DIR/native/AppIcon.icns" "$STAGE_DIR/.VolumeIcon.icns"
ln -s /Applications "$STAGE_DIR/Applications"
xcrun SetFile -a C "$STAGE_DIR"

hdiutil create \
  -volname "dotenvx GUI" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_PATH"

"$PROJECT_DIR/scripts/fix-dmg-background.sh" "$OUTPUT_PATH" "dotenvx GUI.app"
hdiutil verify "$OUTPUT_PATH"

echo "$OUTPUT_PATH"
