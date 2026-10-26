# FurryOS 桌面视觉层（assets/desktop）

桌面视觉层负责「配色 / 默认壁纸 / 桌面主题」三件套，目标是**新用户首次登录
即为 FurryOS 外观**。所有色值统一取自
[`../brand/brand-tokens.md`](../brand/brand-tokens.md)，爪印符号统一取自
[`../brand/paw.svg`](../brand/paw.svg)，未自创配色、未使用任何上游品牌素材。

## 一、产出放在哪里

| 产出 | 位置 | 注入后的系统路径 |
|---|---|---|
| KDE 配色方案 | [`FurryOS.colors`](FurryOS.colors) | `/usr/share/color-schemes/FurryOS.colors` |
| 默认壁纸（位图） | [`wallpaper.png`](wallpaper.png) | `/usr/share/wallpapers/FurryOS/contents/images/1920x1080.png` |
| 默认壁纸（矢量源） | [`wallpaper.svg`](wallpaper.svg) | 同上目录 `1920x1080.svg` |
| 壁纸插件包 | [`wallpapers/FurryOS/`](wallpapers/FurryOS/) | `/usr/share/wallpapers/FurryOS/` |
| 全局主题（look-and-feel） | [`look-and-feel/com.furryos.lookandfeel/`](look-and-feel/com.furryos.lookandfeel/) | `/usr/share/plasma/look-and-feel/com.furryos.lookandfeel/` |
| 桌面主题（plasma theme） | [`plasma-theme/furryos/`](plasma-theme/furryos/) | `/usr/share/plasma/desktoptheme/furryos/` |
| 新用户预置配置 | [`skel/`](skel/) | `/etc/skel/`（含 `.config/kdeglobals` 等） |
| 资产生成脚本 | [`.tools/`](.tools/) | 不进镜像，仅工作区留存 |

注入动作由 build-verify 的
`build/config/hooks/normal/6110-integrate-desktop-assets.chroot` 完成，
该 hook 只搬运本目录内容，不定义内容。

## 二、它解决哪条需求

按 [`../docs/CONTRACTS.md`](../docs/CONTRACTS.md)「成员二：桌面视觉层」表逐条对应：

| 契约要求 | 本层如何满足 |
|---|---|
| 完整 KDE 配色方案，覆盖窗口/视图/按钮等主要界面元素的背景色、文字色、强调色 | `FurryOS.colors` 提供 8 个颜色集（Window / View / Button / Selection / Tooltip / Complementary / Header / Header[Inactive]），每个集合含 BackgroundNormal、BackgroundAlternate、ForegroundNormal、ForegroundActive、ForegroundInactive、ForegroundLink、ForegroundNegative/Neutral/Positive/Visited、DecorationFocus、DecorationHover；另含 `[ColorEffects:Disabled]`、`[ColorEffects:Inactive]`、`[KDE] contrast`、`[WM]` 窗口装饰色 |
| 配色默认随系统下发 | 写入 `/usr/share/color-schemes/`，并在 `/etc/skel/.config/kdeglobals` 与 `/etc/xdg/kdeglobals` 设 `ColorScheme=FurryOS` |
| 默认壁纸：蓝白渐变 + 抽象爪印 | `wallpaper.png` 为 1920×1080 三段蓝白渐变（`#0A3568`→`#1A6FD4`→`#EAF2FF`），叠加由 `paw.svg` 几何派生的爪印符号：左上深色区一枚白色水印爪印，底部浅色带一串由大到小的蓝色爪印 |
| 壁纸中可辨认出爪印元素（非写实兽爪） | 爪印直接复用 `assets/brand/paw.svg` 的 path 与 ellipse 数据（圆润主垫 + 四颗椭圆脚趾），属「爪印符号」；5 个图层的可辨认性、品牌色归属与脚趾分离度均有像素级实测数据（见第三节） |
| 桌面主题样式基于 Breeze 二次设计，不得使用上游品牌素材 | `look-and-feel` 与 `plasma-theme` 只引用系统自带 `breeze` / `breeze_cursors` / `kde-style-breeze`，通过 `plasmarc`、`colors`、`defaults` 覆盖配色与默认壁纸；`X-KDE-fallbackPackage=org.kde.breeze.desktop` 保证缺文件时回落到 Breeze 而不报错 |
| 新用户首次登录即为 FurryOS 外观 | `/etc/skel/.config/` 预置 `kdeglobals`（配色+壁纸+点击特效）、`kwinrc`、`plasmarc`、`plasma-org.kde.plasma.desktop-appletsrc`（壁纸插件与路径） |
| `/etc/skel/.config/kdeglobals` 由成员二统一合并 | 本目录 `skel/.config/kdeglobals` 已合并 motion-effects 提供的 `[Effects] Click=true` 与 `[Effect-mouseclick]` 段（来自 `assets/effects/click-effect/kdeglobals-effects.conf`）；`skel/.config/kwinrc` 已合并 `[Plugins] mouseclickEnabled=true` 与同一组 `[Effect-mouseclick]` 外观键（来自 `kwinrc-effects.conf`）。**kwinrc 是权威位置**：已用 `strings -el` 反查 noble 的 `libkwin.so.5.27.11`，该库只从 `kdeglobals` 读 `Colors:Window` 组、没有任何 `Effects` 组；特效开关走 `kwinrc` `[Plugins]` + `Enabled` 后缀，外观走组名模板 `Effect-%1`（即 `Effect-mouseclick`），由 `kwin_mouseclick_config.so` 提供 8 个键且走 KConfig 对 `kwin` 组件的默认文件 `kwinrc` |

统一验收「配色、壁纸、主题三者一致」的保证方式：三个入口（
`/usr/share/color-schemes/FurryOS.colors`、`/etc/skel/.config/kdeglobals`、
`look-and-feel/.../contents/defaults`）写入的是**同一组色值与同一个壁纸包名**，
不存在可以互相分裂的第二来源。

## 三、用什么方式确认它生效

以下命令在**已构建的 FurryOS 系统**（或 live 会话）中执行。宿主 Debian 12 无法
安装 KDE，故本层验证采用「文件到位 + 格式审查 + 色值比对」，真机观感见
`docs/VERIFICATION.md`（build-verify 负责）。

### 0. 一键自检（本层自带，宿主即可运行）

```bash
cd /root/furryos/assets/desktop && python3 .tools/verify-all.py
```

跑三个脚本：`verify-colors.py`（配色格式+色板合规）、`verify-wallpaper.py`
（壁纸渐变+爪印可辨认性）、`verify-consistency.py`（配色/skel/主题一致性+
对比度复核）。三者全部 PASS 才算本层自检通过。

### 1. 配色方案已随系统下发且被选为默认

```bash
# 文件已安装
ls -l /usr/share/color-schemes/FurryOS.colors

# 默认方案指向 FurryOS（系统级 + 新用户级）
grep -H '^ColorScheme=' /etc/xdg/kdeglobals /etc/skel/.config/kdeglobals
# 期望两行都是 ColorScheme=FurryOS

# 会话内实际生效值（登录后执行；需要 KDE 会话）
kreadconfig5 --file kdeglobals --group General --key ColorScheme
# 期望输出 FurryOS
```

### 2. 壁纸已安装且含爪印

```bash
# 壁纸包结构（与 Breeze 自带 Next 壁纸包同构）
ls -l /usr/share/wallpapers/FurryOS/contents/images/
identify /usr/share/wallpapers/FurryOS/contents/images/1920x1080.png
# 期望 1920x1080
```

**爪印可辨认性的像素级证明**（`python3 .tools/verify-wallpaper.py` 实测输出）：

```
wallpaper: 1920x1080
  gradient top    y=0    expect (10, 53, 104)  got (10, 53, 104)  OK
  gradient bottom y=1079 expect (234, 242, 255) got (234, 242, 255) OK
  gradient middle y=540  expect ~(26, 111, 212) got (26, 111, 212)  OK
  watermark-white pad=(66, 133, 213)  bg=(25, 106, 203)  dev=41 ... VISIBLE BRAND-MATCH
                 gap=(15, 72, 139) gap-dev=0 | toe=(58, 105, 160) toe-dev=43 PAW-SHAPED
  trail-blue-1   pad=(142, 185, 236) bg=(192, 216, 246) dev=50 ... VISIBLE BRAND-MATCH
                 gap=(111, 165, 230) gap-dev=0 | toe=(86, 149, 225) toe-dev=25 PAW-SHAPED
  trail-blue-2   pad=(102, 159, 228) bg=(164, 198, 240) dev=62 ... VISIBLE BRAND-MATCH
                 gap=(102, 159, 228) gap-dev=0 | toe=(68, 137, 221) toe-dev=34 PAW-SHAPED
  trail-blue-3   pad=(65, 136, 220)  bg=(138, 182, 235) dev=73 ... VISIBLE BRAND-MATCH
                 gap=(93, 154, 226) gap-dev=1 | toe=(49, 126, 217) toe-dev=45 PAW-SHAPED
  trail-blue-4   pad=(37, 118, 215)  bg=(118, 169, 231) dev=81 ... VISIBLE BRAND-MATCH
                 gap=(87, 149, 225) gap-dev=0 | toe=(33, 116, 214) toe-dev=54 PAW-SHAPED
PASS: brand gradient + 5 paw layers, each visible, on-palette and paw-shaped
      (separate toes => paw symbol, not a claw).
```

三项含义：

- **渐变是品牌蓝白**：上/中/下三点与 `#0A3568` / `#1A6FD4` / `#EAF2FF`
  逐一相等（误差 0）。
- **爪印可辨认**：5 个爪印图层的主垫像素相对同行理论背景的偏差为
  **41 / 50 / 62 / 73 / 81**，远超"看得见"的阈值 8；且每个像素都是品牌色
  与背景的混合（与理论值误差 0–1），证明爪印确实用 `furryos-blue`
  `#1A6FD4` 或 `furryos-white` `#FFFFFF` 绘制，而非无关色。
- **是爪印符号而非实心块/写实兽爪**：`gap` 是两只内侧脚趾之间的空隙，
  与背景偏差 0–1（仍是背景色）；而脚趾本身偏差 25–54。两者同时成立说明
  脚趾是**互相分离**的，即「圆润主垫 + 四颗独立脚趾」的爪印符号。

在目标系统上等价的单点抽样命令：

```bash
convert /usr/share/wallpapers/FurryOS/contents/images/1920x1080.png \
        -format '%[pixel:p{20,10}] %[pixel:p{20,1070}] %[pixel:p{280,910}]' info:
# 期望形如  srgb(10,53,104) srgb(234,242,255) srgb(...)
# 分别是深蓝端、浅蓝端、以及左下第一个爪印区域的混合色
```

### 3. 桌面主题与全局主题可用

```bash
# 全局主题包已被 KPackage 识别
ls -l /usr/share/plasma/look-and-feel/com.furryos.lookandfeel/
ls -l /usr/share/plasma/desktoptheme/furryos/

# 元数据可解析（Plasma 5 读 metadata.desktop）
grep -E '^(X-KDE-PluginInfo-Name|X-KDE-ServiceTypes|X-Plasma-MainScript)=' \
   /usr/share/plasma/look-and-feel/com.furryos.lookandfeel/metadata.desktop

# 主题声明的默认壁纸与默认配色
grep -E '^(ColorScheme|Image)=' \
   /usr/share/plasma/look-and-feel/com.furryos.lookandfeel/contents/defaults
```

`python3 .tools/verify-consistency.py` 已核对全部 6 个入口
（`FurryOS.colors`、`skel/.config/kdeglobals`、`look-and-feel/.../defaults`、
`skel/.config/plasmarc`、`plasma-theme/furryos/plasmarc`、
`skel/.config/plasma-org.kde.plasma.desktop-appletsrc`）指向同一个
`ColorScheme=FurryOS` 与同一个 `Image=FurryOS`，输出见上。

### 4. 新用户首次登录即定制外观

```bash
# /etc/skel 已预置
ls -l /etc/skel/.config/kdeglobals /etc/skel/.config/kwinrc \
      /etc/skel/.config/plasmarc \
      /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc

# 关键默认值
grep -E '^(ColorScheme|Image|Click)=' /etc/skel/.config/kdeglobals
grep -E '^(mouseclickEnabled|Color1|RingLife)=' /etc/skel/.config/kwinrc
grep -A1 'org.kde.image' /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc

# 点击特效外观的权威位置是 kwinrc（KWin 5.27 不读 kdeglobals 的 [Effects]），
# 所以两个文件里的 [Effect-mouseclick] 必须一致：
diff <(sed -n '/^\[Effect-mouseclick\]/,/^\[/p' /etc/skel/.config/kdeglobals) \
     <(sed -n '/^\[Effect-mouseclick\]/,/^\[/p' /etc/skel/.config/kwinrc) \
  && echo "IDENTICAL"
# 期望 IDENTICAL

# 用一个新用户实测（不需要登出，useradd -m 即会拷贝 /etc/skel）
sudo useradd -m furrytest
sudo -u furrytest dbus-launch kreadconfig5 --file kdeglobals \
     --group General --key ColorScheme
# 期望 FurryOS
sudo -u furrytest dbus-launch kreadconfig5 --file kwinrc \
     --group Plugins --key mouseclickEnabled
# 期望 true
sudo userdel -r furrytest
```

### 5. 三者一致性的最终确认（登录后目视）

依次打开：

1. 桌面背景是否为蓝白渐变 + 爪印；
2. 系统设置 → 颜色 中「FurryOS」是否为当前方案（强调色 `#1A6FD4`）；
3. 系统设置 → 全局主题 中「FurryOS」是否可选且选中后外观不变。

三项都对上即满足「配色、壁纸、主题三者一致」。

## 四、设计说明与限制

### 渐变为什么不用 SVG `<linearGradient>`

宿主 Debian 12 的 ImageMagick 6.9 内置 MSVG 渲染器会**静默丢弃**
`<linearGradient>`（实测退化为 1-bit bilevel 图像），且对每个图元的首末扫描线
画一条黑缝。因此壁纸位图由 `.tools/gen-wallpaper.py` 生成：

- 背景用 ImageMagick 原生 `gradient:`（两段 `#0A3568→#1A6FD4`、
  `#1A6FD4→#EAF2FF`，用 `-append` 拼接，接缝不可见）；
- 爪印用 SVG 渲染后以 `-fuzz 2% -opaque black` 去掉黑缝（爪印是纯
  `#1A6FD4`/`#FFFFFF`，去黑不会损伤图元本身）；
- 图层透明度用 `-compose dissolve -define compose:args=<pct>`（MSVG 忽略 SVG
  `opacity` 属性，且 IM6 的 `-channel A -evaluate multiply` 在 16-bit 下会污染
  RGB）。

以上每一条都有像素级验证记录，见 `.tools/` 下脚本注释。

`wallpaper.svg` 是同一构图的矢量源文件（供后续编辑），不用于光栅化。

### 爪印为什么这样摆放（有实测依据，不是凭感觉）

渐变在 y=540 处正好是 `#1A6FD4`。一枚**蓝色**爪印压在这一行上时，与背景的
最大偏差只有 2–5（255 级），等于看不见。因此构图遵循两条规则：

1. **白色**水印爪印放在**左上深色区**（`#0A3568`→`#1A6FD4` 段），浅色标记在
   深底上对比最强；
2. **蓝色**爪印串放在**底部浅色带**（y ≥ 660），且每个图层的边界框互不重叠，
   保证没有爪印被另一个爪印盖住、每一枚都读作独立的爪印。

`.tools/verify-wallpaper.py` 把这两条作为断言检查：每个图层的主垫偏差必须
≥ 8、与理论混合值误差 ≤ 14、且两只内侧脚趾之间的空隙必须仍是背景色
（证明脚趾分离）。当前 5 个图层的偏差为 41 / 50 / 62 / 73 / 81。

### 语义色为什么保留 Breeze 原值

`ForegroundNegative`（红）/ `ForegroundNeutral`（橙）/ `ForegroundPositive`（绿）/
`ForegroundVisited`（紫）承载「错误 / 警告 / 成功 / 已访问」的语义，不属于品牌
色板范围；保留 Breeze 上游取值，保证语义识别不被破坏。品牌色只用于背景、文字、
强调与装饰。

### Plasma 版本前提

Ubuntu 24.04 LTS（noble）的 Plasma 为 5.27.12（已从 Ubuntu 源实测
plasma-workspace / plasma-desktop / breeze 的 deb 版本确认），因此主题元数据用
`metadata.desktop`（Plasma 5 格式），不是 Plasma 6 的 `metadata.json`。
