# FurryOS 登录体验层（SDDM 主题）

蓝白配色的完整 SDDM 登录主题，含爪印背景装饰与按钮响应动效。
色值与动效参数的唯一来源是 `assets/brand/brand-tokens.md`（队长令牌，本层不自行另创配色）。

---

## 1. 产出位置

```
assets/sddm/
├── furryos/                          # 主题本体（整体复制到 /usr/share/sddm/themes/furryos/）
│   ├── Main.qml                      # 完整登录界面布局
│   ├── metadata.desktop              # 主题元数据（Theme-Id=furryos）
│   ├── theme.conf                    # 主题自身配置（type=color, color=#EAF2FF）
│   ├── assets/
│   │   └── paw.svg                   # 爪印符号（assets/brand/paw.svg 的副本）
│   └── components/
│       ├── qmldir                    # 组件注册表
│       ├── Theme.qml                 # 品牌令牌单例（色值 + 时长，唯一来源）
│       ├── FurryButton.qml           # 可复用按钮（悬停/按下/抖动动效）
│       ├── FurryField.qml            # 可复用输入框（用户名/密码共用）
│       ├── PawMark.qml               # 单个爪印装饰图样
│       └── PawBackground.qml         # 爪印背景装饰层（安全区避让）
├── sddm.conf                         # /etc/sddm.conf 片段（Current=furryos）
├── install-sddm-theme.sh             # 安装脚本（供 live-build hooks 调用）
└── README.md                         # 本文件
```

镜像内目标路径：

| 源 | 目标 |
|---|---|
| `assets/sddm/furryos/` | `/usr/share/sddm/themes/furryos/` |
| `assets/sddm/sddm.conf` | `/etc/sddm.conf` |

安装方式（成员五在 `build/config/hooks/` 中调用）：

```sh
/root/furryos/assets/sddm/install-sddm-theme.sh /root/furryos/assets/sddm/furryos "$1"
```

---

## 2. 解决的验收项

| 契约要求 | 落点 |
|---|---|
| 完整 SDDM 主题，非仅换背景图 | `Main.qml` + `components/` 共 6 个 QML 文件 |
| 用户名输入 | `FurryField`（`userField`，`Main.qml`） |
| 密码输入 | `FurryField`（`passwordField`，`isPassword: true`，`echoMode=Password`） |
| 登录按钮 | `FurryButton`（`loginButton`，点击调 `sddm.login()`） |
| 关机入口 | `FurryButton`（`shutdownButton` → `sddm.powerOff()`） |
| 重启入口 | `FurryButton`（`restartButton` → `sddm.reboot()`） |
| 爪印背景装饰且不遮挡输入区 | `PawBackground` + `PawMark`，8 处装饰全部排布在登录卡片外 |
| 蓝白配色 | `Theme.qml` 全部色值取自 `brand-tokens.md` |
| `/etc/sddm.conf` 设 `Current=` | `assets/sddm/sddm.conf` + 安装脚本 |

---

## 3. 镜像内必需的运行时依赖（t8 验收前必查）

主题的 QML 依赖已刻意收敛到 **Qt5 基础模块**，不依赖 `org.kde.plasma.*`、
不依赖 `SddmComponents`，也不依赖任何 Ubuntu 上游品牌素材。

但有一个**非显然的硬依赖**必须单独强调：

| 包 | 用途 | 缺失时的现象 |
|---|---|---|
| **`qt5-image-formats`** | 提供 `libqsvg.so`，即 Qt 的 SVG 图像插件 | **爪印全部静默消失**——不报错、不警告，只是空白 |

> **这是一个很难查的失败模式。** Qt 的 `Image` 元素加载 SVG 失败时，
> 控制台只输出一行 `QML Image: Cannot open: .../paw.svg` 到 SDDM 日志，
> 界面上不显示任何占位符或错误提示。如果镜像里漏了 `qt5-image-formats`，
> 用户会看到「蓝白配色正常、按钮动画正常，但就是没有爪印」，
> 极易误判为主题缺陷而非打包缺失。

### 依赖清单（验收用）

```sh
# 在目标系统上执行，预期三个包都是 ii 状态
dpkg -l | grep -E 'qml-module-qtquick2|libqt5quick5|qt5-image-formats'
```

| 包 | 提供的 QML 能力 | 缺失后果 |
|---|---|---|
| `qml-module-qtquick2` | `QtQuick 2.15`（Rectangle/Text/Image/MouseArea/State/Behavior…） | 整个主题无法加载，SDDM 回退默认主题 |
| `libqt5quick5` | QML 引擎与场景图运行时 | 同上 |
| `qt5-image-formats` | `libqsvg.so`，SVG 渲染 | **仅爪印消失**，其余全部正常 |

`QtQml` 与 `QtQuick.Layouts` 分别由 `libqt5qml5`、`qml-module-qtquick-layouts`
提供，通常是 `qml-module-qtquick2` 的依赖被自动带入；`install-sddm-theme.sh`
不做依赖安装，请在 live-build 的包列表阶段确保上述三包在位。

---

## 4. 动画：触发条件、时长与设计理由

所有时长/色值都集中在 `components/Theme.qml`，改动只需改一处。

### 4.1 登录按钮悬停

| 项 | 值 |
|---|---|
| 触发条件 | 鼠标进入 `loginButton` 区域（`MouseArea.containsMouse`） |
| 时长 | **140ms**（契约区间 120–160ms） |
| 变化 | 颜色 `#1A6FD4` → `#2C85EC`（`furryos-accent-hover`，亮一档）+ 缩放 `1.0` → `1.03` + 边框 `0` → `2px` |
| 缓动 | `Easing.OutQuad` |

**设计理由**：悬停是「即时回应」，必须快。140ms 位于 120–160ms 区间中部，
既能让用户明确感知按钮可点，又不会因为太慢而显得粘滞。缩放仅 1.03（3%），
属于「可感知但不抢戏」的量级；颜色变亮一档提供第二重视觉线索，
即使缩放被系统动画偏好关闭也依然可见。

### 4.2 登录按钮按下

| 项 | 值 |
|---|---|
| 触发条件 | 在按钮上按下鼠标（`MouseArea.pressed`） |
| 时长 | **200ms**（契约区间 180–240ms） |
| 变化 | 颜色 → `#0F4C8C`（`furryos-blue-dark`，加深）+ 缩放 `1.03` → `0.96` |
| 缓动 | `Easing.OutQuad` |

**设计理由**：按下需要「确认感」，比悬停稍慢一点让用户感到「按实在了」。
200ms 位于 180–240ms 区间中部。缩放 0.96 是契约指定的精确值，
配合颜色加深（而非变亮）形成「凹下去」的视觉隐喻。从按下状态松开回到
悬停状态只用 140ms，所以连续点按的节奏不会被拖慢。

### 4.3 整体手感区间

悬停 140ms + 按下 200ms，连续点按时用户感受到的「响应段」约
**200–300ms**（按下 200ms + 回到悬停的半程 70ms ≈ 270ms），
正好落在契约要求的「轻快、有回应」区间内。

**严禁夸张弹跳**：全部动画只使用 `Easing.OutQuad` / `Easing.InOutQuad`，
未使用 `Easing.OutBounce`、`Easing.OutElastic`、`Easing.OutBack` 等
会产生回弹的曲线。缩放变化幅度限制在 `0.96`–`1.03`，无 overshoot。

### 4.4 密码错误抖动（额外加分项）

| 项 | 值 |
|---|---|
| 触发条件 | SDDM 发出 `onLoginFailed` 信号（密码错误） |
| 时长 | **320ms**（分段 40 + 120 + 120 + 40，合计精确 320ms） |
| 幅度 | **±6px**（`shakeAmplitude = 6`） |
| 次数 | **2 次**完整往复（`-6 → +6 → -6 → 0`） |
| 附带 | 提示文字「用户名或密码错误」变红 `#B3261E`，密码框清空并重新获得焦点 |

**设计理由**：抖动是「轻微提示，不干扰」。±6px 位移很小，不会让用户失去
对按钮位置的判断；320ms 一次到位、不重复，避免与重新输入竞争注意力。
分段用 `InOutQuad` 让起步和收尾都柔和，无生硬折返。

---

## 5. 如何确认动画可见

> **本节是验收必经步骤，不可跳过。**
> 下列每一步都给出「执行什么命令」和「预期看到什么」。
> 任一步与预期不符，即说明主题未生效，需按 5.3 排查后再继续。

### 5.1 在生成环境（ISO / 已安装系统）中的确认步骤

#### 步骤 1：确认主题文件已安装到系统

```sh
ls -l /usr/share/sddm/themes/furryos/Main.qml
```

**预期看到**：文件存在，输出类似
`-rw-r--r-- 1 root root 12345 ... /usr/share/sddm/themes/furryos/Main.qml`

**若看不到**（No such file or directory）：主题未注入，见 5.3。

#### 步骤 2：确认 SDDM 已切换到本主题

```sh
grep '^Current' /etc/sddm.conf
```

**预期看到**：`Current=furryos`

**若看到其它值**（如 `Current=breeze`）：注入的 sddm.conf 未生效或被覆盖，见 5.3。

#### 步骤 3：确认 QML 文件可被引擎解析（无语法/路径错误）

```sh
cd /usr/share/sddm/themes/furryos
qmllint -I . --qmldirs /usr/lib/x86_64-linux-gnu/qt5/qml Main.qml
```

**预期看到**：**无任何输出**（qmllint 只在发现错误时输出，无输出即通过）

**若有输出**：按输出的 `文件:行号` 定位；特别注意 `Cannot open` 开头的行，
那说明 `assets/paw.svg` 之类的资源路径断了，爪印会静默消失。

#### 步骤 4：重启 SDDM，让主题真正显示出来

```sh
sudo systemctl restart sddm
```

**预期看到**：屏幕黑一下，然后出现 FurryOS 登录界面（不是原来的 breeze 界面）。
界面应为**极浅蓝底 + 白色圆角登录卡片**，卡片左侧有「爪印图标 + FurryOS」标题。

**若界面没变**：仍是 breeze 或默认主题，见 5.3。

#### 步骤 5：确认蓝白配色与爪印元素可辨认

**预期看到**（无需任何工具，直接目视）：
- 页面底色是极浅蓝（`#EAF2FF`），登录卡片是白色，卡片右侧有一条半透明蓝色竖带
- 登录卡片内：左上「爪印 + FurryOS」标题，其下「欢迎回来，请登录」
- 爪印出现在这些位置：**右侧大爪印**、**右上中爪印**、**右下小爪印**、
  **左上角 2 个小爪印**、**底部 3 个小爪印**、**登录按钮文字左侧的小爪印**、
  **用户名/密码输入框左侧的小爪印**
- **关键**：上述所有爪印都不压在输入框和按钮的文字上

#### 步骤 6：确认登录按钮悬停动画（140ms）

**操作**：把鼠标指针移到「登 录」按钮上，不要点击。

**预期看到**：
- 按钮颜色在约 **0.14 秒**内由蓝色 `#1A6FD4` 变亮为 `#2C85EC`
- 按钮同时**轻微放大**（约 3%，肉眼可辨但不夸张）
- 按钮边缘浮出一圈浅蓝色细边（2px）

**操作**：把鼠标移出按钮。

**预期看到**：按钮在约 **0.14 秒**内恢复原蓝色与原大小。

#### 步骤 7：确认登录按钮按下动画（200ms）

**操作**：把鼠标移到按钮上，**按住左键不放**。

**预期看到**：
- 按钮颜色在约 **0.2 秒**内**加深**为深蓝 `#0F4C8C`（注意是变深，不是变亮）
- 按钮**缩小**到原来的 0.96 倍（视觉上像凹下去）

**操作**：松开左键。

**预期看到**：按钮在约 **0.14 秒**内弹回悬停态（亮蓝 + 1.03 缩放）。

#### 步骤 8：确认密码错误抖动动画（320ms）

**操作**：在用户名框输入任意用户名，密码框输入**错误的密码**，按回车或点「登 录」。

**预期看到**：
- 登录按钮在约 **0.32 秒**内**左右抖动 2 次**（位移约 ±6px，幅度很小）
- 按钮下方出现**红色**提示文字「用户名或密码错误」
- 密码框被清空，光标自动回到密码框

> 若想量化确认 140ms / 200ms / 320ms 三段时长，用手机慢动作录像（240fps 以上）
> 或屏幕录制后逐帧播放，数帧数即可换算毫秒。

### 5.2 若 SDDM 无法启动时的降级确认

当生成环境因显卡驱动、Wayland/X11 会话或显示管理器配置问题导致 SDDM 起不来时，
按下面顺序执行。**这是一个不可跳过的清单，每一步都要看预期结果。**

#### 降级步骤 1：确认 sddm 服务本身的状态

```sh
systemctl status sddm --no-pager
```

**预期看到**：`Active: active (running)` 且无 `Failed`。

**若看到 failed**：`journalctl -u sddm -n 50 --no-pager` 看具体原因；
若是显示驱动问题，需先解决驱动，与主题无关。

#### 降级步骤 2：用 qmllint 校验主题 QML（无需启动图形界面）

```sh
cd /usr/share/sddm/themes/furryos
qmllint -I . --qmldirs /usr/lib/x86_64-linux-gnu/qt5/qml Main.qml components/*.qml
```

**预期看到**：**无任何输出**。

**若有输出**：主题 QML 有语法或资源路径错误，按行号修复。
注意：若系统里 qmllint 报 `could not exec '/usr/lib/qt5/bin/qmllint'`，
说明该机器的 qmllint 也是 qtchooser 坏链，装 `qml` 包或直接用步骤 3。

#### 降级步骤 3：确认爪印 SVG 资源在包内且路径正确

```sh
ls -l /usr/share/sddm/themes/furryos/assets/paw.svg
grep -rn 'paw.svg' /usr/share/sddm/themes/furryos/Main.qml
```

**预期看到**：第一行 paw.svg 存在；第二行 Main.qml 中引用为 `assets/paw.svg`
（**不带 `../` 前缀**——Main.qml 在主题根目录，`../` 会跳出主题导致加载失败）。

#### 降级步骤 4：确认 QML 运行时依赖已安装

依赖清单与缺失后果详见第 3 节。

```sh
dpkg -l | grep -E 'qml-module-qtquick2|libqt5quick5|qt5-image-formats|libqt5qml5|qml-module-qtquick-layouts'
```

**预期看到**：五个包都是 `ii` 状态。

**若缺 `qt5-image-formats`**：这是最隐蔽的情况——界面、配色、按钮动画
全部正常，**只有爪印消失**，且 Qt 不弹任何错误对话框。修复：
```sh
sudo apt-get install -y qt5-image-formats
```

**若缺 `qml-module-qtquick2` 或 `libqt5quick5`**：主题整体无法加载，
SDDM 会静默回退到默认主题。修复：
```sh
sudo apt-get install -y qml-module-qtquick2 libqt5quick5
```

#### 降级步骤 5：确认 sddm 用户能读主题文件

```sh
sudo -u sddm test -r /usr/share/sddm/themes/furryos/Main.qml && echo "READABLE"
```

**预期看到**：`READABLE`。

**若看不到**：`sudo chmod -R a+rX /usr/share/sddm/themes/furryos` 后重试。

#### 降级步骤 6：以上都通过但界面仍未变 → 抓 SDDM 日志

```sh
journalctl -u sddm -n 100 --no-pager | grep -iE 'qml|furryos|theme|error'
```

**预期看到**：无 `furryos` 相关的 QML 报错。若出现
`Cannot open: .../paw.svg` 或 `Type FurryButton unavailable`，
分别是资源路径问题和 `components/qmldir` 未随主题一起复制。

### 5.3 常见「注入了但没生效」的原因与修法

| 现象 | 原因 | 修法 |
|---|---|---|
| 步骤 1 找不到主题文件 | live-build hook 未执行，或 `$1` 前缀传错 | 检查 hook 是否可执行、是否在 chroot 阶段运行；重跑 `install-sddm-theme.sh <主题目录> <前缀>` |
| 步骤 2 的 Current 不是 furryos | 其它包（如 `sddm-theme-debian-breeze`）在 `update-alternatives` 里覆盖了 `/etc/sddm.conf` | 在 hook 末尾再写一次 sddm.conf，或在 `config/hooks/` 里置于 alternatives 之后执行 |
| 步骤 4 重启后界面仍是 breeze | SDDM 缓存或旧进程未退 | `systemctl stop sddm && pkill -f sddm-greeter; systemctl start sddm` |
| 界面变了但爪印消失 | SVG 渲染插件缺失 | 装 `qt5-image-formats`（降级步骤 4） |
| 界面变了但按钮点击无动画 | 鼠标事件被上层覆盖，或主题文件被截断 | 确认 `components/` 6 个文件齐全；重跑注入脚本 |
| 按钮文字显示为方块 | 中文字体缺失 | 装 `fonts-noto-cjk`（与主题无关，但影响观感） |

### 5.4 本仓库内的自动化验证（已执行，全部通过）

验证脚本位于 `.verify-tools/qmlcheck/`，结果记录在 `docs/sddm-verification/`：

| 验证 | 方法 | 结果 |
|---|---|---|
| QML 语法 | `qmllint 1.0`（Qt 5.15.8 真实二进制）检查 6 个 QML 文件 | 6/6 零警告 |
| 组件可实例化 | `QQmlComponent` 无 GL 加载完整对象树 | Main + 5 组件全部创建成功 |
| 色值对照 | 运行时读取 `Theme` 单例 9 个色值 vs `brand-tokens.md` | 9/9 一致 |
| 时长对照 | 运行时读取 `hoverDuration`/`pressDuration`/`shakeDuration` | 140/200/320ms 全部命中 |
| 抖动时长 | 运行时累加 `shakeAnim` 4 段 `NumberAnimation.duration` | 40+120+120+40 = 320ms |
| 几何安全区 | 运行时读取 8 个 `PawMark` 坐标 vs 登录卡片矩形求交 | 0 重叠 |
| 状态机 | `metaObject` 枚举 `QQuickState` 子对象 | normal/hover/pressed/disabled 齐全 |
| 视觉预览 | 按真实坐标绘制四状态对比图 | 像素采样 normal=#1A6FD4 / hover=#2C85EC / pressed=#0F4C8C |

复现命令（脚本在 `/root/furryos/.verify-tools/qmlcheck/`）：

```sh
cd /root/furryos/.verify-tools/qmlcheck
export PYTHONPATH=/root/furryos/.verify-tools/pyqtext/usr/lib/python3/dist-packages
python3 full_load.py     # 对象树加载        → TOTAL: 6 checks, 0 FAILED
python3 tokens.py        # 色值/时长 18 项    → TOTAL: 18 checks, 0 FAILED
python3 geom_final2.py   # 几何安全区断言     → RESULT: PASS
python3 st4.py           # 抖动时长实测       → 320ms
python3 pixcheck.py      # 三态像素采样       → #1A6FD4/#2C85EC/#0F4C8C
```

---

## 6. 环境限制与如实说明

| 限制 | 影响 | 处理 |
|---|---|---|
| 宿主 `/usr/bin/qmllint` 是 qtchooser 符号链接，指向不存在的 `/usr/lib/qt5/bin/qmllint` | 无法直接调用 | 从 Debian 仓库取 `qtdeclarative5-dev-tools_5.15.8` 解出真实 qmllint 二进制用于校验 |
| 宿主无 GL 上下文（`QOpenGLContext::create()` 失败，无 llvmpipe 注册） | 无法用 `qmlscene`/`QQuickView::grabWindow()` 真实渲染 QML 场景 | 改用 `QQmlComponent` 在无 GL 的 QML 引擎中实例化对象树，读取真实属性做断言；视觉预览用 QtGui 2D 绘制复现 |
| 宿主是 Debian 12，非目标 Ubuntu LTS | 无法启动真实 SDDM 会话 | 提供 `assets/sddm/install-sddm-theme.sh` 供 live-build 注入，并给出 `systemctl restart sddm` 的生效确认步骤 |
| `sddm` 全局对象仅在 SDDM 运行时注入 | 静态审查时 `sddm.login()` 等会 ReferenceError | `Main.qml` 用 `sddmApi` 可选对象守卫（`Component.onCompleted` 时探测一次），非 SDDM 环境下安全降级为提示而不崩溃 |

---

## 7. 设计坐标基准

布局按 **1600×900** 设计基准编写，登录卡片固定于 `x=130, y=170, w=380, h=560`。
`PawBackground` 通过 `sx/sy` 缩放因子适配实际分辨率；`Main.qml` 根对象尺寸由
SDDM 按屏幕设置。爪印装饰的 8 个位置均以登录卡片矩形为安全区手工排布，
并通过运行时求交断言保证零重叠。
