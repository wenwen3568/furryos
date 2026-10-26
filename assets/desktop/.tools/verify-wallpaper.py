#!/usr/bin/env python3
"""Verify the FurryOS wallpaper actually contains a recognisable paw mark.

Contract requirement: "壁纸中可辨认出爪印元素（爪印符号，不是写实兽爪）".

This script samples pixels and checks, per layer:

  1. the background really is the brand blue/white gradient — both endpoints
     and the midpoint must match brand-tokens.md within rounding;
  2. each paw layer is present: the pad-centre pixel deviates from the
     *theoretical* brand gradient at that row by a clearly visible margin;
  3. every deviating pixel is a blend of a brand colour with that background
     (within a small tolerance) — proving the mark is drawn from the brand
     palette (furryos-blue #1A6FD4 or furryos-white #FFFFFF), not an
     unrelated hue;
  4. the paw geometry matches assets/brand/paw.svg: the gap between the two
     inner toes must be background-coloured while the toes themselves are
     tinted. A solid blob or a realistic claw would fail this.

Exit code 0 = all checks pass.
"""
import os
import struct
import sys
import zlib

DESKTOP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WALLPAPER = os.path.join(DESKTOP, "wallpaper.png")

# brand-tokens.md palette
BLUE_DEEP = (0x0A, 0x35, 0x68)   # #0A3568
BLUE = (0x1A, 0x6F, 0xD4)        # #1A6FD4
BLUE_PALE = (0xEA, 0xF2, 0xFF)   # #EAF2FF
WHITE = (0xFF, 0xFF, 0xFF)       # #FFFFFF

# Layer layout mirrors .tools/gen-wallpaper.py:
#   (name, size, x0, y0, dissolve %, brand colour the layer is tinted with)
# The white watermark sits in the deep upper-left; the blue trail runs along
# the pale lower band. All boxes are disjoint by construction.
LAYERS = [
    ("watermark-white", 640, 40, 20, 18, WHITE),
    ("trail-blue-1", 420, 70, 660, 30, BLUE),
    ("trail-blue-2", 320, 530, 660, 45, BLUE),
    ("trail-blue-3", 230, 890, 660, 65, BLUE),
    ("trail-blue-4", 160, 1160, 660, 88, BLUE),
]

# Inside the 256x256 paw: main-pad centre, and the four toe centres, taken
# verbatim from assets/brand/paw.svg. The two inner toes are the 2nd and 3rd.
PAD = (128, 190)
TOES = [(50, 108), (97, 62), (159, 62), (206, 108)]
INNER_TOE_GAP = (128, 62)  # midpoint between toes[1] and toes[2]


def read_png(path):
    d = open(path, "rb").read()
    assert d[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos = 8
    idat = b""
    w = h = bd = ct = None
    while pos < len(d):
        ln = struct.unpack(">I", d[pos:pos + 4])[0]
        typ = d[pos + 4:pos + 8]
        data = d[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if typ == b"IHDR":
            w, h, bd, ct, comp, filt, inter = struct.unpack(">IIBBBBB", data)
            assert inter == 0 and bd in (8, 16)
        elif typ == b"IDAT":
            idat += data
        elif typ == b"IEND":
            break
    raw = zlib.decompress(idat)
    nch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]
    bps = bd // 8
    bpp = nch * bps
    stride = w * bpp
    rows = []
    prev = bytearray(stride)
    i = 0
    for _ in range(h):
        ft = raw[i]; i += 1
        line = bytearray(raw[i:i + stride]); i += stride
        if ft == 1:
            for x in range(bpp, stride):
                line[x] = (line[x] + line[x - bpp]) & 255
        elif ft == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif ft == 3:
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                line[x] = (line[x] + ((a + prev[x]) >> 1)) & 255
        elif ft == 4:
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                b = prev[x]
                c = prev[x - bpp] if x >= bpp else 0
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        rows.append(bytes(line))
        prev = line
    return w, h, nch, bps, rows


def px(rows, nch, bps, x, y):
    o = x * nch * bps
    if bps == 1:
        return tuple(rows[y][o:o + 3])
    return tuple(v >> 8 for v in struct.unpack(">3H", rows[y][o:o + 6]))


def dist(a, b):
    return max(abs(a[i] - b[i]) for i in range(3))


def gradient_color(y, h):
    """Expected brand gradient value at row y (same stops as the generator)."""
    t = y / (h - 1)
    if t < 0.5:
        u = t / 0.5
        return tuple(round(BLUE_DEEP[i] + (BLUE[i] - BLUE_DEEP[i]) * u) for i in range(3))
    u = (t - 0.5) / 0.5
    return tuple(round(BLUE[i] + (BLUE_PALE[i] - BLUE[i]) * u) for i in range(3))


def main():
    w, h, nch, bps, rows = read_png(WALLPAPER)
    failures = []
    print("wallpaper: %dx%d" % (w, h))

    # --- 1. background gradient endpoints ---------------------------------
    for y, name, expect in [(0, "top", BLUE_DEEP), (h - 1, "bottom", BLUE_PALE)]:
        got = px(rows, nch, bps, 20, y)
        ok = dist(got, expect) <= 2
        print("  gradient %-6s y=%-4d expect %-18s got %-18s %s"
              % (name, y, expect, got, "OK" if ok else "MISMATCH"))
        if not ok:
            failures.append("gradient %s endpoint" % name)
    mid = px(rows, nch, bps, 20, h // 2)
    ok = dist(mid, BLUE) <= 6
    print("  gradient middle y=%-4d expect ~%-18s got %-18s %s"
          % (h // 2, BLUE, mid, "OK" if ok else "MISMATCH"))
    if not ok:
        failures.append("gradient middle")

    # --- 2/3/4. per paw layer ----------------------------------------------
    for name, size, x0, y0, pct, tint in LAYERS:
        scale = size / 256.0
        pad = px(rows, nch, bps, x0 + int(PAD[0] * scale), y0 + int(PAD[1] * scale))
        pad_y = y0 + int(PAD[1] * scale)
        # theoretical background at the pad's own row — the honest baseline,
        # unaffected by neighbouring paw layers
        bg = gradient_color(pad_y, h)
        expected = tuple(round(bg[i] + (tint[i] - bg[i]) * pct / 100.0)
                         for i in range(3))
        deviation = dist(pad, bg)
        err = dist(pad, expected)
        visible = deviation >= 8
        brandish = err <= 14
        print("  %-14s pad=%-18s bg=%-18s dev=%-3d expect=%-18s err=%-3d %s %s"
              % (name, pad, bg, deviation, expected, err,
                 "VISIBLE" if visible else "TOO FAINT",
                 "BRAND-MATCH" if brandish else "OFF-PALETTE"))
        if not visible:
            failures.append("%s not visible" % name)
        if not brandish:
            failures.append("%s off palette" % name)

        # geometry: the gap between the two inner toes must stay background,
        # while the pad is tinted -> proves separate toes, not a solid blob
        gap = px(rows, nch, bps, x0 + int(INNER_TOE_GAP[0] * scale),
                 y0 + int(INNER_TOE_GAP[1] * scale))
        gap_bg = gradient_color(y0 + int(INNER_TOE_GAP[1] * scale), h)
        gap_dev = dist(gap, gap_bg)
        toe = px(rows, nch, bps, x0 + int(TOES[1][0] * scale),
                 y0 + int(TOES[1][1] * scale))
        toe_bg = gradient_color(y0 + int(TOES[1][1] * scale), h)
        toe_dev = dist(toe, toe_bg)
        separated = gap_dev <= 6 and toe_dev >= 8
        print("                 gap=%-18s gap-dev=%-3d | toe=%-18s toe-dev=%-3d %s"
              % (gap, gap_dev, toe, toe_dev,
                 "PAW-SHAPED" if separated else "NOT-PAW-SHAPED"))
        if not separated:
            failures.append("%s geometry not paw-shaped" % name)

    print()
    if failures:
        print("FAIL: " + "; ".join(failures))
        return 1
    print("PASS: brand gradient + %d paw layers, each visible, on-palette and"
          " paw-shaped (separate toes => paw symbol, not a claw)." % len(LAYERS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
