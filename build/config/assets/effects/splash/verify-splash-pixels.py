#!/usr/bin/env python3
# FurryOS 交互动效层 —— 启动画面渲染结果像素抽查
#
# 目的：在无法启动真实 Plasma 的宿主上，用「像素级断言」验证启动画面资产
#       的视觉构成（蓝白渐变 + 白爪印 + FurryOS 字标 + 底部进度条），
#       并核对色值与 assets/brand/brand-tokens.md 一致。
#
# 前置：先执行 ./render-preview.sh 生成 furryos-splash-preview.png
#       （宿主 ImageMagick 内部 SVG 渲染器不支持 linearGradient，
#         故用等价 MVG 路径光栅化，SVG 仍是唯一源资产）
#
# 用法：python3 verify-splash-pixels.py [图片路径]
# 退出码：0 = 全部通过；1 = 有失败项

import re
import subprocess
import sys

IMG = sys.argv[1] if len(sys.argv) > 1 else 'furryos-splash-preview.png'

# brand-tokens.md 色值
TOKENS = {
    'furryos-blue-deep':  (0x0A, 0x35, 0x68),
    'furryos-blue':       (0x1A, 0x6F, 0xD4),
    'furryos-blue-pale':  (0xEA, 0xF2, 0xFF),
    'furryos-white':      (0xFF, 0xFF, 0xFF),
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


def check(name, cond, detail=''):
    if cond:
        passes.append(name)
        print(f'  [PASS] {name}' + (f'  {detail}' if detail else ''))
    else:
        fails.append(name)
        print(f'  [FAIL] {name}  {detail}')


def main():
    print(f'=== FurryOS 启动画面像素抽查: {IMG} ===')
    px = load_pixels(IMG)
    if not px:
        print('ERROR: no pixels parsed')
        sys.exit(2)

    xs = [p[0] for p in px]
    ys = [p[1] for p in px]
    W, H = max(xs) + 1, max(ys) + 1
    print(f'尺寸: {W}x{H}  采样点: {len(px)}')

    # ---------- 1. 蓝白渐变：从上到下应经历 深蓝 -> 蓝 -> 浅 -> 白 ----------
    print('\n--- [1] 蓝白渐变垂直分层（避开元素的中线取样） ---')
    # 取左侧 2% 处（远离中央爪印与字标）
    col = 2
    samples = [px.get((col, y)) for y in (int(H * 0.02), int(H * 0.30), int(H * 0.60), int(H * 0.97))]
    labels = ['顶部(深蓝)', '上部(蓝)', '中部(浅)', '底部(白)']
    for lab, c in zip(labels, samples):
        if c is None:
            check(f'渐变采样 {lab}', False, 'pixel missing')
            continue
        print(f'    {lab:10s} = #{c[0]:02X}{c[1]:02X}{c[2]:02X}')
    # 顶部必须明显偏蓝（B 通道最大，且整体暗）
    top = samples[0]
    check('顶部为深蓝端(#0A3568 附近)',
          top is not None and top[2] > top[0] and top[2] > 60 and sum(top) < 300,
          f'got {top}')
    # 底部必须接近白
    bot = samples[3]
    check('底部为白端(#FFFFFF 附近)',
          bot is not None and near(bot, TOKENS['furryos-white'], 20),
          f'got {bot}')
    # 单调性：蓝色分量从顶到底整体上升（深蓝->蓝->浅->白）
    bs = [c[2] for c in samples if c]
    check('蓝色分量自上而下递增（渐变方向正确）',
          all(bs[i] <= bs[i + 1] + 2 for i in range(len(bs) - 1)),
          f'blue channel: {bs}')

    # ---------- 2. 中央爪印：白色，位于画面中央偏上 ----------
    print('\n--- [2] 中央爪印（白色） ---')
    # 设计坐标：translate(810,300)，爪印占 256x256 设计单位
    # 预览坐标 = 设计坐标 * W/1920
    s = W / 1920.0
    paw_x0, paw_y0 = int(810 * s), int(300 * s)
    paw_x1, paw_y1 = int((810 + 256) * s), int((300 + 256) * s)
    # 爪印主垫中心：设计 (810+128, 300+150+27) ≈ (938, 477)
    cx, cy = int(938 * s), int(477 * s)
    white_in_paw = 0
    total_in_paw = 0
    for y in range(paw_y0, min(paw_y1, H), 2):
        for x in range(paw_x0, min(paw_x1, W), 2):
            c = px.get((x, y))
            if c is None:
                continue
            total_in_paw += 1
            if c[0] > 235 and c[1] > 235 and c[2] > 235:
                white_in_paw += 1
    ratio = white_in_paw / max(total_in_paw, 1)
    check('爪印区域存在白色像素（爪印已渲染）',
          white_in_paw > 50,
          f'white={white_in_paw} / sampled={total_in_paw} ({ratio:.1%})')

    # 爪印中心点应接近白
    center = px.get((cx, cy))
    check('爪印主垫中心接近白色',
          center is not None and center[0] > 200 and center[1] > 200,
          f'({cx},{cy})={center}')

    # ---------- 3. FurryOS 字标 ----------
    print('\n--- [3] FurryOS 字标 ---')
    # 设计坐标：text x=960 y=700，font-size 96 → 预览 y ≈ 700*s
    ty = int(700 * s)
    band = [px.get((x, ty)) for x in range(int(0.30 * W), int(0.70 * W))]
    bright = [c for c in band if c and c[0] > 235 and c[1] > 235 and c[2] > 235]
    check('字标行存在白色文字像素',
          len(bright) > 20,
          f'bright={len(bright)} at y={ty}')
    # 字标水平居中
    if bright:
        idx = [i for i, c in enumerate(band) if c and c[0] > 235 and c[1] > 235 and c[2] > 235]
        left = int(0.30 * W) + idx[0]
        right = int(0.30 * W) + idx[-1]
        mid = (left + right) / 2
        check('字标水平居中（偏离 < 8% 屏宽）',
              abs(mid - W / 2) < W * 0.08,
              f'字标 x {left}..{right}, 中心 {mid:.0f} vs 屏幕中心 {W/2:.0f}')

    # ---------- 4. 底部进度条 ----------
    print('\n--- [4] 底部进度条 ---')
    # 设计坐标：rect y=900..906，x 660..1260（底轨）+ 660..900（已完成）
    by = int(903 * s)
    track = [px.get((x, by)) for x in range(int(660 * s), int(1260 * s))]
    filled = [c for c in track if c and c[0] > 235 and c[1] > 235 and c[2] > 235]
    check('进度条区域存在白色像素',
          len(filled) > 10,
          f'filled={len(filled)} at y={by}')

    # ---------- 5. 品牌色一致性 ----------
    print('\n--- [5] brand-tokens.md 色值一致性 ---')
    # 中部应出现 furryos-blue #1A6FD4
    blue_hits = 0
    for y in range(0, H, 3):
        for x in range(0, W, 3):
            c = px.get((x, y))
            if c and near(c, TOKENS['furryos-blue'], 10):
                blue_hits += 1
    check('画面中存在 furryos-blue #1A6FD4',
          blue_hits > 20,
          f'{blue_hits} sampling points')

    pale_hits = 0
    for y in range(int(H * 0.7), H, 2):
        for x in range(0, W, 4):
            c = px.get((x, y))
            if c and near(c, TOKENS['furryos-blue-pale'], 14):
                pale_hits += 1
    check('画面中存在 furryos-blue-pale #EAF2FF',
          pale_hits > 10,
          f'{pale_hits} sampling points')

    # ---------- 6. 无 Ubuntu 元素（品牌合规） ----------
    print('\n--- [6] 品牌合规（无 Ubuntu 商标色/元素） ---')
    # Ubuntu 品牌橙 #E95420；画面中不应出现
    ubuntu_orange = 0
    for y in range(0, H, 2):
        for x in range(0, W, 2):
            c = px.get((x, y))
            if c and c[0] > 200 and 60 < c[1] < 110 and c[2] < 60:
                ubuntu_orange += 1
    check('画面不含 Ubuntu 品牌橙 #E95420',
          ubuntu_orange == 0,
          f'orange-ish pixels: {ubuntu_orange}')

    # ---------- 汇总 ----------
    print('\n=== 汇总 ===')
    print(f'通过 {len(passes)} 项，失败 {len(fails)} 项')
    if fails:
        print('失败项:')
        for f in fails:
            print('  -', f)
        sys.exit(1)
    print('启动画面视觉构成验证通过：蓝白渐变 + 白爪印 + FurryOS 字标 + 进度条，色值与 brand-tokens.md 一致。')


if __name__ == '__main__':
    main()
