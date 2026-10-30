#!/usr/bin/env python3
"""Validate FurryOS.colors against the brand palette and the KDE scheme format.

Two things are checked:

  A. Format — every colour set and key that BreezeLight/BreezeDark.colors
     define must be present here, so no UI element falls back to a default
     the designer never chose. The reference key list is taken from the
     upstream BreezeDark.colors shipped in Plasma 5.27.

  B. Palette — every value must be one of the brand tokens from
     assets/brand/brand-tokens.md. Semantic colours (negative / neutral /
     positive / visited) are allowed to keep Breeze's values, because they
     encode error/warning/success/visited-link meaning rather than brand.

  C. No off-palette literals in the SDDM theme — the theme's own contract is
     "色值的唯一来源是 Theme.qml"; every #RRGGBB literal in assets/sddm must be
     a brand token or a documented semantic colour. This is what catches a
     component that hard-codes a colour instead of referencing Theme.*.

Exit code 0 = valid.
"""
import os
import re
import sys

DESKTOP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COLORS = os.path.join(DESKTOP, "FurryOS.colors")
BRAND = os.path.join(os.path.dirname(DESKTOP), "brand", "brand-tokens.md")

# brand-tokens.md palette -> decimal rgb
BRAND_TOKENS = {
    "#1A6FD4": (26, 111, 212),    # furryos-blue
    "#0F4C8C": (15, 76, 140),     # furryos-blue-dark
    "#0A3568": (10, 53, 104),     # furryos-blue-deep
    "#D6E6F7": (214, 230, 247),   # furryos-blue-light
    "#EAF2FF": (234, 242, 255),   # furryos-blue-pale
    "#FFFFFF": (255, 255, 255),   # furryos-white
    "#12283F": (18, 40, 63),      # furryos-text
    "#4A637C": (74, 99, 124),     # furryos-text-muted
    "#2C85EC": (44, 133, 236),    # furryos-accent-hover
}
BRAND_RGB = set(BRAND_TOKENS.values())

# Breeze upstream semantic colours (kept verbatim: not brand colours)
SEMANTIC_RGB = {
    (218, 68, 83),    # ForegroundNegative
    (246, 116, 0),    # ForegroundNeutral
    (39, 174, 96),    # ForegroundPositive
    (155, 89, 182),   # ForegroundVisited
    (176, 55, 69),    # Selection ForegroundNegative
    (179, 38, 30),    # #B3261E - furryos-negative (SDDM 登录失败提示, 见 brand-tokens.md 1.1)
    (198, 92, 0),     # Selection ForegroundNeutral
    (23, 104, 57),    # Selection ForegroundPositive
}

# Colour sets and keys required by the Breeze colour-scheme format
REQUIRED_SETS = {
    "Colors:Button": ["BackgroundAlternate", "BackgroundNormal", "DecorationFocus",
                      "DecorationHover", "ForegroundActive", "ForegroundInactive",
                      "ForegroundLink", "ForegroundNegative", "ForegroundNeutral",
                      "ForegroundNormal", "ForegroundPositive", "ForegroundVisited"],
    "Colors:Complementary": ["BackgroundAlternate", "BackgroundNormal", "DecorationFocus",
                             "DecorationHover", "ForegroundActive", "ForegroundInactive",
                             "ForegroundLink", "ForegroundNegative", "ForegroundNeutral",
                             "ForegroundNormal", "ForegroundPositive", "ForegroundVisited"],
    "Colors:Header": ["BackgroundAlternate", "BackgroundNormal", "DecorationFocus",
                      "DecorationHover", "ForegroundActive", "ForegroundInactive",
                      "ForegroundLink", "ForegroundNegative", "ForegroundNeutral",
                      "ForegroundNormal", "ForegroundPositive", "ForegroundVisited"],
    "Colors:Header][Inactive": ["BackgroundAlternate", "BackgroundNormal", "DecorationFocus",
                               "DecorationHover", "ForegroundActive", "ForegroundInactive",
                               "ForegroundLink", "ForegroundNegative", "ForegroundNeutral",
                               "ForegroundNormal", "ForegroundPositive", "ForegroundVisited"],
    "Colors:Selection": ["BackgroundAlternate", "BackgroundNormal", "DecorationFocus",
                         "DecorationHover", "ForegroundActive", "ForegroundInactive",
                         "ForegroundLink", "ForegroundNegative", "ForegroundNeutral",
                         "ForegroundNormal", "ForegroundPositive", "ForegroundVisited"],
    "Colors:Tooltip": ["BackgroundAlternate", "BackgroundNormal", "DecorationFocus",
                       "DecorationHover", "ForegroundActive", "ForegroundInactive",
                       "ForegroundLink", "ForegroundNegative", "ForegroundNeutral",
                       "ForegroundNormal", "ForegroundPositive", "ForegroundVisited"],
    "Colors:View": ["BackgroundAlternate", "BackgroundNormal", "DecorationFocus",
                    "DecorationHover", "ForegroundActive", "ForegroundInactive",
                    "ForegroundLink", "ForegroundNegative", "ForegroundNeutral",
                    "ForegroundNormal", "ForegroundPositive", "ForegroundVisited"],
    "Colors:Window": ["BackgroundAlternate", "BackgroundNormal", "DecorationFocus",
                      "DecorationHover", "ForegroundActive", "ForegroundInactive",
                      "ForegroundLink", "ForegroundNegative", "ForegroundNeutral",
                      "ForegroundNormal", "ForegroundPositive", "ForegroundVisited"],
}
REQUIRED_EFFECT_KEYS = ["Color", "ColorAmount", "ColorEffect", "ContrastAmount",
                        "ContrastEffect", "IntensityAmount", "IntensityEffect"]
REQUIRED_GENERAL = ["ColorScheme", "Name"]
REQUIRED_WM = ["activeBackground", "activeBlend", "activeForeground",
               "inactiveBackground", "inactiveBlend", "inactiveForeground"]


def parse(path):
    sets = {}
    section = None
    for lineno, raw in enumerate(open(path), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^\[(.+)\]$", line)
        if m:
            section = m.group(1)
            sets.setdefault(section, {})
            continue
        if "=" in line and section is not None:
            k, v = line.split("=", 1)
            sets[section][k.strip()] = (v.strip(), lineno)
    return sets


def main():
    failures = []
    sets = parse(COLORS)

    # --- A. format ---------------------------------------------------------
    for name, keys in REQUIRED_SETS.items():
        if name not in sets:
            failures.append("missing colour set [%s]" % name)
            continue
        for k in keys:
            if k not in sets[name]:
                failures.append("[%s] missing key %s" % (name, k))
    for sec in ("ColorEffects:Disabled", "ColorEffects:Inactive"):
        if sec not in sets:
            failures.append("missing [%s]" % sec)
        else:
            for k in REQUIRED_EFFECT_KEYS:
                if k not in sets[sec]:
                    failures.append("[%s] missing key %s" % (sec, k))
    for sec, keys in (("General", REQUIRED_GENERAL), ("WM", REQUIRED_WM)):
        if sec not in sets:
            failures.append("missing [%s]" % sec)
        else:
            for k in keys:
                if k not in sets[sec]:
                    failures.append("[%s] missing key %s" % (sec, k))
    if "KDE" not in sets or "contrast" not in sets.get("KDE", {}):
        failures.append("missing [KDE] contrast")

    # --- B. palette --------------------------------------------------------
    brand_used = {}
    off_palette = []
    for sec, kv in sorted(sets.items()):
        for key, (val, lineno) in sorted(kv.items()):
            m = re.match(r"^(\d+),(\d+),(\d+)$", val)
            if not m:
                continue  # non-colour value (Name=, ColorScheme=, ...)
            rgb = tuple(int(g) for g in m.groups())
            if rgb in BRAND_RGB:
                brand_used[rgb] = brand_used.get(rgb, 0) + 1
            elif rgb in SEMANTIC_RGB:
                pass
            else:
                off_palette.append((sec, key, rgb, lineno))

    for sec, key, rgb, lineno in off_palette:
        failures.append("off-palette value %s in [%s] %s (line %d)" % (rgb, sec, key, lineno))

    # --- C. no off-palette hex literals in the SDDM theme -------------------
    sddm_root = os.path.join(os.path.dirname(DESKTOP), "sddm")
    theme_tokens = BRAND_RGB | SEMANTIC_RGB
    hex_re = re.compile(r"#[0-9A-Fa-f]{6}\b")
    qml_scan = []
    if os.path.isdir(sddm_root):
        for dirpath, _dirnames, filenames in os.walk(sddm_root):
            for name in sorted(filenames):
                if not name.endswith((".qml", ".conf", ".desktop")):
                    continue
                fpath = os.path.join(dirpath, name)
                for lineno, raw in enumerate(open(fpath, encoding="utf-8"), 1):
                    if raw.lstrip().startswith(("#", "//")):
                        continue
                    for hit in hex_re.findall(raw):
                        rgb = tuple(int(hit[i:i + 2], 16) for i in (1, 3, 5))
                        rel = os.path.relpath(fpath, sddm_root)
                        qml_scan.append((rel, lineno, hit, rgb in theme_tokens))
    off_theme = [x for x in qml_scan if not x[3]]
    for rel, lineno, hit, _ok in off_theme:
        failures.append("off-palette literal %s in sddm/%s:%d"
                        % (hit, rel, lineno))

    # --- report ------------------------------------------------------------
    print("FurryOS.colors: %d sections" % len(sets))
    for sec in sorted(sets):
        print("  [%s] %d keys" % (sec, len(sets[sec])))
    print()
    print("brand-tokens.md colours actually used (hex -> occurrences):")
    for hexv, rgb in sorted(BRAND_TOKENS.items(), key=lambda kv: kv[1]):
        n = brand_used.get(rgb, 0)
        print("  %-9s %-18s %3d %s" % (hexv, rgb, n, "USED" if n else "unused"))
    print()
    print("semantic (non-brand) colours kept from Breeze: %d distinct"
          % len({rgb for sec, kv in sets.items() for k, (v, _) in kv.items()
                 if re.match(r"^\d+,\d+,\d+$", v)
                 and tuple(int(g) for g in v.split(",")) in SEMANTIC_RGB}))
    print()
    print("SDDM theme hex literals: %d (all on brand/semantic palette: %s)"
          % (len(qml_scan), "yes" if not off_theme else "NO"))
    for rel, lineno, hit, _ok in off_theme:
        print("  off-palette: sddm/%s:%d %s" % (rel, lineno, hit))
    if off_palette:
        print()
        print("off-palette values:")
        for sec, key, rgb, lineno in off_palette:
            print("  line %-4d [%s] %s = %s" % (lineno, sec, key, rgb))
    print()
    if failures:
        print("FAIL:")
        for f in failures:
            print("  - " + f)
        return 1
    print("PASS: all required Breeze sets/keys present; every non-semantic colour"
          " value is a brand-tokens.md token.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
