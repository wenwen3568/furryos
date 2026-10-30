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
import re
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

BRAND_SVG = os.path.join(os.path.dirname(DESKTOP), "brand", "paw.svg")

_NUM = re.compile(r"[MmLlHhVvCcSsQqTtAaZz]|-?\d*\.?\d+(?:[eE][-+]?\d+)?")


def _path_points(d):
    """All points of an SVG path (control points included) as (x, y) floats.

    Supports the subset used by assets/brand/paw.svg (M/m, L/l, H/h, V/v,
    C/c, Z/z). Control points are included in the bounding box: for a smooth
    closed pad the curve stays inside the convex hull of its control points,
    so the box is a safe (slightly generous) bound and its centre is inside
    the shape.
    """
    toks = _NUM.findall(d)
    pts = []
    x = y = 0.0
    start = (0.0, 0.0)
    cmd = None
    i = 0

    def take(n):
        nonlocal i
        vals = [float(v) for v in toks[i:i + n]]
        if len(vals) != n:
            raise ValueError("path %r truncated near token %d" % (d, i))
        i += n
        return vals

    while i < len(toks):
        t = toks[i]
        if t.isalpha():
            cmd = t
            i += 1
            if cmd in "Zz":
                x, y = start
                continue
        elif cmd is None:
            raise ValueError("path %r does not start with a command" % d)
        rel = cmd.islower()
        c = cmd.upper()
        if c == "M":
            nx, ny = take(2)
            x, y = (x + nx, y + ny) if rel else (nx, ny)
            start = (x, y)
            pts.append((x, y))
            cmd = "l" if rel else "L"      # subsequent pairs are implicit lineto
        elif c == "L":
            nx, ny = take(2)
            x, y = (x + nx, y + ny) if rel else (nx, ny)
            pts.append((x, y))
        elif c == "H":
            (nx,) = take(1)
            x = x + nx if rel else nx
            pts.append((x, y))
        elif c == "V":
            (ny,) = take(1)
            y = y + ny if rel else ny
            pts.append((x, y))
        elif c == "C":
            x1, y1, x2, y2, nx, ny = take(6)
            if rel:
                x1, y1, x2, y2, nx, ny = (x + x1, y + y1, x + x2, y + y2,
                                          x + nx, y + ny)
            pts.extend([(x1, y1), (x2, y2), (nx, ny)])
            x, y = nx, ny
        else:
            raise ValueError("unsupported path command %r in %r" % (cmd, d))
    return pts


def parse_paw_svg(path=BRAND_SVG):
    """Read the paw geometry out of the brand SVG.

    Returns (pad_centre, toe_centres, inner_toe_gap) in the SVG's 256x256
    coordinate space. This used to be three hand-copied constants; deriving
    them means a redrawn paw.svg cannot silently invalidate the wallpaper
    check (it would move the probe points with the artwork).
    """
    try:
        src = open(path, encoding="utf-8").read()
    except OSError as exc:
        raise ValueError("cannot read brand paw SVG %s: %s" % (path, exc))

    ellipses = re.findall(r"<ellipse\b[^>]*>", src)
    toes = []
    for tag in ellipses:
        cx = re.search(r'\bcx="([-\d.]+)"', tag)
        cy = re.search(r'\bcy="([-\d.]+)"', tag)
        if cx and cy:
            toes.append((float(cx.group(1)), float(cy.group(1))))
    if len(toes) != 4:
        raise ValueError("expected 4 toe ellipses in %s, found %d"
                         % (path, len(toes)))
    toes.sort(key=lambda t: t[0])          # left to right

    paths = re.findall(r'<path\b[^>]*\bd="([^"]+)"', src)
    if not paths:
        raise ValueError("no <path d=...> in %s" % path)
    # the pad is the largest path by bounding box
    best = None
    for d in paths:
        pts = _path_points(d)
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        area = (max(xs) - min(xs)) * (max(ys) - min(ys))
        if best is None or area > best[0]:
            best = (area, (min(xs), min(ys), max(xs), max(ys)))
    x0, y0, x1, y1 = best[1]
    pad = ((x0 + x1) / 2.0, (y0 + y1) / 2.0)

    gap = ((toes[1][0] + toes[2][0]) / 2.0, (toes[1][1] + toes[2][1]) / 2.0)
    return pad, toes, gap


# Geometry is resolved once, lazily, so a broken SVG becomes a reported
# failure instead of an import-time traceback.
try:
    PAD, TOES, INNER_TOE_GAP = parse_paw_svg()
    GEOMETRY_ERROR = None
except ValueError as _exc:
    PAD, TOES, INNER_TOE_GAP = (128.0, 186.0), [(50, 108), (97, 62), (159, 62), (206, 108)], (128.0, 62.0)
    GEOMETRY_ERROR = str(_exc)


def read_png(path):
    """Decode a PNG and normalise it to 8-bit RGB rows.

    Returns (w, h, nch, bps, rows) where nch/bps are always 3/1 afterwards —
    palette, greyscale and alpha images are expanded/dropped here so px() has
    a single layout to deal with.

    Unsupported files raise ValueError with an explanation instead of
    AssertionError: a bare `assert` disappears under `python -O` and aborts
    with a traceback rather than a check failure.
    """
    with open(path, "rb") as fh:
        d = fh.read()
    if d[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("%s is not a PNG" % path)

    pos = 8
    idat = b""
    w = h = bd = ct = None
    palette = None
    while pos < len(d):
        if pos + 8 > len(d):
            raise ValueError("%s: truncated chunk header at byte %d" % (path, pos))
        ln = struct.unpack(">I", d[pos:pos + 4])[0]
        typ = d[pos + 4:pos + 8]
        data = d[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if typ == b"IHDR":
            w, h, bd, ct, _comp, _filt, inter = struct.unpack(">IIBBBBB", data)
            if inter != 0:
                raise ValueError("%s is interlaced (unsupported)" % path)
            if bd not in (8, 16):
                raise ValueError("%s: bit depth %d unsupported" % (path, bd))
            if ct not in (0, 2, 3, 4, 6):
                raise ValueError("%s: colour type %d unsupported" % (path, ct))
            if ct == 3 and bd != 8:
                raise ValueError("%s: palette image must be 8-bit, got %d"
                                 % (path, bd))
        elif typ == b"PLTE":
            palette = [tuple(data[i:i + 3]) for i in range(0, len(data), 3)]
        elif typ == b"IDAT":
            idat += data
        elif typ == b"IEND":
            break
    if w is None:
        raise ValueError("%s: no IHDR chunk" % path)
    if ct == 3 and not palette:
        raise ValueError("%s: palette image without a PLTE chunk" % path)

    raw = zlib.decompress(idat)
    nch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]
    bps = bd // 8
    bpp = nch * bps
    stride = w * bpp
    if len(raw) < h * (stride + 1):
        raise ValueError("%s: image data shorter than %d rows of %d bytes"
                         % (path, h, stride))

    rows = []
    prev = bytearray(stride)
    i = 0
    for _y in range(h):
        ft = raw[i]
        i += 1
        line = bytearray(raw[i:i + stride])
        i += stride
        if ft == 1:      # Sub
            for x in range(bpp, stride):
                line[x] = (line[x] + line[x - bpp]) & 255
        elif ft == 2:    # Up
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif ft == 3:    # Average
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                line[x] = (line[x] + ((a + prev[x]) >> 1)) & 255
        elif ft == 4:    # Paeth
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                b = prev[x]
                c = prev[x - bpp] if x >= bpp else 0
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        elif ft != 0:
            raise ValueError("%s: unknown row filter type %d" % (path, ft))
        rows.append(bytes(line))
        prev = line

    if bd == 16:
        # keep the high byte of every sample: the checks compare 8-bit values
        rows = [bytes(row[0::2]) for row in rows]
        bps = 1
        bpp = nch

    if ct == 3:
        # palette index -> RGB
        expanded = []
        for row in rows:
            out = bytearray()
            for idx in row:
                try:
                    out += bytes(palette[idx])
                except IndexError:
                    raise ValueError("%s: palette index %d out of range"
                                     % (path, idx))
            expanded.append(bytes(out))
        rows = expanded
    elif ct == 0:
        rows = [bytes(b for v in row for b in (v, v, v)) for row in rows]
    elif ct == 4:
        rows = [bytes(b for v in row[0::2] for b in (v, v, v)) for row in rows]
    elif ct == 6:
        rows = [bytes(b for v in row[0::4] for b in (v, v, v)) for row in rows]
    return w, h, 3, 1, rows


def px(rows, nch, bps, x, y):
    """RGB triple at (x, y) of an image normalised by read_png()."""
    o = x * nch * bps
    return tuple(rows[y][o:o + 3])


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
    failures = []
    if GEOMETRY_ERROR:
        failures.append("cannot derive paw geometry from %s: %s"
                        % (BRAND_SVG, GEOMETRY_ERROR))
        print("FAIL: " + failures[0])
        return 1
    try:
        w, h, nch, bps, rows = read_png(WALLPAPER)
    except (OSError, ValueError, zlib.error) as exc:
        print("FAIL: cannot read %s: %s" % (WALLPAPER, exc))
        return 1
    print("wallpaper: %dx%d" % (w, h))
    # The probe coordinates below are in 1920x1080 space; a much smaller image
    # would make px() index past the row and raise IndexError instead of
    # reporting a readable failure.
    if w < 1200 or h < 700:
        failures.append("wallpaper is %dx%d, too small for the 1920x1080 probes"
                        % (w, h))
        print("FAIL: " + failures[0])
        return 1

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
