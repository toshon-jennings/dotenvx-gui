#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
SOURCE_ICON="$PROJECT_DIR/native/AppIcon.svg"
OUTPUT_ICON="$PROJECT_DIR/native/AppIcon.icns"
WORK_DIR="$(mktemp -d /tmp/dotenvx-native-icon.XXXXXX)"
ICONSET_DIR="$WORK_DIR/AppIcon.iconset"
MASTER_PNG="$WORK_DIR/AppIcon-1024.png"

cleanup() {
  find "$WORK_DIR" -type f -delete
  find "$WORK_DIR" -depth -type d -empty -delete
}
trap cleanup EXIT

mkdir -p "$ICONSET_DIR"
/usr/bin/sips -s format png "$SOURCE_ICON" --out "$MASTER_PNG" >/dev/null

for spec in \
  "16 icon_16x16.png" \
  "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" \
  "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" \
  "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" \
  "512 icon_256x256@2x.png" \
  "512 icon_512x512.png" \
  "1024 icon_512x512@2x.png"
do
  size="${spec%% *}"
  name="${spec#* }"
  /usr/bin/sips -z "$size" "$size" "$MASTER_PNG" --out "$ICONSET_DIR/$name" >/dev/null
done

/usr/bin/iconutil --convert icns --output "$OUTPUT_ICON" "$ICONSET_DIR"
echo "$OUTPUT_ICON"
