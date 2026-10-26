# FurryOS ISO 卷标与启动菜单文本（供 build-verify 使用）

本文件由**系统身份层**提供，只负责「文本内容」。
实际注入由**构建交付层（build-verify）**负责——它已经做了大部分工作
（见 `build/config/binary` 的 `LB_ISO_APPLICATION` / `LB_ISO_VOLUME` /
`LB_ISO_PUBLISHER`，以及 `build/config/bootloaders/syslinux_common/` 与
`build/config/hooks/normal/8000-brand-boot-menu.binary`）。

下面是本层要求的文本取值与校验方式，供构建交付层对齐。

## 1. ISO 元数据（`build/config/binary`，已由 build-verify 设置）

| live-build 变量 | 期望值 | 现状 |
|---|---|---|
| `LB_ISO_APPLICATION` | `FurryOS` | 已设置 ✅ |
| `LB_ISO_VOLUME` | `FurryOS`（≤32 字符） | 已设置 ✅ |
| `LB_ISO_PUBLISHER` | `FurryOS Project` | 已设置 ✅ |
| `LB_ISO_PREPARER` | 建议改为 `FurryOS Project; https://furryos.example.org/` | **仍是 live-build 默认值** ⚠️ |
| `LB_HDD_LABEL` | 建议改为 `FurryOS` | **仍是 `DEBIAN_LIVE`** ⚠️ |

> `LB_ISO_PREPARER` 与 `LB_HDD_LABEL` 属于构建交付层负责的资源
> （见 `docs/CONTRACTS.md` 冲突裁决表：ISO 名称、卷标、启动菜单 → 成员五）。
> 此处仅作为本层的品牌合规观察上报，由队长/成员五决定是否修改。

## 2. 启动菜单文字（`build/config/bootloaders/` + 二进制期钩子）

| 出现位置 | 上游默认 | FurryOS 期望值 | 处理方式 |
|---|---|---|---|
| syslinux `live.cfg.in` menu label | `^Live system (@FLAVOUR@)` | `^FurryOS Live` | build-verify 已覆盖模板 ✅ |
| syslinux 同上（安全模式） | `Live system (@FLAVOUR@ fail-safe mode)` | `FurryOS Live (^fail-safe mode)` | 已覆盖 ✅ |
| syslinux 菜单标题 `menu.cfg` | `Boot menu` | `FurryOS Boot Menu` | 由 `_PROJECT` 注入 |
| splash.svg 首行文字 | `@PROJECT@ @VERSION@ (@DISTRIBUTION@)` → `Debian GNU/Linux ...` | `FurryOS` | build-verify 的 splash.svg 已去掉 `@PROJECT@` ✅ |
| grub menuentry 标签 | `Live system (amd64)` / `... fail-safe mode` / `Live system, kernel <ver>` | `FurryOS Live (amd64)` / `FurryOS Live (amd64 fail-safe mode)` / `FurryOS Live, kernel <ver>` | `8000-brand-boot-menu.binary` 后期替换 ✅ |
| grub 主题标题 `live-theme/theme.txt` | `Live Boot Menu with GRUB` | 建议 `FurryOS Boot Menu` | build-verify 自行决定 |

## 3. 本层提供的文本取值（唯一权威）

```
发行版名称        : FurryOS
完整名称          : FurryOS 24.04 LTS
版本号            : 24.04
代号              : noble
ISO 卷标          : FurryOS
ISO 应用程序 ID    : FurryOS
ISO 发布者        : FurryOS Project
启动菜单默认项    : FurryOS Live
启动菜单安全项    : FurryOS Live (fail-safe mode)
启动菜单标题      : FurryOS Boot Menu
```

## 4. 校验命令（构建交付层在 `binary/` 目录中执行）

```bash
# 4.1 syslinux 生成的菜单里不得出现上游名称
grep -rIiE "debian|ubuntu" binary/isolinux/*.cfg binary/isolinux/*.svg
# 期望：无输出（live.cfg 的注释说明除外，可用 --exclude 或看非注释行）

# 4.2 grub 生成的菜单里不得出现上游名称
grep -rIiE "debian|ubuntu" binary/boot/grub/*.cfg binary/boot/grub/live-theme/*
# 期望：无输出

# 4.3 ISO 卷标/应用程序 ID
xorriso -indev furryos.iso -report_about DEBUG 2>/dev/null | grep -iE "volume|application"
# 期望：Volume Id : FurryOS / Application id: FurryOS
# 或：
isoinfo -d -i furryos.iso | grep -iE "volume id|application id"

# 4.4 挂载 ISO 后人工确认菜单文字
mount -o loop furryos.iso /mnt && ls /mnt/isolinux/
```

## 5. 品牌合规声明

- 上述所有文本均不使用 Ubuntu/Debian 商标、Logo 或上游品牌素材
  （依据 `assets/brand/brand-tokens.md` 第 3 节）。
- 允许的「基于 Ubuntu」表述只出现在说明性位置（`/etc/motd`、
  `docs/BUILD.md`），不出现在卷标、启动菜单、登录横幅。
