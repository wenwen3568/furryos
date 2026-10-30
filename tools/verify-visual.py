#!/usr/bin/env python3
"""FurryOS 视觉统一校验（跨四层：SDDM / 桌面 / 动效 / 系统身份）。

这个脚本回答一个具体问题：**用户从开机到桌面看到的是不是同一套 FurryOS 视觉？**
它不靠读文档，而是读资产文件 + 读渲染出来的 PNG + 读 qmlscene 实例化后的属性值。

数据来源（全部是实际执行结果）：
  1. assets/brand/brand-tokens.md          —— 色板与动效的唯一权威
  2. assets/sddm/furryos/**/*.qml          —— 登录界面（属性值来自 qmlscene 探针）
  3. assets/desktop/**                     —— 配色方案 / plasma 主题 / skel 默认值
  4. assets/effects/**                     —— 点击特效 / ksplash / plymouth / 母版 SVG
  5. assets/identity/**                    —— os-release / kcm-about-distrorc
  6. docs/preview/*.png                    —— tools/render-previews.sh 的渲染产物

用法：
    python3 tools/verify-visual.py [--probe-json FILE]
退出码：0 = 全部通过；1 = 有失败项
"""

import json
import os
import re
import subprocess
import sys

WS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PREVIEW = os.path.join(WS, "docs", "preview")

PASSES = []
FAILS = []


def check(name, cond, detail=""):
    if cond:
        PASSES.append(name)
        print("  [PASS] %s%s" % (name, ("  " + detail) if detail else ""))
    else:
        FAILS.append(name)
        print("  [FAIL] %s  %s" % (name, detail))


def read(path):
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def rel(path):
    return os.path.relpath(path, WS)


# ---------------------------------------------------------------- 色值工具
def hex2rgb(h):
    h = h.strip().lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


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


def near(got, want, tol=3):
    return got is not None and all(abs(a - b) <= tol for a, b in zip(got, want))


def rgb_str(c):
    return "%d,%d,%d" % c


# ---------------------------------------------------------------- 渲染图工具
def histogram(path, crop=None, limit=None):
    """返回 {rgb tuple: count}。crop = (w, h, x, y)。"""
    cmd = ["convert", path, "-depth", "8"]
    if crop:
        w, h, x, y = crop
        cmd += ["-crop", "%dx%d+%d+%d" % (w, h, x, y), "+repage"]
    cmd += ["-format", "%c", "histogram:info:"]
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError("convert failed: %s" % out.stderr[:200])
    hist = {}
    for line in out.stdout.splitlines():
        m = re.match(r"\s*(\d+):\s*\((\d+),(\d+),(\d+)", line)
        if m:
            hist[(int(m.group(2)), int(m.group(3)), int(m.group(4)))] = int(m.group(1))
    return hist


def image_size(path):
    out = subprocess.run(["identify", "-format", "%w %h", path],
                         capture_output=True, text=True)
    if out.returncode != 0:
        return None
    w, h = out.stdout.split()
    return int(w), int(h)


def pixel_at(path, x, y):
    out = subprocess.run(["convert", path, "-depth", "8", "-format",
                          "%%[pixel:p{%d,%d}]" % (x, y), "info:"],
                         capture_output=True, text=True)
    m = re.search(r"s?rgba?\((\d+),(\d+),(\d+)", out.stdout)
    if not m:
        raise RuntimeError("cannot read pixel: %r" % out.stdout)
    return tuple(int(m.group(i)) for i in (1, 2, 3))


def dominant(hist):
    return max(hist.items(), key=lambda kv: kv[1])[0]


def fraction(hist, color, tol=6):
    total = sum(hist.values())
    if not total:
        return 0.0
    hit = sum(n for c, n in hist.items()
              if all(abs(a - b) <= tol for a, b in zip(c, color)))
    return hit / total


# ---------------------------------------------------------------- 1. 令牌
def parse_brand_tokens():
    """从 brand-tokens.md 的表格里读出 9 个品牌色 + 语义色。"""
    txt = read(os.path.join(WS, "assets", "brand", "brand-tokens.md"))
    tokens = {}
    for m in re.finditer(r"^\|\s*`([a-z\-]+)`\s*\|\s*`(#[0-9A-Fa-f]{6})`\s*\|",
                         txt, re.M):
        tokens[m.group(1)] = m.group(2).upper()
    return tokens


def section_1_tokens(probe):
    print("\n=== [1] 品牌令牌：brand-tokens.md 是唯一来源 ===")
    tokens = parse_brand_tokens()
    check("brand-tokens.md 解析出 9 个品牌色 + 语义色",
          len(tokens) >= 10, "tokens=%d %s" % (len(tokens), sorted(tokens)))
    for name, hexv in tokens.items():
        check("令牌 %s = %s" % (name, hexv), len(hexv) == 7)

    # SDDM Theme.qml 运行时值（qmlscene 实例化后读属性，不是正则读字面量）
    if probe:
        t = probe["theme"]
        mapping = {
            "furryos-blue": t["furryosBlue"],
            "furryos-blue-dark": t["furryosBlueDark"],
            "furryos-blue-deep": t["furryosBlueDeep"],
            "furryos-blue-light": t["furryosBlueLight"],
            "furryos-blue-pale": t["furryosBluePale"],
            "furryos-white": t["furryosWhite"],
            "furryos-text": t["furryosText"],
            "furryos-text-muted": t["furryosTextMuted"],
            "furryos-accent-hover": t["furryosAccentHover"],
        }
        for token, got in mapping.items():
            want = tokens.get(token, "").lower()
            check("SDDM Theme.qml 运行时 %s = %s" % (token, want),
                  got.lower() == want, "got %s" % got)
        check("SDDM 错误色 furryos-negative = %s" % tokens.get("furryos-negative"),
              t["furryosNegative"].lower() == tokens.get("furryos-negative", "").lower(),
              "got %s" % t["furryosNegative"])

    # FurryOS.colors：段落齐全 + 四态覆盖 + 语义映射
    colors = read(os.path.join(WS, "assets", "desktop", "FurryOS.colors"))
    groups = re.findall(r"^\[((?:Colors:[A-Za-z]+)(?:\]\[Inactive)?)\]$", colors, re.M)
    need_groups = ["Colors:Button", "Colors:View", "Colors:Window", "Colors:Selection",
                   "Colors:Tooltip", "Colors:Complementary", "Colors:Header",
                   "Colors:Header][Inactive"]
    for g in need_groups:
        check("FurryOS.colors 含段落 [%s]" % g, g in groups, "groups=%s" % groups)

    def group_kv(name):
        out, inside = {}, False
        for raw in colors.splitlines():
            line = raw.strip()
            if line.startswith("[") and line.endswith("]"):
                inside = (line == "[%s]" % name)
                continue
            if inside and "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip()
        return out

    four_state = ["ForegroundNormal", "ForegroundActive", "ForegroundInactive",
                  "DecorationHover", "BackgroundNormal", "BackgroundAlternate"]
    for g in need_groups:
        kv = group_kv(g)
        missing = [k for k in four_state if k not in kv]
        check("[%s] 覆盖 normal/hover/active/inactive 四态" % g, not missing,
              "missing=%s" % missing)

    blue = rgb_str(hex2rgb(tokens["furryos-blue"]))
    hover = rgb_str(hex2rgb(tokens["furryos-accent-hover"]))
    pale = rgb_str(hex2rgb(tokens["furryos-blue-pale"]))
    white = rgb_str(hex2rgb(tokens["furryos-white"]))
    text = rgb_str(hex2rgb(tokens["furryos-text"]))
    muted = rgb_str(hex2rgb(tokens["furryos-text-muted"]))
    light = rgb_str(hex2rgb(tokens["furryos-blue-light"]))
    dark = rgb_str(hex2rgb(tokens["furryos-blue-dark"]))

    semantic = [
        ("Colors:Window", "BackgroundNormal", pale, "窗口底 = 极浅蓝"),
        ("Colors:Window", "ForegroundNormal", text, "窗口文字 = 深蓝文字色"),
        ("Colors:Window", "ForegroundInactive", muted, "非活动文字 = 次要文字色"),
        ("Colors:View", "BackgroundNormal", white, "视图底 = 白"),
        ("Colors:Button", "BackgroundNormal", white, "按钮底 = 白"),
        ("Colors:Button", "BackgroundAlternate", light, "按钮备选底 = 浅蓝"),
        ("Colors:Button", "DecorationFocus", blue, "按钮焦点 = 主色"),
        ("Colors:Button", "DecorationHover", hover, "按钮悬停 = 悬停色"),
        ("Colors:Selection", "BackgroundNormal", blue, "选中底 = 主色"),
        ("Colors:Selection", "BackgroundAlternate", dark, "选中备选 = 深蓝"),
        ("Colors:Selection", "ForegroundNormal", white, "选中文字 = 白"),
        ("Colors:Tooltip", "BackgroundNormal", white, "提示框底 = 白"),
        ("Colors:Tooltip", "ForegroundNormal", text, "提示框文字"),
        ("Colors:Complementary", "BackgroundNormal", "10,53,104", "互补底 = 最深蓝"),
    ]
    for g, k, want, why in semantic:
        got = group_kv(g).get(k)
        check("[%s] %s = %s（%s）" % (g, k, want, why), got == want, "got %r" % got)

    # 窗口装饰（[WM]）：标题栏在活动/非活动两态下的底色与文字色
    wm = group_kv("WM")
    for k, want, why in (("activeBackground", pale, "活动标题栏 = 极浅蓝"),
                         ("activeForeground", text, "活动标题 = 深蓝文字色"),
                         ("inactiveBackground", light, "非活动标题栏 = 浅蓝"),
                         ("inactiveForeground", muted, "非活动标题 = 次要文字色")):
        check("[WM] %s = %s（%s）" % (k, want, why), wm.get(k) == want,
              "got %r" % wm.get(k))
    kg = read(os.path.join(WS, "assets", "desktop", "skel", ".config", "kdeglobals"))

    def kg_group(name):
        out, inside = {}, False
        for raw in kg.splitlines():
            line = raw.strip()
            if line.startswith("[") and line.endswith("]"):
                inside = (line == "[%s]" % name)
                continue
            if inside and "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip()
        return out

    check("skel kdeglobals [Colors:Window] 与配色方案同值",
          kg_group("Colors:Window").get("BackgroundNormal") == pale
          and kg_group("Colors:Window").get("BackgroundAlternate") == light,
          "%r" % kg_group("Colors:Window"))
    check("skel kdeglobals [Colors:View] 与配色方案同值",
          kg_group("Colors:View").get("BackgroundNormal") == white
          and kg_group("Colors:View").get("BackgroundAlternate") == pale,
          "%r" % kg_group("Colors:View"))
    check("skel kdeglobals [KDE] 明确选择 FurryOS 全局主题（否则壁纸回落 Next）",
          kg_group("KDE").get("LookAndFeelPackage") == "com.furryos.lookandfeel",
          "%r" % kg_group("KDE"))

    # plasma 桌面主题的 colors 必须与 FurryOS.colors 逐值一致（同段落）
    theme_colors = read(os.path.join(WS, "assets", "desktop", "plasma-theme",
                                     "furryos", "colors"))

    def theme_group(name):
        out, inside = {}, False
        for raw in theme_colors.splitlines():
            line = raw.strip()
            if line.startswith("[") and line.endswith("]"):
                inside = (line == "[%s]" % name)
                continue
            if inside and "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip()
        return out

    diff_groups = []
    for g in re.findall(r"^\[((?:Colors:[A-Za-z]+)(?:\]\[Inactive)?)\]$", theme_colors, re.M):
        if theme_group(g) != group_kv(g):
            diff_groups.append(g)
    check("plasma 主题 colors 与 FurryOS.colors 逐值一致（同段落）",
          not diff_groups, "diff=%s" % diff_groups)
    check("plasma 主题 colors 也含 [Colors:Header]（面板/弹窗头部）",
          "Colors:Header" in theme_colors and "Colors:Header][Inactive]" in theme_colors)

    # ksplash / 母版 SVG / plymouth 的色值必须都在色板里
    palette = {v.upper() for v in tokens.values()}
    ksplash = read(os.path.join(WS, "assets", "effects", "splash", "furryos-ksplash",
                                "contents", "splash", "Splash.qml"))
    off = [h.upper() for h in re.findall(r'"#([0-9A-Fa-f]{6})"', ksplash)
           if "#" + h.upper() not in {p for p in palette}]
    check("KSplash Splash.qml 不含离板色值", not off, "off-palette=%s" % off)

    sddm_off = []
    for root, _dirs, files in os.walk(os.path.join(WS, "assets", "sddm")):
        for fn in files:
            if not fn.endswith(".qml"):
                continue
            p = os.path.join(root, fn)
            for h in re.findall(r'"#([0-9A-Fa-f]{6})"', read(p)):
                if "#" + h.upper() not in palette:
                    sddm_off.append("%s:%s" % (rel(p), h))
    check("SDDM 主题（含组件）不含离板色值", not sddm_off, "off-palette=%s" % sddm_off)

    svg = read(os.path.join(WS, "assets", "effects", "splash", "furryos-splash.svg"))
    svg_off = [h.upper() for h in re.findall(r'(?:fill|stop-color)="#([0-9A-Fa-f]{6})"', svg)
               if "#" + h.upper() not in palette]
    check("启动画面母版 SVG 不含离板色值", not svg_off, "off-palette=%s" % svg_off)

    # plymouth 脚本：RGB 归一化浮点必须等于色板（误差 < 0.002）
    ply = read(os.path.join(WS, "assets", "effects", "splash", "furryos-plymouth",
                            "furryos.script"))
    ply_off = []
    for m in re.finditer(r"Color\(([0-9.]+),\s*([0-9.]+),\s*([0-9.]+)\)", ply):
        rgb = tuple(round(float(m.group(i)) * 255) for i in (1, 2, 3))
        if not any(all(abs(a - b) <= 1 for a, b in zip(rgb, hex2rgb(p))) for p in palette):
            ply_off.append(rgb)
    check("plymouth 脚本色值与色板一致", not ply_off, "off-palette=%s" % ply_off)
    check("plymouth 屏幕文字是 FurryOS（不是 Ubuntu/Debian）",
          'title.text = "FurryOS"' in ply and "Ubuntu" not in
          re.sub(r"^\s*//.*$", "", ply, flags=re.M),
          "")


# ---------------------------------------------------------------- 2. 动效
def section_2_motion(probe):
    print("\n=== [2] 动效参数统一（消除互相矛盾的时长） ===")
    tokens = parse_brand_tokens()
    brand = read(os.path.join(WS, "assets", "brand", "brand-tokens.md"))
    # brand-tokens 第 4 节：悬停 120-160 / 按下 180-240 / 抖动 320
    def range_of(label):
        m = re.search(re.escape(label) + r"[^\n]*?(\d+)[–-](\d+)ms", brand)
        return (int(m.group(1)), int(m.group(2))) if m else None

    hover_rng = range_of("登录按钮悬停")
    press_rng = range_of("登录按钮按下")
    click_rng = range_of("点击反馈时长")
    check("brand-tokens §4 悬停区间可解析", hover_rng is not None, str(hover_rng))
    check("brand-tokens §4 按下区间可解析", press_rng is not None, str(press_rng))
    check("brand-tokens §4 点击反馈区间可解析", click_rng is not None, str(click_rng))

    if probe:
        t = probe["theme"]
        if hover_rng:
            check("悬停时长 %dms 落在 %s" % (t["hoverDuration"], hover_rng),
                  hover_rng[0] <= t["hoverDuration"] <= hover_rng[1])
        if press_rng:
            check("按下时长 %dms 落在 %s" % (t["pressDuration"], press_rng),
                  press_rng[0] <= t["pressDuration"] <= press_rng[1])
        check("错误抖动 = 320ms / ±6px",
              t["shakeDuration"] == 320 and abs(t["shakeAmplitude"] - 6) < 0.001,
              "%dms / %s px" % (t["shakeDuration"], t["shakeAmplitude"]))
        check("悬停缩放 1.03 / 按下缩放 0.96",
              abs(t["hoverScale"] - 1.03) < 0.001 and abs(t["pressScale"] - 0.96) < 0.001)
        # 组件必须引用令牌而不是另写数字
        btn = read(os.path.join(WS, "assets", "sddm", "furryos", "components",
                                "FurryButton.qml"))
        check("FurryButton 的时长全部取自 Theme 令牌",
              btn.count("Theme.hoverDuration") >= 2 and btn.count("Theme.pressDuration") >= 2,
              "hover=%d press=%d" % (btn.count("Theme.hoverDuration"),
                                     btn.count("Theme.pressDuration")))
        fld = read(os.path.join(WS, "assets", "sddm", "furryos", "components",
                                "FurryField.qml"))
        check("FurryField 抖动与按钮同一套参数",
              "Theme.shakeDuration" in fld and "Theme.shakeAmplitude" in fld)

    # 点击特效：RingLife 必须落在点击反馈区间内，颜色必须是品牌色
    kwin = read(os.path.join(WS, "assets", "effects", "click-effect",
                             "kwinrc-effects.conf"))
    m = re.search(r"^RingLife=(\d+)$", kwin, re.M)
    ring = int(m.group(1)) if m else None
    if click_rng and ring is not None:
        check("点击特效 RingLife=%dms 落在点击反馈区间 %s" % (ring, click_rng),
              click_rng[0] <= ring <= click_rng[1])
    check("点击特效 RingCount=2（双层涟漪）", "RingCount=2" in kwin)
    check("点击特效三色 = 主色/深蓝/最深蓝",
          "Color1=26,111,212" in kwin and "Color2=15,76,140" in kwin
          and "Color3=10,53,104" in kwin)

    # ksplash 旋转 1500ms 必须与 plymouth spinner 的 1.5s 一致
    ksplash = read(os.path.join(WS, "assets", "effects", "splash", "furryos-ksplash",
                                "contents", "splash", "Splash.qml"))
    m = re.search(r"duration:\s*(\d+)", ksplash)
    spin_ms = int(m.group(1)) if m else None
    ply = read(os.path.join(WS, "assets", "effects", "splash", "furryos-plymouth",
                            "furryos.script"))
    m2 = re.search(r"spinner\.duration\s*=\s*([0-9.]+)", ply)
    ply_s = float(m2.group(1)) if m2 else None
    check("ksplash 进度指示 1500ms/圈", spin_ms == 1500, "got %s" % spin_ms)
    check("plymouth spinner 1.5s/圈，与 ksplash 一致",
          ply_s is not None and abs(ply_s * 1000 - (spin_ms or 0)) < 1,
          "plymouth=%s s" % ply_s)
    check("ksplash 淡入时长走 PlasmaCore 令牌（200ms 量级）",
          "PlasmaCore.Units.longDuration" in ksplash)

    # glide（窗口开/关动画）必须在 skel kwinrc 里开启
    skel_kwin = read(os.path.join(WS, "assets", "desktop", "skel", ".config", "kwinrc"))
    check("skel kwinrc 开启 glide（否则窗口无开/关动画，硬弹出）",
          "glideEnabled=true" in skel_kwin)


# ---------------------------------------------------------------- 3. 品牌
def section_3_brand():
    print("\n=== [3] 系统设置里的名称与品牌（关于本系统 / os-release / GRUB） ===")
    osr = read(os.path.join(WS, "assets", "identity", "os-release"))
    fields = dict(re.findall(r'^([A-Z_]+)="?([^"\n]*)"?$', osr, re.M))
    check("os-release NAME=FurryOS", fields.get("NAME") == "FurryOS",
          fields.get("NAME"))
    check("os-release PRETTY_NAME 以 FurryOS 开头",
          fields.get("PRETTY_NAME", "").startswith("FurryOS"),
          fields.get("PRETTY_NAME"))
    check("os-release 用户可见字段不含 Ubuntu",
          "Ubuntu" not in fields.get("NAME", "") + fields.get("PRETTY_NAME", ""))

    kcm = read(os.path.join(WS, "assets", "identity", "about-distro",
                            "kcm-about-distrorc"))
    kv = dict(re.findall(r"^([A-Za-z]+)=(.*)$", kcm, re.M))
    check("kcm-about-distrorc Name=FurryOS", kv.get("Name") == "FurryOS", kv.get("Name"))
    check("kcm-about-distrorc Variant=Plasma Desktop",
          kv.get("Variant") == "Plasma Desktop", kv.get("Variant"))
    check("kcm-about-distrorc Website 指向 furryos 域名",
          "furryos" in kv.get("Website", ""), kv.get("Website"))
    logo = kv.get("LogoPath", "")
    check("kcm-about-distrorc LogoPath 指向 FurryOS logo",
          logo.endswith("/furryos-logo.svg"), logo)
    logo_base = os.path.basename(logo)
    check("LogoPath 的 logo 资源确实在 assets/identity 中（%s）" % logo_base,
          os.path.exists(os.path.join(WS, "assets", "identity", "about-distro",
                                      logo_base))
          or os.path.exists(os.path.join(WS, "assets", "identity", logo_base)))

    # 用户可见的品牌字段不得残留上游品牌
    vis = [
        ("assets/sddm/furryos/metadata.desktop", "Name"),
        ("assets/sddm/furryos/metadata.desktop", "Description"),
        ("assets/desktop/look-and-feel/com.furryos.lookandfeel/metadata.desktop", "Name"),
        ("assets/desktop/look-and-feel/com.furryos.lookandfeel/metadata.desktop", "Comment"),
        ("assets/effects/splash/furryos-ksplash/metadata.json", "Name"),
        ("assets/effects/splash/furryos-ksplash/metadata.json", "Description"),
        ("assets/desktop/plasma-theme/furryos/metadata.json", "Name"),
    ]
    bad = []
    for path, key in vis:
        p = os.path.join(WS, path)
        txt = read(p)
        if p.endswith(".json"):
            data = json.loads(txt)["KPlugin"]
            value = data.get(key, "")
        else:
            value = ""
            for line in txt.splitlines():
                if line.startswith(key + "="):
                    value = line.split("=", 1)[1]
                    break
        for word in ("Ubuntu", "Kubuntu", "KDE Plasma"):
            if word in value:
                bad.append("%s %s=%r" % (path, key, value))
        if not value:
            bad.append("%s %s 为空" % (path, key))
    check("用户可见主题名称/描述均已品牌化（无 Ubuntu/KDE Plasma、非空）",
          not bad, "; ".join(bad))

    # 元数据里的 Website 不得指向上游
    sites = []
    for path in ("assets/desktop/look-and-feel/com.furryos.lookandfeel/metadata.desktop",
                 "assets/desktop/plasma-theme/furryos/metadata.json",
                 "assets/effects/splash/furryos-ksplash/metadata.json"):
        txt = read(os.path.join(WS, path))
        for m in re.finditer(r'"?Website"?[=:]\s*"?(https?://[^"\s,]+)', txt):
            sites.append((path, m.group(1)))
    check("主题元数据 Website 全部指向 furryos 域名（无 kde.org / ubuntu.com）",
          sites and all("furryos" in url for _p, url in sites),
          str(sites))

    # 登录界面必须真的显示 FurryOS 字样
    main_qml = read(os.path.join(WS, "assets", "sddm", "furryos", "Main.qml"))
    check("SDDM 登录界面含 FurryOS 字标（不是空着或写 Ubuntu/KDE）",
          'text: "FurryOS"' in main_qml and "Ubuntu" not in main_qml
          and "KDE" not in main_qml.replace("KDE Plasma", ""))
    check("SDDM 登录界面含品牌爪印 logo",
          "assets/paw.svg" in main_qml)

    # GRUB 启动菜单标题由 8000 钩子重写
    hook = read(os.path.join(WS, "build", "config", "hooks", "normal",
                             "8000-brand-boot-menu.binary"))
    check("8000 钩子把启动菜单标题改写为 FurryOS",
          "Debian GNU/Linux|FurryOS" in hook and "FurryOS Live (" in hook)
    check("8000 钩子重写 /.disk/info 为 FurryOS",
          ".disk/info" in hook and "FurryOS" in hook)


# ---------------------------------------------------------------- 4. 渲染
def section_4_previews():
    print("\n=== [4] 渲染预览（docs/preview/*.png 的像素断言） ===")
    if not os.path.isdir(PREVIEW):
        check("docs/preview 存在", False, PREVIEW)
        return
    expected = {
        "sddm-login-1600x900.png": (1600, 900),
        "sddm-login-2560x1440.png": (2560, 1440),
        "ksplash-1920x1080.png": (1920, 1080),
        "splash-master-1920x1080.png": (1920, 1080),
        "plymouth-1920x1080.png": (1920, 1080),
        "desktop-1920x1080.png": (1920, 1080),
    }
    for name, size in expected.items():
        p = os.path.join(PREVIEW, name)
        ok = os.path.exists(p) and image_size(p) == size
        check("预览 %s 存在且尺寸 %dx%d" % (name, size[0], size[1]), ok,
              str(image_size(p) if os.path.exists(p) else "missing"))

    tokens = parse_brand_tokens()
    blue = hex2rgb(tokens["furryos-blue"])
    pale = hex2rgb(tokens["furryos-blue-pale"])
    white = hex2rgb(tokens["furryos-white"])
    deep = hex2rgb(tokens["furryos-blue-deep"])
    dark = hex2rgb(tokens["furryos-blue-dark"])

    # --- SDDM 1600x900：卡片 / 按钮 / 爪印 / 背景 ---
    p = os.path.join(PREVIEW, "sddm-login-1600x900.png")
    h = histogram(p, (380, 560, 131, 170))       # 登录卡片
    check("SDDM 卡片是白底（>=60% 白色像素）", fraction(h, white) >= 0.6,
          "white=%.2f" % fraction(h, white))
    h = histogram(p, (2, 1, 5, 5))
    check("SDDM 页面底是 furryos-blue-pale", dominant(h) == pale, str(dominant(h)))
    h = histogram(p, (320, 48, 161, 600))        # 登录按钮
    check("SDDM 登录按钮是 furryos-blue", fraction(h, blue) >= 0.3,
          "blue=%.2f" % fraction(h, blue))
    check("SDDM 按钮内的爪印/文字是白色（爪印可见）", fraction(h, white) >= 0.01,
          "white=%.3f" % fraction(h, white))

    # --- 版式缩放：2560 卡片宽度应为 1600 的 1.6 倍 ---
    def card_width(png, y):
        half = image_size(png)[0] // 2
        crop = "100%x1+0+" + str(y)
        out = subprocess.run(["convert", png, "-crop", crop, "+repage", "txt:-"],
                             capture_output=True, text=True).stdout
        xs = []
        for line in out.splitlines()[1:]:
            m = re.match(r"^(\d+),\d+:\s*\((\d+),(\d+),(\d+)", line)
            if m and int(m.group(1)) < half and \
                    (int(m.group(2)), int(m.group(3)), int(m.group(4))) == white:
                xs.append(int(m.group(1)))
        if not xs:
            return 0
        # 卡片 = 该行最左与最右的白色像素（卡片内部有爪印/输入框，不能取最长连续段）
        return max(xs) - min(xs) + 1

    w1600 = card_width(os.path.join(PREVIEW, "sddm-login-1600x900.png"), 450)
    w2560 = card_width(os.path.join(PREVIEW, "sddm-login-2560x1440.png"), 720)
    check("SDDM 版式按 screenScale 等比缩放（2560 卡片宽 ≈ 1.6×1600）",
          abs(w2560 / max(w1600, 1) - 1.6) < 0.05,
          "1600w=%d 2560w=%d ratio=%.2f" % (w1600, w2560, w2560 / max(w1600, 1)))

    # --- KSplash：字标必须深色且 AA 达标 ---
    p = os.path.join(PREVIEW, "ksplash-1920x1080.png")
    # 字标带：设计基线 y=700，字号 96 → 取 y 620..710
    h = histogram(p, (900, 90, 510, 620))
    # 背景取字标带左上角（字标从 y=630 起），不能取直方图众数——众数就是字标本身
    bg = pixel_at(p, 520, 625)
    worst = None
    for c, n in h.items():
        if n < 20:
            continue
        r = contrast(c, bg)
        if worst is None or r > worst[1]:
            worst = (c, r)
    check("KSplash 字标是深色且在背景上达到 AA 4.5:1",
          worst is not None and worst[1] >= 4.5 and luminance(worst[0]) < luminance(bg),
          "color=%s contrast=%.2f bg=%s" % (worst[0], worst[1], bg))
    check("KSplash 字标色接近 furryos-blue-deep",
          worst is not None and all(abs(a - b) <= 60 for a, b in zip(worst[0], deep)),
          str(worst[0] if worst else None))
    # 爪印：上部白色
    h = histogram(p, (300, 300, 810, 300))
    check("KSplash 爪印在画面上部且为白色", fraction(h, white) >= 0.05,
          "white=%.2f" % fraction(h, white))
    # 进度指示：底部品牌蓝弧线（四段弧只有一段是不透明主色，其余按 0.6/0.35/0.15
    # 叠在浅底上，因此只数「精确主色」像素并校验位置）
    h = histogram(p, (100, 100, 910, 860))
    nblue = sum(n for c, n in h.items() if c == blue)
    check("KSplash 进度指示为品牌蓝弧线（精确 #1A6FD4 像素 >= 50）", nblue >= 50,
          "count=%d" % nblue)
    out = subprocess.run(["convert", p, "-crop", "100x100+910+860", "+repage",
                          "-fill", "black", "+opaque", "#1A6FD4",
                          "-fill", "white", "-opaque", "#1A6FD4",
                          "-format", "%@", "info:"],
                         capture_output=True, text=True).stdout
    m = re.match(r"(\d+)x(\d+)\+(\d+)\+(\d+)", out)
    if m:
        cx = 910 + int(m.group(3)) + int(m.group(1)) / 2
        cy = 860 + int(m.group(4)) + int(m.group(2)) / 2
        check("KSplash 进度指示位于画面底部中央（设计坐标 960,900 ±30）",
              abs(cx - 960) <= 30 and abs(cy - 900) <= 30,
              "center=(%.0f,%.0f)" % (cx, cy))
    else:
        check("KSplash 进度指示位于画面底部中央（设计坐标 960,900 ±30）", False, out)

    # --- 启动画面母版：字标/进度条同样达标（复用 verify-splash-pixels） ---
    sp = subprocess.run([sys.executable,
                         os.path.join(WS, "assets", "effects", "splash",
                                      "verify-splash-pixels.py"),
                         os.path.join(PREVIEW, "splash-master-1920x1080.png")],
                        capture_output=True, text=True)
    tail = [l for l in sp.stdout.splitlines() if "通过" in l or "失败" in l]
    check("启动画面母版 SVG 渲染后通过像素校验（18 项）",
          sp.returncode == 0, "; ".join(tail[-2:]))

    # --- Plymouth 合成图：渐变 + 白爪印 ---
    p = os.path.join(PREVIEW, "plymouth-1920x1080.png")
    top = dominant(histogram(p, (10, 10, 0, 0)))
    bot = dominant(histogram(p, (10, 10, 0, 1070)))
    check("Plymouth 背景上端 = furryos-blue-deep", near(top, deep), str(top))
    check("Plymouth 背景下端 = furryos-blue", near(bot, blue), str(bot))
    h = histogram(p, (256, 256, 832, 412))
    check("Plymouth 中央爪印为白色", fraction(h, white) >= 0.1,
          "white=%.2f" % fraction(h, white))

    # --- 桌面合成图：面板 / 标题栏 / 选中色 ---
    p = os.path.join(PREVIEW, "desktop-1920x1080.png")
    h = histogram(p, (200, 20, 800, 1046))
    check("桌面面板条 = [Colors:Window] BackgroundNormal（极浅蓝）",
          fraction(h, pale) >= 0.9, "pale=%.2f" % fraction(h, pale))
    # 取标题栏右半段（避开标题文字与 1px 分隔线）
    h = histogram(p, (600, 30, 700, 226))
    check("窗口标题栏 = [WM] activeBackground（极浅蓝）", fraction(h, pale) >= 0.9,
          "pale=%.2f" % fraction(h, pale))
    h = histogram(p, (600, 20, 320, 270))
    check("窗口内容区 = [Colors:View] BackgroundNormal（白）", fraction(h, white) >= 0.9,
          "white=%.2f" % fraction(h, white))
    h = histogram(p, (200, 14, 340, 344))
    check("选中态 = [Colors:Selection] BackgroundNormal（主色）",
          fraction(h, blue) >= 0.9, "blue=%.2f" % fraction(h, blue))
    h = histogram(p, (200, 14, 340, 388))
    check("次要文字 = furryos-text-muted", fraction(h, hex2rgb(
        tokens["furryos-text-muted"])) >= 0.5,
        str(dominant(h)))


# ---------------------------------------------------------------- 5. 探针
def section_5_probe(probe):
    print("\n=== [5] 组件属性（qmlscene 实例化后读运行时值） ===")
    if not probe:
        check("qmlscene 探针可用", False, "未提供 --probe-json")
        return
    b = probe["button"]
    f = probe["field"]
    t = probe["theme"]
    check("按钮高度 = Theme.buttonHeight",
          b["implicitHeight"] == t["buttonHeight"], str(b["implicitHeight"]))
    check("按钮圆角 = Theme.radiusControl", b["radius"] == t["radiusControl"],
          str(b["radius"]))
    check("按钮正常态 = furryos-blue", b["normalColor"].lower() == t["furryosBlue"],
          b["normalColor"])
    check("按钮禁用态底 = furryos-blue-pale", b["disabledColor"].lower() == t["furryosDisabledBg"],
          b["disabledColor"])
    ratio = contrast(hex2rgb(b["disabledTextColor"]), hex2rgb(b["disabledColor"]))
    check("按钮禁用态文字可读（>=4.5:1）", ratio >= 4.5, "%.2f:1" % ratio)
    check("输入框错误态描边 = furryos-negative",
          f["errorBorderColor"].lower() == t["furryosNegative"], f["errorBorderColor"])
    check("输入框错误态描边宽 = 2px", f["errorBorderWidth"] == 2,
          str(f["errorBorderWidth"]))
    check("输入框字号 = Theme.bodyFontPx", f["fontSize"] == t["bodyFontPx"],
          str(f["fontSize"]))
    check("字号层级递增（label < body < title < display）",
          t["labelFontPx"] < t["bodyFontPx"] < t["titleFontPx"] < t["displayFontPx"],
          "%d < %d < %d < %d" % (t["labelFontPx"], t["bodyFontPx"],
                                 t["titleFontPx"], t["displayFontPx"]))
    check("圆角层级递增（control < card）",
          t["radiusControl"] < t["radiusCard"],
          "%d < %d" % (t["radiusControl"], t["radiusCard"]))
    check("输入框与按钮圆角同一档（radiusControl）", f["radius"] == t["radiusControl"],
          "%d vs %d" % (f["radius"], t["radiusControl"]))


def main():
    probe_path = None
    args = sys.argv[1:]
    for i, a in enumerate(args):
        if a == "--probe-json" and i + 1 < len(args):
            probe_path = args[i + 1]
    probe = None
    if probe_path and os.path.exists(probe_path):
        with open(probe_path) as fh:
            probe = json.load(fh)

    print("=== FurryOS 视觉统一校验（工作区 %s） ===" % WS)
    section_1_tokens(probe)
    section_2_motion(probe)
    section_3_brand()
    section_4_previews()
    section_5_probe(probe)

    print("\n=== 汇总 ===")
    print("通过 %d 项，失败 %d 项" % (len(PASSES), len(FAILS)))
    if FAILS:
        print("失败项:")
        for f in FAILS:
            print("  -", f)
        return 1
    print("视觉统一校验通过：四层资产共用同一套色板/动效/爪印母题，"
          "登录→桌面→启动画面观感一致，系统设置显示 FurryOS。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
