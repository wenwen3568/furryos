# FurryOS 源码发布记录

> 日期：2026-10-31
> 分支：`main`
> 远端：`git@github.com:wenwen3568/furryos.git`
> 发布范围：**可直接构建的源码、配置、工具、文档与验证证据；不包含 ISO。**

## 1. 本次交付

本次源码发布合并以下质量轮次：

- t1/t2：静态代码审核与完整验证报告；
- t3/t4：live-build 可复现构建、工具链自举、品牌与构建钩子修复；
- t5：SDDM、Plasma 桌面、KSplash、图标、字体、系统设置名称与动效的统一美化；
- t8：UEFI 内核路径、KSplash 权限崩溃、Look-and-Feel 回落与 hostname 修复；
- t7：最终完整干净构建及 BIOS/UEFI/SDDM/KDE/串口实测；
- t6：仓库卫生整理与源码推送。

文档入口：

| 文档 | 内容 |
|---|---|
| `docs/BUILD.md` | 构建环境与完整构建说明 |
| `docs/REVIEW.md` | 静态审核发现及后续报告入口 |
| `docs/TEST-REPORT.md` | 校验脚本实测 |
| `docs/FIXES.md` | 第一轮功能修复 |
| `docs/VISUAL.md` | 视觉规范、运行时属性与像素验收 |
| `docs/FIXES-ROUND2.md` | UEFI/KSplash/壁纸/hostname 根因与修复 |
| `docs/BUILD-LOG.md` | 最终完整构建日志摘要、产物哈希 |
| `docs/VM-VERIFY.md` | BIOS/UEFI/SDDM/KDE/串口与 RMSE 证据 |

## 2. 本地已验收 ISO（不进入 Git）

```text
文件：build/live-image-amd64.hybrid.iso
大小：2143289344 bytes
SHA256：2d9048bc07565566e64bd7c85615bfcd98b302578b2469ac65a87340a68fb002
squashfs：1990787072 bytes
```

验收结论：

- BIOS 正常 ISO 菜单进入 KDE；
- UEFI/OVMF 默认菜单项直接启动，无需手工输入内核路径；
- SDDM 显示真实 FurryOS 蓝白登录主题；
- KSplash 无 KCrash、段错误或权限错误；
- 桌面使用 FurryOS 壁纸，未回落 Breeze Next；
- `hostname`、`hostnamectl --static` 与 `/etc/hostname` 均为 `furryos`；
- ISO 卷标、Application ID、`.disk/info` 和启动菜单均为 FurryOS 品牌。

用户自行发布上述本地 ISO；仓库仅提供可复现的构建源。

## 3. 从源码重建

```sh
git clone git@github.com:wenwen3568/furryos.git
cd furryos
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
sha256sum live-image-amd64.hybrid.iso
```

最终验收使用完整的 clean/config/build，不使用中间 stagefile 续跑生成发布产物。

## 4. 发布前真实检查

```text
bash tools/verify-visual.sh：15 项顶层检查零失败
  - verify-visual.py：131 项
  - 启动画面像素：18 项
bash tools/verify-brand.sh --no-fetch：4/4 通过，0 跳过
  - 身份层：PASS=33 FAIL=0
git diff --check：通过
diff -rq assets build/config/assets：无差异
```

完整虚拟机证据与限制见 `docs/VM-VERIFY.md`。

## 5. 仓库卫生

不得提交：

- `build/*.iso`、`build/*.zsync`、squashfs；
- `build/chroot*`、`build/binary/`、`build/.build/`、cache；
- `build/*.contents`、`build/*.files`、`*modified_timestamps`；
- 下载的 deb、解包工具链、`.verify`、临时探针；
- `__pycache__`、`*.pyc`；
- `.ssh/`、私钥或其他凭据。

`.gitignore` 已覆盖这些类别。`build/config/` 是构建源，不与被排除的 `build/binary/` 混淆。

## 6. 推送后核对

```sh
git rev-parse HEAD
git ls-remote origin refs/heads/main
git status --short
```

本地 HEAD 与远端 `refs/heads/main` 必须一致；工作区中只能保留被忽略的本地构建产物。

## 7. 已知边界

- 实测环境为 QEMU/KVM，UEFI 使用 OVMF，不等同于所有实体硬件认证。
- Plymouth 主题文件已就位，但包列表未包含 `plymouth`，因此不宣称 Plymouth 动画已启用；
  本次通过的是 SDDM、KSplash 与 Plasma 桌面链路。
