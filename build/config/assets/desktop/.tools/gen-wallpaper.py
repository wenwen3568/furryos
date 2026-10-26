#!/usr/bin/env python3
"""FurryOS default wallpaper generator (1920x1080).

Composition
-----------
* Background: two-stop vertical blue gradient from the brand palette
      #0A3568 (furryos-blue-deep, top)  ->  #1A6FD4 (furryos-blue, middle)
      -> #EAF2FF (furryos-blue-pale, bottom)
  Rendered with ImageMagick's native `gradient:` because the bundled MSVG
  internal SVG renderer silently drops <linearGradient> (verified: it degrades
  a gradient rect to a 1-bit bilevel image). The two segments are joined with
  -append so the seam is invisible.

* Foreground: the authoritative paw mark from assets/brand/paw.svg, reused
  verbatim as geometry (rounded main pad + four elliptical toes = a paw *symbol*,
  not a realistic animal claw). Two treatments:
    - a large white watermark in the dark upper area (clearly visible, subtle),
    - a diagonal trail of brand-blue paws rising into the light lower area,
      the last one near full opacity so the mark reads as the motif.

Renderer workarounds (all verified by pixel sampling)
-----------------------------------------------------
1. MSVG paints a 1px black seam on the first/last scanline of every shape.
   The paw is pure #1A6FD4 / #FFFFFF, so `-fuzz 2% -opaque black` removes the
   seam without touching the mark itself.
2. MSVG ignores the SVG `opacity` attribute, and ImageMagick 6's
   `-channel A -evaluate multiply` corrupts RGB on 16-bit images. Layer
   transparency is therefore applied at composite time with
   `-compose dissolve -define compose:args=<pct>`, which behaves correctly.

Output
------
assets/desktop/wallpaper.png  (raster, used by the KDE wallpaper package)
assets/desktop/wallpaper.svg  (same composition as vector, kept as source art)
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DESKTOP = os.path.dirname(HERE)

W, H = 1920, 1080

# brand-tokens.md palette — no invented colours
BLUE_DEEP = "#0A3568"
BLUE = "#1A6FD4"
BLUE_PALE = "#EAF2FF"
WHITE = "#FFFFFF"

# Paw geometry copied verbatim from assets/brand/paw.svg (viewBox 0 0 256 256).
PAW_PATHS = (
    '<path d="M128 150c32 0 58 21 58 45 0 16-15 27-33 27h-50c-18 0-33-11-33-27 '
    '0-24 26-45 58-45z"/>'
    '<ellipse cx="50" cy="108" rx="25" ry="32"/>'
    '<ellipse cx="97" cy="62" rx="24" ry="32"/>'
    '<ellipse cx="159" cy="62" rx="24" ry="32"/>'
    '<ellipse cx="206" cy="108" rx="25" ry="32"/>'
)


def run(cmd):
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        sys.stderr.write("FAILED: %s\n%s\n%s\n" % (" ".join(cmd), res.stdout, res.stderr))
        raise SystemExit(1)
    return res


def paw_svg(color, size=256):
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
        'viewBox="0 0 256 256">\n'
        '  <title>FurryOS paw mark (derived from assets/brand/paw.svg)</title>\n'
        '  <g fill="%s">\n    %s\n  </g>\n</svg>\n'
        % (size, size, color, PAW_PATHS)
    )


def render_paw(color, out_png, size=256):
    """Render the paw to a transparent PNG and strip the MSVG black seam."""
    svg = os.path.join(HERE, ".paw-tmp.svg")
    with open(svg, "w") as fh:
        fh.write(paw_svg(color, size))
    run(["convert", "-background", "none", "-density", "96", svg, out_png])
    os.remove(svg)
    # remove the 1px black edge seam; the mark itself is never black
    run(["convert", out_png, "-alpha", "set", "-channel", "RGBA",
         "-fuzz", "2%", "-fill", "none", "-opaque", "black", out_png])


def build_background(out):
    stops = [(BLUE_DEEP, BLUE), (BLUE, BLUE_PALE)]
    seg_h = H // len(stops)
    parts = []
    for i, (a, b) in enumerate(stops):
        height = seg_h if i < len(stops) - 1 else H - seg_h * (len(stops) - 1)
        p = os.path.join(HERE, ".bg-seg%d.png" % i)
        run(["convert", "-size", "%dx%d" % (W, height), "gradient:%s-%s" % (a, b), p])
        parts.append(p)
    run(["convert"] + parts + ["-append", out])
    for p in parts:
        os.remove(p)


def compose_layer(base, layer, geometry, dissolve_pct):
    """Alpha-composite `layer` onto `base` at `geometry` with a given opacity."""
    cmd = ["convert", base, "(", layer, ")", "-geometry", geometry,
           "-compose", "dissolve", "-define", "compose:args=%d" % dissolve_pct,
           "-composite", base]
    run(cmd)


def main():
    tmp = os.path.join(HERE, ".wp")
    os.makedirs(tmp, exist_ok=True)
    bg = os.path.join(tmp, "bg.png")
    build_background(bg)

    paw_white = os.path.join(tmp, "paw-white.png")
    paw_blue = os.path.join(tmp, "paw-blue.png")
    render_paw(WHITE, paw_white)
    render_paw(BLUE, paw_blue)

    # (source, size, geometry, dissolve %) — dissolve is the layer opacity.
    #
    # Composition rationale (verified by .tools/verify-wallpaper.py):
    #   * the white watermark sits in the DEEP upper-left, where a light mark
    #     has the strongest contrast against #0A3568..#1A6FD4;
    #   * the blue trail runs along the PALE lower band, because a blue paw
    #     over the mid-blue #1A6FD4 row has almost no contrast (the gradient
    #     passes through exactly #1A6FD4 at y=540);
    #   * every layer box is disjoint from the others, so no paw is painted
    #     over another and each mark reads as a separate paw.
    layers = [
        (paw_white, 640, "+40+20", 18),
        (paw_blue, 420, "+70+660", 30),
        (paw_blue, 320, "+530+660", 45),
        (paw_blue, 230, "+890+660", 65),
        (paw_blue, 160, "+1160+660", 88),
    ]
    for i, (src, size, geo, pct) in enumerate(layers):
        sized = os.path.join(tmp, "l%d.png" % i)
        run(["convert", src, "-resize", "%dx%d" % (size, size), sized])
        compose_layer(bg, sized, geo, pct)
        os.remove(sized)

    out_png = os.path.join(DESKTOP, "wallpaper.png")
    run(["convert", bg, "-quality", "95", out_png])
    for f in (bg, paw_white, paw_blue):
        os.remove(f)
    os.rmdir(tmp)
    print("wrote", out_png)


if __name__ == "__main__":
    main()
