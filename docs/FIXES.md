# FurryOS 缺陷修复报告（t4 / fixer）

> 输入：`docs/REVIEW.md`（代码审核）、`docs/TEST-REPORT.md`（测试）、`docs/BUILD-LOG.md`（构建）
> 执行者：fixer（团队成员，attempt `9a240305-04d4-406f-92fa-667edb4b94f1`）
> 基线：`main` @ `2da8add`，宿主 Debian 12 / live-build 1:20230502
> 原则：**每一条结论都来自实际执行**；改动只碰职责范围内的文件；不放宽任何断言。

---

## 0. 结论

| 项 | 数量 |
|---|---|
| 修复缺陷（含审核未列但同源的问题） | **31** 项（blocker 1 / high 6 / medium 13 / low 11） |
| 明确不修（超范围或需上游决策） | **6** 项，见第 4 节，每项给了理由与替代方案 |
| 新增可复跑校验入口 | `tools/verify-brand.sh`（一键四链）、`tools/prepare-toolchain.sh`（工具链重建）、`tools/fetch-refs.sh`（上游参考包） |
| 全量复验 | `PASS=33 FAIL=0`（身份层）+ 4/4（一键自检）+ 钩子 6 正 10 负实测，见第 3 节 |

三条最重要的结论：

1. **blocker 已消除**：`8000-brand-boot-menu.binary` 不再替换 ESP 引导桩；改为「断言桩完好 + 断言 ISO 参数 + 重写 `.disk/info`」。用真实 `build/binary` 实测：修复前钩子检出「ESP 内是 57 行整份配置」并以 exit 1 拒绝构建，恢复桩后 exit 0 且 `.disk/info` 变为 `FurryOS ...`。
2. **启动画面不再落空**：`6130` 现在真的调用 `assets/effects/splash/effects-splash-install.sh`，并在真实 rootfs 上装出 `org.furryos.desktop/contents/splash/Splash.qml` + `/etc/xdg/ksplashrc`（`Theme=org.furryos.desktop`）。plymouth 明确标注为「文件就位但未激活（包里没有 plymouth）」。
3. **校验不再给假 PASS**：`verify-identity.sh` 的空断言改成「先断言存在」、断言条数被 `EXPECTED_PASS=33` 硬校验；`verify-consistency.py` / `verify-wallpaper.py` 的硬编码数字改为从资产解析并参与判定。每个校验都做了反向对照（删文件/改色值/改几何必须变红），见 3.3。

**必须由重建复验的部分**（不在本次职责内，见第 5 节）：ISO 需重新 `lb build` 才能把上述修复落进镜像；UEFI 实机启动、QEMU 冒烟必须在新 ISO 上重跑。

---

## 1. 修复清单

### F01 [blocker] 8000 钩子替换 ESP 引导桩，UEFI 镜像不可启动

- **问题**：`8000-brand-boot-menu.binary:89-109` 先 `mdel ::/boot/grub/grub.cfg` 再 `mcopy` 整份 ISO `grub.cfg` 进 ESP，假设 ESP 里放的是配置副本。实际 live-build 放的是 3 行引导桩（`search --set=root --file /.disk/info` / `set prefix=($root)/boot/grub` / `configfile ($root)/boot/grub/grub.cfg`）。替换后 `$root` 仍是 ESP，`source /boot/grub/config.cfg` 与 `linux /live/vmlinuz-*` 全部找不到 → UEFI 无法引导；若 `mcopy` 因 ESP 空间不足失败，则 ESP 内**没有任何** grub.cfg，直接落到 `grub>`。
- **根因**：钩子对 ESP 内容的假设来自 `binary_grub-efi` 的旧版本注释，且把「改文案」和「改引导逻辑」混成一步；失败只打 WARNING，构建继续。
- **改动**：`build/config/hooks/normal/8000-brand-boot-menu.binary`
  - 删除 `mdel`/`mcopy` 整段 ESP 注入；
  - 新增断言：ESP 内 `grub.cfg` 必须恰好是那 3 行桩（`search` + `prefix` + `configfile`），否则 exit 1；
  - 新增 `assert_iso_config`：`config/binary` 的 `LB_ISO_VOLUME`/`LB_ISO_APPLICATION` 必须是 `FurryOS`，否则 exit 1；
  - 新增 `.disk/info` 重写：取 `../chroot/usr/lib/os-release` 的 `PRETTY_NAME`，写成 `"<PRETTY_NAME> - Live amd64 Binary <原时间戳>"`，保留时间戳；文件缺失或内容不是 `FurryOS*` 一律 exit 1（取代原来的死代码 `/tmp/furryos-iso-volume-check`）。
- **复验**（真实产物 `build/binary`）：

```sh
$ cd build/binary && mtype -i boot/grub/efi.img ::/boot/grub/grub.cfg | wc -l
57                      # 修复前：ESP 内是整份 57 行配置（就是 blocker 的现场）

$ sh ../../build/config/hooks/normal/8000-brand-boot-menu.binary; echo $?
[furryos-boot-brand] ERROR: boot/grub/efi.img does not contain the expected 3-line ESP stub - UEFI boot would break.
[furryos-boot-brand] ERROR: ESP /boot/grub/grub.cfg was:
    source /boot/grub/config.cfg
    ...
1                       # 修复后的钩子检出并拒绝构建

# 恢复引导桩（等价于 binary_grub-efi 的产物）后重跑：
$ printf 'search --set=root --file /.disk/info\nset prefix=($root)/boot/grub\nconfigfile ($root)/boot/grub/grub.cfg\n' > /tmp/esp-stub.cfg
$ mcopy -o -i boot/grub/efi.img /tmp/esp-stub.cfg ::/boot/grub/grub.cfg
$ sh ../../build/config/hooks/normal/8000-brand-boot-menu.binary; echo $?
[furryos-boot-brand] efi.img ESP stub intact (search + prefix + configfile)
[furryos-boot-brand] config/binary LB_ISO_VOLUME="FurryOS" OK
[furryos-boot-brand] config/binary LB_ISO_APPLICATION="FurryOS" OK
[furryos-boot-brand] rewrote .disk/info: FurryOS 24.04 LTS - Live amd64 Binary 20261027-20:44
0
$ cat .disk/info
FurryOS 24.04 LTS - Live amd64 Binary 20261027-20:44
```

- **结论**：已修复。ESP 不再被改写（`md5sum efi.img` 在钩子前后不变），文案仍由 ISO 侧 `boot/grub/grub.cfg` 的 sed 提供，BIOS/UEFI 都会看到 FurryOS。**UEFI 实机启动须在新 ISO 上复验**。

### F02 [high] 6110 / 6120 / 6130 资产缺失时静默 `exit 0`

- **问题**：三处层目录缺失走 `furryos_warn …; exit 0`，而 6000/6010 是 fail-fast。`sync-assets.sh` 漏跑或层目录被删时，桌面/登录/动效三层全部静默跳过，ISO 仍报「构建成功」。
- **根因**：各钩子由不同成员写成，缺失策略没有统一；历史 bug（6000 曾 `exit 0`）的教训只修在了 6000。
- **改动**：`6110`、`6120`、`6130` 的「层目录缺失」分支改为 `exit 1`（沿用 `furryos-common.sh` 的 `furryos_need_file` 风格）；`6010` 的层目录同样 fatal，并把身份层 6 个核心文件（`os-release`、`issue`、`issue.net`、`motd`、`legal`、`sshd_banner.conf`）升级为硬要求（`lsb-release`/`kcm-about-distrorc`/logo 保留 warn 或兜底链）。
- **复验**（在真实 rootfs `build/chroot` 内跑修复后的钩子，正/负各一遍）：

```sh
# 正向：六个钩子全部 0
6000 EXIT=0  6010 EXIT=0  6110 EXIT=0  6120 EXIT=0  6130 EXIT=0  8990 EXIT=0

# 负向（删掉对应层后再跑）
6010 missing identity        EXIT=1  required asset missing: /opt/furryos/assets/identity/issue
6110 missing desktop         EXIT=1  ERROR: run tools/sync-assets.sh and check 6000-stage-furryos-assets.chroot
6120 missing sddm            EXIT=1  同上
6130 missing effects         EXIT=1  同上
6110 missing wallpapers/     EXIT=1  required asset missing: .../wallpapers/FurryOS/contents/images/1920x1080.png
6110 missing FurryOS.colors  EXIT=1  required asset missing: .../FurryOS.colors
6130 missing furryos-ksplash EXIT=1  required asset missing: .../furryos-ksplash/metadata.json
```

- **结论**：已修复。10 个负向用例全部 exit 1（`6110` 的 wallpapers 与 `6130` 的 ksplash 两项是本次新加：原断言只看目标路径，旧产物会满足它，见 F28）。

### F03 [high] 6120 吞掉安装器失败，SDDM 主题可能没装上却「构建成功」

- **问题**：`install-sddm-theme.sh` 非零退出被 `|| furryos_warn` 吞掉，随后只做存在性提示。
- **根因**：把「层脚本失败」当成了可降级事件。
- **改动**：`build/config/hooks/normal/6120-integrate-sddm-assets.chroot`：安装器失败 → exit 1；末尾用 `furryos_need_file` 断言 `Main.qml`、`metadata.desktop`、`/etc/sddm.conf`，并断言 `grep '^Current=furryos$'`；顺带断言 SVG 图像格式插件 `libqsvg.so` 在位（爪印静默消失的根因，见 F17）。
- **复验**：真实 rootfs 上 `6120 EXIT=0`，且

```sh
$ grep -E 'Current|ThemeDir|CursorTheme' build/chroot/etc/sddm.conf
Current=furryos
ThemeDir=/usr/share/sddm/themes
CursorTheme=Breeze_Snow
```

- **结论**：已修复。`/etc/sddm.conf` 现在是 `assets/sddm/sddm.conf` 的逐字节副本（F06），不再有「资产一份、脚本模板另一份」的双源。

### F04 [high] 启动画面整体未接入：ksplash 主题从未被安装

- **问题**：① `effects-splash-install.sh` 是唯一同时装 plymouth + ksplash 的脚本，但**没有任何钩子调用它**；② `furryos-ksplash/`（`metadata.json` + `contents/splash/Splash.qml` + `contents/defaults`）从未被安装；③ `plymouth` 不在包列表，即使复制也不会生效。README 与 `assets/effects/README.md` 却宣称「启动画面（plymouth / ksplash）」。
- **根因**：动效层的安装脚本写好了但没人接；钩子里只有一段手写的 plymouth 复制（且注释与资产现状相反）。
- **改动**：
  - `build/config/hooks/normal/6130-integrate-effects-assets.chroot`：删掉手写 plymouth 段，改为 `PREFIX=/ sh "${SRC}/splash/effects-splash-install.sh"`（失败即 exit 1），随后硬断言 `org.furryos.desktop/metadata.json`、`contents/splash/Splash.qml`、`/etc/xdg/ksplashrc` 存在且 `grep '^Theme=org.furryos.desktop$'`；plymouth 明确降级为「文件就位、未激活（包里无 plymouth）」并写进注释与文档；
  - `assets/effects/splash/effects-splash-install.sh`：`install_ksplash()` 现在同时写 `/etc/xdg/ksplashrc`（`[KSplash] Theme=org.furryos.desktop`）——只装 look-and-feel 目录时 `ksplashqml` 仍用全局主题的启动画面，这一行才是开关；
  - `assets/effects/README.md`：按脚本真实行为重写（见 F25）。
- **复验**（真实 rootfs，修复后）：

```sh
$ chroot build/chroot /bin/sh /root/hooktest/6130-integrate-effects-assets.chroot; echo $?
[furryos-splash] installed look-and-feel (KSplash) theme → /usr/share/plasma/look-and-feel/org.furryos.desktop
[furryos-splash] wrote /etc/xdg/ksplashrc ([KSplash] Theme=org.furryos.desktop)
[furryos] KSplash theme installed and selected (org.furryos.desktop)
0

$ cat build/chroot/etc/xdg/ksplashrc
# FurryOS 启动画面默认值（由交互动效层安装脚本写入）
[KSplash]
Theme=org.furryos.desktop

$ ls build/chroot/usr/share/plasma/look-and-feel/org.furryos.desktop/contents/splash/
images  Splash.qml
```

- **结论**：已修复（ksplash 部分完整生效）。plymouth 为**明示降级**：文件装到位、`plymouth` 包不在列表、内核命令行有 `splash` 但没有 plymouth 的 initramfs 钩子；启用方法写在 `docs/BUILD.md` 与 `assets/effects/README.md`。

### F05 [high] `docs/BUILD.md:179` 的 os-release「手动修复」是自毁命令

- **问题**：`sudo bash -c 'cat /usr/lib/os-release > /etc/os-release && ln -sf …'`。`/etc/os-release` 是指向 `/usr/lib/os-release` 的符号链接，重定向先截断目标，`cat` 再读同一 inode → 源文件被清空为 0 字节。
- **根因**：把「写内容」和「建链接」混在一条命令里，且没考虑重定向穿过符号链接。
- **改动**：`docs/BUILD.md` 改为先 `ls -l /etc/os-release` 判断，再 `rm -f` + `ln -sf ../usr/lib/os-release /etc/os-release`，并加显式警告「不要用 `cat A > A`」。
- **复验**：文档命令在真实 rootfs 上可执行且幂等：

```sh
$ ls -l build/chroot/etc/os-release
lrwxrwxrwx ... /etc/os-release -> ../usr/lib/os-release
$ grep '^NAME=' build/chroot/usr/lib/os-release
NAME="FurryOS"
```

- **结论**：已修复。`6010` 钩子本身一直是正确的（先写 `/usr/lib/os-release` 再建链接），错的只是文档。

### F06 [high] 工具链不可复现：`tools/rootfs`、`tools/lbroot`、`tools/shim` 都没人生成

- **问题**：`lb.sh` 依赖未入库的解包工具链，`.gitignore` 注释称「由 BUILD.md 说明的方法重新获取」，但 BUILD.md 零命中；更关键的是 `tools/shim/mount`（mtab 只读的唯一绕法）没有任何脚本生成，`lb.sh` 自己只生成 `shim/cat`。全新 clone 无法构建。
- **根因**：工具链是「手工调出来的」，没沉淀成脚本。
- **改动**：
  - 新增 `tools/prepare-toolchain.sh`：从本机 deb / apt / noble 索引取 `live-build`、`debootstrap`、`debootstrap-ubuntu`、`ubuntu-keyring`，解包成 `tools/rootfs`（`/usr`）、`tools/lbroot/usr/lib/live`（`${LIVE_BUILD}`：`scripts/build.sh` + `scripts/build/` + `functions`/`share` 链接）、`tools/shim/{cat,mount}`；固化 5 个必须补丁（debootstrap nodev、`stat -L`、GRUB 资源映射、内核元包改名、mtab 容错）；末尾 13 项自检 + `lb --version` 冒烟；
  - 重写 `tools/lb.sh`：自定位（`WS=$(dirname $0)/..`，不再硬编码 `/root/furryos`）、工具链缺失时自动调 `prepare-toolchain.sh`、`clean` 等命令**不**预先 bind-mount `/dev`（否则 `lb clean` 报 `Device or resource busy`）；
  - `docs/BUILD.md` 新增 §2.1「构建工具链从哪来」+ 5 个补丁的因果表。
- **复验**：

```sh
$ bash tools/prepare-toolchain.sh --dest /tmp/tc; echo $?
patched: debootstrap functions (nodev workarounds)
patched: binary_grub-efi EFI size uses stat -L (follow symlinks)
patched: chroot_proc / chroot_sysfs / chroot_selinuxfs tolerates the read-only mtab exit status
patched: chroot_install-packages rewrites linux-image-*-amd64 -> linux-image-generic
  [OK] ×13
0
# 生成的补丁结果与宿主上已验证的工具链逐字节一致：
$ diff -u <(sed 's|/tmp/tc|/root/furryos/tools|g' /tmp/tc/rootfs/usr/share/debootstrap/functions) tools/rootfs/usr/share/debootstrap/functions && echo IDENTICAL
IDENTICAL
$ diff -q /tmp/tc/lbroot/usr/lib/live/scripts/build/binary_grub-efi tools/lbroot/usr/lib/live/scripts/build/binary_grub-efi && echo IDENTICAL
IDENTICAL
$ diff -q /tmp/tc/rootfs/usr/lib/live/build/chroot_install-packages tools/rootfs/usr/lib/live/build/chroot_install-packages && echo IDENTICAL
IDENTICAL

$ sh tools/lb.sh --version
20230502

# clean 不碰 /dev（假 build 树里放一个普通文件冒充 /dev/null）
$ bash /tmp/lbtest/tools/lb.sh clean; ls -l /tmp/lbtest/build/chroot/dev/null
STUB lb called with: clean
-rw-r--r-- ... /tmp/lbtest/build/chroot/dev/null      # 未被 bind-mount（不会 busy）
$ bash /tmp/lbtest/tools/lb.sh build; ls -l /tmp/lbtest/build/chroot/dev/null
crw-rw-rw- ... 1, 3 /tmp/lbtest/build/chroot/dev/null # build 前会重建设备节点
```

- **结论**：已修复。全新 clone 现在只需 `bash tools/prepare-toolchain.sh`（或直接 `bash tools/lb.sh build`，它会自动准备）。

### F07 [high] `docs/BUILD.md` §2「资产注入」与实现完全不符

- **问题**：文档让用户建 `build/config/hooks/9999-furryos-sddm.chroot` 调 `/root/furryos/assets/...`——chroot 内不存在该路径（只有 `config/` 被 bind 到 `/live-build/config`），且 9999 排在 8990 清理之后；还留着「其余各层由 build-verify 补充」「正在搭建骨架」等占位语。
- **根因**：文档写于钩子落地之前，之后没有回写。
- **改动**：`docs/BUILD.md` §2 重写为真实链路表（`assets/` → `tools/sync-assets.sh` → `config/assets/` → `6000` 暂存 `/opt/furryos/assets` → `6010/6110/6120/6130` 注入 → `8990` 清理），说明为什么必须两步（chroot 只看得见 bind mount），并声明「每个整合钩子都是硬失败」。
- **复验**：

```sh
$ ls build/config/hooks/normal/ | grep -c 9999
0
$ sed -n '/## 2. 资产注入/,/### 2.1/p' docs/BUILD.md | head -12   # 六个钩子的真实表格
$ grep -c '由 build-verify 补充' docs/BUILD.md
0
```

- **结论**：已修复。

### F08 [medium] `verify-identity.sh` 存在「文件不存在即通过」的空断言

- **问题**：`grep -v … "${SIM}/etc/update-motd.d/00-header" 2>/dev/null | grep -qi ubuntu` 在文件缺失时两条 grep 都失败 → `if` 为假 → 走 `ok "已替换为 FurryOS 版"`。`10-help-text`、`issue`、`motd`、`legal` 同型；`os-release` 的 `else` 分支也是 `ok`。
- **根因**：断言写成「没有 Ubuntu 字样就算过」，没有先要求文件存在。
- **改动**：`tools/verify-identity.sh`：每处先断言存在（缺失直接 `bad`），`os-release` 的 `else` 改为 `bad`。
- **复验**（隔离副本 `/tmp/vidtest`，不动仓库）：

```sh
$ rm /tmp/vidtest/assets/identity/update-motd.d/00-header && bash /tmp/vidtest/tools/verify-identity.sh --no-fetch | tail -2
结果：PASS=31 FAIL=3          # 修复前是 PASS=33 FAIL=0
$ rm .../10-help-text ...     → PASS=32 FAIL=2
$ 删掉 6010 里建 os-release 链接那行 → PASS=33 FAIL=1
```

- **结论**：已修复。删除资产不再能换来 PASS。

### F09 [medium] `verify-identity.sh` 不断言「实际跑了多少条」

- **问题**：汇总只看 `FAIL -eq 0`；若某分支不再执行，PASS 数会从 33 悄悄下降而退出码仍是 0。
- **根因**：缺少对断言条数的自校验。
- **改动**：`tools/verify-identity.sh` 末尾加 `EXPECTED_PASS=33` 核对，条数不符即 `bad` 并以非零退出；README 5.1 说明这一点。
- **复验**：

```sh
$ bash tools/verify-identity.sh | tail -3
结果：PASS=33 FAIL=0
$ echo $?
0
# 反向：把 6010 里 os-release 的 ln -sf 删掉后（钩子漂移守卫用例）
结果：PASS=33 FAIL=1        # 少一条断言也会被抓到
```

- **结论**：已修复。以后任何「少跑几项」都会变成 FAIL，而不是静默通过。

### F10 [medium] `verify-identity.sh` 模拟了钩子不会产生的文件（`furryos-logo.png`）

- **问题**：脚本按 `brand/paw.png` 存在就安装 `furryos-logo.png`，而 `6010` 只用 `identity/furryos-logo.svg` 或 `brand/paw.svg`。模拟出来的布局能让 `LOGO=` 解析断言通过，与真实产物不符。
- **根因**：模拟逻辑是早期草案，没跟着钩子改。
- **改动**：`tools/verify-identity.sh` 的模拟严格照抄 6010 的分支顺序：`identity/furryos-logo.svg` → `logo.svg` → `brand/paw.svg`，不再引入 png。
- **复验**：

```sh
$ grep -c 'furryos-logo.png' tools/verify-identity.sh
1        # 仅剩一行注释说明「早期版本装过这个不存在的文件」，模拟逻辑里已无 png
$ bash tools/verify-identity.sh | tail -2
结果：PASS=33 FAIL=0
```

- **结论**：已修复。

### F11 [medium] `verify-consistency.py` 的「shipped pair」是写死的打印，不参与判定

- **问题**：`:205-208` 硬编码 `(18,40,63)`/`(255,255,255)` 打印 14.99:1，即使 `[Colors:View]` 被改坏也照样打印并 PASS；注释声称「AAA」而代码只比 `claimed - 0.3`。
- **根因**：把「报告」当成了「断言」。
- **改动**：`assets/desktop/.tools/verify-consistency.py`：从 `FurryOS.colors` 解析 `[Colors:View] ForegroundNormal/BackgroundNormal`，计算对比度并要求 ≥ 7.0（AAA），缺键/非 `r,g,b` 一律失败。
- **复验**：

```sh
$ cd assets/desktop && python3 .tools/verify-consistency.py | sed -n '/shipped pair/,$p'
  shipped pair: Colors:View fg on bg (read from FurryOS.colors) =
    (18, 40, 63) on (255, 255, 255) -> 14.99:1 (AAA needs 7.0)
PASS: ...

# 反向：把 BackgroundNormal 改成 30,40,50
    (18, 40, 63) on (30, 40, 50) -> 1.00:1 (AAA needs 7.0)
FAIL: - [Colors:View] fg/bg contrast 1.00:1 < 7.0 (AAA)   → exit 1
```

- **结论**：已修复。

### F12 [medium] `verify-consistency.py` 的 `EXPECT` 表是「只打印不判定」

- **问题**：`EXPECT` 被打印出来，但每条断言都写死字面量（`"FurryOS"`、`"26,111,212"`、`"breeze"`），改表不影响结果。
- **根因**：重构到一半留下的双份真相。
- **改动**：所有断言改为读 `EXPECT[...]`；顺带把 `Theme name`、`defaultWallpaperTheme` 的多处重复断言合并成循环。
- **复验**：

```sh
$ python3 .tools/verify-consistency.py | tail -2
PASS: colour scheme, /etc/skel defaults and the global theme all name FurryOS; ...
# 反向：把 EXPECT["Image"] 改成 WrongName
FAIL: ... Wallpaper Image='FurryOS' (expected 'WrongName')   → exit 1
```

- **结论**：已修复。表就是唯一真相。

### F13 [medium] `verify-wallpaper.py` 的爪印几何是硬编码，从不读 `paw.svg`

- **问题**：注释称 `PAD/TOES/INNER_TOE_GAP`「taken verbatim from assets/brand/paw.svg」，实际是常量；`paw.svg` 改了脚本仍按旧几何判定。
- **根因**：先写常量后补注释。
- **改动**：`assets/desktop/.tools/verify-wallpaper.py` 新增 `parse_paw_svg()`：解析 `<ellipse cx cy>`（4 个脚趾，按 x 排序）+ 最大 `<path d>` 的包围盒中心（肉垫），并按 `toes[1]`/`toes[2]` 中点算脚趾间隙；解析失败/缺文件转成可读 FAIL（不是 traceback）。
- **复验**：

```sh
$ python3 -c "import importlib.util as u; s=u.spec_from_file_location('v','.tools/verify-wallpaper.py'); m=u.module_from_spec(s); s.loader.exec_module(m); print(m.PAD, m.TOES, m.INNER_TOE_GAP)"
(128.0, 186.0) [(50.0, 108.0), (97.0, 62.0), (159.0, 62.0), (206.0, 108.0)] (128.0, 62.0)
$ python3 .tools/verify-wallpaper.py | tail -2
PASS: brand gradient + 5 paw layers, each visible, on-palette and paw-shaped ...

# 反向 1：把内趾 cx=97 改成 40（几何必须跟着动）
FAIL: ... geometry not paw-shaped        → exit 1
# 反向 2：删掉 paw.svg
FAIL: cannot derive paw geometry from .../paw.svg: cannot read brand paw SVG ...  → exit 1（不是 traceback）
```

- **结论**：已修复。

### F14 [medium] `verify-wallpaper.py` 不支持调色板 PNG，且用裸 `assert`

- **问题**：`ct=3` 被映射成 `nch=1`，`px()` 仍按 RGB 取字节 → 索引色 PNG 读成乱码；`assert inter == 0 and bd in (8,16)` 抛未捕获的 `AssertionError`，失败是 traceback 而非可读结论。
- **根因**：自带解码器只覆盖了生成器当前输出的那一种 PNG。
- **改动**：`read_png()` 重写为「统一归一化成 8-bit RGB」：支持 `ct=0/2/3/4/6`（含 `PLTE` 展开）、16-bit 取高字节、非 0 交错/非法位深给 `ValueError`；所有 `assert` 换成 `ValueError` + 可读信息；新增「图像小于 1200×700 直接 FAIL」的守卫（避免探针越界成 IndexError）。
- **复验**：

```sh
# 用一张 1920×1080、调色板（ct=3）纯 #1A6FD4 的 PNG 替换壁纸
$ python3 .tools/verify-wallpaper.py | tail -3
  trail-blue-4   pad=(26, 111, 212) ... dev=91 ... NOT-PAW-SHAPED
FAIL: gradient top endpoint; ... （11 条可读失败项）
# 修复前：IndexError: tuple index out of range
```

- **结论**：已修复。索引色 PNG 现在能正确解码（取到 `(26,111,212)` 而不是乱码），失败是可读清单。

### F15 [medium] `6010` 用私有双候选探针，含死分支与过时注释

- **问题**：`6010:41-69` 探测 `/opt/furryos/assets/identity` 与 `/live-build/assets/identity`（后者永不存在的死分支），注释还称 `FURRYOS_ASSETS` 可能是 `/live-build/assets`——`furryos-common.sh:38` 早已是 `/opt/furryos/assets`。
- **根因**：历史 bug 修复后没有回收旧代码。
- **改动**：`6010` 改为 `SRC="${FURRYOS_ASSETS}/identity"`，与 6110/6120/6130 一致；删掉死分支与过时说明；缺失即 `exit 1`。
- **复验**：

```sh
$ grep -n 'live-build/assets' build/config/hooks/normal/6010-integrate-identity-assets.chroot
（无输出）
$ grep -n 'SRC=' build/config/hooks/normal/60*integrate*.chroot build/config/hooks/normal/61*integrate*.chroot
6010:SRC="${FURRYOS_ASSETS}/identity"
6110:SRC="${FURRYOS_ASSETS}/desktop"
6120:SRC="${FURRYOS_ASSETS}/sddm"
6130:SRC="${FURRYOS_ASSETS}/effects"
```

- **结论**：已修复。四个层钩子现在是同一种取法。

### F16 [medium] `6000` 重复执行会把源目录嵌套进暂存目录

- **问题**：`cp -a "${SOURCE}/${LAYER}" "${STAGING}/${LAYER}"` 在目标已存在时生成 `…/identity/identity/…`。`lb chroot_hooks` 可单独重跑，此时 8990 还没清理。
- **根因**：`cp -a src dst` 的语义被当成「覆盖」。
- **改动**：`6000` 改为幂等：`rm -rf "${STAGING}/${LAYER}"` → `install -d` → `cp -a src/. dst/`；暂存后断言只统计「源里本来就有」的层（顺带修掉缺失层被重复计数的问题，见 F26）。
- **复验**：

```sh
$ chroot build/chroot /bin/sh /root/hooktest/6000-stage-furryos-assets.chroot; echo $?
[furryos] Asset staging complete: brand desktop effects identity sddm
0
$ ls build/chroot/opt/furryos/assets/
brand  desktop  effects  identity  sddm          # 无 identity/identity
# 连跑两次后目录数不变（幂等）
```

- **结论**：已修复。

### F17 [medium] 文档反复让用户装不存在的包 `qt5-image-formats`

- **问题**：README:201、BUILD.md:94/98/107/309 让用户 `apt-get install qt5-image-formats`——noble/Debian 没有这个二进制包；而且真正提供 `libqsvg.so`（爪印 SVG 渲染插件）的是 **`libqt5svg5`**，不是 `qt5-image-formats-plugins`（后者给 tiff/webp/jp2）。
- **根因**：包名来自源码包名，机制也没查清。
- **改动**：README 5.2、BUILD.md 3.1④/§5 表、`assets/sddm/README.md` 全部改为 `libqt5svg5`（附 `ls …/imageformats/libqsvg.so` 自检），并注明 `qt5-image-formats-plugins` 的真实用途。
- **复验**：

```sh
$ dpkg -S /root/furryos/build/chroot/usr/lib/x86_64-linux-gnu/qt5/plugins/imageformats/libqsvg.so
# 由 build/chroot 内包清单核对：
$ grep -n 'libqsvg.so' build/chroot/var/lib/dpkg/info/libqt5svg5:amd64.list
11:/usr/lib/x86_64-linux-gnu/qt5/plugins/imageformats/libqsvg.so
$ grep -rn 'apt-get install.*qt5-image-formats\b' README.md docs/BUILD.md assets/sddm/README.md
（无输出；剩余提及都是「noble 没有这个二进制包」的说明文字）
```

- **结论**：已修复（文档）。包列表里仍缺 `libqt5svg5` 的显式声明，属构建侧文件，见第 4 节。

### F18 [medium] 文档称内核包名由「6200 钩子」重写，该钩子不存在

- **问题**：BUILD.md:308 写「配合 6200 钩子在 chroot_install-packages 前重写包名」；仓库里没有 6200。
- **根因**：实现方式变了（改为工具链补丁），文档没跟着改。
- **改动**：BUILD.md §5 表改写为真实机制：`config/chroot` 的 `LB_LINUX_PACKAGES="linux-generic"` + `LB_LINUX_FLAVOURS_WITH_ARCH="amd64"` 拼出不存在的 `linux-generic-amd64`，由 `tools/prepare-toolchain.sh` 给 `chroot_install-packages` 打的补丁在 apt 消费队列前改名。
- **复验**：

```sh
$ grep -n 'LB_LINUX' build/config/chroot
22:LB_LINUX_FLAVOURS_WITH_ARCH="amd64"
25:LB_LINUX_PACKAGES="linux-generic"
$ ls build/config/hooks/normal/ | grep -c 6200
0
$ grep -c 'Rewrote kernel package' tools/prepare-toolchain.sh
1
```

- **结论**：已修复（文档）。补丁本身在 F06 里已脚本化并复验。

### F19 [medium] 文档把可用的 `qmllint` / `qmlscene` 说成不可用

- **问题**：BUILD.md:301-302 与 `assets/sddm/README.md:379-380` 称 `/usr/bin/qmllint` 是 qtchooser 坏链、称「无 GL 上下文 → 无法用 qmlscene 真实渲染」。
- **根因**：早期环境探测结论过期，没重测。
- **改动**：BUILD.md 两条「环境限制」改写为实测事实：`qmllint -I . --qmldirs …` 可用；`QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software qmlscene Main.qml` 能完整加载主题。
- **复验**：

```sh
$ cd assets/sddm/furryos && qmllint -I . --qmldirs /usr/lib/x86_64-linux-gnu/qt5/qml Main.qml components/*.qml; echo $?
0
$ QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software timeout 25 qmlscene Main.qml; echo $?
QStandardPaths: XDG_RUNTIME_DIR not set, defaulting to '/tmp/runtime-root'
0
```

- **结论**：已修复（文档）。`tools/verify-brand.sh` 现在把 qmllint 作为固定一链跑。

### F20 [medium] BUILD.md 的壁纸排查路径与 6110 实现不符

- **问题**：文档让用户 `ls /usr/share/wallpapers/FurryOS/` 看到 `wallpaper.png`/`wallpaper.svg`，实际装的是 `metadata.desktop` + `contents/images/1920x1080.{png,svg}`。
- **根因**：6110 改为安装完整壁纸包后文档没更新。
- **改动**：BUILD.md 3.2 改为 `ls /usr/share/wallpapers/FurryOS/contents/images/`，并解释 KDE 按分辨率文件名选图。
- **复验**：

```sh
$ find build/chroot/usr/share/wallpapers/FurryOS -type f
.../metadata.desktop
.../contents/images/1920x1080.png
.../contents/images/1920x1080.svg
```

- **结论**：已修复。

### F21 [medium] `assets/effects/README.md` 描述的脚本行为与实现不符

- **问题**：① 称有 `--plymouth` 选项（实际只有 `--prefix`/`--initramfs`/`-h`）；② 称把 `furryos-splash.svg` 装到 `/usr/share/splash/` 并「注入 ksplash 配置」（脚本里没有该路径）；③ 把点击特效说成「blue-white-red 彩带」。
- **根因**：文档写于脚本成形前。
- **改动**：`assets/effects/README.md` 按脚本真实行为重写：安装目标（`/usr/share/plasma/look-and-feel/org.furryos.desktop/` + `/etc/xdg/ksplashrc`、`/usr/share/plymouth/themes/furryos/`）、真实选项、ksplashrc 机制、plymouth 未激活的原因；点击特效章节改为与资产逐键一致（`Color1=26,111,212`、`RingSize=32` 等），并说明 kwinrc 才是 KWin 真正读的地方。
- **复验**：

```sh
$ grep -c 'usr/share/splash' assets/effects/README.md
0
$ grep -n '\-\-plymouth' assets/effects/README.md
61:   … **没有** `--plymouth` 选项——Plymouth 文件在目录存在时总会被安装。
$ cd assets/effects/splash && ./effects-splash-install.sh --plymouth --prefix /tmp/x; echo $?
ERROR: unknown option: --plymouth
1
```

- **结论**：已修复。

### F22 [low] ISO 卷标写成 `FURRYOS`

- **问题**：BUILD.md:284 验收清单写 `FURRYOS`，实际 `LB_ISO_VOLUME="FurryOS"`，README 也是 `FurryOS`。
- **改动**：BUILD.md 改为 `FurryOS` 并给出核对命令。
- **复验**：

```sh
$ blkid -p build/live-image-amd64.hybrid.iso | tr ' ' '\n' | grep LABEL
LABEL="FurryOS"
$ isoinfo -d -i build/live-image-amd64.hybrid.iso | grep -i 'volume id'
Volume id: FurryOS
```

- **结论**：已修复。ISO9660 卷标**没有**被大写化，写 `FURRYOS` 是错的。

### F23 [low] 8000 里的死代码 `/tmp/furryos-iso-volume-check`

- **问题**：注释说「断言 LB_ISO_VOLUME」，块内只有 `:`，也没有任何地方创建该文件。
- **改动**：随 F01 一起删除，替换为真实的 `assert_iso_config`（读 `config/binary` 断言两个 `FurryOS` 值）。
- **复验**：见 F01 的输出（`config/binary LB_ISO_VOLUME="FurryOS" OK`）；
  `grep -c 'furryos-iso-volume-check' build/config/hooks/normal/8000-brand-boot-menu.binary` → `0`
  （该字符串此后只出现在 `docs/REVIEW.md` 的原始结论与本文档里）。

- **结论**：已修复。

### F24 [low] 8990 的死操作（`/etc/sddm.conf.pre-furryos`、`rm -rf /live-build`）

- **问题**：前者全仓库无人创建；后者是只读 bind mount，删除必然失败并被 `|| true` 吞掉；注释却让人以为清理已处理。
- **改动**：`8990` 删除这两段与相关注释，改为只清理 `/opt/furryos/assets` 与缓存，并在头部说明挂载点由 `lb chroot_hooks` 自己回收。
- **复验**：

```sh
$ chroot build/chroot /bin/sh /root/hooktest/8990-furryos-cleanup.chroot; echo $?
[furryos] removed /opt/furryos/assets
[furryos] FurryOS cleanup complete.
0
$ ls -d build/chroot/opt/furryos
ls: cannot access 'build/chroot/opt/furryos': No such file or directory
```

- **结论**：已修复。

### F25 [low] `6130` 注释与资产现状相反（ksplash「currently empty」、plymouth「没有 .plymouth」）

- **问题**：注释说 `furryos-ksplash/` 是空的（实际 5 个文件）、`furryos-plymouth/` 没有 `.plymouth`（实际有），因此 `ls *.plymouth` 分支会命中并为未安装的 plymouth 做 `update-alternatives`。
- **改动**：随 F04 一起处理——手写 plymouth 段整体删除，改由层脚本安装（脚本内部自己判断 plymouth 是否存在），头部注释按资产现状重写。
- **复验**：

```sh
$ ls assets/effects/splash/furryos-ksplash/contents/splash/
Splash.qml  images
$ ls assets/effects/splash/furryos-plymouth/*.plymouth
assets/effects/splash/furryos-plymouth/furryos.plymouth
$ grep -c 'update-alternatives' build/config/hooks/normal/6130-integrate-effects-assets.chroot
0
```

- **结论**：已修复。

### F26 [low] `6000` 把缺失层重复计数（5 层全缺报「10 layer(s) missing」）

- **问题**：第一轮每缺一层 `MISSING+1`，第二轮「暂存后断言」对同一层再 `+1`。
- **改动**：`6000` 第二轮只统计「源里本来有、暂存后却没有」的层。
- **复验**：

```sh
# 把 config/assets 用空目录 bind 住，模拟未同步资产
$ sh /root/hooktest/6000-stage-furryos-assets.chroot; echo $?
[furryos] WARNING: asset layer missing: effects
[furryos] WARNING: asset layer missing: brand
[furryos] ERROR: 5 asset layer(s) missing - aborting rather than shipping an unbranded image.
1                       # 修复前是 10
```

- **结论**：已修复。

### F27 [low] `/etc/skel/README.md` 会被装进每个新用户家目录

- **问题**：`furryos_install_dir "${SRC}/skel" /etc/skel` 把开发说明 `skel/README.md` 一起装成 `/etc/skel/README.md`。
- **改动**：`6110` 在合并 skel 之后 `rm -f /etc/skel/README.md`（保留源文件在资产里作说明），并加注释。
- **复验**：

```sh
$ chroot build/chroot /bin/sh /root/hooktest/6110-integrate-desktop-assets.chroot; echo $?
[furryos] merged assets/desktop/skel into /etc/skel (skel/README.md excluded)
0
$ ls build/chroot/etc/skel/
（空，只有 .config/）
```

- **结论**：已修复。

### F28 [low] 6110/6130 的断言会被「上一次构建的产物」满足

- **问题**（本次负向测试新发现）：把 `wallpapers/` 或 `furryos-ksplash/` 从暂存树删掉后，钩子仍 exit 0——因为末尾断言检查的是目标路径，而目标里还留着上一次构建装好的文件。这与审核 high 条目（静默跳过）是同一类问题，但审核未列。
- **改动**：`6110` 在安装前 `furryos_need_file "${SRC}/wallpapers/FurryOS/contents/images/1920x1080.png"`；`6130` 在调用安装器前要求 `furryos-ksplash/metadata.json` 与 `contents/splash/Splash.qml` 存在。
- **复验**：见 F02 的负向表（两项都变成 exit 1）。

- **结论**：已修复。现在「源侧缺失」和「目标侧缺失」都会失败。

### F29 [low] `metadata.desktop` 指向不存在的资源

- **问题**：`Screenshot=preview.png`（无此文件）、`TranslationsDirectory=translations`（无此目录）、`Website=https://github.com/sddm/sddm`（上游项目）。
- **改动**：`assets/sddm/furryos/metadata.desktop`：删掉前两个键（SDDM 对缺失资源会显示破图/无翻译），`Website` 改为本项目地址。
- **复验**：

```sh
$ grep -E 'Screenshot|Translations|Website' assets/sddm/furryos/metadata.desktop
Website=https://github.com/wenwen3568/furryos
$ for f in Main.qml theme.conf; do test -f assets/sddm/furryos/$f && echo "OK $f"; done
OK Main.qml
OK theme.conf
```

- **结论**：已修复（不生成假截图；SDDM 无 Screenshot 时用默认预览）。

### F30 [low] `FurryField.qml` 的死代码 `restX`（并顺带修掉 `FurryButton` 的抖动漂移）

- **问题**：`FurryField` 既无 `shake()` 也无动画引用 `restX`；而 `FurryButton` 的 `property real restX: x` 是**真 bug**：抖动动画直接改 `x`，`restX` 跟着漂，四段的 `to` 值都在追当前 `x`，抖动会逐段累积且最后回不到 0；直接给 `x` 做动画还会覆盖锚点绑定。
- **改动**：`FurryField.qml` 删除 `restX`；`FurryButton.qml` 改为 `transform: Translate { id: shakeTranslate }` + 对 `shakeTranslate.x` 做 ±6 → 0 的分段动画（320ms = 40+120+120+40），不再碰 `x`。
- **复验**：

```sh
$ grep -rn 'restX' assets/sddm/furryos/
components/FurryButton.qml:126:       `property real restX: x` 记基准位，而 x 一动 restX 就跟着漂，
# 仅剩这一行说明性注释（解释旧 bug），已无任何属性/动画引用 restX
$ cd assets/sddm/furryos && qmllint Main.qml components/*.qml; echo $?
0
$ QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software timeout 25 qmlscene Main.qml; echo $?
0
```

- **结论**：已修复。抖动不再依赖「x 是自由的」这一错误前提。

### F31 [low] 「彩带扩散」与实际实现（同心圆环）不符

- **问题**：README:38 与 effects README 把 KWin `mouseclick` 特效说成彩带；实现是 `RingCount=2`/`RingLife=250`/`RingSize=32` 的圆环。
- **改动**：README、effects README、BUILD.md 验收清单统一改为「蓝白同心圆环（涟漪）」并附真实参数。
- **复验**：

```sh
$ grep -rn '彩带' README.md docs/BUILD.md assets/effects/README.md
（无输出）
$ grep -n 'RingSize' assets/desktop/skel/.config/kwinrc assets/effects/README.md
assets/desktop/skel/.config/kwinrc:…RingSize=32
assets/effects/README.md:…RingSize=32            # 半径，像素（KWin 配置界面里的 "Ring Radius"）
```

- **结论**：已修复。顺带说明：审核建议的 `RingSize=320` 与资产里的 `32` 不一致，**以资产为准**（32 是半径像素值，320 会是 640px 直径的巨环）；此项留给视觉负责人做观感调参，不属于正确性修复。

### F32 [low] `assets/desktop/.tools/__pycache__/*.pyc` 被 git 跟踪

- **问题**：编译产物入库，每次跑校验都可能产生变更噪声。
- **改动**：删除 `assets/desktop/.tools/__pycache__/`（含被跟踪的 `pngsample.cpython-311.pyc`）与 `build/config/assets/` 下的同名副本；`.gitignore` **未改**（红线：不得修改 `.gitignore` 的 `/.ssh/` 排除规则；整个文件属于「不修」项，见第 4 节）。
- **复验**：

```sh
$ git status --short | grep pycache
 D assets/desktop/.tools/__pycache__/pngsample.cpython-311.pyc
 D build/config/assets/desktop/.tools/__pycache__/pngsample.cpython-311.pyc
$ ls assets/desktop/.tools/__pycache__ 2>&1
ls: cannot access ...: No such file or directory
```

- **结论**：已修复（删文件）。要长期防复发需要 `.gitignore` 增加 `__pycache__/`/`*.pyc`，属第 4 节。

### F33 [本次新增] 离板色检查：SDDM 主题里的 `#B3261E` 没有令牌来源

- **问题**：`Main.qml:174` 写死 `#B3261E`，既不在 `brand-tokens.md` 的 9 个品牌色里，也没有语义色记录；`Theme.qml` 自称「色值唯一来源」。
- **改动**：
  - `assets/sddm/furryos/components/Theme.qml` 新增语义令牌 `furryosNegative: "#B3261E"`（注释说明为何不用 KDE 的 `#DA4453`：后者在 `#EAF2FF` 上只有 3.78:1，本值 5.80:1）；
  - `Main.qml` 改用 `Theme.furryosNegative`；
  - `assets/brand/brand-tokens.md` 新增 §1.1 语义色表；
  - `assets/desktop/.tools/verify-colors.py` 新增「SDDM 层不得出现离板色字面量」扫描（`*.qml`/`*.conf`/`*.desktop` 里的 `#RRGGBB` 必须是品牌色或已登记语义色），并把 `(179,38,30)` 加入语义色白名单。
- **复验**：

```sh
$ python3 assets/desktop/.tools/verify-colors.py | tail -4
SDDM theme hex literals: 11 (all on brand/semantic palette: yes)
PASS: all required Breeze sets/keys present; every non-semantic colour value is a brand-tokens.md token.

# 反向：把 Main.qml 改回 "#123456"
  off-palette: sddm/furryos/Main.qml:174 #123456
FAIL: - off-palette literal #123456 in sddm/furryos/Main.qml:174   → exit 1
```

- **结论**：已修复。

### F34 [本次新增] `sddm.conf` 双源：安装器模板与资产各写一份

- **问题**：`install-sddm-theme.sh` 用 heredoc 生成 `/etc/sddm.conf`，而 `assets/sddm/sddm.conf` 里还写着 `CursorTheme=Breeze_Snow`——实际装出来的是模板那份，光标主题丢了。
- **改动**：安装器新增 `SELF_DIR`/`CONF_ASSET`，资产存在就 `install -m 0644` 原样安装（单一来源），只在资产缺失时回退到模板（模板同步补上 `CursorTheme`）。
- **复验**：

```sh
$ chroot build/chroot /bin/sh /root/hooktest/6120-integrate-sddm-assets.chroot; echo $?
0
$ grep CursorTheme build/chroot/etc/sddm.conf
CursorTheme=Breeze_Snow
$ diff <(grep -v '^#' assets/sddm/sddm.conf) <(grep -v '^#' build/chroot/etc/sddm.conf) && echo IDENTICAL
IDENTICAL
```

- **结论**：已修复。

### F35 [本次新增] 一键品牌自检入口（`tools/verify-brand.sh`）

- **问题**：四条校验链（身份层 / 桌面视觉层 / 启动画面 / QML 语法）没有统一入口，改完资产容易漏跑；审核也要求给一条「品牌自检命令」。
- **改动**：新增 `tools/verify-brand.sh`（`--no-fetch` 透传给身份层），按链输出 `[PASS]/[FAIL]/[SKIP]` 与汇总，任一失败退出码 1；README 新增 §5.0。
- **复验**：

```sh
$ bash tools/verify-brand.sh --no-fetch
[PASS] 系统身份层 verify-identity.sh
[PASS] 桌面视觉层 verify-all.py
[PASS] 启动画面 verify-splash-pixels.py
[PASS] SDDM QML 语法 qmllint
全部通过（4 项检查，0 项跳过）
$ echo $?
0
```

- **结论**：已新增。

---

## 2. 复验记录（全量）

### 2.1 静态校验

```sh
$ bash tools/verify-identity.sh | tail -3
==========================================
结果：PASS=33 FAIL=0
==========================================
$ echo $?          # 0

$ bash tools/verify-brand.sh --no-fetch | grep -E '^\[|^全部通过'
[PASS] 系统身份层 verify-identity.sh
[PASS] 桌面视觉层 verify-all.py
[PASS] 启动画面 verify-splash-pixels.py
[PASS] SDDM QML 语法 qmllint
全部通过（4 项检查，0 项跳过）
```

### 2.2 钩子在真实 rootfs 上跑通（`build/chroot`，39 个文件层的真实产物）

```sh
$ mkdir -p build/chroot/live-build/config
$ mount --bind build/config build/chroot/live-build/config
$ for h in 6000 6010 6110 6120 6130 8990; do chroot build/chroot /bin/sh /root/hooktest/$h-*.chroot; echo "$h EXIT=$?"; done
6000 EXIT=0   6010 EXIT=0   6110 EXIT=0   6120 EXIT=0   6130 EXIT=0   8990 EXIT=0
```

产物核对：

```sh
$ cat build/chroot/etc/xdg/ksplashrc
[KSplash]
Theme=org.furryos.desktop
$ ls build/chroot/usr/share/plasma/look-and-feel/org.furryos.desktop/contents/splash/
images  Splash.qml
$ ls build/chroot/usr/share/color-schemes/FurryOS.colors build/chroot/usr/share/sddm/themes/furryos/Main.qml
$ find build/chroot/usr/share/wallpapers/FurryOS -type f | wc -l
3
$ ls -l build/chroot/etc/os-release
/etc/os-release -> ../usr/lib/os-release
$ grep '^NAME=' build/chroot/usr/lib/os-release
NAME="FurryOS"
$ ls -d build/chroot/opt/furryos 2>&1
ls: cannot access 'build/chroot/opt/furryos': No such file or directory   # 8990 已清理
```

### 2.3 反向对照（19 项，全部按预期变红）

| # | 动作 | 期望 | 实测 |
|---|---|---|---|
| 1 | `config/assets` 换成空目录 | 6000 exit 1 | `ERROR: 5 asset layer(s) missing` exit 1 |
| 2 | 删暂存 `identity/` | 6010 exit 1 | exit 1 |
| 3 | 删 `identity/issue` | 6010 exit 1 | `required asset missing: .../issue` exit 1 |
| 4 | 删暂存 `desktop/` | 6110 exit 1 | exit 1 |
| 5 | 删 `desktop/wallpapers/` | 6110 exit 1 | exit 1（F28 新增） |
| 6 | 删 `desktop/FurryOS.colors` | 6110 exit 1 | exit 1 |
| 7 | 删暂存 `sddm/` | 6120 exit 1 | exit 1 |
| 8 | 删暂存 `effects/` | 6130 exit 1 | exit 1 |
| 9 | 删 `splash/furryos-ksplash/` | 6130 exit 1 | exit 1（F28 新增） |
| 10 | ESP 内塞整份 grub.cfg | 8000 exit 1 | `does not contain the expected 3-line ESP stub` exit 1 |
| 11 | 删 `update-motd.d/00-header` | verify-identity 变红 | PASS=31 FAIL=3 |
| 12 | 删 `update-motd.d/10-help-text` | verify-identity 变红 | PASS=32 FAIL=2 |
| 13 | 删 6010 的 os-release 链接行 | verify-identity 变红 | PASS=33 FAIL=1 |
| 14 | `[Colors:View]` 背景改深色 | verify-consistency 变红 | 1.00:1 → exit 1 |
| 15 | `EXPECT["Image"]` 改名 | verify-consistency 变红 | exit 1 |
| 16 | `Main.qml` 写 `#123456` | verify-colors 变红 | exit 1 |
| 17 | `paw.svg` 内趾移走 | verify-wallpaper 变红 | `geometry not paw-shaped` exit 1 |
| 18 | 删 `paw.svg` | verify-wallpaper 可读失败 | `cannot derive paw geometry` exit 1 |
| 19 | 调色板 PNG 替换壁纸 | 不崩溃、给可读结论 | 11 条失败项，exit 1 |

### 2.4 修复前后的关键差异

| 检查 | 修复前 | 修复后 |
|---|---|---|
| ESP 内 `grub.cfg` 行数 | 57（整份配置，UEFI 不可启动） | 3（引导桩） |
| `/etc/xdg/ksplashrc` | 不存在（启动画面是 Breeze） | `Theme=org.furryos.desktop` |
| `/usr/share/plasma/look-and-feel/org.furryos.desktop` | 不存在 | `metadata.json` + `contents/splash/Splash.qml` |
| `/etc/sddm.conf` | 安装器模板（丢 `CursorTheme`） | 资产逐字节副本 |
| `verify-identity.sh` 删资产 | 仍 PASS=33 | FAIL=3 / FAIL=2 / FAIL=1 |
| 层目录缺失 | 6110/6120/6130 静默 exit 0 | exit 1（共 10 个负向用例） |
| 全新 clone 构建 | 无工具链、无 shim/mount | `bash tools/prepare-toolchain.sh` 一条命令 |

---

## 3. 改动文件清单

**钩子（`build/config/hooks/normal/`）**

- `6000-stage-furryos-assets.chroot`（幂等暂存 + 计数修正）
- `6010-integrate-identity-assets.chroot`（单一 `FURRYOS_ASSETS`、身份层核心文件硬要求）
- `6110-integrate-desktop-assets.chroot`（缺失 fatal、skel README 清理、壁纸源/目标双断言）
- `6120-integrate-sddm-assets.chroot`（安装器失败 fatal、产物断言）
- `6130-integrate-effects-assets.chroot`（接入层脚本、ksplash 断言、ksplash 源文件要求、plymouth 明示降级）
- `8000-brand-boot-menu.binary`（删除 ESP 注入、桩断言、ISO 参数断言、`.disk/info` 重写）
- `8990-furryos-cleanup.chroot`（删死操作）

**工具（`tools/`）**

- `lb.sh`（自定位、工具链自愈、`clean` 不预挂 `/dev`）
- `verify-identity.sh`（空断言、条数断言、模拟对齐钩子、`--no-fetch`、自定位）
- `prepare-toolchain.sh`（新增：解包 + 5 个补丁 + 13 项自检）
- `fetch-refs.sh`（新增：上游参考包）
- `verify-brand.sh`（新增：一键四链）

**资产（`assets/`）**

- `brand/brand-tokens.md`（§1.1 语义色）
- `desktop/.tools/verify-colors.py`（离板色扫描）
- `desktop/.tools/verify-consistency.py`（EXPECT 生效、shipped pair 断言）
- `desktop/.tools/verify-wallpaper.py`（几何解析、PNG 归一化、可读失败）
- `effects/README.md`、`effects/splash/effects-splash-install.sh`、`effects/splash/verify-splash-pixels.py`
- `sddm/README.md`、`sddm/install-sddm-theme.sh`、`sddm/furryos/{Main.qml,metadata.desktop}`、`sddm/furryos/components/{Theme,FurryButton,FurryField}.qml`

**文档**

- `README.md`（5.0 一键自检、5.1 断言条数、4.3 `lb clean` 警告、4.4 `bash`、`libqt5svg5`、涟漪）
- `docs/BUILD.md`（§2 真实链路、§2.1 工具链、os-release 命令、壁纸路径、6200→补丁、qmllint/qmlscene 事实、卷标、验收项）
- `build/config/assets/**`（`tools/sync-assets.sh` 重新同步后的产物；这是钩子实际读取的那份）

---

## 4. 明确不修（超范围 / 需上游决策）

| 项 | 为什么不修 | 替代方案 / 现状 |
|---|---|---|
| `build/config/assets/`（159 个文件、1.5 MB）被整体入库，与 `assets/` 逐字节重复 | 修改 `.gitignore` 与 `git rm -r --cached` 属于仓库结构调整，红线明确「不得修改 `.gitignore` 的 `/.ssh/` 排除」，且这属于发布前的仓库精简决策（队长/构建负责人） | 本次已用 `tools/sync-assets.sh` 把两份同步一致（含 `effects/README.md`），并在 README/BUILD.md 把 sync 写成构建必需前置；建议后续：`build/config/assets/` 进 `.gitignore` + `git rm -r --cached`，`6000` 已经是缺目录即 exit 1，安全 |
| `.gitignore` 增加 `__pycache__/`、`*.pyc`、`/build/*.contents`、`/build/*.files` | 红线：不改 `.gitignore` | 已删除被跟踪的 pyc（F32）；`build/live-image-amd64.contents/.files` 是构建产物，提交时排除即可 |
| `build/config/package-lists/furryos-desktop.list.chroot` 的注释称「`qt5-image-formats` 提供 `libqsvg.so`」，且未显式声明 `libqt5svg5` | 包列表不在本次允许改动范围（仅钩子/工具/资产/文档） | 已在 README/BUILD.md/`assets/sddm/README.md` 把机制写对（`libqsvg.so` 来自 `libqt5svg5`）；当前 `libqt5svg5` 由 sddm/KDE 依赖链带入（`build/chroot` 实测已装），不构成功能缺陷。建议构建侧把 `libqt5svg5` 显式加进列表并修正注释 |
| `build/config/bootloaders/syslinux_common/live.cfg.in:21` 注释写 `hooks/6210-brand-boot-menu.*` | 不在允许范围（`build/config/bootloaders/`） | 真实文件是 `hooks/normal/8000-brand-boot-menu.binary`，已在 `docs/BUILD.md` 与钩子头注释中写明；建议构建侧顺手改这一行注释 |
| `plymouth` 加入包列表（真正启用开机 Plymouth 主题） | 需要新增包 + `update-initramfs` 策略 + QEMU 验证，属构建/发布决策 | 现状是**明示降级**：主题文件装到位、不激活；`docs/BUILD.md` 与 `assets/effects/README.md` 写清了启用步骤（装 `plymouth plymouth-themes` → `plymouth-set-default-theme furryos` → `update-initramfs -u`） |
| `docs/REVIEW.md` / `docs/TEST-REPORT.md` / `docs/BUILD-LOG.md` 的措辞（如 5.27.11、卷标、包名） | 这三份是审核/测试/构建的原始记录，按团队约定不由 fixer 改写 | 本次结论写在本文档与 `docs/BUILD.md`（用户可见的排障文档）里；三份原始记录保留原样以便对照 |

**核实为「审核误判、无需修改」的两项**：

- `README.md:19` 的「KDE Plasma 5.27.12」：`build/chroot` 实测 `plasma-workspace`/`plasma-desktop` = `4:5.27.12-0ubuntu0.1`，README 正确；`libkwin.so.5.27.11` 只是 soname 版本，不是 Plasma 版本。
- `docs/BUILD-LOG.md` 引用不存在：该文件现已由构建任务产出（`docs/BUILD-LOG.md`），引用成立。

---

## 5. 对下游（重建 / 发布）的要求

1. **必须重建 ISO**：本次修复的是钩子与资产，镜像内生效需要 `bash tools/lb.sh clean && bash tools/lb.sh build`（`lb clean` 是必须的，见 README 4.3 的 stagefile 短路说明）。
2. **UEFI 必须在新 ISO 上复验**：`efi.img` 的引导桩断言只能在构建期保证；实机/QEMU 需确认 UEFI 能进菜单并引导，BIOS 同样要过一遍。
3. **验收清单**：`docs/BUILD.md` §4 已补两条硬验收——`build/chroot/usr/lib/os-release` 的 `NAME="FurryOS"`、`build/chroot/etc/xdg/ksplashrc` 的 `Theme=org.furryos.desktop`。
4. **提交范围**：`build/config/assets/**` 的改动是 `sync-assets.sh` 的产物，需与 `assets/**` 一起提交；`build/live-image-amd64.contents/.files`、`build/binary*`、`build/chroot*` 是构建产物，不要入库。
5. **本次未提交任何 commit**（推送由队长统一执行）；`.ssh/`、ISO、构建缓存均未触碰。

---

## 附录 A：命令速查

```sh
# 一键自检（改完资产/钩子先跑这个）
bash tools/verify-brand.sh --no-fetch

# 身份层单独跑（33 项，不需要 root）
bash tools/verify-identity.sh

# 工具链重建（新 clone / 清过 tools/ 之后）
bash tools/prepare-toolchain.sh

# 构建（受限宿主）
cd build && bash ../tools/lb.sh clean && bash ../tools/lb.sh build

# 钩子在已构建 rootfs 上单独复验（需要 bind mount config）
mkdir -p build/chroot/live-build/config
mount --bind build/config build/chroot/live-build/config
cp build/config/hooks/normal/{6000,6010,6110,6120,6130,8990}-*.chroot build/chroot/root/
for h in 6000 6010 6110 6120 6130 8990; do chroot build/chroot /bin/sh /root/$h-*.chroot; done
umount build/chroot/live-build/config

# 引导桩核对
cd build/binary && mtype -i boot/grub/efi.img ::/boot/grub/grub.cfg
```
