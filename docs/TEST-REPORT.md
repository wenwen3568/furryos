# FurryOS 测试报告（实测，非文档转述）

| 项 | 值 |
|---|---|
| 报告生成时间（UTC） | 2026-10-26T14:58:48Z |
| 被测仓库 | `/root/furryos`，分支 `main` |
| 被测提交 | `2da8add`（"docs: 补全 README，修复 BUILD.md 重复章节与 verify-identity.sh shebang"） |
| 跟踪文件数 / `.git` 体积 | 381 / 2.5M |
| 执行者 | test-runner（FurryOS Quality Team） |
| 执行方式 | 全部命令在本机实际执行；本文件是唯一被写入的工程文件 |
| 被测文件是否被修改 | **否**。执行前后 `git status --porcelain` 均只有一条既有的未跟踪项 `?? build/config/assets/effects/README.md` |

> 红线遵守说明：本报告所有结论均来自实际执行的命令与真实输出；未修改任何被测文件、脚本或断言，未放宽任何检查。
> 测试过程中安装到宿主的是两个**只读校验工具**（`qtdeclarative5-dev-tools`、`qmlscene`），属于宿主工具链补全，不改动仓库内容（见 §8）。

---

## 0. 环境信息

```
$ uname -a
Linux trim-219b 6.18.18.c952-trim #952 SMP PREEMPT_DYNAMIC ... x86_64 GNU/Linux

$ head -3 /etc/os-release
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
NAME="Debian GNU/Linux"
VERSION_ID="12"

$ dpkg-query -W -f='${Package} ${Version}\n' live-build
live-build 1:20230502

$ python3 -VV
Python 3.11.2 (main, May 12 2026, 05:17:27) [GCC 12.2.0]

$ bash --version | head -1
GNU bash, version 5.2.15(1)-release (x86_64-pc-linux-gnu)

$ convert --version | head -1
Version: ImageMagick 6.9.11-60 Q16 x86_64 2021-01-25

$ /usr/lib/qt5/bin/qmllint --version
qmllint 1.0                       # Qt 5.15.8+dfsg-3

$ git --version
git version 2.39.5
```

宿主 `qmllint` 原始状态为**坏链**：`/usr/bin/qmllint -> qtchooser`，而
`/usr/lib/qt5/bin/qmllint` 不存在（`qtdeclarative5-dev-tools` 未安装）。见 §3.4 与 §8。

---

## 1. 结论摘要

| 类别 | 结果 |
|---|---|
| 工程自带验证脚本 | **6 个脚本 / 11 次执行，10 次 exit 0，1 次 exit 1（宿主无 Plasma 会话，环境限制，非工程缺陷）** |
| 语法/编译检查 | **bash -n 53 文件 0 失败；python3 -m py_compile 16 文件 0 失败；dash -n 1 失败（预期内，脚本自身声明必须用 bash）** |
| QML 校验 | **qmllint 6 文件 0 问题；qmlscene 离屏加载 6/6 组件 + Main.qml 全部 exit 0** |
| 色值一致性 | **4 个指定令牌在 `FurryOS.colors` 全部存在；跨面重叠键 5/5 一致；发现 1 处离板硬编码 `#B3261E`** |
| 阻断性缺陷 | **无**（没有任何一项因为工程缺陷而失败） |
| 上报问题 | **10 项**（0 blocker / 0 high / 4 medium / 4 low / 2 info），详见 §5、§6 |

一句话结论：**工程自带的验证体系全部通过且可复验；但验证体系本身有 4 处"永远 PASS / 不读被测文件"的弱断言、1 个脚本无法在干净克隆上复现、1 处离板色值、1 个资产（ksplash）永不进入镜像。** 这些不是"跑不过"，而是"跑过了但证明力不足或覆盖面缺口"，需要 fixer / 审核方处理。

---

## 2. 逐项结果表

| # | 检查项 | 命令（工作目录 `/root/furryos`） | 退出码 | 结论 |
|---|---|---|---|---|
| 1 | 系统身份层 | `bash tools/verify-identity.sh` | 0 | PASS=33 FAIL=0 ✅ |
| 2a | 配色方案格式+调色板 | `python3 assets/desktop/.tools/verify-colors.py` | 0 | PASS ✅ |
| 2b | 壁纸渐变+爪印 | `python3 assets/desktop/.tools/verify-wallpaper.py` | 0 | PASS ✅ |
| 2c | 主题/skel/对比度一致性 | `python3 assets/desktop/.tools/verify-consistency.py` | 0 | PASS ✅ |
| 2d | 桌面视觉层聚合 | `python3 assets/desktop/.tools/verify-all.py` | 0 | 3/3 PASS ✅ |
| 3a | 启动画面像素抽查 | `cd assets/effects/splash && python3 verify-splash-pixels.py` | 0 | 通过 11 / 失败 0 ✅ |
| 3b | 点击特效（真实系统） | `sh assets/effects/click-effect/effects-verify.sh` | **1** | 宿主无 Plasma/无系统级配置 → 预期失败，见 §4.1 |
| 3c | 点击特效（构建前缀） | `PREFIX=/tmp/furryos-effects-prefix sh assets/effects/click-effect/effects-verify.sh` | 0 | 已启用（/etc/xdg 生效）✅ |
| 3d | 点击特效注入器 | `PREFIX=/tmp/furryos-effects-prefix sh assets/effects/click-effect/effects-install.sh` | 0 | 写入 4 个文件；二次执行 **diff 为空**（幂等）✅ |
| 3e | SDDM 主题安装器 | `sh assets/sddm/install-sddm-theme.sh assets/sddm/furryos /tmp/furryos-sddm-prefix` | 0 | 装出 11 个文件 + `/etc/sddm.conf`；幂等 ✅ |
| 4a | QML 语法（qmllint） | `cd assets/sddm/furryos && for f in Main.qml components/*.qml; do qmllint "$f"; done` | 0 | 6/6 无输出、无告警 ✅ |
| 4b | QML 实际加载（离屏） | `QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software qmlscene --quit Main.qml` | 0 | 零告警加载 ✅ |
| 4c | QML 组件实例化 | `qmlscene --quit /tmp/qmlcheck/check-components.qml` | 0 | 6 个组件全部实例化、绑定求值成功 ✅ |
| 5a | 色值：4 令牌存在性 | `python3 /tmp/audit/color-audit.py` | 0 | `#1A6FD4`×16、`#2C85EC`×9、`#0F4C8C`×8、`#EAF2FF`×10 ✅ |
| 5b | 色值：跨面同键一致 | `python3 /tmp/audit/key-overlap.py` | 0 | 重叠 5 键，0 不一致 ✅ |
| 5c | 色值：离板值扫描 | 同上 5a | 0 | 发现 `Main.qml:174 #B3261E` ⚠️ 见 §5 F5 |
| 6a | shell 语法 | `while read f; do bash -n "$f"; done < <(git ls-files \| grep -E '\.(sh\|chroot)$')` | 0 | 53 文件（18 `.sh` + 35 `.chroot`）0 失败 ✅ |
| 6b | POSIX 严格语法 | 同上，`sh -n` | 1 | 53 中 1 失败：`tools/verify-identity.sh`（**预期内**，见 §4.2）✅ |
| 6c | Python 编译 | `while read f; do python3 -m py_compile "$f"; done < <(git ls-files \| grep '\.py$')` | 0 | 16 文件 0 失败 ✅ |
| 7 | 提交物新鲜度 | 在 `/tmp` 重跑 `render-preview.sh` 后与入库 PNG 比对 | 0 | 像素 **完全一致**（md5 相同），仅 PNG 容器字节不同 ✅ |

---

## 3. 详细记录（命令 + 真实输出）

### 3.1 `tools/verify-identity.sh` — PASS=33 FAIL=0

```
$ bash tools/verify-identity.sh; echo "EXIT=$?"
== 1. 用上游包原始文件搭建模拟文件系统 ==
  快照目录：/root/furryos/.verify/sim
  注入前 /etc/os-release : PRETTY_NAME="Ubuntu 24.04.x LTS"
  ...
== 4. 注入后全文件系统扫描（登录后用户可见内容） ==
  [PASS] 注入后用户可见内容无 Ubuntu 字样（os-release 仅保留 ID=ubuntu 兼容字段）
==========================================
结果：PASS=33 FAIL=0
==========================================
EXIT=0

$ grep -c '\[PASS\]' <output>   # 33
$ grep -c '\[FAIL\]' <output>   # 0
```

**结论**：与任务给定的期望 `PASS=33 FAIL=0` 完全一致。**但该脚本不能在干净克隆上复现**，见 §5 F1。

### 3.2 桌面视觉层三件套 + 聚合器

```
$ python3 assets/desktop/.tools/verify-colors.py; echo EXIT=$?
FurryOS.colors: 13 sections
  [ColorEffects:Disabled] 7 keys     [Colors:Button] 12 keys
  [ColorEffects:Inactive] 9 keys     [Colors:Complementary] 12 keys
  [Colors:Header] 12 keys            [Colors:Header][Inactive] 12 keys
  [Colors:Selection] 12 keys         [Colors:Tooltip] 12 keys
  [Colors:View] 12 keys              [Colors:Window] 12 keys
  [General] 4 keys   [KDE] 1 keys   [WM] 6 keys

brand-tokens.md colours actually used (hex -> occurrences):
  #0A3568 (10, 53, 104)        1 USED
  #0F4C8C (15, 76, 140)        7 USED
  #12283F (18, 40, 63)         7 USED
  #1A6FD4 (26, 111, 212)      15 USED
  #2C85EC (44, 133, 236)       8 USED
  #4A637C (74, 99, 124)        8 USED
  #D6E6F7 (214, 230, 247)      9 USED
  #EAF2FF (234, 242, 255)      9 USED
  #FFFFFF (255, 255, 255)      8 USED

semantic (non-brand) colours kept from Breeze: 1 distinct
PASS: all required Breeze sets/keys present; every non-semantic colour value is a brand-tokens.md token.
EXIT=0
```

> 说明：脚本打印的 "semantic ... 1 distinct" 与 `SEMANTIC_RGB` 里列的 7 个 Breeze 语义色不一致，是因为
> 只有 `ForegroundNegative` 一族（`218,68,83`）真正出现在 `FurryOS.colors` 里；其余 6 个是白名单预留。
> 不影响判定，但会让读者误以为语义色只用了 1 个——属可读性问题，非失败。

```
$ python3 assets/desktop/.tools/verify-wallpaper.py; echo EXIT=$?
wallpaper: 1920x1080
  gradient top    y=0    expect (10, 53, 104)   got (10, 53, 104)   OK
  gradient bottom y=1079 expect (234, 242, 255) got (234, 242, 255) OK
  gradient middle y=540  expect ~(26, 111, 212) got (26, 111, 212)  OK
  watermark-white pad=(66, 133, 213) bg=(25, 106, 203) dev=41 expect=(66, 133, 212) err=1  VISIBLE BRAND-MATCH
                 gap=(15, 72, 139) gap-dev=0 | toe=(58, 105, 160) toe-dev=43 PAW-SHAPED
  trail-blue-1   pad=(142, 185, 236) bg=(192, 216, 246) dev=50 expect=(142, 184, 236) err=1 VISIBLE BRAND-MATCH
                 gap=(111, 165, 230) gap-dev=0 | toe=(86, 149, 225) toe-dev=25 PAW-SHAPED
  trail-blue-2   pad=(102, 159, 228) bg=(164, 198, 240) dev=62 expect=(102, 159, 227) err=1 VISIBLE BRAND-MATCH
                 gap=(102, 159, 228) gap-dev=0 | toe=(68, 137, 221) toe-dev=34 PAW-SHAPED
  trail-blue-3   pad=(65, 136, 220)  bg=(138, 182, 235) dev=73 expect=(65, 136, 220)  err=0 VISIBLE BRAND-MATCH
                 gap=(93, 154, 226)  gap-dev=1 | toe=(49, 126, 217) toe-dev=45 PAW-SHAPED
  trail-blue-4   pad=(37, 118, 215)  bg=(118, 169, 231) dev=81 expect=(37, 118, 214)  err=1 VISIBLE BRAND-MATCH
                 gap=(87, 149, 225)  gap-dev=0 | toe=(33, 116, 214) toe-dev=54 PAW-SHAPED

PASS: brand gradient + 5 paw layers, each visible, on-palette and paw-shaped (separate toes => paw symbol, not a claw).
EXIT=0
```

```
$ python3 assets/desktop/.tools/verify-consistency.py; echo EXIT=$?
=== 1. entry-point agreement ===
  FurryOS.colors           {'ColorScheme': 'FurryOS'}
  skel kdeglobals          {'ColorScheme': 'FurryOS', 'AccentColor': '26,111,212', 'Theme': 'breeze', 'widgetStyle': 'breeze', 'Image': 'FurryOS'}
  look-and-feel defaults   {'widgetStyle': 'breeze', 'ColorScheme': 'FurryOS', 'AccentColor': '26,111,212', 'Theme': 'breeze', 'name': 'breeze', 'Image': 'FurryOS'}
  skel plasmarc            {'name': 'breeze', 'defaultWallpaperTheme': 'FurryOS'}
  plasma-theme plasmarc    {'defaultWallpaperTheme': 'FurryOS'}
  skel appletsrc           {'Image': 'file:///usr/share/wallpapers/FurryOS/contents/images/1920x1080.png'}
  [Effect-mouseclick] identical in kdeglobals and kwinrc (8 keys)

=== 2. WCAG contrast ratios (brand-tokens.md claims) ===
  furryos-text on furryos-blue-pale   claimed  12.9  computed 13.31  OK
  furryos-text on furryos-white       claimed  15.2  computed 14.99  OK
  furryos-white on furryos-blue       claimed   4.7  computed  4.92  OK
  furryos-white on furryos-blue-dark  claimed   7.4  computed  8.63  OK

  shipped pair: Colors:View fg on bg =
    (18, 40, 63) on (255, 255, 255) -> 14.99:1
PASS: colour scheme, /etc/skel defaults and the global theme all name FurryOS; click-effect keys merged; contrast claims verified.
EXIT=0
```

```
$ python3 assets/desktop/.tools/verify-all.py; echo EXIT=$?
...
SUMMARY
  colour scheme format + palette           PASS
  wallpaper gradient + paw mark            PASS
  theme / skel / contrast agreement        PASS
All 3 checks passed.
EXIT=0
```

三个脚本均**与工作目录无关**（内部用 `abspath(__file__)` 定位），已在 `/` 下复跑验证：

```
$ cd / && python3 /root/furryos/assets/desktop/.tools/verify-colors.py      # exit 0
$ cd / && python3 /root/furryos/assets/desktop/.tools/verify-wallpaper.py   # exit 0
$ cd / && python3 /root/furryos/assets/desktop/.tools/verify-consistency.py # exit 0
```

### 3.3 交互动效层

```
$ cd assets/effects/splash && python3 verify-splash-pixels.py; echo EXIT=$?
=== FurryOS 启动画面像素抽查: furryos-splash-preview.png ===
尺寸: 640x360  采样点: 230400
--- [1] 蓝白渐变垂直分层 ---
    顶部(深蓝) = #0A376D   上部(蓝) = #155EB5   中部(浅) = #83B1E9   底部(白) = #FCFDFF
  [PASS] 顶部为深蓝端(#0A3568 附近)  got (10, 55, 109)
  [PASS] 底部为白端(#FFFFFF 附近)    got (252, 253, 255)
  [PASS] 蓝色分量自上而下递增（渐变方向正确）  blue channel: [109, 181, 233, 255]
--- [2] 中央爪印（白色） ---
  [PASS] 爪印区域存在白色像素（爪印已渲染）  white=471 / sampled=1849 (25.5%)
  [PASS] 爪印主垫中心接近白色  (312,159)=(246, 249, 253)
--- [3] FurryOS 字标 ---
  [PASS] 字标行存在白色文字像素  bright=67 at y=233
  [PASS] 字标水平居中（偏离 < 8% 屏宽）  字标 x 250..388, 中心 319 vs 屏幕中心 320
--- [4] 底部进度条 ---
  [PASS] 进度条区域存在白色像素  filled=200 at y=301
--- [5] brand-tokens.md 色值一致性 ---
  [PASS] 画面中存在 furryos-blue #1A6FD4  1439 sampling points
  [PASS] 画面中存在 furryos-blue-pale #EAF2FF  5272 sampling points
--- [6] 品牌合规（无 Ubuntu 商标色/元素） ---
  [PASS] 画面不含 Ubuntu 品牌橙 #E95420  orange-ish pixels: 0
=== 汇总 ===
通过 11 项，失败 0 项
EXIT=0
```

**点击特效（真实系统，环境不具备）**：

```
$ sh assets/effects/click-effect/effects-verify.sh; echo EXIT=$?
--- [2] 系统级默认 /etc/xdg（用户未设置时对新/老用户生效） ---
  [--] /etc/xdg/kwinrc mouseclickEnabled              文件不存在
  [--] /etc/xdg/kdeglobals Click                      文件不存在
--- [3] 新用户模板 /etc/skel（首次登录时复制到 ~/.config） ---
  [--] /etc/skel/.config/kwinrc mouseclickEnabled     文件不存在
--- [4] 运行时状态（需在 Plasma 会话中执行） ---
  [--] 当前不在 Plasma 会话或无 qdbus，跳过
=== 结论 ===
未启用：用户配置、系统级默认、新用户模板均未开启。
EXIT=1
```

这不是工程缺陷：宿主 Debian 12 上没有 Plasma，也没有 `/etc/xdg/kwinrc`。为了真正验证注入器+校验器的闭环，用 `PREFIX` 做了两组测试：

```
$ PFX=/tmp/furryos-effects-prefix; rm -rf $PFX; mkdir -p $PFX
$ PREFIX=$PFX sh assets/effects/click-effect/effects-install.sh; echo EXIT=$?
[furryos-effects] wrote $PFX/etc/skel/.config/kwinrc ([Plugins] mouseclickEnabled=true)
[furryos-effects] created $PFX/etc/skel/.config/kdeglobals with [Effects] Click=true (minimal, ...)
[furryos-effects] appended [Effect-mouseclick] palette to $PFX/etc/skel/.config/kwinrc
[furryos-effects] appended [Effect-mouseclick] palette to $PFX/etc/skel/.config/kdeglobals (compat)
[furryos-effects] wrote $PFX/etc/xdg/kwinrc ([Plugins] mouseclickEnabled=true)
[furryos-effects] wrote $PFX/etc/xdg/kdeglobals ([Effects] Click=true, compat layer)
[furryos-effects] appended [Effect-mouseclick] palette to $PFX/etc/xdg/kwinrc
[furryos-effects] done
EXIT=0

$ PREFIX=$PFX sh assets/effects/click-effect/effects-verify.sh; echo EXIT=$?
  [OK] /etc/xdg/kwinrc mouseclickEnabled              = true
  [OK] /etc/xdg/kdeglobals Click                      = true
  [OK] /etc/skel/.config/kwinrc mouseclickEnabled     = true
  [OK] /etc/skel/.config/kdeglobals Click             = true
=== 结论 ===
已启用：通过 /etc/xdg 系统级默认生效（用户未覆盖）。
EXIT=0
```

幂等性（真实构建顺序：6110 先把 `assets/desktop/skel` 合进 `/etc/skel`，再跑 6130 的安装器）：

```
$ PFX=/tmp/furryos-real-prefix; mkdir -p $PFX/etc/skel
$ cp -a assets/desktop/skel/. $PFX/etc/skel/
$ PREFIX=$PFX sh assets/effects/click-effect/effects-install.sh   # EXIT=0
$ diff -ru assets/desktop/skel/. $PFX/etc/skel/                   # 空 → 安装器对已合并文件零改写
$ PREFIX=$PFX sh assets/effects/click-effect/effects-verify.sh    # EXIT=0，结论同上

$ # 二次执行幂等性
$ cp -a $PFX/etc /tmp/effects-snap1/
$ PREFIX=$PFX sh assets/effects/click-effect/effects-install.sh   # EXIT2=0
$ diff -ru /tmp/effects-snap1/etc $PFX/etc; echo DIFF_EXIT=$?
DIFF_EXIT=0
```

**SDDM 主题安装器**（带 PREFIX，可测）：

```
$ sh assets/sddm/install-sddm-theme.sh assets/sddm/furryos /tmp/furryos-sddm-prefix; echo EXIT=$?
[furryos-sddm] 安装主题到 /tmp/furryos-sddm-prefix/usr/share/sddm/themes/furryos
[furryos-sddm] 写入 /tmp/furryos-sddm-prefix/etc/sddm.conf (Current=furryos)
[furryos-sddm] 完成。生效需要重启 SDDM: systemctl restart sddm
EXIT=0

$ find /tmp/furryos-sddm-prefix -type f | sort
/etc/sddm.conf
/usr/share/sddm/themes/furryos/Main.qml
/usr/share/sddm/themes/furryos/metadata.desktop
/usr/share/sddm/themes/furryos/theme.conf
/usr/share/sddm/themes/furryos/assets/paw.svg
/usr/share/sddm/themes/furryos/components/{FurryButton,FurryField,PawBackground,PawMark,Theme}.qml
/usr/share/sddm/themes/furryos/components/qmldir
```

> 注意：安装器生成的 `/etc/sddm.conf` 与 `assets/sddm/sddm.conf` **不一致**（后者有 `CursorTheme=Breeze_Snow`），见 §5 F6。

### 3.4 QML 校验（qmllint + 离屏实载）

宿主原始状态是坏链，**如实记录**：

```
$ ls -l /usr/bin/qmllint
lrwxrwxrwx 1 root root 9 May  4  2019 /usr/bin/qmllint -> qtchooser

$ qmllint --version
qmllint: could not exec '/usr/lib/qt5/bin/qmllint': No such file or directory
$ qtchooser -print-env
QT_SELECT="default"; QTTOOLDIR="/usr/lib/qt5/bin"; QTLIBDIR="/usr/lib/x86_64-linux-gnu"

$ ls /usr/lib/qt5/bin/
qdbus                      # 只有 qdbus，qmllint 不存在
$ dpkg -l | grep qtdeclarative5-dev-tools   # 未安装（Installed: (none)）
```

为让"QML 语法校验"这一项**真正被执行**而不是记为"无法执行"，安装了只读工具链（见 §8），之后：

```
$ cd assets/sddm/furryos
$ for f in Main.qml components/*.qml; do qmllint "$f"; echo "$f exit=$?"; done
Main.qml                   exit=0   (无输出)
components/FurryButton.qml exit=0   (无输出)
components/FurryField.qml  exit=0   (无输出)
components/PawBackground.qml exit=0 (无输出)
components/PawMark.qml     exit=0   (无输出)
components/Theme.qml       exit=0   (无输出)
```

Qt5 的 `qmllint 1.0` 只做语法/结构级检查，证明力有限，因此**加做了真实加载**（离屏 + 软件渲染）：

```
$ QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software XDG_RUNTIME_DIR=/tmp/runtime-root \
    /usr/lib/qt5/bin/qmlscene --quit Main.qml; echo EXIT=$?
EXIT=0                      # 零告警

$ qmlscene --quit /tmp/qmlcheck/check-components.qml; echo EXIT=$?
qml: Theme.furryosBlue      = #1a6fd4
qml: Theme.furryosBlueDark  = #0f4c8c
qml: Theme.furryosBlueDeep  = #0a3568
qml: Theme.furryosBluePale  = #eaf2ff
qml: Theme.furryosAccentHover = #2c85ec
qml: Theme.hoverDuration    = 140
qml: Theme.pressDuration    = 200
qml: Theme.shakeDuration    = 320
qml: btn.implicitHeight     = 48
qml: btn.state              = normal
qml: fld.implicitHeight     = 46
qml: shake() invoked OK
EXIT=0
```

（`check-components.qml` 是写在 `/tmp` 的一次性夹具，不属于仓库；它 `import "file:///root/furryos/assets/sddm/furryos/components"` 后实例化全部 6 个组件并调用 `shake()`。）
第一次尝试未加 `QT_QUICK_BACKEND=software` 时以 134 退出，原因是离屏平台建不出 OpenGL 上下文（`Failed to create OpenGL context`），**不是 QML 缺陷**；换软件渲染后 exit 0。

### 3.5 色值一致性（`#1A6FD4` / `#2C85EC` / `#0F4C8C` / `#EAF2FF`）

被测面：`assets/desktop/FurryOS.colors`、`assets/desktop/skel/.config/{kdeglobals,kwinrc}`、
`assets/sddm/**`、`assets/effects/**`、`assets/brand/brand-tokens.md`（唯一真源）。

**(a) 四个指定令牌在 `FurryOS.colors` 的实际出现次数**（十进制 RGB 形式）：

```
$ for pair in 1A6FD4:26,111,212 2C85EC:44,133,236 0F4C8C:15,76,140 EAF2FF:234,242,255; do
    hex=${pair%%:*}; rgb=${pair##*:}; echo "#$hex ($rgb) -> $(grep -c -- "$rgb" assets/desktop/FurryOS.colors)"
  done
#1A6FD4 (26,111,212) -> 15
#2C85EC (44,133,236) -> 8
#0F4C8C (15,76,140)  -> 7
#EAF2FF (234,242,255)-> 9
```

**(b) 同键跨面比对**（`FurryOS.colors` ↔ `skel/.config/kdeglobals`）：

```
  Colors:View    BackgroundAlternate  colors=234,242,255  kdeglobals=234,242,255  SAME
  Colors:View    BackgroundNormal     colors=255,255,255  kdeglobals=255,255,255  SAME
  Colors:Window  BackgroundAlternate  colors=214,230,247  kdeglobals=214,230,247  SAME
  Colors:Window  BackgroundNormal     colors=234,242,255  kdeglobals=234,242,255  SAME
  General        ColorScheme          colors=FurryOS      kdeglobals=FurryOS      SAME
  overlap keys=5  mismatches=0
```

`AccentColor=26,111,212` = `#1A6FD4` ✅；`kwinrc`/`kdeglobals` 的 `[Effect-mouseclick]`
`Color1/2/3 = 26,111,212 / 15,76,140 / 10,53,104` = `#1A6FD4 / #0F4C8C / #0A3568`，与
`brand-tokens.md` 及 `kdeglobals` 注释中的对应关系逐项吻合 ✅。

**(c) 全量离板值扫描**（`#RRGGBB` + `R,G,B` 两种写法，全部文件）：

```
  assets/desktop/FurryOS.colors                OFF-PALETTE {'#DA4453':7,'#F67400':7,'#27AE60':7,'#9B59B6':8,'#B03745':1,'#C65C00':1,'#176839':1}
  assets/desktop/skel/.config/kdeglobals       all 6 on-palette
  assets/desktop/skel/.config/kwinrc           all 3 on-palette
  assets/sddm/furryos/components/Theme.qml     all 9 on-palette
  assets/sddm/furryos/Main.qml                 OFF-PALETTE {'#B3261E': 1}      <-- 见 §5 F5
  assets/sddm/furryos/assets/paw.svg           all 1 on-palette
  assets/sddm/furryos/theme.conf               all 1 on-palette
  assets/effects/splash/furryos-splash.svg     all 4 on-palette
  assets/effects/click-effect/*.conf           all 3 on-palette each
  assets/brand/brand-tokens.md                 all 9 on-palette
```

`FurryOS.colors` 里的 7 个"离板"值全部是 `verify-colors.py` 显式白名单的 Breeze 语义色
（negative/neutral/positive/visited），属设计内行为，**不是不一致**。真正的离板值只有 1 个：
`Main.qml:174` 的 `#B3261E`。

### 3.6 语法与编译检查

```
$ git ls-files | grep -E '\.(sh|chroot)$' | wc -l
53          # 18 个 .sh + 35 个 .chroot

$ while read -r f; do bash -n "$f" || echo "FAIL $f"; done < <(git ls-files | grep -E '\.(sh|chroot)$')
checked=53 failed=0

$ while read -r f; do sh -n "$f" || echo "FAIL $f"; done < <(git ls-files | grep -E '\.(sh|chroot)$')
FAIL(2) tools/verify-identity.sh :: 155: Syntax error: "(" unexpected
checked=53 failed=1        # 预期内：该脚本 shebang 为 #!/bin/bash 且头注释明确"只能由 bash 执行"

$ export PYTHONPYCACHEPREFIX=/tmp/furryos-pycache
$ while read -r f; do python3 -m py_compile "$f" || echo "FAIL $f"; done < <(git ls-files | grep '\.py$')
checked=16 failed=0
```

补充：全部 6 个自有 `.chroot` 钩子 + `8000-brand-boot-menu.binary` 在 git 中均为 `100755`；
`furryos-common.sh` 是 `100644` 但它是被 `.` source 的库文件，无需可执行位。26 个 live-build 自带钩子是 `120000` 符号链接（指向宿主 `/usr/share/live/build/...`）。

### 3.7 提交物新鲜度（防止"预览图/SVG 漂移导致像素测试失真"）

`render-preview.sh` 会覆写被跟踪的 `furryos-splash-preview.png`，按约束**没有在仓库内执行**；
改为把脚本复制到 `/tmp/render/` 执行（脚本用 `dirname $0` 定位输出，因此输出落在 `/tmp`）：

```
$ cp assets/effects/splash/render-preview.sh /tmp/render/ && cd /tmp/render && sh ./render-preview.sh 640
wrote /tmp/render/furryos-splash-preview.png (640x360)

$ convert /tmp/render/furryos-splash-preview.png rgba:- | md5sum
e94377f4c7e98de22039b206892630d1
$ convert /root/furryos/assets/effects/splash/furryos-splash-preview.png rgba:- | md5sum
e94377f4c7e98de22039b206892630d1        # 像素完全一致

$ cmp /tmp/render/furryos-splash-preview.png assets/effects/splash/furryos-splash-preview.png
（字节不同，仅 tIME/tEXt 等 PNG 容器块差异；IDAT 长度同为 11190）
```

**结论**：入库的预览图与当前生成器输出**像素级一致**，像素测试不是对着过期图跑。

---

## 4. 两个"非缺陷失败"的定性

### 4.1 `effects-verify.sh` 在宿主上 exit 1 —— 环境限制，不是工程缺陷

* 根因：宿主是 Debian 12 无 Plasma 会话，`/etc/xdg/{kwinrc,kdeglobals}`、`/etc/skel/.config/*` 都不存在，`qdbus` 连不上 KWin。
* 该脚本的设计就是"检查真实系统"，因此它如实报告"未启用"并 exit 1，**行为正确**。
* 已用 `PREFIX` 在构建前缀上验证同一套逻辑 → exit 0（§3.3），证明脚本本身可用。
* 供 fixer 参考的复现：`PREFIX=/tmp/furryos-effects-prefix sh assets/effects/click-effect/effects-verify.sh`（需先跑安装器）。

### 4.2 `sh -n tools/verify-identity.sh` 报错 —— 脚本自我声明只能由 bash 执行

* 第 155 行使用进程替换 `<(...)`，dash 不支持。
* 脚本第 1 行已是 `#!/bin/bash`，第 7–8 行明确写着"只能由 bash 执行；用 sh（dash）运行会在第 152 行报 Syntax error"。
* **结论：符合预期，无需修复。** 仅提示：文档/CI 里必须写 `bash tools/verify-identity.sh`，不能写 `./tools/verify-identity.sh` 之外的 `sh tools/...`。

---

## 5. 测试断言质量审查（重点：永远 PASS / 不读被测文件）

> 按约束，发现断言写错**只上报、不改动**。

### F1 [medium] `tools/verify-identity.sh` 无法在干净克隆上复现

脚本依赖 `.verify/x/{base,ssh,motd}`（上游 Ubuntu 包解包产物）与 `.verify/fetch-refs.sh`，
而 `.verify/` 整个目录被 `.gitignore:42` 排除，**未入库**。

最小复现（已在独立 mount namespace 中实测，不污染真实目录）：

```
$ git ls-files .verify | wc -l
0
$ git check-ignore -v .verify/fetch-refs.sh
.gitignore:42:/.verify/	.verify/fetch-refs.sh

$ unshare -m --propagation private bash -c '
    mount -t tmpfs tmpfs /root/furryos/.verify
    cd /root/furryos && bash tools/verify-identity.sh; echo "EXIT=$?"'
== 1. 用上游包原始文件搭建模拟文件系统 ==
缺少上游参考包解包目录：/root/furryos/.verify/x/{base,ssh}
请先运行 .verify/fetch-refs.sh
EXIT=2
```

（测试后 `.verify/` 完好：21 个条目。）

**影响**：CI/新成员拿到仓库后 `bash tools/verify-identity.sh` 直接 exit 2，"PASS=33" 不可复现。
**建议修复方向**：把 `fetch-refs.sh` 纳入版本控制（它本身是脚本，不是大文件），并在
`tools/verify-identity.sh` 缺少参考包时自动调用或给出可一键执行的命令；同时在 CI 文档里写明前置步骤。
另注：脚本第 26 行把 `WS=/root/furryos` 写死，路径不可移植，建议改为 `WS="$(cd "$(dirname "$0")/.." && pwd)"`。

### F2 [low] `verify-identity.sh` 有 3 处结构上不可能 FAIL 的断言（PASS=33 含水分）

**(a) `/etc/os-release` 符号链接检查：两个分支都调用 `ok()`**

```
$ sed -n '162,172p' tools/verify-identity.sh
if [ -L "${SIM}/etc/os-release" ]; then
	ok '/etc/os-release 是指向 ../usr/lib/os-release 的符号链接（保留 dpkg 归属）'
	...
else
	ok '/etc/os-release 是真实文件（未保留符号链接，dpkg -S 将失效，可接受）'
fi
```

→ 无论哪种形态都记 PASS，这条断言**永远不可能失败**（它实际只是"记录形态"）。

**(b)(c) `00-header` / `10-help-text` 文件缺失时反而 PASS**

```
$ SIM=/tmp/w2-sim; mkdir -p $SIM/etc/update-motd.d    # 故意不放 00-header
$ grep -vE '^[[:space:]]*#' "$SIM/etc/update-motd.d/00-header" 2>/dev/null | grep -qi "ubuntu" \
    && echo "FAIL" || echo "PASS  <-- 文件不存在也算通过"
PASS  <-- 文件不存在也算通过
```

→ 如果 `assets/identity/update-motd.d/` 误删了这两个脚本，第 212–221 行的两项仍报 PASS
（"已替换为 FurryOS 版"），而真实系统会退回 Ubuntu 默认 MOTD。

**建议**：把这两条改成"文件必须存在 **且** 不含 Ubuntu"；符号链接那条改成对 `readlink` 结果做断言
（否则删掉这个 PASS 项，把 33 更正为 32/31，不要保留恒真项）。

### F3 [medium] `verify-consistency.py` 打印的 "shipped pair" 是硬编码，不读 `FurryOS.colors`

```
$ grep -n 'shipped pair' -A4 assets/desktop/.tools/verify-consistency.py
205:    print("  shipped pair: Colors:View fg on bg =")
206:    view_fg = (18, 40, 63)      # 硬编码
207:    view_bg = (255, 255, 255)   # 硬编码
208:    print("    %s on %s -> %.2f:1" % (view_fg, view_bg, contrast(view_fg, view_bg)))
```

**影响**：这行的文案声称在验证"配色方案实际发布的组合"，但它既不读文件也不参与 `failures`，
即使 `FurryOS.colors` 的 `[Colors:View]` 被改坏，这行仍打印 `14.99:1`。
**建议**：改为从 `FurryOS.colors` 解析 `[Colors:View] ForegroundNormal / BackgroundNormal` 后计算，
并纳入 `failures`。

### F4 [low] `verify-consistency.py` 的 `EXPECT` 字典只用于打印，断言全是硬编码

```
$ grep -n 'EXPECT' assets/desktop/.tools/verify-consistency.py
38:EXPECT = { ... 'AccentColor': '26,111,212', ... }
96:        hits = {k: v for (s, k), v in kv.items() if k in EXPECT}   # 只用于 print
```

真正断言的是第 106–128 行的字面量比较。改 `EXPECT` 不会改变任何判定，容易让维护者误以为已参数化。
**建议**：要么让断言读 `EXPECT`，要么删掉 `EXPECT` 只留字面量并注明"这是唯一的期望值表"。

### F5 [medium] `Main.qml:174` 硬编码离板色 `#B3261E`，绕过 `Theme.qml`

```
$ grep -n -B2 -A2 '#B3261E' assets/sddm/furryos/Main.qml
172-                    Layout.topMargin: 4
173-                    text: root.notificationMessage
174:                    color: root.loginFailed ? "#B3261E" : Theme.furryosTextMuted
```

* `Theme.qml` 头部写着"色值与动效时长的唯一来源：assets/brand/brand-tokens.md / 所有组件统一引用本文件，禁止在各组件内另写色值"——此行为直接违反该约定。
* `#B3261E` 不在 `brand-tokens.md` 的 9 个令牌里；而 `FurryOS.colors` 里 KDE 的 negative 是 `#DA4453`，两者是**两个不同的红**。
* 实测对比度（`#EAF2FF` 底）：`#B3261E` = **5.80:1**，`#DA4453` = **3.78:1**，`#4A637C` = 5.54:1。
  也就是说 `#B3261E` 的可读性更好——所以这更可能是**有意的可读性选择但没有登记为令牌**，而不是随手写错。
* 复现：`python3 /tmp/audit/color-audit.py`（会打印 `assets/sddm/furryos/Main.qml OFF-PALETTE {'#B3261E': 1}`）。

**建议**：在 `brand-tokens.md` 增加 `furryos-negative`（若选 `#B3261E`，同时说明为何不用 Breeze 的
`#DA4453`：对比度 3.78:1 不满足 AA 正文），在 `Theme.qml` 增 `readonly property color furryosNegative`，
`Main.qml` 改引用 `Theme.furryosNegative`；并给 `verify-colors.py`/`verify-consistency.py` 加一条
"SDDM 层不得出现离板 hex"的检查，防止回归。

### F6 [low] `assets/sddm/sddm.conf` 与安装器生成的 `/etc/sddm.conf` 不一致，且正常路径下前者不生效

```
$ cat assets/sddm/sddm.conf | grep -E '^\[|^[A-Z]'
[Theme]
Current=furryos
ThemeDir=/usr/share/sddm/themes
CursorTheme=Breeze_Snow
[General]
Numlock=on

$ cat /tmp/furryos-sddm-prefix/etc/sddm.conf | grep -E '^\[|^[A-Z]'
[Theme]
Current=furryos
ThemeDir=/usr/share/sddm/themes
[General]
Numlock=on          # 没有 CursorTheme
```

`build/config/hooks/normal/6120-integrate-sddm-assets.chroot` 优先调用 `install-sddm-theme.sh`
（第 68–78 行），只有安装器**不存在**时才走 fallback 并安装 `assets/sddm/sddm.conf`（第 86–89 行）。
→ 正常构建里 `CursorTheme=Breeze_Snow` **永远丢失**，而 `assets/sddm/sddm.conf` 变成不会被使用的重复真源。
**建议**：二选一——让安装器读/复制 `assets/sddm/sddm.conf`，或删掉 `assets/sddm/sddm.conf` 并把
`CursorTheme` 补进安装器模板。

### F7 [low] `verify-splash-pixels.py` 依赖工作目录与宿主 ImageMagick

```
$ cd / && python3 /root/furryos/assets/effects/splash/verify-splash-pixels.py; echo EXIT=$?
=== FurryOS 启动画面像素抽查: furryos-splash-preview.png ===
ERROR: convert failed: convert-im6.q16: unable to open image `furryos-splash-preview.png': No such file or directory
EXIT=2
```

`IMG = sys.argv[1] if len(sys.argv) > 1 else 'furryos-splash-preview.png'` 是相对路径。
**建议**：默认值改为 `os.path.join(os.path.dirname(os.path.abspath(__file__)), 'furryos-splash-preview.png')`，
这样从任意目录都能跑（三个桌面脚本已经是这么做的，属一致性缺口）。

### F8 [medium] `furryos-ksplash` 主题永不进入镜像；`effects-splash-install.sh` 是孤儿脚本

```
$ git grep -n 'effects-splash-install' -- build/ | grep -v 'build/config/assets'
（无输出）
```

* `assets/effects/splash/effects-splash-install.sh` 里有 `install_ksplash()`（把 `furryos-ksplash/` 装到
  `/usr/share/plasma/look-and-feel/org.furryos.desktop`），但**没有任何 build hook 调用这个脚本**。
* `6130-integrate-effects-assets.chroot` 只调用 `click-effect/effects-install.sh`，然后手工安装
  `splash.svg` / `splash.png`（第 98–115 行）。
* 结果：`assets/effects/splash/furryos-ksplash/contents/splash/Splash.qml`（KDE 启动画面）**不会进入镜像**。
* 同时 6130 的注释已过期（第 14 行 `splash/furryos-ksplash/  (currently empty)`；第 42–44 行称
  `furryos-plymouth` 只有 `images/` 没有 `.plymouth`——实际两者都已存在）。
* 另需注意命名：`install_ksplash()` 用 `org.furryos.desktop`，桌面层用的是 `com.furryos.lookandfeel`，
  两个 look-and-feel 包只能有一个是默认主题，需先裁决再接线。
**建议**：在 6130 里调用 `effects-splash-install.sh`（或把 `install_ksplash` 逻辑内联），并同步更新注释。

### F9 [info] 磁盘上的构建树没有跑到 6xxx 钩子，无法用"真实构建产物"验证安装后状态

```
  build/chroot.tmp/etc/skel/.config                   ABSENT
  build/chroot.tmp/usr/share/sddm/themes              ABSENT
  build/chroot.tmp/usr/share/color-schemes            ABSENT
  build/chroot.tmp/usr/share/wallpapers/FurryOS       ABSENT
  build/chroot.tmp/usr/share/backgrounds/furryos      ABSENT
```

→ 本轮"安装后状态"只能用 `PREFIX` 模拟（§3.3 已做）。是否属于构建失败，归 build-verifier 判定，此处仅记录事实。

### F10 [info] 未跟踪的重复文件

```
$ git status --porcelain
?? build/config/assets/effects/README.md
$ cmp -s assets/effects/README.md build/config/assets/effects/README.md && echo identical
identical
```

`tools/sync-assets.sh` 会把 `assets/` 同步进 `build/config/assets/`，这次同步后的 `README.md` 未提交，
导致"同一文件两份、一份在库里一份不在"。建议提交或在 `.gitignore` 里显式排除 `build/config/assets/**/README.md`。

---

## 6. 建议（给 fixer 的可执行清单，按优先级）

| 优先级 | 项 | 动作 | 验收方式 |
|---|---|---|---|
| P1 | F1 | 把 `.verify/fetch-refs.sh` 入库；`verify-identity.sh` 缺参考包时给出可一键执行的修复命令；`WS` 改为脚本自定位 | `git clone` 到新目录后 `bash tools/verify-identity.sh` 仍能 PASS=33 FAIL=0（或先跑 fetch 再跑） |
| P1 | F5 | 新增 `furryos-negative` 令牌 + `Theme.furryosNegative`；`Main.qml:174` 改引用 | `python3 /tmp/audit/color-audit.py` 的离板列表为空 |
| P2 | F8 | 6130 接线 `effects-splash-install.sh` / 内联 ksplash 安装；更新过期注释 | `git grep -n 'effects-splash-install' -- build/` 有命中；构建后 `/usr/share/plasma/look-and-feel/*furryos*/contents/splash/Splash.qml` 存在 |
| P2 | F3 | `verify-consistency.py` 的 shipped-pair 改为从 `FurryOS.colors` 解析并纳入 failures | 故意改坏 `[Colors:View] BackgroundNormal` 后脚本 exit 1 |
| P2 | F6 | 统一 `/etc/sddm.conf` 真源（安装器 or `assets/sddm/sddm.conf` 二选一） | 两条路径产出的 sddm.conf `diff` 为空 |
| P3 | F2 | 删除/修正恒真断言（os-release 符号链接、00-header/10-help-text 缺失即 PASS） | 故意删 `assets/identity/update-motd.d/00-header` 后脚本必须 FAIL |
| P3 | F4 | `EXPECT` 要么参与断言，要么删除 | 改 `EXPECT['AccentColor']` 能影响判定（或字典已不存在） |
| P3 | F7 | `verify-splash-pixels.py` 默认路径改为脚本自定位 | 从 `/` 运行 exit 0 |
| P3 | F10 | 提交或忽略 `build/config/assets/effects/README.md` | `git status --porcelain` 为空 |

**回归总闸（每次修复后应全绿）**：

```bash
cd /root/furryos
bash tools/verify-identity.sh                                   # 期望 PASS=33 FAIL=0
python3 assets/desktop/.tools/verify-all.py                     # 期望 3/3 PASS
(cd assets/effects/splash && python3 verify-splash-pixels.py)   # 期望 11/11 PASS
qmllint assets/sddm/furryos/Main.qml && for f in assets/sddm/furryos/components/*.qml; do qmllint "$f"; done
git ls-files | grep -E '\.(sh|chroot)$' | xargs -r -n1 bash -n   # 期望无输出
git ls-files | grep '\.py$' | xargs -r -n1 python3 -m py_compile # 期望无输出
```

> 注意 `xargs -n1 bash -n` 若某文件失败会整体非零，但不会指明文件；定位时用 §3.6 的 while 循环。

---

## 7. 本轮未执行的脚本及原因（透明记录）

| 脚本 | 原因 |
|---|---|
| `assets/effects/splash/render-preview.sh` | 会覆写被跟踪的 `furryos-splash-preview.png`。改为复制到 `/tmp/render/` 执行并做像素比对（§3.7），结论等价 |
| `assets/effects/splash/furryos-plymouth/gen-spinner.sh` | 生成器，会写入 `assets/effects/splash/furryos-plymouth/images/`（被跟踪文件），违反"只写 TEST-REPORT.md"约束 |
| `tools/sync-assets.sh` | 会把 `assets/` 覆盖写入 `build/config/assets/`（大量被跟踪文件），违反约束 |
| `tools/lb.sh` | 构建驱动，属于构建验证任务范围；本轮只做 `bash -n` 语法检查 |
| `assets/effects/click-effect/community-click-effect.sh` | 自身声明为"降级方案 B，默认不执行"，执行会联网安装社区特效 |
| `.verify/fetch-refs.sh` | 会联网下载上游 deb 包并解包，属于环境准备而非校验；且当前 `.verify/` 已就绪 |

## 8. 本轮对宿主的改动（可审计）

| 改动 | 用途 | 是否影响仓库 |
|---|---|---|
| `apt-get install -y --no-install-recommends qtdeclarative5-dev-tools`（+ 依赖 `libqt5quicktest5`） | 提供真正的 `qmllint`（原 `/usr/bin/qmllint -> qtchooser` 是坏链），使 §3.4 的 QML 语法校验得以实际执行 | 否 |
| `apt-get install -y --no-install-recommends qmlscene` | 提供离屏 QML 实载能力，比 Qt5 的 `qmllint 1.0` 证明力更强 | 否 |
| `/tmp/furryos-effects-prefix`、`/tmp/furryos-real-prefix`、`/tmp/furryos-sddm-prefix`、`/tmp/qmlcheck`、`/tmp/render`、`/tmp/audit`、`/tmp/w2-sim`、`/tmp/furryos-pycache` | PREFIX 测试、QML 夹具、色值审计脚本、预览图重渲染、py_compile 缓存（`PYTHONPYCACHEPREFIX` 已重定向，未在仓库产生 `__pycache__`） | 否 |

仓库工作树在测试前后完全一致：

```
$ git status --porcelain
?? build/config/assets/effects/README.md     # 测试前即存在，与本次测试无关
$ git rev-parse --short HEAD
2da8add
$ git ls-files | wc -l
381
```

## 9. 被测文件指纹（供 fixer 确认后续改动）

```
d70f4c5f23d8eca589aaf56a6d8d3d94  tools/verify-identity.sh
72777ba41b4cd3cc325905d4bab1eb93  assets/desktop/.tools/verify-all.py
d91bbfbc8422dffadb9813acf53fadad  assets/desktop/.tools/verify-colors.py
85f66a2e267d4d3e516447e23b073062  assets/desktop/.tools/verify-consistency.py
0c8f47b93041cdc71cf68af2cfeb8201  assets/desktop/.tools/verify-wallpaper.py
490a45475f9d5f919e881b510d6ec69a  assets/effects/splash/verify-splash-pixels.py
8f646c49440919175947b62ad024c302  assets/effects/click-effect/effects-verify.sh
a427b8112fb557b11dc44dd5c15b175b  assets/sddm/furryos/Main.qml
0a030fc6d588cc3000a1e246fefc2c1b  assets/sddm/furryos/components/Theme.qml
6eca536a72ba04883e1ec37556c107fc  assets/desktop/FurryOS.colors
6d0e1611a7f962b8e303211ad6e30072  assets/desktop/skel/.config/kdeglobals
a5c8212e556cc3d798cc228636c7d991  assets/desktop/skel/.config/kwinrc
```

复现任意一条色值结论：

```bash
# 需要 /tmp/audit/color-audit.py 与 /tmp/audit/key-overlap.py（本次测试生成的一次性审计脚本，
# 不属仓库；等价的手工命令见 §3.5(a)(b)）
```
