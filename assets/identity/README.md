# FurryOS 系统身份层（assets/identity）

**负责人**：brand-identity（品牌与合规）
**契约依据**：[docs/CONTRACTS.md](../docs/CONTRACTS.md)「成员一：系统身份层」
**品牌底线**：[assets/brand/brand-tokens.md](../brand/brand-tokens.md)

本目录提供所有「用户可能看到系统名称的位置」的替换内容。目标：
**远程 SSH 登录时看到 FurryOS 横幅，且登录后任何位置都不出现 Ubuntu。**

---

## 1. 文件清单与注入目标

| 本目录文件 | 安装到目标系统 | 权限 | 作用 |
|---|---|---|---|
| `os-release` | `/etc/os-release`（并同步 `/usr/lib/os-release`） | 0644 | `NAME="FurryOS"`、`PRETTY_NAME="FurryOS 24.04 LTS"` |
| `issue` | `/etc/issue` | 0644 | 本地终端（getty/console）登录提示 |
| `issue.net` | `/etc/issue.net` | 0644 | **远程 SSH 登录横幅**（硬性要求：不含 Ubuntu） |
| `motd` | `/etc/motd` | 0644 | 登录后静态欢迎信息 |
| `legal` | `/etc/legal` | 0644 | pam_motd 首次登录展示的免责声明（上游写的是 Ubuntu） |
| `lsb-release` | `/etc/lsb-release` | 0644 | 兼容层：`DISTRIB_ID`/`DISTRIB_NAME` 为 FurryOS |
| `motd-news` | `/etc/default/motd-news` | 0644 | `ENABLED=0`，关闭 motd.ubuntu.com 动态新闻 |
| `sshd_banner.conf` | `/etc/ssh/sshd_config.d/010-furryos-banner.conf` | 0644 | 显式开启 `Banner /etc/issue.net` |
| `furryos-logo.svg` | `/usr/share/about-distro/logo.svg` | 0644 | KDE「关于本机」爪印 logo |
| `about-distro/furryos-logo.svg` | `/usr/share/about-distro/furryos-logo.svg` | 0644 | 同上，CONTRACTS 要求的目录布局 |
| `about-distro/kcm-about-distrorc` | `/etc/xdg/kcm-about-distrorc` | 0644 | KDE「关于本机」Name/Version/Website/Variant/LogoPath |
| `update-motd.d/00-header` | `/etc/update-motd.d/00-header` | **0755** | 替换上游版（上游会打印 `DISTRIB_DESCRIPTION`） |
| `update-motd.d/10-help-text` | `/etc/update-motd.d/10-help-text` | **0755** | 替换上游版（上游打印 help.ubuntu.com / landscape.canonical.com） |
| `update-motd.d/20-furryos` | `/etc/update-motd.d/20-furryos` | **0755** | FurryOS 自己的动态信息，纯本地、无网络请求 |
| `iso-boot-text.md` | 不安装 | — | 提供给成员五的 ISO 卷标/启动菜单文本取值 |

爪印符号来源：[assets/brand/paw.svg](../brand/paw.svg)（256×256 viewBox，`furryos-blue #1A6FD4`），
未做任何修改，仅原样复制。**未使用任何 Ubuntu/Debian 商标、Logo 或上游品牌素材。**

---

## 2. 逐项改动点：位置、作用、验证方式

### 2.1 系统信息查询 → `/etc/os-release`

**作用**：`lsb_release`、`hostnamectl`、KDE `KOSRelease`、`neofetch` 等都读这里。
上游原值 `NAME="Ubuntu"` / `PRETTY_NAME="Ubuntu 24.04 LTS"`。

**保留的兼容字段**（brand-tokens.md 第 3 节允许）：`ID=ubuntu`、`ID_LIKE="ubuntu debian"`。
这两项是包管理兼容链（apt/PPA/lsb_release）所需，不能改。

**关键坑**：上游 `base-files` 把 `/etc/os-release` 做成指向 `/usr/lib/os-release` 的
**符号链接**。直接写入会穿透到 `/usr/lib/os-release`，导致两份内容不一致。
注入时必须先 `rm -f /etc/os-release` 再落真实文件，并同步写 `/usr/lib/os-release`
（`KOSRelease::defaultFilePath()` 在 `/etc/os-release` 不存在时会回退到它）。

```bash
# 在已组装文件系统（或 live-build chroot）中：
cat chroot/etc/os-release                     # 应见 NAME="FurryOS"
. chroot/etc/os-release && echo "$NAME / $PRETTY_NAME"
chroot chroot /usr/bin/lsb_release -a         # Distributor ID: FurryOS
grep -c Ubuntu chroot/etc/os-release          # 期望 0（ID=ubuntu 是小写，不匹配）
```

### 2.2 本地终端登录提示 → `/etc/issue`

**作用**：agetty/getty 在本地控制台登录前打印。`\n \l` 会被展开为换行与终端名。

```bash
cat chroot/etc/issue                          # 期望 "FurryOS 24.04 LTS \n \l"
grep -i ubuntu chroot/etc/issue               # 期望无输出
```

### 2.3 远程 SSH 登录横幅 → `/etc/issue.net` + sshd Banner

**作用**：sshd 在认证**之前**打印 `/etc/issue.net`，这是远程用户看到的第一行。

**为什么需要 drop-in 文件**：openssh-server 的模板
`/usr/share/openssh/sshd_config` 里 Banner 是注释状态（`#Banner none`），
**默认关闭**。但模板第 12 行有 `Include /etc/ssh/sshd_config.d/*.conf`，
所以放一个 drop-in 就能显式开启，无需改动 `sshd_config` 本体（避免包升级冲突）。

```bash
cat chroot/etc/ssh/sshd_config.d/010-furryos-banner.conf   # 期望 "Banner /etc/issue.net"
grep -i ubuntu chroot/etc/issue.net                        # 硬性要求：必须无输出

# 真实 SSH 登录验证（需要能启动 sshd 的环境）：
#   sshd -t -f /etc/ssh/sshd_config        # 配置语法检查，应无输出
#   ssh -o StrictHostKeyChecking=no user@localhost
#   连接后、输入密码之前，应先看到 "FurryOS 24.04 LTS"
```

### 2.4 登录后欢迎信息 → `/etc/motd` + `update-motd.d/`

**作用**：`pam_motd.so` 在登录成功后展示。展示内容分两部分：

1. **静态**：`/etc/motd`
2. **动态**：`pam_motd.so` 以 root 身份执行
   `run-parts --lsbsysinit /etc/update-motd.d > /run/motd.dynamic.new`
   （该命令行可从 `libpam-modules` 的 `pam_motd.so` 字符串中直接确认）

**必须处理的四个上游暴露点**：

| 上游文件 | 暴露内容 | 处理方式 |
|---|---|---|
| `update-motd.d/00-header` | `. /etc/lsb-release` 后打印 `DISTRIB_DESCRIPTION` → "Welcome to Ubuntu 24.04 LTS (...)" | 删除，装 `update-motd.d/00-header`（只读 `DISTRIB_NAME`/`DISTRIB_VERSION`，不回退 `lsb_release`） |
| `update-motd.d/10-help-text` | 打印 `help.ubuntu.com` / `landscape.canonical.com` / `ubuntu.com/pro` | 删除，装 `update-motd.d/10-help-text` |
| `update-motd.d/50-motd-news` | 从 `https://motd.ubuntu.com` 拉新闻；User-Agent 含 `DISTRIB_DESCRIPTION` | 删除，不替换 |
| `/etc/legal` | `pam_motd.so` 为每个用户**首次登录**展示一次，内容是 "The programs included with the Ubuntu system..." / "Ubuntu comes with ABSOLUTELY NO WARRANTY..." | 装 `legal` |

**双保险关闭 motd-news**：`base-files` 的 postinst 会
`deb-systemd-helper enable motd-news.timer`，即使删了 `50-motd-news`
脚本，定时器仍会按 `OnStartupSec=1min` / 每天 `00,12:00` 触发。
因此除了 `ENABLED=0`，还要：

```bash
ln -sf /dev/null /etc/systemd/system/motd-news.timer
ln -sf /dev/null /etc/systemd/system/motd-news.service
rm -f /var/cache/motd-news        # 清掉可能已缓存的 Ubuntu 新闻
```

**验证**：

```bash
# 静态内容
grep -i ubuntu chroot/etc/motd chroot/etc/legal            # 期望无输出
ls -l chroot/etc/update-motd.d/                            # 期望只有 00-header 10-help-text 20-furryos

# 实际执行动态脚本，看输出（不需要启动系统）
(cd chroot && run-parts --lsbsysinit /etc/update-motd.d) 2>&1 | grep -i ubuntu   # 期望无输出
(cd chroot && sh ./etc/update-motd.d/00-header)            # 期望 "Welcome to FurryOS 24.04 (...)"

# 确认动态脚本都是可执行的（run-parts 只跑有 x 位的）
ls -l chroot/etc/update-motd.d/ | awk '{print $1, $NF}'
```

### 2.5 图形界面系统信息 → `/usr/share/about-distro/` + `/etc/xdg/kcm-about-distrorc`

**作用**：KDE 系统设置 / KInfoCenter 的「关于本机」（About this System）页面。

**实现依据**（已从上游源码确认）：
`plasma/kinfocenter/Modules/about-distro/src/main.cpp` 的 `loadOSData()` 用
`KSharedConfig::openConfig("kcm-about-distrorc", KConfig::NoGlobals)` 读
`[General]` 组，字段缺省值来自 `KOSRelease`（即 `/etc/os-release`）：

| 字段 | 缺省来源 | 我们的显式值 |
|---|---|---|
| `LogoPath` | `os.logo()` → `LOGO=` 经图标主题解析 | `/usr/share/about-distro/furryos-logo.svg` |
| `Name` | `os.name()` | `FurryOS` |
| `Version` | `os.versionId()` | `24.04 LTS` |
| `Website` | `os.homeUrl()` | `https://furryos.example.org/` |
| `Variant` | `os.variant()` | `Plasma Desktop` |

> `openConfig` 不带 `KConfig::NoGlobals` 之外的合并，且按 XDG_CONFIG_DIRS 搜索，
> `/etc/xdg` 优先于用户目录，因此对所有用户生效。

**为什么两个 logo 路径都要装**：
- `kcm-about-distrorc` 的 `LogoPath` 用绝对路径 `/usr/share/about-distro/furryos-logo.svg`（最稳）
- `/etc/os-release` 的 `LOGO=furryos-logo` 供没装 `kcm-about-distrorc` 的代码路径
  经图标主题解析，所以 `/usr/share/about-distro/logo.svg` 也要存在
- CONTRACTS.md 明确要求「通过 `config/includes.chroot/usr/share/about-distro/` 覆盖」，
  因此目录布局保留 `about-distro/` 子目录形式

```bash
cat chroot/etc/xdg/kcm-about-distrorc                     # Name=FurryOS, LogoPath=...
ls -l chroot/usr/share/about-distro/                      # furryos-logo.svg + logo.svg
grep '^LOGO=' chroot/etc/os-release                       # LOGO=furryos-logo

# 实际验证（需要图形环境）：
#   kinfocenter 或 systemsettings 的「关于本机」
#   期望：Operating System: FurryOS 24.04 LTS，logo 是蓝色爪印
```

### 2.6 ISO 卷标与启动菜单文字 → `iso-boot-text.md`

**本层只提供文本取值**，实际注入由成员五（build-verify）负责。
已由成员五完成的部分见 [iso-boot-text.md](iso-boot-text.md)，
其中记录了两项仍待成员五决定的品牌合规观察：
`LB_HDD_LABEL="DEBIAN_LIVE"` 与 `LB_ISO_PREPARER` 默认值。

---

## 3. 验证方式（两种，都不需要启动真实系统）

宿主是 Debian 12，无法安装 Ubuntu 包、也不能启动 Ubuntu 内核，所以用
**上游包原始文件 + 模拟文件系统**做静态审查。

### 方式 A：本层自带的自动化校验（推荐）

```bash
# 第一步：下载并解包上游 Ubuntu noble 参考包（只需一次）
bash /root/furryos/.verify/fetch-refs.sh

# 第二步：跑 30 项校验
bash /root/furryos/tools/verify-identity.sh
# 期望末尾：结果：PASS=30 FAIL=0
```

它做三件事：
1. 用 `base-files` / `lsb-release` / `motd-news-config` / `openssh-server` /
   `update-motd` 的**原始解包文件**搭一个 `/etc` 快照（即「注入前」真实状态），
   包括 `/etc/os-release` 是指向 `/usr/lib/os-release` 的符号链接这一细节；
2. 按注入逻辑把 `assets/identity/` 应用上去；
3. 对应用后的文件系统逐项断言 + 全量 grep 扫描用户可见内容。

### 方式 B：在 live-build chroot 里手动 grep（t8 验收用）

```bash
cd /root/furryos/build

# B1. SSH 横幅硬性要求
grep -i ubuntu chroot/etc/issue.net && echo "FAIL" || echo "PASS: issue.net 无 Ubuntu"
grep -q "FurryOS" chroot/etc/issue.net && echo "PASS: 有 FurryOS 横幅"

# B2. 登录后任何位置都不出现 Ubuntu（只看会被打印的非注释行）
for f in chroot/etc/issue chroot/etc/issue.net chroot/etc/motd chroot/etc/legal; do
    grep -vE '^\s*#' "$f" | grep -i ubuntu && echo "FAIL: $f" || echo "PASS: $f"
done

# B3. 动态 MOTD 脚本
ls chroot/etc/update-motd.d/
chroot chroot run-parts --lsbsysinit /etc/update-motd.d | grep -i ubuntu && echo FAIL || echo PASS

# B4. os-release 只保留 ID=ubuntu 兼容字段
grep -vE '^(ID|ID_LIKE|.*_URL)=' chroot/etc/os-release | grep -i ubuntu && echo FAIL || echo PASS

# B5. SSH Banner 显式开启
grep -rE '^Banner' chroot/etc/ssh/sshd_config.d/ chroot/etc/ssh/sshd_config 2>/dev/null

# B6. KDE 关于本机
grep -E '^(Name|LogoPath)' chroot/etc/xdg/kcm-about-distrorc
ls chroot/usr/share/about-distro/

# B7. motd-news 双保险
grep '^ENABLED=' chroot/etc/default/motd-news
ls -l chroot/etc/systemd/system/motd-news.* 2>/dev/null
```

---

## 4. 与成员五（build-verify）的接口

> **6010 的最终内容以本目录资产为准。**
> 队长裁决（A 项）：6010 钩子由 brand-identity 直接维护，因为它注入的全部是系统身份层
> 资产；成员五只负责「钩子如何被 live-build 调用」，不负责「身份层资产包含什么」。
> 如果 6010 的行为与本 README 描述不一致，**以本 README + 本目录文件为准**，
> 并按本文件第 2 节的暴露点清单核对。

### 4.1 6010 已覆盖的本层资产（12/12）

`build/config/hooks/normal/6010-integrate-identity-assets.chroot` 现已处理
本目录全部 12 个可安装资产：

| 资产 | 6010 安装到 | 备注 |
|---|---|---|
| `os-release` | `/usr/lib/os-release` + `/etc/os-release` 符号链接 | 见 4.2 |
| `issue` | `/etc/issue` | |
| `issue.net` | `/etc/issue.net` | |
| `motd` | `/etc/motd` | |
| `legal` | `/etc/legal` | |
| `lsb-release` | `/etc/lsb-release` | |
| `motd-news` | `/etc/default/motd-news` | |
| `sshd_banner.conf` | `/etc/ssh/sshd_config.d/010-furryos-banner.conf` | |
| `furryos-logo.svg` | `/usr/share/about-distro/logo.svg` | |
| `about-distro/furryos-logo.svg` | `/usr/share/about-distro/furryos-logo.svg` + hicolor 图标链接 | |
| `about-distro/kcm-about-distrorc` | `/etc/xdg/kcm-about-distrorc` | |
| `update-motd.d/*` | `/etc/update-motd.d/<同名>`，**0755** | 见 4.3 |

`iso-boot-text.md` 与 `README.md` 不安装，前者供成员五读取文本取值。

### 4.2 os-release 的符号链接策略（6010 的做法，优于本层原方案）

上游 `base-files` 把 `/etc/os-release` 做成指向 `../usr/lib/os-release` 的符号链接。
6010 的做法是：**真实文件写 `/usr/lib/os-release`，然后重建符号链接**。
这样 `dpkg -S /etc/os-release` 仍能解析到 `base-files`，升级行为正常。

`tools/verify-identity.sh` 已按此逻辑断言三条：
符号链接存在、目标为 `../usr/lib/os-release`、两份内容一致
（`KOSRelease::defaultFilePath()` 在 `/etc/os-release` 缺失时会回退到
`/usr/lib/os-release`，两份不一致会让回退路径暴露上游值）。

### 4.3 update-motd.d 的处理顺序（6010 已实现）

1. **删除**上游 `00-header` / `10-help-text` / `50-motd-news`，以及一组可选的
   （`51-cloudguest`、`70-available-updates`、`90-updates-available`、
   `91-contract-ua-eligible`、`95-hwe-eol`、`97-overlayroot`、`98-fsck-at-boot`、
   `98-reboot-required`）。删除而非 `chmod a-x`，因为这三个是 `base-files` 的
   dpkg conffile，只去掉执行位会让 `dpkg -V` 报内容被改。
2. **安装**本层三个脚本，`chmod 0755`（`run-parts --lsbsysinit` 只执行有 x 位的）。
3. **兜底扫描**：对任何残留脚本，只查**非注释行**是否含 ubuntu，命中则 `chmod a-x`。
   注意不能写 `grep -rIl "Ubuntu"`——本层脚本的注释里提到了上游名称作为维护说明，
   那条命令会误删自己的脚本。

### 4.4 motd-news 的双保险（6010 已实现）

`ENABLED=0` 不够：`base-files` 的 postinst 会 `deb-systemd-helper enable
motd-news.timer`，定时器仍按 `OnStartupSec=1min` / 每天 `00,12:00` 触发。
6010 同时做了 `ln -sf /dev/null /etc/systemd/system/motd-news.{timer,service}`。

### 4.5 遗留：6000 的资产暂存路径不一致（已上报成员五，待其修复）

`furryos-common.sh:23` 定义 `FURRYOS_ASSETS="/live-build/assets"`，而
`6000-stage-furryos-assets.chroot:35` 暂存到 `/opt/furryos/assets`，
且 `lb chroot_hooks` 只 bind-mount 了 `config` → `/live-build/config`，
**没有任何地方创建 `/live-build/assets`**。

后果：6000 的 `[ ! -d ... ]` 守卫命中 → warning → `exit 0`（不中断构建）→
6010/6110/6120/6130 全部读到不存在的 SRC → **四层资产静默全部失效，构建显示成功**。

本层已在 6010 内做了防御：不再依赖 `${FURRYOS_ASSETS}`，改为在
`/opt/furryos/assets/identity` 与 `/live-build/assets/identity` 中探测，
两者都不存在则 `exit 1`（让构建失败而不是静默跳过）。
但 `6110`/`6120`/`6130` 仍读同一个变量，需要成员五在 `furryos-common.sh`
或 `6000` 中统一，并建议把「资产目录不存在」从 `exit 0` 改为 `exit 1`。

---

## 5. 品牌合规自查

| 检查项 | 结果 |
|---|---|
| `/etc/issue.net` 含 Ubuntu 字样（含注释行） | 无 |
| 用户可见内容含 Ubuntu 字样 | 无（仅 `os-release` 的 `ID=ubuntu`/`ID_LIKE` 兼容字段） |
| 引用 Ubuntu/Debian 商标或 Logo | 无 |
| 使用上游品牌素材 | 无（爪印为 `assets/brand/paw.svg` 原样复制） |
| 「基于 Ubuntu」表述 | 仅出现在 `lsb-release` 的 `DISTRIB_DESCRIPTION`（brand-tokens.md 第 3 节允许） |
