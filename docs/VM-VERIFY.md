# FurryOS 最终 ISO 虚拟机验收

> 验收对象：`build/live-image-amd64.hybrid.iso`
> SHA256：`2d9048bc07565566e64bd7c85615bfcd98b302578b2469ac65a87340a68fb002`
> 方法：正常 ISO 启动 + OVMF + OCR + 像素/RMSE + guest 串口命令。
> 结论：**BIOS、UEFI、SDDM、KDE、KSplash、FurryOS 壁纸和 hostname 全部通过。**

本报告只使用上述哈希的 ISO。上一轮的 UEFI 内核路径错误、KSplash Signal 11 和 Breeze Next
壁纸不再作为当前状态；其根因与修复见 `docs/FIXES-ROUND2.md`。

## 1. 环境

```text
QEMU：qemu-system-x86_64，machine q35，accel=kvm，CPU host
资源：4096 MiB RAM，4 vCPU，-snapshot，无虚拟磁盘写入
显示：-vga std，-display none，monitor screendump
BIOS：SeaBIOS（QEMU 默认）
UEFI：/usr/share/OVMF/OVMF_CODE.fd + 独立可写 OVMF_VARS.fd 副本
分析：ImageMagick identify/convert/compare，tesseract OCR，guest 串口 shell
```

判定不是“截屏文件存在”，而是同时检查：

1. 启动过程没有路径错误或崩溃对话框；
2. 多个时间点的图像/颜色/RMSE；
3. guest 内实际配置、进程与日志。

## 2. BIOS：正常 ISO 菜单到 KDE

核心启动命令：

```sh
qemu-system-x86_64 \
  -machine type=q35,accel=kvm -cpu host -m 4096 -smp 4 \
  -boot d -snapshot -no-reboot -nic none -vga std -display none \
  -monitor unix:/tmp/furryos-final-bios/monitor.sock,server,nowait \
  -cdrom build/live-image-amd64.hybrid.iso
```

在菜单停留 8 秒截屏，然后通过 monitor `sendkey ret` 选择默认项；60、100、140 秒截屏。

| 时间点 | 可复现观察 |
|---|---|
| 菜单 | 640x480，1351 色；OCR 读到 FurryOS |
| 60s | 1280x800，4010 色；图形启动阶段，无崩溃文字 |
| 100s | 1280x800，11508 色，mean=0.554633；KDE 桌面 |
| 140s | 与 100s 完全相同的 11508 色稳定桌面；OCR 无 KCrash/段错误 |

证物：

- `docs/preview/vm-bios-bootmenu.png`
- `docs/preview/vm-desktop-bios.png`

## 3. UEFI/OVMF：默认项直接启动

```sh
cp /usr/share/OVMF/OVMF_VARS.fd /tmp/furryos-final-uefi/OVMF_VARS.fd
qemu-system-x86_64 \
  -machine type=q35,accel=kvm -cpu host -m 4096 -smp 4 \
  -boot d -snapshot -no-reboot -nic none -vga std -display none \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
  -drive if=pflash,format=raw,file=/tmp/furryos-final-uefi/OVMF_VARS.fd \
  -monitor unix:/tmp/furryos-final-uefi/monitor.sock,server,nowait \
  -cdrom build/live-image-amd64.hybrid.iso
```

12 秒时保存 GRUB 菜单并按回车；未编辑 `linux` 行，未进入手工 GRUB 命令行。

| 时间点 | 可复现观察 |
|---|---|
| GRUB 菜单 | 800x600，1323 色；FurryOS 菜单 |
| 60s | 图形切换中间态；没有 `vmlinuz-*amd64 not found` |
| 100s | 1280x800，11539 色，mean=0.554626；KDE 桌面 |
| 140s | 1280x800，11527 色，mean=0.554631；稳定，无 KCrash |

对所有 BIOS/UEFI OCR 文本执行错误扫描：

```sh
grep -Ehi 'not found|load the kernel|Segmentation fault|KCrash|Permission denied|ksplashqml.*closed' \
  /tmp/furryos-final-{bios,uefi}/*.txt
# 无输出
```

结论：**P1 已关闭，OVMF 默认项不再需要手工 `/live/vmlinuz` 命令。**

证物：

- `docs/preview/vm-uefi-bootmenu.png`
- `docs/preview/vm-desktop-uefi.png`

## 4. 壁纸与双固件桌面一致性

取 140 秒桌面，排除底部 40px 面板，映射到壁纸母版尺寸，分别比较 FurryOS 与 Breeze Next：

```sh
convert /tmp/furryos-final-bios/04-140s.png \
  -crop 1280x760+0+0 +repage -resize 1920x1080! \
  /tmp/furryos-final-bios/wall-region.png
compare -metric RMSE /tmp/furryos-final-bios/wall-region.png \
  assets/desktop/wallpapers/FurryOS/contents/images/1920x1080.png null:
# 10369.1 (0.158222)

convert /tmp/furryos-final-bios/wall-region.png -resize 1280x800! \
  /tmp/furryos-final-bios/wall-1280.png
compare -metric RMSE /tmp/furryos-final-bios/wall-1280.png \
  build/chroot/usr/share/wallpapers/Next/contents/images/1280x800.png null:
# 24801 (0.37844)
```

| 比较 | RMSE（越小越相似） |
|---|---:|
| BIOS 桌面对 FurryOS 母版 | **0.158222** |
| BIOS 桌面对 Breeze Next | 0.378440 |
| UEFI 桌面对 FurryOS 母版 | **0.158215** |
| UEFI 桌面对 Breeze Next | 0.378438 |
| BIOS 桌面对 UEFI 桌面 | **0.00318091** |

上一轮为 FurryOS 0.365 / Next 0.089；本轮已明确反转。桌面对母版不是零是因为包含图标、
面板、缩放与合成，但它与 FurryOS 的相似度显著高于 Next，且两种固件桌面几乎一致。

结论：**P3 已关闭，真实桌面不再回落到 Breeze Next。**

## 5. SDDM 登录界面

为停在登录界面而非自动登录，在 BIOS 菜单按 Tab，仅追加：

```text
live-config.noautologin
```

60、100、140 秒三张截屏完全相同：

```text
1280x800，4323 色，mean=0.932934
OCR 可读到 FurryOS 字标
```

主要颜色：

| 颜色 | 像素数 | 含义 |
|---|---:|---|
| `#EAF2FF` | 653886 | 蓝白背景 |
| `#D5E4FA` | 174775 | 背景渐变/层次 |
| `#FFFFFF` | 117764 | 登录卡片 |
| `#A5C6F0` | 10617 | 辅助层次 |
| `#1A6FD4` | 9264 | FurryOS 品牌蓝 |
| `#0F4C8C` | 7721 | 深蓝文字/强调 |

这些色值和像素计数与 t5 的 SDDM 预览缩放结果一致。证物：
`docs/preview/vm-sddm-login.png`。

## 6. guest 串口：真实配置、进程与日志

为了读取会话内部状态，用 ISO 的同一内核/initrd 直接启动并加 `console=ttyS0`；这只是诊断入口，
不替代第 2/3 节正常菜单验收。

```sh
qemu-system-x86_64 \
  -machine type=q35,accel=kvm -cpu host -m 4096 -smp 4 \
  -boot d -snapshot -no-reboot -nic none -display none -monitor none -serial stdio \
  -kernel build/binary/live/vmlinuz \
  -initrd build/binary/live/initrd.img \
  -append 'boot=live components quiet splash console=ttyS0' \
  -cdrom build/live-image-amd64.hybrid.iso
```

登录 `user` / `live`，再等待 45 秒让自动登录和 Plasma 完全建立，然后执行检查。实际输出：

```text
$ hostname
furryos
$ hostnamectl --static
furryos
$ cat /etc/hostname
furryos

/etc/xdg/kdeglobals:8:LookAndFeelPackage=com.furryos.lookandfeel
/home/user/.config/kdeglobals:164:LookAndFeelPackage=com.furryos.lookandfeel
/etc/xdg/ksplashrc:3:Theme=org.furryos.desktop

1359 /usr/bin/sddm
1491 .../sddm-helper ... --start /usr/bin/startplasma-x11 --user user --autologin
1641 /usr/bin/plasmashell --no-respawn

__XSESSION_ERROR_SCAN__
no_session_errors
```

扫描表达式：

```sh
grep -Ei 'Permission denied|KCrash|Segmentation fault|ksplashqml.*(crash|error)' \
  ~/.xsession-errors
```

延迟扫描时文件已存在，grep 无匹配；不是把“文件尚未生成”当成通过。桌面稳定后 `ksplashqml`
已正常退出，因此进程列表只要求 SDDM/Plasma 存活，不要求 KSplash 永久驻留。

结论：**P2 与 P4 已关闭。没有隐藏的主题权限错误或 KSplash 崩溃，用户可见 hostname 为 FurryOS。**

## 7. 实际 squashfs 交叉检查

直接提取 ISO 将要使用的 `binary/live/filesystem.squashfs` 中的身份文件：

```text
/etc/hostname: furryos
/etc/hosts: 127.0.1.1 furryos
/etc/xdg/kdeglobals:8:LookAndFeelPackage=com.furryos.lookandfeel
/etc/skel/.config/kdeglobals:47:LookAndFeelPackage=com.furryos.lookandfeel
```

这排除了“只看构建后 chroot，squashfs 里却是另一版本”的假阳性。

## 8. 最终判定与边界

| t7/t8 缺陷 | 最终状态 | 证据 |
|---|---|---|
| P1 UEFI 默认项路径错误 | 关闭 | OVMF 默认菜单直接到桌面，无手工命令 |
| P2 KSplash Signal 11 | 关闭 | BIOS/UEFI 无崩溃；延迟 guest 日志无权限/KCrash/段错误 |
| P3 Breeze Next 壁纸 | 关闭 | FurryOS RMSE 0.1582，Next 0.3784；双固件一致 |
| P4 Debian/默认 hostname | 关闭 | squashfs 与运行中均为 `furryos` |

边界：本报告证明 QEMU/KVM + OVMF 的可观察结果，不等同于所有实体硬件认证。Plymouth 包未安装，
因此只验收 SDDM/KSplash/Plasma 链路，不宣称 Plymouth 动画已启用。
