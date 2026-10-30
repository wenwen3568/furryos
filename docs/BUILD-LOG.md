# FurryOS 构建日志与发布候选产物（最终复验轮）

> 日期：2026-10-31
> 执行：队长接管 t7（成员 build-runner 两次均在开工前因模型线路 503 失败）
> 基础：t8 的 P1/P2/P3/P4 修复，见 `docs/FIXES-ROUND2.md`
> 结论：**完整干净构建成功；BIOS、UEFI、SDDM、KDE、KSplash、壁纸、hostname 均通过实机虚拟机验收。**

## 1. 最终产物

```text
路径：build/live-image-amd64.hybrid.iso
大小：2143289344 bytes（2044.00 MiB）
SHA256：2d9048bc07565566e64bd7c85615bfcd98b302578b2469ac65a87340a68fb002

filesystem.squashfs：1990787072 bytes（1898.56 MiB）
内核：linux-image-generic 6.8.0-147.147
Plasma：plasma-workspace 4:5.27.12-0ubuntu0.1
SDDM：0.20.0-2ubuntu4.2
```

此哈希对应本文全部 QEMU 证据。早期失败或中间候选 ISO 的哈希均不作为发布依据。

## 2. 最终构建方式

最终 ISO 来自一次完整的 `lb clean → lb config → lb build`，不是从中间 stagefile 续跑。
开始于 2026-10-31 00:37:12（+08:00），结束于 01:12:23，约 35 分钟。

```sh
cd /root/furryos
bash tools/prepare-toolchain.sh
sh tools/sync-assets.sh
bash tools/verify-brand.sh --no-fetch
bash tools/verify-visual.sh

cd build
bash ../tools/lb.sh clean
bash ../tools/lb.sh config \
  --distribution noble \
  --binary-images iso-hybrid \
  --iso-application FurryOS \
  --iso-volume FurryOS \
  --mirror-binary http://archive.ubuntu.com/ubuntu/ \
  --mirror-binary-security http://security.ubuntu.com/ubuntu/
bash ../tools/lb.sh build
```

实际结束输出：

```text
P: Binary stage completed
P: Begin unmounting filesystems...
P: Saving caches...
[2026-10-31 01:12:23] lb source
P: Source stage disabled, skipping
P: Build completed successfully
[2026-10-31T01:12:23+08:00] release lb build exit=0
```

原始构建输出在本轮环境保存为 `/tmp/furryos-t7-release-build.log`。该临时日志不是 Git 交付物。

### 为什么不使用 binary 续跑作为最终产物

验收过程中曾检查 binary-only 重跑；它会重新引入构建期状态，且失败退出可能留下
`chroot.tmp/dev/*` bind mount。最终产物因此重新从完整 clean 构建，避免嵌套/缓存/阶段残留。
若失败退出留下设备挂载，必须先确认并卸载明确的临时挂载点，不能直接强删。

## 3. 关键构建钩子输出

### 3.1 视觉权限与 Look-and-Feel

```text
[furryos] desktop/skel asset permissions verified for unprivileged live users
[furryos] live/new users and system fallback select com.furryos.lookandfeel
[furryos] Desktop visual layer installed.
[furryos] KSplash QML/metadata/images are readable by the live user
[furryos] KSplash theme installed and selected (org.furryos.desktop)
[furryos] Motion effects layer installed.
```

最终 rootfs 中关键文件：

```text
644 usr/share/plasma/look-and-feel/org.furryos.desktop/contents/splash/Splash.qml
644 usr/share/plasma/look-and-feel/com.furryos.lookandfeel/metadata.desktop
644 usr/share/plasma/desktoptheme/furryos/metadata.json
644 usr/share/icons/FurryOS/index.theme
644 etc/skel/.config/kdeglobals
```

### 3.2 UEFI 路径与 ESP

```text
[furryos-boot-brand] patched boot/grub/grub.cfg
[furryos-boot-brand] grub.cfg kernel paths -> /live/vmlinuz + /live/initrd.img (both resolve)
[furryos-boot-brand] efi.img ESP stub intact (search + prefix + configfile)
[furryos-boot-brand] rewrote .disk/info: FurryOS 24.04 LTS - Live amd64 Binary 20261031-00:37
[furryos-boot-brand] boot menu branding pass complete
```

ISO 侧 GRUB：

```text
linux  /live/vmlinuz boot=live components quiet splash findiso=${iso_path}
initrd /live/initrd.img
```

`boot/grub/*.cfg` 无 `/live/*amd64` 残留。ESP 内仍只有三行引导桩：

```grub
search --set=root --file /.disk/info
set prefix=($root)/boot/grub
configfile ($root)/boot/grub/grub.cfg
```

## 4. ISO 与实际 squashfs 验证

```text
$ isoinfo -d -i build/live-image-amd64.hybrid.iso | grep -E 'Volume id|Application id'
Volume id: FurryOS
Application id: FURRYOS

$ isoinfo -R -i build/live-image-amd64.hybrid.iso -x /.disk/info
FurryOS 24.04 LTS - Live amd64 Binary 20261031-00:37
```

直接从最终 `binary/live/filesystem.squashfs` 只提取身份文件（不是读取构建后可能被收尾修改的
`build/chroot`）：

```text
/etc/hostname: furryos
/etc/hosts:    127.0.1.1 furryos
/etc/xdg/kdeglobals:8:LookAndFeelPackage=com.furryos.lookandfeel
/etc/skel/.config/kdeglobals:47:LookAndFeelPackage=com.furryos.lookandfeel
```

hostname 的最终来源同时包括：

- `6010-integrate-identity-assets.chroot` 的身份阶段写入与断言；
- `config/includes.chroot_after_packages/etc/{hostname,hosts}` 在 live-build 收尾阶段恢复，
  防止其写死的 `localhost.localdomain` / `debian` 值进入最终系统。

## 5. 源码回归

最终构建源码上的真实结果：

| 校验 | 结果 |
|---|---|
| `bash tools/verify-visual.sh` | 15 项顶层检查，失败 0；`verify-visual.py` 131 项，splash 18 项 |
| `bash tools/verify-brand.sh --no-fetch` | 4 项全部通过，0 跳过；身份 PASS=33 FAIL=0 |
| `dash -n` 修复的 shell 脚本/钩子 | 通过 |
| `git diff --check` | 通过 |
| `diff -rq assets build/config/assets` | 无差异 |

## 6. 虚拟机验收

详细命令、OCR、串口输出与 RMSE 见 `docs/VM-VERIFY.md`。摘要：

| 项目 | 结果 |
|---|---|
| BIOS 正常 ISO 菜单 | 进入稳定 KDE 桌面 |
| UEFI/OVMF 默认菜单项 | 直接启动，无需手工内核路径 |
| SDDM | 真实 FurryOS 蓝白登录主题，60/100/140s 稳定 |
| KSplash | 无 KCrash、段错误、权限错误 |
| 桌面壁纸 | FurryOS RMSE 0.1582；Breeze Next RMSE 0.3784 |
| BIOS/UEFI 桌面一致性 | 两张截屏 RMSE 0.00318 |
| 运行中 hostname | `hostname`、`hostnamectl --static`、`/etc/hostname` 均为 `furryos` |
| 延迟会话日志扫描 | `plasmashell` 运行，无 Permission denied/KCrash/Segmentation fault |

证物：

- `docs/preview/vm-bios-bootmenu.png`
- `docs/preview/vm-desktop-bios.png`
- `docs/preview/vm-uefi-bootmenu.png`
- `docs/preview/vm-desktop-uefi.png`
- `docs/preview/vm-sddm-login.png`

## 7. 已知边界

- 验收环境为 QEMU/KVM，UEFI 使用 OVMF；尚未声称覆盖每一种实体机固件/GPU。
- Plymouth 主题文件已安装，但包列表没有 `plymouth`，因此不宣称 Plymouth 动画已启用；
  本次通过的是 SDDM 后进入 Plasma 的 KSplash/桌面链路。
- ISO、zsync、squashfs、chroot、binary 与缓存均保留在本地并不进入 Git；用户自行发布 ISO。
