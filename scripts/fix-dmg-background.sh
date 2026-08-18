#!/bin/bash
set -euo pipefail

DMG="${1:?usage: $0 <dmg> [app-name] [w] [h] [icon_x] [icon_y] [apps_x] [apps_y]}"
APP="${2:-}"
W="${3:-540}"
H="${4:-380}"
ICON_X="${5:-140}"
ICON_Y="${6:-225}"
APPS_X="${7:-400}"
APPS_Y="${8:-225}"

[ -f "$DMG" ] || { echo "No such DMG: $DMG" >&2; exit 1; }
DMG=$(cd "$(dirname "$DMG")" && pwd)/$(basename "$DMG")
READ_WRITE_IMAGE=$(mktemp -u /tmp/dotenvx-fix-dmg.XXXXXX).dmg

cleanup() {
  if [ -n "${VOLUME:-}" ]; then
    hdiutil detach "$VOLUME" -quiet 2>/dev/null || true
  fi
  find "$(dirname "$READ_WRITE_IMAGE")" -maxdepth 1 -name "$(basename "$READ_WRITE_IMAGE")" -type f -delete 2>/dev/null || true
}
trap cleanup EXIT

echo "Converting DMG to read-write"
hdiutil convert "$DMG" -format UDRW -o "$READ_WRITE_IMAGE" -quiet

echo "Mounting DMG for Finder layout"
VOLUME=$(hdiutil attach "$READ_WRITE_IMAGE" -nobrowse -noautoopen | sed -n 's/.*\(\/Volumes\/.*\)/\1/p' | tail -1)
[ -n "$VOLUME" ] || { echo "DMG mount failed" >&2; exit 1; }
VOLUME_NAME=$(basename "$VOLUME")
BACKGROUND=$(find "$VOLUME/.background" -maxdepth 1 -type f -name '*.png' -exec basename {} \; | head -1)
[ -n "$BACKGROUND" ] || { echo "DMG has no PNG background" >&2; exit 1; }

if [ -z "$APP" ]; then
  APP=$(find "$VOLUME" -maxdepth 1 -type d -name '*.app' -exec basename {} \; | head -1)
fi
[ -n "$APP" ] || { echo "DMG has no application" >&2; exit 1; }

LEFT=400
TOP=120
RIGHT=$((LEFT + W))
BOTTOM=$((TOP + H))

osascript <<EOF >/dev/null
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {$LEFT, $TOP, $RIGHT, $BOTTOM}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 100
    set background picture of viewOptions to file ".background:$BACKGROUND"
    set position of item "$APP" of container window to {$ICON_X, $ICON_Y}
    set position of item "Applications" of container window to {$APPS_X, $APPS_Y}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
EOF

sync
sleep 1

python3 - "$VOLUME/.DS_Store" <<'PY'
import plistlib
import re
import sys

data = open(sys.argv[1], "rb").read()
for start in [match.start() for match in re.finditer(b"bplist00", data)]:
    blob = data[start:]
    value = None
    for end in range(len(blob), 60, -1):
        try:
            value = plistlib.loads(blob[:end])
            if isinstance(value, dict):
                break
        except Exception:
            value = None
    if value and "backgroundImageAlias" in value:
        print(
            f"Finder background alias: {len(value['backgroundImageAlias'])} bytes; "
            f"type={value.get('backgroundType')}"
        )
        raise SystemExit(0)
print("Finder did not write the background alias", file=sys.stderr)
raise SystemExit(1)
PY

hdiutil detach "$VOLUME" -quiet
VOLUME=""
COMPRESSED_IMAGE=$(mktemp -u /tmp/dotenvx-fixed-dmg.XXXXXX).dmg
hdiutil convert "$READ_WRITE_IMAGE" -format UDZO -o "$COMPRESSED_IMAGE" -quiet
mv -f "$COMPRESSED_IMAGE" "$DMG"

echo "Styled DMG ready: $DMG"
