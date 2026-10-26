#!/usr/bin/env python3
"""Minimal PNG reader + pixel sampler used to verify ImageMagick SVG rendering.

No PIL available in this environment, so decode PNG manually (zlib + unfilter)
and sample specific pixels. Enough to confirm gradients / alpha / shapes land.
"""
import struct
import sys
import zlib


def read_png(path):
    d = open(path, "rb").read()
    assert d[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos = 8
    idat = b""
    w = h = bd = ct = None
    while pos < len(d):
        ln = struct.unpack(">I", d[pos : pos + 4])[0]
        typ = d[pos + 4 : pos + 8]
        data = d[pos + 8 : pos + 8 + ln]
        pos += 12 + ln
        if typ == b"IHDR":
            w, h, bd, ct, comp, filt, inter = struct.unpack(">IIBBBBB", data)
            assert inter == 0, "interlaced PNG unsupported here"
            assert bd in (8, 16), "only 8/16-bit depth supported here"
        elif typ == b"IDAT":
            idat += data
        elif typ == b"IEND":
            break
    raw = zlib.decompress(idat)
    nch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]
    bps = bd // 8  # bytes per sample
    bpp = nch * bps
    stride = w * bpp
    rows = []
    prev = bytearray(stride)
    i = 0
    for _ in range(h):
        ft = raw[i]
        i += 1
        line = bytearray(raw[i : i + stride])
        i += stride
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
        return tuple(rows[y][o : o + 3])
    vals = struct.unpack(">3H", rows[y][o : o + 6])
    return tuple(v >> 8 for v in vals)


def px_rgba(rows, nch, bps, x, y):
    """Return (r,g,b,a) 8-bit; for RGB-only images a is 255."""
    o = x * nch * bps
    if bps == 1:
        if nch == 4:
            return tuple(rows[y][o : o + 4])
        return tuple(rows[y][o : o + 3]) + (255,)
    if nch == 4:
        return tuple(v >> 8 for v in struct.unpack(">4H", rows[y][o : o + 8]))
    return tuple(v >> 8 for v in struct.unpack(">3H", rows[y][o : o + 6])) + (255,)


def blend_over(dst, src_rgba):
    """Alpha-composite an 8-bit src_rgba over an opaque dst rgb tuple."""
    r, g, b, a = src_rgba
    t = a / 255.0
    return (
        round(dst[0] * (1 - t) + r * t),
        round(dst[1] * (1 - t) + g * t),
        round(dst[2] * (1 - t) + b * t),
    )


if __name__ == "__main__":
    path = sys.argv[1]
    w, h, nch, bps, rows = read_png(path)
    print("size=%dx%d channels=%d bps=%d" % (w, h, nch, bps))
    pts = [(5, 5), (100, 10), (195, 95), (10, 60), (70, 50), (170, 60),
           (50, 90), (150, 90)]
    for (x, y) in pts:
        if x >= w or y >= h:
            print((x, y), "out of range")
            continue
        print((x, y), px(rows, nch, bps, x, y))
