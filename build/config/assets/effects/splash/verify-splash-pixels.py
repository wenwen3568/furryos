#!/usr/bin/env python3
# FurryOS 交互动效层 —— 启动画面渲染结果像素抽查
#
# 目的：在无法启动真实 Plasma 的宿主上，用「像素级断言」验证启动画面资产
#       的视觉构成（蓝白渐变 + 白爪印 + FurryOS 字标 + 副标语 + 底部进度条），
#       并核对色值与 assets/brand/brand-tokens.md 一致。
#
# 前置：先执行 ./render-preview.sh 生成 furryos-splash-preview.png
#       （宿主 ImageMagick 内部 SVG 渲染器不支持 linearGradient，
#         故用等价 MVG 路径光栅化，SVG 仍是唯一源资产）
#
# 前置也可用 Qt 渲染的真实 SVG 母版（tools/render-previews.sh 产出
#       docs/preview/splash-master-1920x1080.png），本脚本对两者都适用：
#       断言全部基于「元素像素相对同一行背景的对比度」，不依赖绝对色号。
#
# t5 变更（强化，不是放宽）：
#   早先第 3/4 节断言「字标行/进度条区域存在白色像素」。这条断言有两个问题：
#     (a) 它把「白色」当成设计前提，而白色字标压在浅蓝背景上只有 1.8:1；
#     (b) 它用 235/235/235 阈值，进度条那一行背景本身就是 (239,245,255)，
#         于是「一个像素都没画」也能通过 —— 是恒真断言。
#   现在改为：断言字标/副标语是深蓝且在背景上达到 WCAG AA（>=4.5:1），
#   进度条是品牌蓝且达到 >=3:1，并且底轨与已完成段可区分（进度条形状存在）。
#
# 用法：python3 verify-splash-pixels.py [图片路径]
# 退出码：0 = 全部通过；1 = 有失败项；2 = 无法解析图片

import os
import re
import subprocess
import sys

# 默认图与脚本同目录：早先的版本用相对当前目录的裸文件名，只有恰好在
# assets/effects/splash 下执行才找得到（CI 从仓库根目录跑就会失败）。
SELF_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_IMG = os.path.join(SELF_DIR, 'furryos-splash-preview.png')
IMG = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_IMG

# brand-tokens.md 色值
TOKENS = {
    'furryos-blue-deep':  (0x0A, 0x35, 0x68),
    'furryos-blue-dark':  (0x0F, 0x4C, 0x8C),
    'furryos-blue':       (0x1A, 0x6F, 0xD4),
    'furryos-blue-light': (0xD6, 0xE6, 0xF7),
    'furryos-blue-pale':  (0xEA, 0xF2, 0xFF),
    'furryos-white':      (0xFF, 0xFF, 0xFF),
    'furryos-text':       (0x12, 0x28, 0x3F),
    'furryos-text-muted': (0x4A, 0x63, 0x7C),
}

# 设计坐标（furryos-splash.svg 的 1920x1080 基准）
DESIGN_W = 1920.0
DESIGN_H = 1080.0
DESIGN = {
    'paw':      (810, 300, 256),        # 中央爪印 bbox
    'wordmark': 700,                    # 字标基线
    'subtitle': 762,                    # 副标语基线
    'bar_y':    903,                    # 进度条中心线
    'bar_x0':   660,                    # 进度条左端
    'bar_fill': 900,                    # 已完成段右端
    'bar_x1':   1260,                   # 底轨右端
    'wordmark_px': 96,
    'subtitle_px': 30,
}

fails = []
passes = []


def load_pixels(path):
    """解析 ImageMagick txt: 输出为 {(x,y): (r,g,b)}"""
    out = subprocess.run(['convert', path, 'txt:-'], capture_output=True, text=True)
    if out.returncode != 0:
        print('ERROR: convert failed:', out.stderr[:300])
        sys.exit(2)
    px = {}
    pat = re.compile(r'^(\d+),(\d+):\s*\((\d+),(\d+),(\d+)(?:,(\d+))?\)')
    for line in out.stdout.split('\n')[1:]:
        m = pat.match(line)
        if m:
            x, y, r, g, b = (int(m.group(i)) for i in range(1, 6))
            px[(x, y)] = (r, g, b)
    return px


def near(c1, c2, tol=12):
    return all(abs(a - b) <= tol for a, b in zip(c1, c2))


def luminance(rgb):
    def ch(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(x) for x in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(c1, c2):
    la, lb = luminance(c1), luminance(c2)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def check(name, cond, detail=''):
    if cond:
        passes.append(name)
        print(f'  [PASS] {name}' + (f'  {detail}' if detail else ''))
    else:
        fails.append(name)
        print(f'  [FAIL] {name}  {detail}')


class Canvas:
    """像素画布 + 渐变背景查询（背景只沿垂直方向变化，故取左边缘同行为背景）。"""

    def __init__(self, px, w, h):
        self.px = px
        self.w = w
        self.h = h

    def get(self, x, y):
        return self.px.get((x, y))

    def bg(self, y):
        # 左边缘 2px 处没有任何元素（装饰爪印从 x=120 设计坐标起）
        for x in (2, 1, 3):
            c = self.get(x, y)
            if c is not None:
                return c
        return None

    def band_extremes(self, x0, x1, y0, y1, step=1):
        """返回 (最高对比像素, 最高对比值, 达标像素数) 相对同一行背景。"""
        best = None
        best_ratio = 0.0
        strong = 0
        for y in range(max(0, y0), min(self.h, y1), step):
            bg = self.bg(y)
            if bg is None:
                continue
            for x in range(max(0, x0), min(self.w, x1), step):
                c = self.get(x, y)
                if c is None:
                    continue
                r = contrast(c, bg)
                if r >= 4.5:
                    strong += 1
                if r > best_ratio:
                    best_ratio, best = r, c
        return best, best_ratio, strong


def main():
    print(f'=== FurryOS 启动画面像素抽查: {IMG} ===')
    px = load_pixels(IMG)
    if not px:
        print('ERROR: no pixels parsed')
        sys.exit(2)

    xs = [p[0] for p in px]
    ys = [p[1] for p in px]
    W, H = max(xs) + 1, max(ys) + 1
    c = Canvas(px, W, H)
    s = W / DESIGN_W
    print(f'尺寸: {W}x{H}  采样点: {len(px)}  缩放 s={s:.4f}')

    # ---------- 1. 蓝白渐变：从上到下应经历 深蓝 -> 蓝 -> 浅 -> 白 ----------
    print('\n--- [1] 蓝白渐变垂直分层（左边缘取样，避开元素） ---')
    samples = [c.get(2, y) for y in (int(H * 0.02), int(H * 0.30), int(H * 0.60), int(H * 0.97))]
    labels = ['顶部(深蓝)', '上部(蓝)', '中部(浅)', '底部(白)']
    for lab, col in zip(labels, samples):
        if col is None:
            check(f'渐变采样 {lab}', False, 'pixel missing')
            continue
        print(f'    {lab:10s} = #{col[0]:02X}{col[1]:02X}{col[2]:02X}')
    top = samples[0]
    check('顶部为深蓝端(#0A3568 附近)',
          top is not None and near(top, TOKENS['furryos-blue-deep'], 24)
          and top[2] > top[0] and sum(top) < 300,
          f'got {top}')
    bot = samples[3]
    check('底部为白端(#FFFFFF 附近)',
          bot is not None and near(bot, TOKENS['furryos-white'], 20),
          f'got {bot}')
    bs = [col[2] for col in samples if col]
    check('蓝色分量自上而下递增（渐变方向正确）',
          all(bs[i] <= bs[i + 1] + 2 for i in range(len(bs) - 1)),
          f'blue channel: {bs}')

    # ---------- 2. 中央爪印：白色，位于画面中央偏上 ----------
    print('\n--- [2] 中央爪印（白色） ---')
    pdx, pdy, pds = DESIGN['paw']
    paw_x0, paw_y0 = int(pdx * s), int(pdy * s)
    paw_x1, paw_y1 = int((pdx + pds) * s), int((pdy + pds) * s)
    white_in_paw = 0
    total_in_paw = 0
    for y in range(paw_y0, min(paw_y1, H), 2):
        for x in range(paw_x0, min(paw_x1, W), 2):
            col = c.get(x, y)
            if col is None:
                continue
            total_in_paw += 1
            if col[0] > 235 and col[1] > 235 and col[2] > 235:
                white_in_paw += 1
    check('爪印区域存在白色像素（爪印已渲染）',
          white_in_paw > 50,
          f'white={white_in_paw} / sampled={total_in_paw}')
    center = c.get(int(938 * s), int(477 * s))
    check('爪印主垫中心接近白色',
          center is not None and center[0] > 200 and center[1] > 200,
          f'({int(938*s)},{int(477*s)})={center}')

    # ---------- 3. FurryOS 字标：深蓝 + AA 对比度 ----------
    print('\n--- [3] FurryOS 字标（深蓝字，背景为浅蓝渐变） ---')
    wy = DESIGN['wordmark']
    band_y0, band_y1 = int((wy - DESIGN['wordmark_px'] * 0.9) * s), int((wy + 10) * s)
    best, ratio, strong = c.band_extremes(int(0.28 * W), int(0.72 * W), band_y0, band_y1)
    print(f'    采样带 y={band_y0}..{band_y1}  最强像素={best}  对比度={ratio:.2f}:1'
          f'  达标像素={strong}')
    check('字标行存在高对比度文字像素（不是空白）', strong > 20, f'strong={strong}')
    check('字标颜色为深蓝品牌色（不是白色）',
          best is not None and near(best, TOKENS['furryos-blue-deep'], 45),
          f'best={best}')
    check('字标对比度达到 WCAG AA 4.5:1', ratio >= 4.5, f'{ratio:.2f}:1')

    # ---------- 4. 副标语 ----------
    print('\n--- [4] 副标语（深蓝字） ---')
    sy = DESIGN['subtitle']
    b0, b1 = int((sy - DESIGN['subtitle_px'] * 0.9) * s), int((sy + 8) * s)
    best2, ratio2, strong2 = c.band_extremes(int(0.28 * W), int(0.72 * W), b0, b1)
    print(f'    采样带 y={b0}..{b1}  最强像素={best2}  对比度={ratio2:.2f}:1'
          f'  达标像素={strong2}')
    check('副标语行存在高对比度文字像素', strong2 > 8, f'strong={strong2}')
    check('副标语颜色为深蓝（blue-dark 一档）',
          best2 is not None and near(best2, TOKENS['furryos-blue-dark'], 50),
          f'best={best2}')
    check('副标语对比度达到 WCAG AA 4.5:1', ratio2 >= 4.5, f'{ratio2:.2f}:1')

    # ---------- 5. 底部进度条：品牌蓝，底轨与已完成段可区分 ----------
    print('\n--- [5] 底部进度条（品牌蓝，非白色） ---')
    by = int(DESIGN['bar_y'] * s)
    fx0, fx1 = int(DESIGN['bar_x0'] * s), int(DESIGN['bar_fill'] * s)
    tx0, tx1 = int((DESIGN['bar_fill'] + 10) * s), int((DESIGN['bar_x1'] - 10) * s)
    fill_best, fill_ratio, _ = c.band_extremes(fx0, fx1, by, by + 1)
    track_best, track_ratio, _ = c.band_extremes(tx0, tx1, by, by + 1)
    print(f'    已完成段 最强像素={fill_best}  对比度={fill_ratio:.2f}:1')
    print(f'    底轨段   最强像素={track_best}  对比度={track_ratio:.2f}:1')
    check('进度条已完成段为品牌蓝（#1A6FD4/#0F4C8C 一档）',
          fill_best is not None and (near(fill_best, TOKENS['furryos-blue'], 45)
                                     or near(fill_best, TOKENS['furryos-blue-dark'], 45)),
          f'filled={fill_best}')
    check('进度条已完成段对比度 >= 3:1（非文字图形阈值）',
          fill_ratio >= 3.0, f'{fill_ratio:.2f}:1')
    check('底轨可见但与已完成段可区分（进度条形状存在）',
          track_ratio > 1.05 and track_ratio < fill_ratio * 0.85,
          f'track={track_ratio:.2f}:1 vs filled={fill_ratio:.2f}:1')

    # 进度条水平范围必须与设计坐标一致（660..1260）
    # 阈值 1.15：8-bit 渐变在同一行内的量化噪声实测最大 1.10:1，
    # 底轨（18% 品牌蓝）是 1.28:1，已完成段是 4.49:1 —— 三者可清晰分开。
    row = [x for x in range(0, W)
           if c.get(x, by) is not None and c.bg(by) is not None
           and contrast(c.get(x, by), c.bg(by)) > 1.15]
    if row:
        check('进度条水平范围与设计坐标一致（660..1260 设计像素）',
              abs(row[0] - DESIGN['bar_x0'] * s) <= 4 and abs(row[-1] - DESIGN['bar_x1'] * s) <= 4,
              f'got x={row[0]}..{row[-1]}, expect {DESIGN["bar_x0"]*s:.0f}..{DESIGN["bar_x1"]*s:.0f}')
    else:
        check('进度条水平范围与设计坐标一致（660..1260 设计像素）', False, 'no bar pixels')

    # ---------- 6. 品牌色一致性 ----------
    print('\n--- [6] brand-tokens.md 色值一致性 ---')
    blue_hits = 0
    for y in range(0, H, 3):
        for x in range(0, W, 3):
            col = c.get(x, y)
            if col and near(col, TOKENS['furryos-blue'], 10):
                blue_hits += 1
    check('画面中存在 furryos-blue #1A6FD4', blue_hits > 20, f'{blue_hits} sampling points')

    pale_hits = 0
    for y in range(int(H * 0.7), H, 2):
        for x in range(0, W, 4):
            col = c.get(x, y)
            if col and near(col, TOKENS['furryos-blue-pale'], 14):
                pale_hits += 1
    check('画面中存在 furryos-blue-pale #EAF2FF', pale_hits > 10, f'{pale_hits} sampling points')

    # ---------- 7. 品牌合规（无 Ubuntu 元素） ----------
    print('\n--- [7] 品牌合规（无 Ubuntu 商标色/元素） ---')
    ubuntu_orange = 0
    for y in range(0, H, 2):
        for x in range(0, W, 2):
            col = c.get(x, y)
            if col and col[0] > 200 and 60 < col[1] < 110 and col[2] < 60:
                ubuntu_orange += 1
    check('画面不含 Ubuntu 品牌橙 #E95420', ubuntu_orange == 0,
          f'orange-ish pixels: {ubuntu_orange}')

    # ---------- 汇总 ----------
    print('\n=== 汇总 ===')
    print(f'通过 {len(passes)} 项，失败 {len(fails)} 项')
    if fails:
        print('失败项:')
        for f in fails:
            print('  -', f)
        sys.exit(1)
    print('启动画面视觉构成验证通过：蓝白渐变 + 白爪印 + 深蓝字标/副标语 + 品牌蓝进度条；'
          '文字与进度条相对背景均达到 WCAG 阈值，色值与 brand-tokens.md 一致。')


if __name__ == '__main__':
    main()
