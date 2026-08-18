#!/usr/bin/env python3
import struct
import sys

from PIL import Image


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} background.png", file=sys.stderr)
        return 2

    path = sys.argv[1]
    with open(path, "rb") as handle:
        header = handle.read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        print("DMG background is not a PNG", file=sys.stderr)
        return 1

    width, height = struct.unpack(">II", header[16:24])
    if (width, height) != (540, 380):
        print(f"DMG background is {width}x{height}; expected 540x380", file=sys.stderr)
        return 1

    image = Image.open(path).convert("RGB")
    problems = []
    for label, center_x in (("app", 140), ("Applications", 400)):
        pixels = image.crop((center_x - 50, 277, center_x + 50, 293)).tobytes()
        total = sum(
            0.299 * pixels[index]
            + 0.587 * pixels[index + 1]
            + 0.114 * pixels[index + 2]
            for index in range(0, len(pixels), 3)
        )
        luminance = total / (len(pixels) / 3) / 255
        print(f"{label} label luminance: {luminance:.3f}")
        if not 0.60 <= luminance <= 0.75:
            problems.append(f"{label} label luminance {luminance:.3f} is outside 0.60-0.75")

    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1

    print("DMG background: 540x380 PNG; label rows pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
