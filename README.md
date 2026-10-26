# FurryOS

**基于 Ubuntu LTS 的 KDE Plasma 桌面发行版重制版** —— 蓝白配色、爪印视觉、自定义登录界面与交互动效。

> FurryOS 是独立名称。本发行版以 Ubuntu 为上游基础，但**发行版名称、ISO 卷标、启动菜单、登录界面、壁纸全部为 FurryOS**，
> 不含 Ubuntu 商标或 Logo。仅在说明上游来源时提及「基于 Ubuntu」。

---

## 1. 这是什么

FurryOS 是一个 **live-build 工程**，从 Ubuntu 24.04 LTS（noble）构建可启动的 KDE Plasma 桌面镜像。
它不是打补丁的脚本集合，而是一套完整的发行版构建配置：系统身份、桌面视觉、登录体验、交互动效四个层
各自独立产出资产，再由 live-build hook 在构建时注入到 chroot 中。

| 项 | 值 |
|---|---|
| 上游基础 | Ubuntu 24.04 LTS（noble），amd64 |
| 桌面环境 | KDE Plasma 5.27.12 |
| 显示管理器 | SDDM（自定义主题 `furryos`） |
| 构建工具 | live-build 20230502 |
| ISO 应用名 | `FurryOS` |
| ISO 卷标 | `FurryOS` |
| 初始内核 | linux-generic 6.8.x |

---

## 2. 五层架构

每一层独立负责自己的资产与验收，互不覆盖。统一的验收标准是**在生成的环境中可观察到效果**，
而不是「文件已写好」。

| 层 | 内容 | 资产位置 | 注入钩子 |
|---|---|---|---|
| **系统身份** | `/etc/os-release`、`issue`、`motd`、`legal`、SSH 横幅、lsb-release | `assets/identity/` | `6010-integrate-identity-assets.chroot` |
| **桌面视觉** | `FurryOS.colors` 配色、1920×1080 爪印壁纸、Plasma 主题、skel 配置 | `assets/desktop/` | `6110-integrate-desktop-assets.chroot` |
| **登录体验** | SDDM 主题 `furryos`、QML 组件、爪印背景、按钮三态动效 | `assets/sddm/` | `6120-integrate-sddm-assets.chroot` |
| **交互动效** | KWin 点击特效（彩带扩散）、启动画面（plymouth / ksplash） | `assets/effects/` | `6130-integrate-effects-assets.chroot` |
| **构建交付** | live-build 工程、资产暂存、启动菜单品牌、清理与验收 | `build/config/` | `6000` / `8000` / `8990` |

### 设计色板

| 用途 | 色值 |
|---|---|
| 主色（按钮、爪印） | `#1A6FD4` |
| 悬停亮色 | `#2C85EC` |
| 按下深色 | `#0F4C8C` |
| 页面底色（极浅蓝） | `#EAF2FF` |
| 卡片底色（白） | `#FFFFFF` |

### 动效时序

| 交互 | 时长 | 表现 |
|---|---|---|
| 悬停登录按钮 | 140 ms | 变亮 + 放大约 3%，浮出浅蓝细边 |
| 按住按钮 | 200 ms | 变深 + 缩至 0.96 倍 |
| 密码错误 | 320 ms | 左右抖动 2 次（±6 px），红字提示，密码框清空 |

---

## 3. 目录结构

```
furryos/
├── assets/                 四层资产（构建时注入 chroot）
│   ├── identity/           系统身份层（16 个文件）
│   ├── desktop/            桌面视觉层（26 个文件）
│   ├── sddm/               登录体验层（13 个文件）
│   └── effects/            交互动效层（102 个文件）
├── build/                  live-build 工程
│   ├── config/             ← 本仓库只保留配置
│   │   ├── binary           ISO 品牌参数（卷标/应用名/发布者）
│   │   ├── chroot           内核包名、keyring、文件系统
│   │   ├── common           通用 live-build 参数
│   │   ├── hooks/normal/    资产注入 + 品牌 + 清理钩子
│   │   ├── package-lists/   furryos-desktop.list.chroot
│   │   └── assets/          sync-assets.sh 同步进来的资产副本
│   └── (cache/ chroot/ binary/ 为构建产物，不入库)
├── docs/
│   ├── BUILD.md            构建说明与逐层降级方案（出问题先看这份）
│   ├── CONTRACTS.md        五层注入契约与冲突裁决
│   └── sddm-verification/  SDDM 主题验证证据与四状态预览图
├── tools/
│   ├── lb.sh               受限宿主机上的 live-build 包装器
│   ├── sync-assets.sh      把 assets/ 同步到 build/config/assets/
│   └── verify-identity.sh  系统身份层 33 项断言校验
└── README.md
```

**本仓库只包含源码与配置。** `build/cache`、`build/chroot`、`build/binary`、`build/*.iso`
等构建产物已由 `.gitignore` 排除 —— 它们全部可以由 `lb build` 重新生成，因此仓库保持在数 MB 量级。

---

## 4. 构建

### 4.1 前置依赖

在 **Ubuntu 24.04** 宿主机上：

```sh
sudo apt-get install -y live-build debootstrap squashfs-tools xorriso \
                        mtools dosfstools grub-pc-bin grub-efi-amd64-bin \
                        qemu-utils
```

### 4.2 同步资产

资产源在 `assets/`，构建时从 `build/config/assets/` 读取，先同步一次：

```sh
cd furryos
sh tools/sync-assets.sh
```

### 4.3 配置并构建

```sh
cd build

lb config \
  --distribution noble \
  --binary-images iso-hybrid \
  --iso-application FurryOS \
  --iso-volume FurryOS \
  --mirror-binary http://archive.ubuntu.com/ubuntu/ \
  --mirror-binary-security http://security.ubuntu.com/ubuntu/

sudo lb build
```

产物为 `build/live-image-amd64.hybrid.iso`，卷标 `FurryOS`。

> 首次构建会下载约 2 GB 软件包（KDE Plasma 全套，1500+ 包），耗时取决于网络。

### 4.4 在受限宿主机上构建

如果宿主机满足以下任一条件，直接 `lb build` 会失败：

- `/root` 或工作目录挂载了 `nodev`（设备节点不可写，`/dev/null` 变成普通文件）
- live-build 未安装为系统包，只能解包运行
- `/etc/mtab` 是指向只读 `/proc` 的符号链接

此时用仓库自带的包装器：

```sh
cd build
sh ../tools/lb.sh build
```

`tools/lb.sh` 在每次调用前会重建 `/dev` 设备节点并 bind-mount 宿主 `/dev` 进 chroot，
并把 `FURRYOS_BIND_DEVICES=1` 传给第二阶段 debootstrap。
具体每个限制的成因与绕法见 `docs/BUILD.md` 第 5 节。

### 4.5 测试镜像

```sh
# QEMU 直接启动
qemu-system-x86_64 -m 4096 -enable-kvm \
  -cdrom build/live-image-amd64.hybrid.iso

# 或写入 U 盘
sudo dd if=build/live-image-amd64.hybrid.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

启动后应看到：FurryOS 启动菜单 → 蓝白爪印登录界面 → KDE Plasma 桌面（蓝白配色 + 爪印壁纸）。

---

## 5. 验证

### 5.1 系统身份层（33 项断言）

```sh
sudo bash tools/verify-identity.sh
```

预期输出 `PASS=33 FAIL=0`，退出码 0。校验项包括 `/etc/os-release` 的 `NAME`/`PRETTY_NAME`、
`/etc/os-release` 指向 `/usr/lib/os-release` 的符号链接、`issue`/`motd`/`legal` 无上游字样、
`update-motd.d` 脚本权限等。

### 5.2 登录界面

```sh
grep '^Current' /etc/sddm.conf                 # → Current=furryos
ls /usr/share/sddm/themes/furryos/{Main.qml,metadata.desktop,theme.conf}
ls /usr/share/sddm/themes/furryos/components/  # 6 个文件
ls /usr/share/sddm/themes/furryos/assets/paw.svg
```

QML 语法校验：

```sh
cd /usr/share/sddm/themes/furryos
qmllint -I . --qmldirs /usr/lib/x86_64-linux-gnu/qt5/qml Main.qml components/*.qml
```

**最容易踩的坑**：缺 `qt5-image-formats` 时界面和动画都正常，**只有爪印静默消失**，且不弹任何错误。

```sh
sudo apt-get install -y qt5-image-formats qml-module-qtquick2 libqt5quick5
sudo systemctl restart sddm
```

### 5.3 出问题时

**只看一份文件：`docs/BUILD.md` 第 3 节。** 里面按层列出了「预期效果 → 看不到时逐条执行的命令」，
包括 SDDM 主题未生效、os-release 被上游覆盖、壁纸缺失、点击特效不出现等全部降级路径。

---

## 6. 品牌合规

| 位置 | 要求 | 实现 |
|---|---|---|
| `/etc/os-release` | `NAME="FurryOS"`、`PRETTY_NAME="FurryOS 24.04 LTS"` | `6010` 钩子写入 `/usr/lib/os-release` 并重建符号链接 |
| ISO 卷标 | `FurryOS` | `LB_ISO_VOLUME` |
| ISO 应用名 | `FurryOS` | `LB_ISO_APPLICATION` |
| 启动菜单 | `FurryOS` | `8000-brand-boot-menu.binary` |
| 登录界面 | 无 Ubuntu 标识 | SDDM 主题 `furryos` 完全替换 |
| 壁纸 | 无 Ubuntu Logo | 自绘爪印壁纸 |
| SSH 横幅 / motd / issue | 无 Ubuntu 商标 | `6010` 覆盖 + 移除上游 `update-motd.d` drop-in |

「基于 Ubuntu」这一上游来源说明仅出现一次，不做二次强调。
包管理兼容所需的底层标识（如 apt 源地址、`ubuntu-keyring`）属于技术必需，不面向用户展示。

---

## 7. 已知限制

工程在 **Debian 12 宿主机**上开发验证，与目标 Ubuntu 24.04 存在差异，如实记录：

| 限制 | 影响 | 应对 |
|---|---|---|
| 宿主无 GL 上下文 | 无法在宿主机渲染 SDDM 真实截图 | 用 `QQmlComponent` 实例化主题对象树做属性断言；另按真实坐标绘制四状态预览图 |
| 宿主非目标发行版 | 无法启动真实 SDDM 会话 | 提供 `install-sddm-theme.sh` 供注入；目视确认步骤见 BUILD.md 3.1 ⑦ |
| `qt5-image-formats` 在 noble 已并入源包 | 缺失时爪印静默消失 | 显式安装，见 5.2 |
| 宿主 `/root` 挂载 `nodev` | 设备节点不可写 | `tools/lb.sh` bind-mount 宿主 `/dev` |

完整的 11 条环境限制见 `docs/BUILD.md` 第 5 节。

---

## 8. 文档索引

| 文档 | 内容 |
|---|---|
| [`docs/BUILD.md`](docs/BUILD.md) | 构建环境、资产注入、**逐层降级方案**、ISO 验收清单、环境限制 |
| [`docs/CONTRACTS.md`](docs/CONTRACTS.md) | 五层资产注入契约、落盘路径、冲突裁决规则 |
| [`docs/sddm-verification/`](docs/sddm-verification/) | SDDM 主题验证报告（QML 6/6、色值 18/18、几何 0 重叠）与四状态预览图 |
| [`assets/sddm/README.md`](assets/sddm/README.md) | SDDM 主题设计说明、坐标基准、动画参数 |
| [`assets/effects/README.md`](assets/effects/README.md) | 点击特效与启动画面的实现与校验方法 |

---

## 9. 许可证与声明

FurryOS 作为 Ubuntu 的衍生作品，遵循 Ubuntu 及其所含软件包各自的许可证。
本仓库中的原创资产（配色、壁纸、SDDM 主题、启动画面、品牌文件）由 FurryOS 项目提供。

Ubuntu 是 Canonical Ltd. 的注册商标。FurryOS 与 Canonical Ltd. 无隶属关系，也未获其背书。
