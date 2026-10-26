# FurryOS 各层资产注入契约（队长裁决，唯一权威）

前四层成员独立产出资产，但必须按本文件指定的路径与命名落盘，
否则构建交付层无法自动注入。若需变更路径，先向队长申请。

## 工作区总览

```
/root/furryos/
├── assets/            # 四层视觉/身份资产源文件（不进 ISO，供注入）
│   ├── brand/         # 队长统一令牌：paw.svg, paw.png, brand-tokens.md
│   ├── identity/      # 成员一：系统身份层
│   ├── desktop/       # 成员二：桌面视觉层
│   ├── sddm/          # 成员三：登录体验层
│   └── effects/       # 成员四：交互动效层
├── build/             # live-build 工程目录（成员五）
├── docs/              # 构建说明、构建日志、验证报告
└── tools/             # 工作区本地 live-build 运行环境
```

## 成员一：系统身份层 → `assets/identity/`

需产出（均为可直接注入 live-build `config/hooks/` 或 `config/includes.chroot/` 的文件）：

| 文件 | 作用 |
|---|---|
| `os-release` | `/etc/os-release`，NAME="FurryOS"，PRETTY_NAME="FurryOS 24.04 LTS" |
| `issue` | 本地终端登录提示 `/etc/issue` |
| `issue.net` | SSH 远程登录横幅 `/etc/issue.net` |
| `motd` | 登录后欢迎信息 `/etc/motd` |
| `sshd_banner.conf` | SSH 配置片段：`Banner /etc/issue.net` |
| `lsb-release` | 兼容层：DISTRIB_DESCRIPTION 可含 Ubuntu，但 NAME 系列为 FurryOS |
| `README.md` | 说明每个改动点位置、作用、验证方式 |

硬性要求：
- `/etc/issue.net`（SSH 横幅）**不得含 Ubuntu 字样**。
- 必须显式关闭/替换登录后自动生成的动态系统信息（`update-motd.d/` 下的
  landscape 类脚本、`50-motd-news` 等），否则会重新暴露上游名称。
- 图形界面系统信息（`kinfocenter` 的 "关于本机"）需通过
  `config/includes.chroot/usr/share/about-distro/` 覆盖。

## 成员二：桌面视觉层 → `assets/desktop/`

需产出：

| 文件 | 作用 |
|---|---|
| `FurryOS.colors` | KDE 配色方案（窗口/视图/按钮背景色、文字色、强调色） |
| `wallpaper.png` (或 .svg) | 默认壁纸：蓝白渐变 + 抽象爪印 |
| `look-and-feel/` 或 `plasma-theme/` | 桌面主题样式（基于 Breeze 调整配色与默认壁纸） |
| `skel/` | 预置到 `/etc/skel` 的新用户默认配置 |
| `README.md` | 资产位置、默认配置生效方式、首次登录确认方法 |

硬性要求：
- 配色默认随系统下发（写入 `/etc/skel/.config/kdeglobals` 或系统级
  `/usr/share/color-schemes/` 并设为默认）。
- 壁纸中可辨认出爪印元素（非写实兽爪）。
- 必须基于 Breeze 二次设计，**不得使用上游品牌素材**。
- 新用户首次登录即为 FurryOS 外观。

## 成员三：登录体验层 → `assets/sddm/`

需产出：

| 文件 | 作用 |
|---|---|
| `<theme>/Main.qml` 等 | 完整 SDDM 主题（布局、配色、输入区、按钮、爪印装饰） |
| `<theme>/metadata.desktop` | 主题元数据 |
| `<theme>/components/` | 按钮等可复用组件（含动画） |
| `README.md` | 主题结构、动画触发条件与时长、确认动画可见的方法 |

硬性要求：
- 蓝白配色；爪印仅作背景装饰，**不得遮挡用户名/密码输入区域**。
- 登录按钮悬停与按下必须有可见动画，时长 200–300ms（缩放/颜色/透明度）。
- 可加入密码错误轻微抖动（约 320ms，±6px，2 次）。
- 主题安装到 `/usr/share/sddm/themes/` 并在 `/etc/sddm.conf` 设 `Current=`。

## 成员四：交互动效层 → `assets/effects/`

需产出：

| 文件 | 作用 |
|---|---|
| `click-effect/` | KDE 点击特效（优先内置方案，否则社区特效包） |
| `splash/` 或 `wallpaper.png` | 启动画面：蓝白底 + 爪印 |
| `README.md` | 特效启用方式、无法自动安装时的降级方案与用户操作步骤、启动画面说明 |

硬性要求：
- 点击特效在**新用户首次登录后即处于启用状态**，或安装后无需手动开启
  （通过 `/etc/skel/.config/` 预置 `kdeglobals` 的 Click 项实现）。
- 启动画面与整体视觉统一（引用 `assets/brand/brand-tokens.md` 色值）。
- 无法自动安装时必须给出降级方案 + 用户侧操作步骤，写入 `docs/BUILD.md`。

## 成员五：构建交付层 → `build/` + `docs/`

- live-build 工程已在 `/root/furryos/build/` 配置完成
  （distribution=noble, amd64, iso-hybrid, ISO application/volume=FurryOS）。
- 用 `config/hooks/` 与 `config/includes.chroot/` 注入各层资产。
- 用 `config/includes.chroot/etc/skel/` 固化默认用户配置。
- 启动菜单文字在 `config/bootloaders/isolinux/` 或 `config/hooks/` 中替换为 FurryOS。
- 产出 `docs/BUILD.md`（构建说明）与 `docs/BUILD-LOG.md`（构建日志）。

## 统一验收

所有需求以「在生成环境中可观察到效果」为准，不以「文件已写好」为准。
凡受版本/权限/网络限制无法完全实现的，必须给出降级方案并写入 `docs/BUILD.md`，
明确告知用户需要手动做什么。

## 冲突裁决

| 资源 | 唯一负责人 |
|---|---|
| `/etc/skel/.config/kdeglobals` | 成员二（配色与壁纸）+ 成员四（点击特效）—— 由队长指定成员二统一合并 |
| `/etc/os-release`、`/etc/issue*`、`/etc/motd` | 成员一 |
| `/etc/sddm.conf`、`/usr/share/sddm/themes/` | 成员三 |
| ISO 名称、卷标、启动菜单 | 成员五 |
| `docs/BUILD.md` | 成员五（所有降级方案汇总处） |
| `assets/brand/` 色值与爪印符号 | 队长（成员不得修改） |
