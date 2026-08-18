#!/bin/zsh
set -euo pipefail

SOURCE="${1:?usage: $0 source.svg output.png}"
OUTPUT="${2:?usage: $0 source.svg output.png}"

if command -v rsvg-convert >/dev/null; then
  rsvg-convert -w 540 -h 380 -f png -o "$OUTPUT" "$SOURCE"
elif python3 -c 'import cairosvg' 2>/dev/null; then
  python3 -c 'import cairosvg,sys; cairosvg.svg2png(url=sys.argv[1],write_to=sys.argv[2],output_width=540,output_height=380)' "$SOURCE" "$OUTPUT"
elif command -v magick >/dev/null; then
  magick -background none -density 288 "$SOURCE" -resize '540x380!' "$OUTPUT"
else
  echo "No SVG renderer found. Install librsvg, CairoSVG, or ImageMagick." >&2
  exit 1
fi

sips -s dpiWidth 72 -s dpiHeight 72 "$OUTPUT" >/dev/null
file "$OUTPUT"
