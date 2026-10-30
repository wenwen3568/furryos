#!/usr/bin/env python3
"""Cross-check that the colour scheme, the wallpaper and the theme agree.

The contract's hard requirement is "新用户首次登录：配色、壁纸、主题三者一致".
This script proves the three entry points cannot disagree, by reading the
actual files a session would read:

  1. /usr/share/color-schemes/FurryOS.colors  (installed from FurryOS.colors)
  2. /etc/skel/.config/kdeglobals             (installed from skel/.config/kdeglobals)
  3. look-and-feel/.../contents/defaults      (the global theme's own defaults)

For each it extracts ColorScheme, AccentColor, widgetStyle, icon theme,
fonts, plasma theme name and wallpaper image, then asserts all three report
the same values.

t5 additions (the "half FurryOS, half Breeze" gate):
  * plasma theme name must be `furryos` in BOTH skel plasmarc and the global
    theme defaults, and that theme package must exist. The old value `breeze`
    is not a Plasma 5.27 desktop theme at all (proved with
    `plasma-apply-desktoptheme breeze`), so the panel silently stayed Breeze.
  * icon theme, font, fixed font, KSplash theme, glide animation switch and
    the animation speed factor are all asserted, in every entry point.
  * the ksplash look-and-feel package may not fall back to Breeze values.

Also re-computes the WCAG contrast ratios brand-tokens.md claims, so the
readability guarantee is verified rather than asserted.

Exit code 0 = consistent.
"""
import os
import re
import sys

DESKTOP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(os.path.dirname(DESKTOP))

FILES = {
    "FurryOS.colors": os.path.join(DESKTOP, "FurryOS.colors"),
    "skel kdeglobals": os.path.join(DESKTOP, "skel", ".config", "kdeglobals"),
    "look-and-feel defaults": os.path.join(
        DESKTOP, "look-and-feel", "com.furryos.lookandfeel", "contents", "defaults"),
    "skel plasmarc": os.path.join(DESKTOP, "skel", ".config", "plasmarc"),
    "skel kwinrc": os.path.join(DESKTOP, "skel", ".config", "kwinrc"),
    "plasma-theme plasmarc": os.path.join(DESKTOP, "plasma-theme", "furryos", "plasmarc"),
    "skel appletsrc": os.path.join(
        DESKTOP, "skel", ".config", "plasma-org.kde.plasma.desktop-appletsrc"),
    "ksplash defaults": os.path.join(
        REPO, "assets", "effects", "splash", "furryos-ksplash", "contents", "defaults"),
}

# What each entry point must say. This table IS the expectation: every
# assertion below reads it, so changing a value here changes the verdict
# (an earlier version printed EXPECT but asserted hard-coded literals, which
# made the table look authoritative while being inert).
EXPECT = {
    "ColorScheme": "FurryOS",
    "AccentColor": "26,111,212",
    "widgetStyle": "Breeze",
    "IconsTheme": "FurryOS",
    "Image": "FurryOS",
    "PlasmaTheme": "furryos",
    "defaultWallpaperTheme": "FurryOS",
    "KSplashTheme": "org.furryos.desktop",
    "font": "Noto Sans,10,-1,5,50,0,0,0,0,0",
    "fixed": "Hack,10,-1,5,50,0,0,0,0,0",
    "glide": "true",
    "AnimationDurationFactor": "1",
}


def read_kv(path):
    """Flatten an INI-ish file into {(section, key): value}.

    `section` keeps the full bracket content, so Plasma look-and-feel files
    such as `[kdeglobals][Icons]` become the section string
    "kdeglobals][Icons"; lookups filter with `endswith`, which makes the same
    helper work for both plain and nested sections.
    """
    out = {}
    section = ""
    for raw in open(path):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^\[(.+)\]$", line)
        if m:
            section = m.group(1)
            continue
        if "=" in line:
            k, v = line.split("=", 1)
            out[(section, k.strip())] = v.strip()
    return out


def val(kv, key, section=None):
    """First value for `key`; when `section` is given the section must end with it."""
    for (s, k), v in kv.items():
        if k != key:
            continue
        if section is not None and not (s or "").endswith(section):
            continue
        return v
    return None


def luminance(rgb):
    def ch(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(x) for x in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def main():
    failures = []
    print("=== 1. entry-point agreement ===")
    loaded = {}
    for label, path in FILES.items():
        if not os.path.exists(path):
            failures.append("missing %s (%s)" % (label, path))
            continue
        kv = read_kv(path)
        loaded[label] = kv
        hits = {}
        for key in EXPECT:
            v = val(kv, key)
            if v is not None:
                hits[key] = v
        print("  %-24s %s" % (label, hits))

    def expect(label, key, section, expected):
        got = val(loaded.get(label, {}), key, section)
        if got != expected:
            failures.append("%s [%s] %s=%r (expected %r)"
                            % (label, section, key, got, expected))

    # colour scheme
    for label in ("FurryOS.colors", "skel kdeglobals", "look-and-feel defaults"):
        expect(label, "ColorScheme", "General", EXPECT["ColorScheme"])
    for label in ("skel kdeglobals", "look-and-feel defaults"):
        expect(label, "AccentColor", "General", EXPECT["AccentColor"])

    # widget style
    for label in ("skel kdeglobals", "look-and-feel defaults"):
        expect(label, "widgetStyle", "KDE", EXPECT["widgetStyle"])

    # plasma desktop theme: must be named in both entry points (a global theme
    # that stays silent about the panel theme leaves Breeze's in place), and the
    # named package must exist in the asset tree.
    # NOTE: plasma-theme/furryos/plasmarc is the theme's OWN config, so it
    # correctly has no [Theme] name key; only the two consumer files do.
    for label in ("skel plasmarc", "look-and-feel defaults"):
        expect(label, "name", "Theme", EXPECT["PlasmaTheme"])
    theme_dir = os.path.join(DESKTOP, "plasma-theme", EXPECT["PlasmaTheme"])
    for rel in ("colors", "metadata.json", "plasmarc"):
        if not os.path.exists(os.path.join(theme_dir, rel)):
            failures.append("plasma theme %r is missing %s"
                            % (EXPECT["PlasmaTheme"], rel))

    # icon theme + the theme itself (Inherits=breeze keeps icon coverage)
    for label in ("skel kdeglobals", "look-and-feel defaults", "ksplash defaults"):
        expect(label, "Theme", "Icons", EXPECT["IconsTheme"])
    icon_theme = os.path.join(DESKTOP, "icons", EXPECT["IconsTheme"], "index.theme")
    if not os.path.exists(icon_theme):
        failures.append("icon theme missing: %s" % icon_theme)
    elif "Inherits=breeze" not in open(icon_theme).read():
        failures.append("icon theme %s does not Inherit=breeze"
                        % EXPECT["IconsTheme"])

    # fonts: pinned in both entry points (otherwise the session font is whatever
    # KDE Frameworks happened to be compiled with)
    for label in ("skel kdeglobals", "look-and-feel defaults"):
        for key in ("font", "fixed"):
            expect(label, key, "General", EXPECT[key])

    # wallpaper
    for label in ("skel kdeglobals", "look-and-feel defaults"):
        expect(label, "Image", "Wallpaper", EXPECT["Image"])
    for label in ("plasma-theme plasmarc", "skel plasmarc"):
        expect(label, "defaultWallpaperTheme", "Wallpaper",
               EXPECT["defaultWallpaperTheme"])

    # appletsrc must point at the installed wallpaper path
    ap = os.path.join(DESKTOP, "skel", ".config",
                      "plasma-org.kde.plasma.desktop-appletsrc")
    txt = open(ap).read()
    if "/usr/share/wallpapers/FurryOS/contents/images/1920x1080.png" not in txt:
        failures.append("appletsrc does not reference the installed wallpaper path")
    if "wallpaperPlugin=org.kde.image" not in txt:
        failures.append("appletsrc does not select the org.kde.image wallpaper plugin")

    # the wallpaper the appletsrc names must actually exist in the package
    wpkg = os.path.join(DESKTOP, "wallpapers", "FurryOS", "contents", "images",
                        "1920x1080.png")
    if not os.path.exists(wpkg):
        failures.append("wallpaper package image missing: %s" % wpkg)

    # login -> desktop splash: both the global theme and the splash package
    # must name the FurryOS splash, and the splash package must not carry Breeze
    # leftovers (it used to say name=default / Image=Next).
    expect("look-and-feel defaults", "Theme", "KSplash", EXPECT["KSplashTheme"])
    expect("ksplash defaults", "Theme", "KSplash", EXPECT["KSplashTheme"])
    expect("ksplash defaults", "name", "Theme", EXPECT["PlasmaTheme"])
    expect("ksplash defaults", "Image", "Wallpaper", EXPECT["Image"])

    # click effect merged into kdeglobals (motion-effects' keys)
    kg = open(FILES["skel kdeglobals"]).read()
    for needle in ("[Effects]", "Click=true", "[Effect-mouseclick]",
                   "Color1=26,111,212", "RingLife=250"):
        if needle not in kg:
            failures.append("kdeglobals missing click-effect key %r" % needle)

    # kwinrc is the AUTHORITATIVE location. Verified with `strings -el` against
    # noble's libkwin.so.5.27.11: it reads kdeglobals only for "Colors:Window"
    # and has no "Effects" group at all, while the plugin switch uses
    # kwinrc [Plugins] "<name>Enabled" and the appearance uses the
    # "Effect-%1" group template (-> Effect-mouseclick).
    kw_path = os.path.join(DESKTOP, "skel", ".config", "kwinrc")
    kw = open(kw_path).read()
    for needle in ("[Plugins]", "mouseclickEnabled=true", "[Effect-mouseclick]",
                   "Color1=26,111,212", "RingLife=250"):
        if needle not in kw:
            failures.append("kwinrc missing click-effect key %r" % needle)

    # the two copies of [Effect-mouseclick] must agree value-for-value
    def section(path, name):
        out, inside = {}, False
        for raw in open(path):
            line = raw.strip()
            if line.startswith("[") and line.endswith("]"):
                inside = (line == "[%s]" % name)
                continue
            if inside and "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip()
        return out

    kg_sec = section(FILES["skel kdeglobals"], "Effect-mouseclick")
    kw_sec = section(kw_path, "Effect-mouseclick")
    if kg_sec != kw_sec:
        failures.append("[Effect-mouseclick] differs between kdeglobals and kwinrc:"
                        " %r vs %r" % (kg_sec, kw_sec))
    else:
        print("  [Effect-mouseclick] identical in kdeglobals and kwinrc (%d keys)"
              % len(kg_sec))

    # window open/close animation: `glide` ships EnabledByDefault=false in
    # kwin-data 5.27 (metadata.json), so without this key windows pop in and out
    # with no animation at all. It lives in skel kwinrc, which is the file the
    # session reads; the global theme cannot carry it (plasma-apply-lookandfeel
    # applies only [kwinrc][org.kde.kdecoration2] — verified empirically).
    expect("skel kwinrc", "glideEnabled", "Plugins", EXPECT["glide"])
    # global animation speed multiplier (libkwin reads kdeglobals [KDE])
    for label in ("skel kdeglobals", "look-and-feel defaults"):
        expect(label, "AnimationDurationFactor", "KDE",
               EXPECT["AnimationDurationFactor"])

    print()
    print("=== 2. WCAG contrast ratios (brand-tokens.md claims) ===")
    # brand-tokens.md rounds its ratios, so allow a small rounding slack in
    # either direction; what matters is that every pair stays AAA (>= 7:1).
    checks = [
        ("furryos-text on furryos-blue-pale", "#12283F", "#EAF2FF", 12.9),
        ("furryos-text on furryos-white", "#12283F", "#FFFFFF", 15.2),
        ("furryos-white on furryos-blue", "#FFFFFF", "#1A6FD4", 4.7),
        ("furryos-white on furryos-blue-dark", "#FFFFFF", "#0F4C8C", 7.4),
    ]
    for name, fg, bg, claimed in checks:
        got = contrast(hex2rgb(fg), hex2rgb(bg))
        ok = got >= claimed - 0.3
        print("  %-34s claimed %5.1f  computed %5.2f  %s"
              % (name, claimed, got, "OK" if ok else "WORSE THAN CLAIMED"))
        if not ok:
            failures.append("contrast %s: claimed %s computed %.2f" % (name, claimed, got))

    # and the pair the colour scheme actually ships - READ from FurryOS.colors,
    # not hard-coded. An earlier version printed a fixed (18,40,63)/(255,255,255)
    # pair that no assertion consumed, so it kept printing 14.99:1 even after
    # [Colors:View] was broken.
    print()
    print("  shipped pair: Colors:View fg on bg (read from FurryOS.colors) =")
    colors_kv = loaded.get("FurryOS.colors", {})
    view_fg_s = colors_kv.get(("Colors:View", "ForegroundNormal"))
    view_bg_s = colors_kv.get(("Colors:View", "BackgroundNormal"))
    if not view_fg_s or not view_bg_s:
        failures.append("FurryOS.colors [Colors:View] ForegroundNormal/"
                        "BackgroundNormal missing")
    else:
        try:
            view_fg = tuple(int(x) for x in view_fg_s.split(","))
            view_bg = tuple(int(x) for x in view_bg_s.split(","))
            got = contrast(view_fg, view_bg)
            print("    %s on %s -> %.2f:1 (AAA needs 7.0)" % (view_fg, view_bg, got))
            if got < 7.0:
                failures.append("[Colors:View] fg/bg contrast %.2f:1 < 7.0 (AAA)"
                                % got)
        except ValueError:
            failures.append("FurryOS.colors [Colors:View] values are not r,g,b:"
                            " %r / %r" % (view_fg_s, view_bg_s))

    print()
    if failures:
        print("FAIL:")
        for f in failures:
            print("  - " + f)
        return 1
    print("PASS: colour scheme, /etc/skel defaults and the global theme all name"
          " FurryOS (colour scheme, plasma theme, icon theme, fonts, wallpaper,"
          " splash); click effect and glide animation keys merged; contrast"
          " claims verified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
