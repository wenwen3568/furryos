# FurryOS 视觉规范与验收

> **一句话**：开机（GRUB 菜单）→ Plymouth 启动动画 → SDDM 登录界面 → KSplash 过渡 →
> 桌面，这五段共用**同一套 9 色色板、同一套动效参数、同一个爪印母题**；系统设置的
> 「关于本系统」显示的是 FurryOS 而不是 Ubuntu。
>
> **一键验收**：`bash tools/verify-visual.sh`
> → 15 项顶层检查（内含 `tools/verify-visual.py` 的 131 条断言、启动画面的 18 项像素断言）。

本文档的每一条结论都来自实际执行，命令与输出原样贴出。凡是本机无法真实渲染的部分
（完整 Plasma 桌面会话、Plymouth 帧缓冲），第 5 节明确写出替代方法与证据边界，
**不使用「已目视确认」这类无法复现的措辞**。

---

## 1. 视觉基线

### 1.1 色板

唯一来源是 [`assets/brand/brand-tokens.md`](../assets/brand/brand-tokens.md)。
任何界面新增颜色都必须先落到这张表，再被 `tools/verify-visual.py` 断言。

| 令牌 | 色值 | 用途 | 实测对比度 |
|---|---|---|---|
| `furryos-blue` | `#1A6FD4` | 主色：按钮、选中、进度条、焦点环 | 白字在其上 **4.92:1** |
| `furryos-accent-hover` | `#2C85EC` | 悬停态 | — |
| `furryos-blue-dark` | `#0F4C8C` | 按下态、副标语 | 白字在其上 **8.63:1** |
| `furryos-blue-deep` | `#0A3568` | 最深端：渐变顶、字标 | 浅蓝底上 **6.84:1** |
| `furryos-blue-light` | `#D6E6F7` | 边框、分隔线、非活动标题栏 | — |
| `furryos-blue-pale` | `#EAF2FF` | 页面底、面板底、非活动文字底 | 深蓝字在其上 **13.31:1** |
| `furryos-white` | `#FFFFFF` | 卡片、视图底 | 深蓝字在其上 **14.99:1** |
| `furryos-text` | `#12283F` | 正文 | — |
| `furryos-text-muted` | `#4A637C` | 次要文字、占位符 | — |
| `furryos-negative`（语义色） | `#B3261E` | 错误态 | 白底 **5.80:1** |

> 为什么错误色不用 KDE 默认的 `#DA4453`：它在白底上只有 3.78:1，达不到 AA。
> 换成 `#B3261E` 后是 5.80:1，同时仍在「红」的语义范围内。

### 1.2 母题：爪印

爪印是**唯一**的装饰元素，不允许出现第二个图形母题。两种反白版本：

| 文件 | 颜色 | 用在 |
|---|---|---|
| `assets/brand/paw.svg` | `#1A6FD4` 蓝 | 白/浅蓝底（登录卡片标题、SDDM 品牌面板） |
| `assets/sddm/furryos/assets/paw-white.svg` | `#FFFFFF` 白 | 主色底（登录按钮、启动画面、Plymouth） |

> t5 修复：登录按钮上的爪印原来是蓝色 `paw.svg` 压在 `#1A6FD4` 蓝底上，
> 像素级不可见（同色叠加）。新增白色反白版后，按钮内白色像素占比实测 43.6%。

### 1.3 动效

统一参数表见第 3 节。原则是**同一语义在所有界面用同一时长**：
悬停 140ms、按下 200ms、错误抖动 320ms、进度旋转 1500ms/圈、淡入 200ms。

---

## 2. 逐界面：改前问题 → 改后做法 → 验收

### 2.1 SDDM 登录界面（`assets/sddm/furryos/`）

#### 问题 1：禁用态按钮「消失」

改前 `FurryButton.qml` 的禁用态是「主色 + 0.45 透明度」，而文字颜色仍是白色：

```
# 改前实测（同一采样脚本）
禁用态底色 ≈ (26,111,212) × 0.45 叠加白底 → (140,176,231)
白字在其上 = 1.35:1   ← 远低于 AA 4.5:1，等于看不见
```

改后：禁用态底色 `furryos-blue-pale #EAF2FF` + 1px `furryos-blue-light` 边框，
文字 `furryos-text-muted #4A637C`。运行时实测：

```
$ bash tools/verify-visual.sh
  [PASS] 按钮禁用态底 = furryos-blue-pale  #eaf2ff
  [PASS] 按钮禁用态文字可读（>=4.5:1）  5.54:1
```

#### 问题 2：爪印在按钮上不可见

见 1.2 节。修复后按钮区域白色像素占比 **0.436**（`verify-visual.py` 断言 ≥0.01）。

#### 问题 3：版式不随分辨率缩放、字号没有层级

改前所有尺寸是写死的像素常数（卡片 380×560、字号 26/15/13 混用），
在 2560×1440 下卡片只占屏幕 15%，看起来「一小块飘在中间」。

改后引入 `Theme` 令牌 + `readonly property real screenScale`（= `height/900`），
所有尺寸写成 `Math.round(令牌 × s)`；字号定为 5 级阶梯
（`captionFontPx 12 < labelFontPx 13 < bodyFontPx 15 < titleFontPx 26 < displayFontPx 44`），
圆角 3 级（`radiusChip 8 < radiusControl 10 < radiusCard 18`）。

验收：同一份 QML 渲染两个尺寸，卡片宽度比必须等于缩放比：

```
$ bash tools/verify-visual.sh
  [PASS] SDDM 版式按 screenScale 等比缩放（2560 卡片宽 ≈ 1.6×1600）
         1600w=378 2560w=606 ratio=1.60
```

#### 问题 4：错误态没有反馈、键盘无法 Tab 切换

改后：`errorState` 让两个输入框描边变成 `furryos-negative` 2px，并让按钮与密码框
同时抖动 320ms（`Theme.shakeDuration` / `Theme.shakeAmplitude` = ±6px）；
`FurryField` 支持 Tab/Backtab 在字段间移动，占位符与输入文字同字号（避免焦点时跳字）。

```
$ bash tools/verify-visual.sh
  [PASS] 输入框错误态描边 = furryos-negative  #b3261e
  [PASS] 输入框错误态描边宽 = 2px  2
  [PASS] 输入框字号 = Theme.bodyFontPx  15
  [PASS] 错误抖动 = 320ms / ±6px  320ms / 6 px
```

#### 问题 5：登录界面上没有「FurryOS」字样

改前品牌面板只有爪印，没有字标。改后右侧品牌面板用 `displayFontPx`（44px）渲染
`FurryOS`，下方是副标语；卡片标题同样是「爪印 + FurryOS」。

```
$ grep -n 'text: "FurryOS"' assets/sddm/furryos/Main.qml
$ bash tools/verify-visual.sh
  [PASS] SDDM 登录界面含 FurryOS 字标（不是空着或写 Ubuntu/KDE）
  [PASS] SDDM 登录界面含品牌爪印 logo
```

#### 语法与渲染验收

```
$ bash tools/verify-visual.sh
== [1] qmllint（登录界面 + 组件） ==
  [PASS] qmllint 6 个文件无任何输出
== [2] qmlscene 探针：实例化组件树读运行时属性 ==
  [PASS] 探针输出解析成功（960 字节 JSON）
```

> 探针（`tools/preview/probe-sddm.qml`）真的用 `qmlscene` 创建组件树再读属性，
> 断言的是 Qt 解析后的运行时值，不是正则匹配源码字面量。

渲染产物：`docs/preview/sddm-login-1600x900.png`、`docs/preview/sddm-login-2560x1440.png`。

### 2.2 桌面（`assets/desktop/`）

#### 问题 1（本轮最严重）：面板停在 Breeze，窗口是 FurryOS —— 「一半一半」

改前 `skel/.config/plasmarc` 与全局主题的 `defaults` 都写着：

```ini
[plasmarc][Theme]
name=breeze
```

但 **Plasma 5.27 没有名为 `breeze` 的桌面主题**。证据（本机实跑，宿主的
KDE 5.27 组件与镜像内同源）：

```
$ QT_QPA_PLATFORM=offscreen XDG_DATA_HOME=… plasma-apply-desktoptheme breeze
Could not find theme "breeze". The theme should be one of the following options:
air, default, breeze-dark, breeze-light, furryos, oxygen, …
exit=255

$ plasma-apply-desktoptheme furryos
The current Plasma session's theme has been set to furryos
exit=0
```

`breeze` 主题名不存在时，Plasma **不报错**，只是保留上一次的主题 —— 于是面板背景、
弹窗、Oxygen 图标底都留在 Breeze，而窗口配色、壁纸、登录界面已经是 FurryOS。
这就是用户描述的「一半 FurryOS 一半 Breeze 的割裂感」的根因。

改后两处都写 `name=furryos`（指向 `assets/desktop/plasma-theme/furryos/`），
并且**用 KDE 自己的工具验证**，而不是只 grep 文件：

```
$ bash tools/verify-visual.sh
== [3] 在沙箱里真跑 plasma-apply-*，看 KDE 写出的 kdedefaults ==
  [PASS] plasma-apply-desktoptheme furryos 成功（主题是合法的 Plasma 主题）
  [PASS] plasma-apply-desktoptheme breeze 报错（证明 'breeze' 不是 Plasma 5.27 主题名，
  [PASS]   这正是旧配置 name=breeze 导致面板停在 Breeze 的根因）
  [PASS] 全局主题应用后 Plasma 桌面主题 = furryos
```

`plasma-apply-lookandfeel` 在沙箱里实际写出的 `kdedefaults/`：

```
$ for f in $XDG_CONFIG_HOME/kdedefaults/*; do echo "--- $f"; cat "$f"; done
--- …/kdedefaults/kcminputrc
[Mouse]
cursorTheme=breeze_cursors
--- …/kdedefaults/kdeglobals
[General]
fixed=Hack,10,-1,5,50,0,0,0,0,0
font=Noto Sans,10,-1,5,50,0,0,0,0,0
menuFont=Noto Sans,10,-1,5,50,0,0,0,0,0
toolBarFont=Noto Sans,10,-1,5,50,0,0,0,0,0
[Icons]
Theme=FurryOS
--- …/kdedefaults/kwinrc
[org.kde.kdecoration2]
NoPlugin=false
library=org.kde.breeze
theme=Breeze
--- …/kdedefaults/package
com.furryos.lookandfeel
--- …/kdedefaults/plasmarc
[Theme]
name=furryos
```

#### 问题 2：图标主题没有品牌化

改前 `[Icons] Theme=breeze`（直接用上游图标主题名）。改后新增极薄的品牌层
`assets/desktop/icons/FurryOS/index.theme`：

```ini
[Icon Theme]
Name=FurryOS
Inherits=breeze,hicolor
Directories=
ScaledDirectories=
```

它**不含任何图标文件**，只声明继承关系 —— 所以不可能因为「缺图标」而退化，
但系统设置里显示的图标主题名是 FurryOS。由构建钩子 `6110` 安装（见第 7 节）。

```
$ grep -E '^(Name|Inherits)=' assets/desktop/icons/FurryOS/index.theme
Name=FurryOS
Inherits=breeze,hicolor

$ bash tools/verify-visual.sh
  [PASS] 全局主题应用后图标主题 = FurryOS
```

#### 问题 3：字体没有钉死

改前全局主题的 `defaults` 与 skel `kdeglobals` 都**没有** `[General] font` 键，
会话字体取决于 KDE Frameworks 的编译期默认值。改后统一写
`font=Noto Sans,10,-1,5,50,0,0,0,0,0`、`fixed=Hack,10,…`
（两者都随镜像安装；镜像里没有 Ubuntu 字体，因此不存在上游字体泄漏）。

```
  [PASS] 全局主题应用后 正文字体 = Noto Sans,10,-1,5,50,0,0,0,0,0
  [PASS] 全局主题应用后 等宽字体 = Hack,10,-1,5,50,0,0,0,0,0
```

#### 问题 4：在系统设置里选中 FurryOS 全局主题，启动画面会变回 Breeze

改前 `com.furryos.lookandfeel/contents/defaults` 没有 `[KSplash]` 组
（Breeze 自己的全局主题是有的），于是选择 FurryOS 后 splash 保持上一次的选择。
改后写入 `[KSplash] Theme=org.furryos.desktop`。

> 证据边界：`plasma-apply-lookandfeel` 实测**不会**写 `kdedefaults/ksplashrc`
> （沙箱里 `find cfg -name '*ksplash*'` 为空），所以这一项只做静态断言 +
> 构建产物断言：镜像里 `/etc/xdg/ksplashrc` 由 `6131` 钩子写成
> `Theme=org.furryos.desktop`（`build/chroot/etc/xdg/ksplashrc` 实读）。

```
$ cat build/chroot/etc/xdg/ksplashrc
# FurryOS 启动画面默认值（由交互动效层安装脚本写入）
[KSplash]
Theme=org.furryos.desktop

$ grep -A1 '^\[KSplash\]' assets/desktop/look-and-feel/com.furryos.lookandfeel/contents/defaults
[KSplash]
Theme=org.furryos.desktop

$ python3 assets/desktop/.tools/verify-consistency.py | tail -1
PASS: colour scheme, /etc/skel defaults and the global theme all name FurryOS
(colour scheme, plasma theme, icon theme, fonts, wallpaper, splash); click effect
and glide animation keys merged; contrast claims verified.
```

#### 问题 5：窗口打开/关闭没有动画（硬弹出）

KWin 5.27 的 `glide` 效果元数据是 `EnabledByDefault=False`，即**默认关闭**，
所以窗口是「瞬间出现/消失」。改后在 `skel/.config/kwinrc` 写
`[Plugins] glideEnabled=true`。

> 为什么不写在全局主题里：实测 `plasma-apply-lookandfeel` 只应用
> `[kwinrc][org.kde.kdecoration2]`，`[kwinrc][Plugins]` 会被丢弃（上面的
> kdedefaults/kwinrc 只有 kdecoration2 一组）。所以它必须落在 skel。
> 也不写 `[Compositing] AnimationSpeed` —— 该键在 noble 的 `libkwin.so.5.27.11`
> 字符串表里不存在，写了无效。

#### 问题 6：plasma 主题的 `colors` 比配色方案少两组

改前 `plasma-theme/furryos/colors` 只有 6 个段落，缺 `[Colors:Header]` 与
`[Colors:Header][Inactive]`，面板/弹窗头部会回落到默认色。改后补齐为 8 组，
并与 `FurryOS.colors` **逐值一致**：

```
$ python3 tools/verify-visual.py
  [PASS] plasma 主题 colors 与 FurryOS.colors 逐值一致（同段落）  diff=[]
  [PASS] plasma 主题 colors 也含 [Colors:Header]（面板/弹窗头部）
```

#### 问题 7：主题元数据里的 Website 指向上游

`kde.org` 三处（全局主题、plasma 主题、splash 主题）改为
`https://furryos.example.org/`。

```
  [PASS] 主题元数据 Website 全部指向 furryos 域名（无 kde.org / ubuntu.com）
```

#### 桌面一致性总验收

```
$ python3 assets/desktop/.tools/verify-all.py
  colour scheme format + palette           PASS
  wallpaper gradient + paw mark            PASS
  theme / skel / contrast agreement        PASS
All 3 checks passed.
```

`verify-consistency.py` 现在覆盖 **6 个入口 × 8 个语义键**
（ColorScheme / AccentColor / widgetStyle / Icons Theme / plasma Theme name /
Image / defaultWallpaperTheme / KSplash Theme / font / fixed / glide /
AnimationDurationFactor），任一入口缺键或写错都直接 FAIL。

### 2.3 动效（`assets/effects/`）

#### 问题 1：启动画面白字压在浅蓝渐变上，几乎读不出来

改前 ksplash 与母版 SVG 的字标/副标语都是白色，而渐变在 y=65% 处已经淡到浅蓝：

```
# 改前实测（convert 采样同一行背景色，按 WCAG 公式计算）
ksplash 字标行 y=612  背景 (110,164,229)  白字 → 2.5:1
SVG 母版字标 y=700    背景 (159,193,239)  白字 → 1.8:1
SVG 进度条  y=903     背景 (239,245,255)  白条 → 1.1:1（等于没有）
```

改后保留四段渐变（与壁纸同构图），把下半部分的文字与进度条改成**深色/品牌蓝**：
字标 `#0A3568`、副标语 `#0F4C8C`、进度条已完成段 `#1A6FD4`、底轨 `#1A6FD4` 18%。

```
$ python3 assets/effects/splash/verify-splash-pixels.py docs/preview/splash-master-1920x1080.png
  [PASS] 字标颜色为深蓝品牌色（不是白色）  best=(10, 53, 104)
  [PASS] 字标对比度达到 WCAG AA 4.5:1  6.84:1
  [PASS] 副标语对比度达到 WCAG AA 4.5:1  5.87:1
  [PASS] 进度条已完成段对比度 >= 3:1（非文字图形阈值）  4.49:1
  [PASS] 底轨可见但与已完成段可区分（进度条形状存在）  track=1.28:1 vs filled=4.49:1
通过 18 项，失败 0 项
```

> 附带修复：这个脚本原来的「进度条存在」断言是白像素计数 —— 而进度条那一行的
> 背景本身就是 (239,245,255)，所以即使进度条根本没画出来也能通过（自证式断言）。
> 已改为基于对比度的断言（底轨 1.28:1 vs 已完成 4.49:1），并把「无 Ubuntu 橙」
> 一起纳入。

#### 问题 2：ksplash 与 Plymouth 的位置/速度各写一套

改后 ksplash 的所有元素按 `height/1080` 的比例定位，与母版 SVG 的设计网格一一对应
（爪印 y=300、字标基线 700、副标语 762、进度条 903）；旋转 1500ms/圈，
与 Plymouth spinner 的 `duration = 1.5` 秒完全一致：

```
  [PASS] ksplash 进度指示 1500ms/圈  1500
  [PASS] plymouth spinner 1.5s/圈，与 ksplash 一致  plymouth=1.5 s
  [PASS] ksplash 淡入时长走 PlasmaCore 令牌（200ms 量级）
```

淡入从 `veryLongDuration*2`（1000ms，偏拖沓）改为 `PlasmaCore.Units.longDuration`（200ms）。

#### 问题 3：点击特效的时长/颜色没有和品牌表对齐

点击特效三色为主色三阶（`26,111,212` / `15,76,140` / `10,53,104`），
`RingLife=250ms` 落在 brand-tokens 的「点击反馈 200–300ms」区间内，双层涟漪。

```
  [PASS] 点击特效 RingLife=250ms 落在点击反馈区间 (200, 300)
  [PASS] 点击特效 RingCount=2（双层涟漪）
  [PASS] 点击特效三色 = 主色/深蓝/最深蓝
```

### 2.4 系统设置里的品牌（`assets/identity/`）

改前的残留：「登录界面写 KDE Plasma、系统设置关于页写 Ubuntu」。

| 位置 | 改后值 | 断言 |
|---|---|---|
| `/etc/os-release` | `NAME="FurryOS"`、`PRETTY_NAME="FurryOS 24.04 LTS"` | `verify-identity.sh` / `verify-visual.py` |
| `kcm-about-distrorc` | `Name=FurryOS`、`Variant=Plasma Desktop`、`LogoPath=/usr/share/about-distro/furryos-logo.svg`、`Website=https://furryos.example.org/` | 同上 |
| 关于页 logo | 真实读取路径 `/usr/share/about-distro/furryos-logo.svg` | `verify-identity.sh` 断言文件存在 |
| GRUB 菜单标题 | `FurryOS Live (…amd64…)` 等 | `8000-brand-boot-menu.binary` |
| SDDM 主题名 | `FurryOS 登录主题` | `verify-visual.py` |
| 启动画面名 | `FurryOS 启动画面`（本轮从 `FurryOS` 改名，避免与全局主题在列表中重名） | 同上 |

```
$ bash tools/verify-identity.sh
结果：PASS=33 FAIL=0

$ python3 tools/verify-visual.py
  [PASS] os-release NAME=FurryOS  FurryOS
  [PASS] os-release PRETTY_NAME 以 FurryOS 开头  FurryOS 24.04 LTS
  [PASS] kcm-about-distrorc Name=FurryOS  FurryOS
  [PASS] kcm-about-distrorc Variant=Plasma Desktop  Plasma Desktop
  [PASS] kcm-about-distrorc LogoPath 指向 FurryOS logo  /usr/share/about-distro/furryos-logo.svg
  [PASS] 用户可见主题名称/描述均已品牌化（无 Ubuntu/KDE Plasma、非空）
  [PASS] 8000 钩子把启动菜单标题改写为 FurryOS
  [PASS] 8000 钩子重写 /.disk/info 为 FurryOS
```

---

## 3. 统一动效参数表

一张表覆盖全部界面。表中「落在区间」列对照 `brand-tokens.md` 第 4 节的区间，
由 `verify-visual.py` 自动核对（不是人工比对）。

| 语义 | 时长 | 曲线 | 用在哪 | 落在区间 |
|---|---|---|---|---|
| 悬停 | 140ms | `OutQuad` | SDDM 按钮/会话芯片底色与边框 | 120–160ms ✅ |
| 按下 | 200ms | `OutQuad` | SDDM 按钮缩放 0.96 | 180–240ms ✅ |
| 焦点描边 | 140ms | `OutQuad` | 输入框描边色/宽度 | 与悬停同档 |
| 错误抖动 | 320ms | 4 段 `InOutQuad`，±6px | 登录失败时按钮 + 密码框 | 320ms ✅ |
| 点击反馈 | 250ms | KWin `mouseclick` 涟漪 | 桌面任意点击 | 200–300ms ✅ |
| 进度旋转 | 1500ms/圈 | 线性 | ksplash 弧线 + Plymouth spinner | 与 Plymouth 一致 ✅ |
| 淡入 | 200ms | `InOutQuad` | ksplash 整屏淡入 | 200–300ms ✅ |
| 窗口开/关 | KWin 默认（`glide`） | — | 窗口出现/消失 | 已启用 ✅ |
| 全局倍率 | `AnimationDurationFactor=1` | — | KDE 全局动画速度 | 不加速也不拖慢 |

> 三个数字（140 / 200 / 320）只存在于 `Theme.qml` 一处，
> `FurryButton.qml` 与 `FurryField.qml` 通过 `Theme.hoverDuration` 等令牌引用，
> `verify-visual.py` 断言组件里没有另写数字（`Theme.hoverDuration` 出现 ≥2 次等）。

---

## 4. 预览图：每张能证明什么

`docs/preview/` 由 `bash tools/render-previews.sh` 生成（`verify-visual.sh --render`
会自动调用）。每张图的来源与断言如下 —— **不是截图，而是可复现的渲染产物**。

| 文件 | 怎么来的 | 断言（`verify-visual.py`） |
|---|---|---|
| `sddm-login-1600x900.png` | `qmlscene` 离屏实例化 `Main.qml` 后 `grabToImage()` | 卡片白底 83%、页面底 `#EAF2FF`、按钮主色 55%、按钮内白像素 43.6% |
| `sddm-login-2560x1440.png` | 同上，换成 2560×1440 | 卡片宽 606 / 378 = **1.60**，等于缩放比 |
| `ksplash-1920x1080.png` | 离屏实例化 `Splash.qml`，stage=2 淡入结束后抓帧 | 字标 `(10,53,104)` 对背景 `(117,168,231)` = **4.94:1**；爪印白色 18%；进度弧精确主色 93px 且中心 (948,914) ≈ 设计坐标 (960,900) |
| `splash-master-1920x1080.png` | QtSvg 渲染母版 `furryos-splash.svg` | 直接交给 `verify-splash-pixels.py`：18/18 |
| `plymouth-1920x1080.png` | **合成**：真实素材（`paw-white-256.png`、`spinner0.png`）+ `furryos.script` 的真实坐标公式 | 上端 `#0A3568`、下端 `#1A6FD4`、中央白爪印 26% |
| `desktop-1920x1080.png` | **合成**：真实壁纸 + 用 `FurryOS.colors`/`kdeglobals` 实值画的面板条与窗口示意 | 面板条 100% `#EAF2FF`、标题栏 100% `#EAF2FF`、窗口内容区 100% 白、选中条 100% `#1A6FD4`、次要文字 `#4A637C` |

---

## 5. 本机无法真渲染的部分（诚实声明）

宿主是 Debian 12 + KDE 5.27 组件库，**没有 X/Wayland 会话、没有 framebuffer**。
以下三项因此无法「截图」，本文档不声称目视确认，只给出替代证据：

1. **完整 Plasma 桌面（面板 + 窗口 + 图标）**
   - 替代：用 `plasma-apply-desktoptheme` / `plasma-apply-lookandfeel` 真跑，
     断言 KDE 自己写出的配置（第 2.2 节）；面板外观只用 `FurryOS.colors` 的实值
     合成示意（`desktop-1920x1080.png`），并在图注中标注「示意」。
   - 曾尝试直接渲染 Breeze 的 `widgets/panel-background.svg`（`PlasmaCore.FrameSvgItem`），
     在本机对**任何**主题都返回全透明并报 `kf.windowsystem: Could not find any platform plugin`，
     因此放弃该路径，改用「主题名可解析 + 配色逐值一致 + 结构与 KDE 自带
     breeze-light/breeze-dark 同构」三条可复现证据。

2. **Plymouth 启动动画**
   - 替代：用真实素材 + `furryos.script` 里的真实坐标公式合成
     （`plymouth-1920x1080.png`），断言渐变端点色与爪印可见性。
   - 未验证：Plymouth 自己的缩放策略（`Window.SetPosition`）与真机分辨率适配，
     需要在真机/虚拟机启动时观察。

3. **SDDM 真实会话**
   - 替代：`qmlscene` 离屏渲染同一份 `Main.qml`（同 Qt 版本、同 QML 引擎），
     两个分辨率验证等比缩放；`sddm` 的 `sddm-greeter` 专有 API 用
     `typeof sddm !== "undefined"` 探测，缺失时界面仍可渲染（探针即此路径）。

> 凡是「需要真机才能确认」的条目，都在 `docs/BUILD.md` 的 ISO 验收清单里，
> 不混进本文档的 PASS 计数。

---

## 6. 复跑清单

```bash
# 1) 视觉统一（15 项顶层检查 / 131 条断言）
bash tools/verify-visual.sh

# 2) 重新渲染预览（改了资产之后）
bash tools/render-previews.sh

# 3) 品牌与身份回归（t4 维护，本轮未改动其断言）
bash tools/verify-identity.sh      # 期望 PASS=33 FAIL=0
bash tools/verify-brand.sh         # 期望「全部通过（4 项检查，0 项跳过）」

# 4) 桌面层自身的三项检查
python3 assets/desktop/.tools/verify-all.py

# 5) 启动画面像素（可对任意图跑）
python3 assets/effects/splash/verify-splash-pixels.py docs/preview/splash-master-1920x1080.png
```

本轮实测结果（全部为实际执行输出）：

| 命令 | 结果 |
|---|---|
| `bash tools/verify-visual.sh` | 汇总 15 项，失败 0；其中 `verify-visual.py` 131 项、splash 18 项 |
| `bash tools/verify-identity.sh` | `PASS=33 FAIL=0` |
| `bash tools/verify-brand.sh` | 全部通过（4 项检查，0 项跳过） |
| `python3 assets/desktop/.tools/verify-all.py` | All 3 checks passed |
| `qmllint Main.qml components/*.qml` | 无输出（exit 0） |

---

## 7. 与构建钩子的接口

本轮**没有修改任何钩子的逻辑**（钩子归构建层维护）。只有一处「多装一个目录」的
最小改动，且带失败断言：

```diff
# build/config/hooks/normal/6110-integrate-desktop-assets.chroot
+    if [ -d "${SRC}/icons" ]; then
+        furryos_install_dir "${SRC}/icons" /usr/share/icons
+        furryos_log "installed icon theme packages"
+    fi
+    furryos_need_file /usr/share/icons/FurryOS/index.theme \
+        "installed FurryOS icon theme (run tools/sync-assets.sh)"
```

- 为什么必须改：`assets/desktop/icons/FurryOS/index.theme` 是 2.2 节「图标主题品牌化」
  的载体，不安装就等于没做。
- 为什么安全：`furryos_install_dir` 是已有函数（与同钩子里 wallpaper/plasma-theme
  的安装方式一致）；`furryos_need_file` 让「目录没同步」在构建时**立刻失败**，
  而不是产出一个看起来正常的镜像。
- 其余改动全部落在 `assets/` 内（配色、plasma 主题、全局主题 defaults、skel 配置、
  SDDM QML、splash 资源、元数据），钩子照原样安装即可。

---

## 8. 变更文件清单（本轮）

| 类别 | 文件 |
|---|---|
| SDDM 主题 | `assets/sddm/furryos/Main.qml`、`components/{Theme,FurryButton,FurryField,PawMark}.qml`、`assets/paw-white.svg`（新增） |
| 桌面 | `assets/desktop/FurryOS.colors`（未改值，仅核对）、`plasma-theme/furryos/{colors,metadata.json}`、`look-and-feel/com.furryos.lookandfeel/{contents/defaults,metadata.desktop}`、`skel/.config/{kdeglobals,kwinrc,plasmarc}`、`icons/FurryOS/index.theme`（新增） |
| 动效 | `assets/effects/splash/furryos-ksplash/{contents/splash/Splash.qml,contents/defaults,metadata.json}`、`assets/effects/splash/furryos-splash.svg`、`render-preview.sh`、`verify-splash-pixels.py` |
| 构建接口 | `build/config/hooks/normal/6110-integrate-desktop-assets.chroot`（+5 行） |
| 验收工具 | `tools/verify-visual.sh`（新）、`tools/verify-visual.py`（新）、`tools/render-previews.sh`（新）、`tools/preview/probe-sddm.qml`（新）、`assets/desktop/.tools/verify-consistency.py`（强化） |
| 文档/预览 | `docs/VISUAL.md`（本文）、`docs/preview/*.png`（6 张）、`assets/desktop/skel/README.md` |
