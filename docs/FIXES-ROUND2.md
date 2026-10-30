# FurryOS 第二轮运行时缺陷修复（t8）

> 输入：`docs/BUILD-LOG.md`、`docs/VM-VERIFY.md` 中 t7 的 P1/P2/P3。
> 执行：队长接管（成员线路连续 503/403，用户明确批准接管）。
> 原则：不删除效果、不放宽断言；每项都有真实命令与输出。
> 状态：修复已完成；后续完整干净构建及 BIOS/UEFI/SDDM/串口复验也已通过。最终证据见 `docs/BUILD-LOG.md`、`docs/VM-VERIFY.md`（ISO SHA256 `2d9048bc…fb002`）。

## 0. 结果摘要

| 项 | 根因 | 修复 | 当前证据 |
|---|---|---|---|
| P1 UEFI 默认项不可启动 | GRUB 保留 Debian flavour glob `/live/vmlinuz-*amd64`，Ubuntu 实际内核为 `generic` | 8000 改为 `/live/vmlinuz`、`/live/initrd.img`，断言目标存在且无残留 | 真实 `build/binary` hook exit 0；路径、ESP 三行桩、`.disk/info` 全通过 |
| P2 `ksplashqml` Signal 11 | KSplash QML/metadata/images 在 rootfs 中是 0600 root，live 用户读取失败；`rootObject()` 为 null 后 `setStage()` 仍写 `stage` | 同步/安装时规范化权限，6130 对最终 rootfs 做世界可读/可遍历硬断言 | guest 反汇编/线程栈 + `.xsession-errors` 坐实；同一 guest 只 chmod 后 `ksplashqml` exit 0、无 KCrash |
| P3 桌面壁纸回落 Breeze Next | 没有 `LookAndFeelPackage`，Plasma 仍选择 Breeze 全局主题 | skel 与 `/etc/xdg/kdeglobals` 明确选择 `com.furryos.lookandfeel`；6110 硬断言 | 真实 rootfs 两处键均正确；删除该键的负向校验 exit 1 |
| P4 串口/Shell 显示 `debian` | live-build 默认 hostname 未覆盖，后续阶段还会写死默认值 | 6010 写入并断言；includes 在收尾恢复 `/etc/hostname=furryos` 和 `127.0.1.1 furryos` | 最终 squashfs 与运行中 hostname 均为 `furryos` |

---

## 1. P1：UEFI 默认项的内核/initrd 路径

### 1.1 改动

`build/config/hooks/normal/8000-brand-boot-menu.binary`：

- 将 ISO 侧 GRUB 的 `/live/vmlinuz-*amd64` 替换为 `/live/vmlinuz`。
- 将 `/live/initrd.img-*amd64` 替换为 `/live/initrd.img`。
- 断言两个目标在 `binary/live/` 中存在。
- 对 `boot/grub/*.cfg` 执行 `*amd64` 残留检查，发现即 exit 1。
- 保留 t4 的 ESP 三行引导桩断言，不再向 ESP 注入整份 GRUB 配置。

没有改全局 `LB_LINUX_FLAVOURS_*`，避免同时影响包选择和 live-build 其他阶段。

### 1.2 真实 binary 复验

```text
$ cd build/binary
$ sh ../config/hooks/normal/8000-brand-boot-menu.binary
[furryos-boot-brand] grub.cfg kernel paths -> /live/vmlinuz + /live/initrd.img (both resolve)
[furryos-boot-brand] efi.img ESP stub intact (search + prefix + configfile)
[furryos-boot-brand] rewrote .disk/info: FurryOS 24.04 LTS - Live amd64 Binary 20261028-00:05
[furryos-boot-brand] boot menu branding pass complete

$ grep -n 'linux\|initrd' boot/grub/grub.cfg | head -4
5:  linux  /live/vmlinuz boot=live components quiet splash findiso=${iso_path}
6:  initrd /live/initrd.img
9:  linux  /live/vmlinuz boot=live components memtest noapic noapm nodma nomce nolapic nosmp nosplash vga=788
10: initrd /live/initrd.img

$ grep -n '\*amd64' boot/grub/*.cfg
（无输出）

$ mtype -i boot/grub/efi.img ::/boot/grub/grub.cfg
search --set=root --file /.disk/info
set prefix=($root)/boot/grub
configfile ($root)/boot/grub/grub.cfg
```

**边界**：这证明生成配置和引导桩正确；OVMF 默认项必须在新 ISO 上复验，不能把本项写成“UEFI 已实启通过”。

---

## 2. P2：KSplash 段错误是权限导致的空 rootObject 解引用

### 2.1 guest 日志与真实线程栈

用直接内核启动当前 ISO，并加 `console=ttyS0` 进入 live 用户串口会话。`~/.xsession-errors` 原文：

```text
kf.coreaddons: Couldn't open "/usr/share/plasma/look-and-feel/org.furryos.desktop/metadata.json"
"file:///usr/share/plasma/look-and-feel/org.furryos.desktop/contents/splash/Splash.qml"
 "Error loading QML file.\nPermission denied\n"
KCrash: Application Name = ksplashqml path = /usr/bin pid = 1509
```

对仍在 KCrash 处理器里的 PID 1509 执行 guest 内 `gdb -p 1509 -batch -ex 'thread apply all bt'`，主线程栈：

```text
KCrash::defaultCrashHandler(int)
<signal handler called>
QObject::setProperty(char const*, QVariant const&)
ksplashqml +0x6f0d
...
__libc_start_main(main=ksplashqml +0x4cf0)
```

对镜像内 `usr/bin/ksplashqml` 反汇编，`0x6ec0` 起的函数依次执行：

```text
QuickViewSharedEngine::rootObject()
QVariant::QVariant(int stage)
QObject::setProperty("stage", stage)     # call 位于 0x6f08，返回地址 0x6f0d
```

即 QML 加载失败后 `rootObject()==nullptr`，KSplash 的 `setStage()` 仍向它写 `stage`，触发 Signal 11。不是 SVG 渲染线程、不是 `Plasma::QuickTheme` 单例缺失，也不是动画时长问题。

### 2.2 权限证据

旧 rootfs 实测：

```text
600 usr/share/plasma/look-and-feel/org.furryos.desktop/metadata.json
600 .../contents/splash/Splash.qml
600 .../contents/splash/images/{busywidget.svg,paw-white.svg}
600 usr/share/plasma/look-and-feel/com.furryos.lookandfeel/metadata.desktop
600 usr/share/plasma/desktoptheme/furryos/metadata.json
600 usr/share/icons/FurryOS/index.theme
600 etc/skel/.config/{kdeglobals,plasmarc,kwinrc}
```

Git 只保存 blob 的可执行位，不保存完整的 world-read 位。构建者若使用 `umask 077`，普通文件会变成 0600；各层使用 `cp -a` 后，该权限一直进入 ISO。

### 2.3 同一 guest 的因果对照

在同一个已崩溃 guest 里，不重装主题、不改 QML，只执行：

```sh
sudo chmod -R a+rX,go-w /usr/share/plasma/look-and-feel/org.furryos.desktop
DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
  timeout 15s ksplashqml --test --window --nofork org.furryos.desktop
```

结果：

```text
Splash.qml mode: 644
retry_rc=0
no_crash_or_permission_errors
```

这证明权限是该次崩溃的因果根因。对照日志还暴露了 icons/FurryOS 与 desktoptheme/furryos 的读取错误，因此修复覆盖整个 FurryOS 运行时资产树，而非只 chmod 一个文件。

### 2.4 持久修复

1. `tools/sync-assets.sh`
   - 每次同步后执行 `chmod -R a+rX,go-w`。
   - 所有文件可读、目录可遍历；大写 X 保留脚本可执行位。
2. `assets/effects/splash/effects-splash-install.sh`
   - `umask 022`。
   - KSplash/Plymouth 安装后再次规范化。
   - 安装器自身检查任何目录缺 `055`、文件缺 `044` 都 exit 1。
   - `/etc/xdg/ksplashrc` 显式 0644。
3. `build/config/hooks/normal/6130-integrate-effects-assets.chroot`
   - 对最终 rootfs 的 KSplash 树做权限硬断言，不再只检查文件存在。
4. `build/config/hooks/normal/6110-integrate-desktop-assets.chroot`
   - 对 FurryOS LNF、Plasma 主题、壁纸、图标和 `/etc/skel` 做同样的规范化与硬断言。
   - 只处理 FurryOS 自有目录，不递归改动相邻 Breeze/系统包。

### 2.5 权限负向/边界测试

把安装器源树故意改为目录 0700、文件 0600，并在 `umask 077` 下安装：

```text
644 .../org.furryos.desktop/contents/splash/Splash.qml
644 .../org.furryos.desktop/metadata.json
644 .../etc/xdg/ksplashrc
PASS: umask 077 + 0600 sources cannot produce unreadable KSplash assets
```

真实 rootfs 顺序执行 `6000 → 6110 → 6130 → 8990`，全部 exit 0；最终 QML、metadata、icons、skel 都是 0644，权限扫描无残留。

---

## 3. P3：明确选择 FurryOS Look-and-Feel

### 3.1 改动

`assets/desktop/skel/.config/kdeglobals` 的 `[KDE]` 新增：

```ini
LookAndFeelPackage=com.furryos.lookandfeel
```

`6110-integrate-desktop-assets.chroot`：

- 新建或已存在的 `/etc/xdg/kdeglobals` 都必须具有同一个键。
- 对 `/etc/skel/.config/kdeglobals` 与 `/etc/xdg/kdeglobals` 做硬断言。
- 断言 `com.furryos.lookandfeel/metadata.desktop` 已安装。

`tools/verify-visual.py` 新增对应静态断言；断言总数由 130 增至 131，`docs/VISUAL.md` 的计数已同步。

### 3.2 真实 rootfs 输出

```text
/etc/skel/.config/kdeglobals:47:LookAndFeelPackage=com.furryos.lookandfeel
/etc/xdg/kdeglobals:11:LookAndFeelPackage=com.furryos.lookandfeel
```

负向对照：临时删除 skel 中的该键后运行 `verify-visual.py`：

```text
negative verify-visual exit=1
[FAIL] skel kdeglobals [KDE] 明确选择 FurryOS 全局主题（否则壁纸回落 Next）
PASS: wallpaper fallback regression is a hard assertion
```

**边界**：配置与校验已通过；最终桌面 RMSE/截屏必须在新 ISO 上重新比较，不能提前宣称壁纸已经实启通过。

---

## 4. P4：登录提示符中的 Debian hostname

串口实测旧 ISO 显示 `debian login:` 与 `user@debian`。修复分两层：

- `6010-integrate-identity-assets.chroot` 在身份注入阶段写 `/etc/hostname=furryos` 与 `127.0.1.1 furryos`，并做硬断言。
- `build/config/includes.chroot_after_packages/etc/{hostname,hosts}` 保存同样的最终值。live-build 20230502 没有 `--hostname` 选项，`chroot_hostname install` 会写死 `localhost.localdomain`，`chroot_hosts install` 会写死 `debian`；它们的 remove 阶段会从该 includes 目录恢复自定义文件，因此这里是防覆盖的权威收尾入口。

真实 rootfs 复验：

```text
[furryos] installed FurryOS hostname and loopback host mapping
/etc/hostname: furryos
/etc/hosts:    127.0.1.1 furryos
```

---

## 5. 回归结果

| 校验 | 结果 |
|---|---|
| `dash -n`（同步、安装器、6010/6110/6130/8000） | 全部通过 |
| `sh tools/sync-assets.sh` | 162 文件同步，源/配置一致 |
| 权限边界安装测试（0600 源 + umask 077） | 通过 |
| 真实 rootfs 6000/6010/6110/6130/8990 | 全部 exit 0 |
| 真实 binary 8000 | exit 0；无 `*amd64`，ESP 桩完好 |
| `bash tools/verify-visual.sh` | 15 项顶层检查，失败 0；verify-visual.py 131 项，splash 18 项 |
| `bash tools/verify-brand.sh --no-fetch` | 4/4 通过；身份 PASS=33 FAIL=0 |
| LookAndFeelPackage 负向对照 | 按预期 exit 1 |
| 旧 guest 内只修权限后重跑 ksplashqml | exit 0，无 Permission denied/KCrash |

## 6. 最终新 ISO 复验（已完成）

后续 t7 已从最终源码完成完整 `lb clean → lb config → lb build`，并逐项关闭上述问题：

1. OVMF 默认菜单项直接进入桌面，不再需要手工内核路径。
2. BIOS/UEFI 均无 `ksplashqml` KCrash；延迟 guest 日志扫描无权限/段错误。
3. 真实桌面对 FurryOS 母版 RMSE 0.1582，对 Breeze Next 为 0.3784。
4. SDDM 60/100/140 秒截屏稳定，蓝白色板与字标生效。
5. 最终 squashfs 与运行中 hostname 均为 `furryos`。
6. 新 ISO 为 2143289344 bytes，SHA256 `2d9048bc07565566e64bd7c85615bfcd98b302578b2469ac65a87340a68fb002`。

完整命令与证据见 `docs/BUILD-LOG.md`、`docs/VM-VERIFY.md`。本修复报告编写阶段没有提交/推送；
后续 Git 交付状态以 `docs/RELEASE.md` 为准。

Plymouth 仍是已记录的降级状态：主题文件就位，但镜像没有 `plymouth` 包，不能宣称 Plymouth 动画已启用。
