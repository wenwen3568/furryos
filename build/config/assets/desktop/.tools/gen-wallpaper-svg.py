#!/usr/bin/env python3
"""Emit the vector source art for the FurryOS wallpaper (wallpaper.svg).

The raster wallpaper.png is produced by .tools/gen-wallpaper.py (ImageMagick,
because the bundled MSVG renderer drops gradients). This script writes the
equivalent composition as an SVG so the artwork stays editable as vector source.

Colours come from assets/brand/brand-tokens.md:
    furryos-blue-deep  #0A3568   gradient top
    furryos-blue       #1A6FD4   gradient middle + paw
    furryos-blue-pale  #EAF2FF   gradient bottom
    furryos-white      #FFFFFF   watermark paw

Paw geometry is copied verbatim from assets/brand/paw.svg.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
DESKTOP = os.path.dirname(HERE)

W, H = 1920, 1080

PAW_PATHS = (
    '<path d="M128 150c32 0 58 21 58 45 0 16-15 27-33 27h-50c-18 0-33-11-33-27 '
    '0-24 26-45 58-45z"/>'
    '<ellipse cx="50" cy="108" rx="25" ry="32"/>'
    '<ellipse cx="97" cy="62" rx="24" ry="32"/>'
    '<ellipse cx="159" cy="62" rx="24" ry="32"/>'
    '<ellipse cx="206" cy="108" rx="25" ry="32"/>'
)

# (size, x, y, fill, opacity) — mirrors the raster composition in
# .tools/gen-wallpaper.py. The white watermark sits in the deep upper-left and
# the blue trail runs along the pale lower band; all boxes are disjoint.
LAYERS = [
    (640, 40, 20, "#FFFFFF", 0.18),
    (420, 70, 660, "#1A6FD4", 0.30),
    (320, 530, 660, "#1A6FD4", 0.45),
    (230, 890, 660, "#1A6FD4", 0.65),
    (160, 1160, 660, "#1A6FD4", 0.88),
]


def build():
    parts = [
        '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
        'viewBox="0 0 %d %d">' % (W, H, W, H),
        '  <title>FurryOS default wallpaper</title>',
        '  <defs>',
        '    <linearGradient id="furryos-bg" x1="0" y1="0" x2="0" y2="1">',
        '      <stop offset="0" stop-color="#0A3568"/>',
        '      <stop offset="0.5" stop-color="#1A6FD4"/>',
        '      <stop offset="1" stop-color="#EAF2FF"/>',
        '    </linearGradient>',
        '    <g id="furryos-paw">%s</g>' % PAW_PATHS,
        '  </defs>',
        '  <rect width="%d" height="%d" fill="url(#furryos-bg)"/>' % (W, H),
    ]
    for size, x, y, fill, op in LAYERS:
        parts.append(
            '  <use href="#furryos-paw" x="%d" y="%d" width="%d" height="%d" '
            'fill="%s" opacity="%s"/>' % (x, y, size, size, fill, op)
        )
    parts.append('</svg>')
    return "\n".join(parts) + "\n"


if __name__ == "__main__":
    out = os.path.join(DESKTOP, "wallpaper.svg")
    with open(out, "w") as fh:
        fh.write(build())
    print("wrote", out)
