#!/usr/bin/env python3
"""Draw the app icon and write every platform's variant.

A bus pulse on a dark tile: one bold square wave, the only shape that still
reads at 16 px. Run after changing the design:

    python3 tools/make_icon.py

Needs Pillow (`pip install pillow`); nothing in the build depends on it.
"""

from PIL import Image, ImageDraw

S = 1024          # design size
SS = 4            # supersampling factor
BG_TOP = (19, 36, 30)
BG_BOTTOM = (9, 18, 15)
WAVE_GREEN = (61, 220, 132)    # the app's seed green
RADIUS = 0.225            # of the edge length, roughly macOS' squircle

# The square wave in design coordinates: mirror-symmetric about x=512, equal
# pulse widths and equal end stubs, or the mark looks accidentally lopsided.
LOW, HIGH = 660, 364
WAVE = [(140, LOW), (252, LOW), (252, HIGH), (432, HIGH), (432, LOW),
        (592, LOW), (592, HIGH), (772, HIGH), (772, LOW), (884, LOW)]


def draw(size):
    n = size * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))

    # Vertical gradient, clipped to the rounded tile.
    grad = Image.new("RGB", (1, n))
    for y in range(n):
        t = y / (n - 1)
        grad.putpixel((0, y), tuple(
            round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)))
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, n - 1, n - 1], radius=round(n * RADIUS), fill=255)
    img.paste(grad.resize((n, n)), (0, 0), mask)

    k = n / S
    d = ImageDraw.Draw(img)
    scale = lambda pts: [(x * k, y * k) for x, y in pts]
    d.line(scale(WAVE), fill=WAVE_GREEN, width=round(84 * k), joint="curve")

    return img.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    import os
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    icons = {s: draw(s) for s in (16, 32, 48, 64, 128, 256, 512, 1024)}

    mac = f"{root}/macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for s in (16, 32, 64, 128, 256, 512, 1024):
        icons[s].save(f"{mac}/app_icon_{s}.png")

    icons[256].save(f"{root}/windows/runner/resources/app_icon.ico",
                    sizes=[(s, s) for s in (16, 32, 48, 64, 128, 256)])
    icons[256].save(f"{root}/linux/cantracer.png")
    print("icons written")
