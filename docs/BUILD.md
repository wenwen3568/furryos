# FurryOS 构建说明与降级方案

> 本文件由构建交付层（build-verify）维护，**所有层的降级方案汇总于此**。
> 用户遇到「装了 FurryOS 但看不到效果」时，**只看这一份文件**。
>
> 当前状态：工程骨架与四层资产注入已落地（`6000`/`6010`/`6110`/`6120`/`6130`/`8000`/`8990`），
> 完整 ISO 已产出；缺陷修复记录见 `docs/FIXES.md`，审核/测试/构建原始结论见
> `docs/REVIEW.md`、`docs/TEST-REPORT.md`、`docs/BUILD-LOG.md`。

---

## 1. 构建环境

| 项 | 值 |
|---|---|
| 基础发行版 | Ubuntu LTS（noble），amd64 |
| 桌面环境 | KDE Plasma |
| 显示管理器 | SDDM（自定义主题 `furryos`） |
| 构建工具 | live-build |
| ISO 应用名 / 卷标 | FurryOS |

构建工程目录：`/root/furryos/build/`（由 build-verify 维护）。

---

## 2. 资产注入

四层资产的落盘路径由 `docs/CONTRACTS.md` 规定。真实管线是**一个暂存钩子 + 四个整合钩子**，
都在 `build/config/hooks/normal/` 下，按编号顺序执行：

| 钩子 | 作用 |
|---|---|
| `6000-stage-furryos-assets.chroot` | 把 `build/config/assets/`（`tools/sync-assets.sh` 从仓库 `assets/` 同步而来）整棵暂存到 `/opt/furryos/assets`（`FURRYOS_ASSETS`），供后续钩子读取 |
| `6010-integrate-identity-assets.chroot` | `os-release` / `issue` / `motd` / `legal` / `lsb-release` / SSH 横幅 |
| `6110-integrate-desktop-assets.chroot` | `FurryOS.colors`、Plasma look-and-feel 主题、`/etc/skel` 默认配置、壁纸包 `/usr/share/wallpapers/FurryOS/` |
| `6120-integrate-sddm-assets.chroot` | SDDM 主题 `furryos` + `/etc/sddm.conf` |
| `6130-integrate-effects-assets.chroot` | KWin 点击特效 + ksplash 主题 `org.furryos.desktop` + `/etc/xdg/ksplashrc` |
| `8990-furryos-cleanup.chroot` | 删除暂存目录与钩子产生的临时文件 |

**为什么需要 6000 暂存**：chroot 钩子运行在 `build/chroot` 内部，仓库在宿主上，
唯一可见的入口是 live-build 把 `build/config` 绑定到 chroot 的 `/live-build/config`。
所以 6000 先把 `config/assets/` 拷进 chroot，后面的钩子只读 `/opt/furryos/assets`
（路径由 `furryos-common.sh` 的 `FURRYOS_ASSETS` 给出）。

**每个整合钩子都是硬失败**：缺层目录、缺关键文件、安装脚本返回非 0、装完自检不到产物，
一律 `exit 1`。宁可构建停住，也不产出一套「看起来是 FurryOS、实际只换了个壁纸」的镜像。

### 2.1 构建工具链从哪来（受限宿主）

`live-build` / `debootstrap` / `ubuntu-keyring` 在受限宿主上装不成系统包（`/usr` 与
dpkg 数据库只读），因此解包到仓库内使用：

```sh
bash tools/prepare-toolchain.sh          # → tools/rootfs、tools/lbroot、tools/shim
```

产物被 `.gitignore` 排除（可重建的构建依赖），克隆下来并不存在；
`tools/lb.sh` 发现缺失会自动调用它。脚本固化的补丁都是「不打就构建不出来」的环境事实：

| 补丁 | 不打会怎样 |
|---|---|
| `debootstrap/functions`：非容器分支改走 `setup_devices_bind()`，跳过 nodev 上的 device-node 探针 | `/root` 挂 nodev 时，`mknod` 出来的 `/dev/null` 存在但打不开，所有 postinst 的 `> /dev/null` 失败（base-files、dpkg、libc6、procps 全线崩） |
| `binary_grub-efi`：`stat -c %s` → `stat -L -c %s` | Ubuntu 的 `bootx64.efi` 是指向签名 shim 的符号链接，不跟链接只量到 36 字节，EFI FAT 镜像小到装不下，`mcopy: Disk full` |
| `${LIVE_BUILD}/share/bootloaders` 等符号链接 | `binary_grub_cfg` 从 `${LIVE_BUILD}/share/bootloaders` 取 GRUB 资源，而 Debian 包装在 `/usr/share/live/build/` 下 |
| `chroot_install-packages`：`linux-image-generic-amd64` → `linux-image-generic` | live-build 拼出的内核元包名带 `-amd64` 后缀，noble 的 generic 内核元包没有这个后缀，`No such package` |
| `chroot_{proc,sysfs,selinuxfs}`：`mount ... \|\| true` | 宿主 `/etc/mtab` 指向只读 `/proc`，一次**成功**的挂载也以 16 退出，打断 chroot 阶段（`tools/shim/mount` 的 `mount -n` 是第一道防线，这是第二道） |

---

## 3. 降级方案汇总（用户需手动做的事）

> **每一条都是「效果没出现时，用户必须执行的步骤」。**
> 按顺序做到位，不要跳过。

### 3.1 登录界面（SDDM 主题）—— 登录体验层

**预期效果**：登录界面为蓝白配色（极浅蓝底 + 白色登录卡片），
背景与按钮上有爪印图案；鼠标悬停登录按钮时按钮变亮并轻微放大（约 140ms），
按住时按钮变深并缩小（约 200ms），密码错误时按钮左右抖动（约 320ms）。

**若看不到上述效果，按顺序执行：**

#### ① 确认主题已安装

```sh
ls -l /usr/share/sddm/themes/furryos/Main.qml
```
预期：文件存在。若报 No such file，说明注入失败，需重新执行第 2 节的注入脚本。

#### ② 确认 SDDM 已启用该主题

```sh
grep '^Current' /etc/sddm.conf
```
预期输出：`Current=furryos`

若为其它值，说明 `/etc/sddm.conf` 被 `sddm-theme-*` 包的 alternatives 机制覆盖。
手动修复：
```sh
sudo sed -i 's/^Current=.*/Current=furryos/' /etc/sddm.conf
```

#### ③ 确认 QML 无语法/资源错误

```sh
cd /usr/share/sddm/themes/furryos
qmllint -I . --qmldirs /usr/lib/x86_64-linux-gnu/qt5/qml Main.qml components/*.qml
```
预期：**无任何输出**。

> 若本机 qmllint 报 `could not exec '/usr/lib/qt5/bin/qmllint'`，
> 说明是 qtchooser 坏链（部分 Debian/Ubuntu 版本的已知问题），
> 装 `qml` 包或改用第 ④ 步。

#### ④ 确认 QML 运行时依赖在位（爪印能否显示的关键）

```sh
dpkg -l | grep -E 'qml-module-qtquick2|libqt5quick5|libqt5svg5|qt5-image-formats-plugins|libqt5qml5|qml-module-qtquick-layouts'
```
预期：五个包均为 `ii`。

**这是最难查的失败模式，请务必单独确认 `libqt5svg5`：**

| 缺失的包 | 现象 |
|---|---|
| `libqt5svg5` | **只有爪印消失**。界面、蓝白配色、按钮动画全部正常；Qt 不弹错误对话框，只在 SDDM 日志里留一行 `QML Image: Cannot open: .../paw.svg`。极易误判为「主题没做爪印」 |
| `qml-module-qtquick2` / `libqt5quick5` | 主题整体无法加载，SDDM **静默回退**到默认主题（连蓝白配色都不会出现） |

修复：
```sh
sudo apt-get install -y libqt5svg5 qt5-image-formats-plugins qml-module-qtquick2 libqt5quick5

# 爪印是 SVG，渲染它需要的是 Qt 的 SVG 图像格式插件：
ls /usr/lib/x86_64-linux-gnu/qt5/plugins/imageformats/libqsvg.so   # 由 libqt5svg5 提供
# qt5-image-formats-plugins 提供的是 tiff/webp/jp2 等格式，不含 libqsvg.so；
# noble 里也没有叫 qt5-image-formats 的二进制包（只有同名源码包）。
```

#### ⑤ 重启 SDDM 让主题生效

```sh
sudo systemctl restart sddm
```
预期：黑屏一下后出现 FurryOS 登录界面（极浅蓝底 + 白色圆角卡片）。

若重启后仍是旧主题，强制清一次：
```sh
sudo systemctl stop sddm
sudo pkill -f sddm-greeter
sudo systemctl start sddm
```

#### ⑥ 确认 sddm 用户有读权限

```sh
sudo -u sddm test -r /usr/share/sddm/themes/furryos/Main.qml && echo READABLE
```
预期：输出 `READABLE`。否则：
```sh
sudo chmod -R a+rX /usr/share/sddm/themes/furryos
```

#### ⑦ 动画效果的目视确认（不可跳过）

重启后在登录界面上依次做：

| 操作 | 预期看到 | 对应契约 |
|---|---|---|
| 鼠标移到「登 录」按钮上 | 约 0.14 秒内按钮由 `#1A6FD4` 变亮为 `#2C85EC`，并轻微放大约 3%，边缘浮出浅蓝细边 | 悬停 120–160ms |
| 按住左键不放 | 约 0.2 秒内按钮**变深**为 `#0F4C8C`，并缩小到 0.96 倍 | 按下 180–240ms + 缩放 0.96 + 颜色加深 |
| 松开左键 | 约 0.14 秒内回到悬停态 | 整体 200–300ms 轻快手感 |
| 输入错误密码后回车 | 登录按钮左右抖动 2 次（约 0.32 秒，±6px），下方出现红字「用户名或密码错误」，密码框清空 | 密码错误抖动 320ms |

想量化时长就用手机慢动作录像（240fps 以上）或屏幕录制逐帧播放。

#### ⑧ 仍无效时抓日志

```sh
journalctl -u sddm -n 100 --no-pager | grep -iE 'qml|furryos|theme|error'
```
常见报错与含义：
- `Cannot open: .../paw.svg` → 资源路径断了（Main.qml 里应为 `assets/paw.svg`，不带 `../`）
- `Type FurryButton unavailable` → `components/qmldir` 没随主题一起复制
- `Failed to create OpenGL context` → 显卡驱动问题，与主题无关，需先解决驱动

> 完整说明（含设计理由、坐标基准、本仓库自动化验证）见
> `assets/sddm/README.md`；自动化验证证据见 `docs/sddm-verification/`。

### 3.2 系统身份层 / 桌面视觉层 / 交互动效层 —— 由各层负责人与 build-verify 补充

**系统身份层**：

- **预期效果**：
  - `/etc/os-release` NAME="FurryOS"，PRETTY_NAME="FurryOS 24.04 LTS"
  - SSH 登录横幅 `/etc/ssh/sshd_config.d/010-furryos-banner.conf` 头部不出现「Ubuntu」
  - 登录后动态信息（motd / issue.net）不暴露上游 Ubuntu 字样
  - `/etc/legal` / `/etc/motd` 均显示 FurryOS 免责声明

- **若看不到上述效果，按顺序执行**：

  1. **确认 os-release 未被上游覆盖**
     ```sh
     cat /etc/os-release
     ```
     预期：`NAME="FurryOS"` 且 `VERSION_ID="24.04"`。若为 `Ubuntu`，说明 base-files postinst 仍保留上游行为。
     手动修复（`6010` 钩子做的就是这件事）：
     ```sh
     # /etc/os-release 必须是指向 ../usr/lib/os-release 的相对符号链接
     ls -l /etc/os-release
     # 若不是符号链接（被上游 base-files 写成了普通文件），重建链接：
     sudo rm -f /etc/os-release
     sudo ln -sf ../usr/lib/os-release /etc/os-release
     ```

     > **不要**用 `cat /usr/lib/os-release > /etc/os-release` 去「修复」：
     > 如果 `/etc/os-release` 已经是指向该文件的符号链接，这条命令会先截断源文件，
     > 结果是 `/usr/lib/os-release` 变成空文件，系统连 `NAME` 都没有。

  2. **确认 SSH 横幅未写入 Ubuntu 字样**
     ```sh
     grep -i ubuntu /etc/ssh/sshd_config.d/010-furryos-banner.conf || echo 'No Ubuntu reference'
     ```
     预期：无 Ubuntu 相关行，或仅出现「基于 Ubuntu」（允许一次上游来源说明）。

  3. **确认 motd/issue 无动态上游信息**
     ```sh
     cat /etc/motd; cat /etc/issue.net
     ```
     预期：仅显示 FurryOS LOGO 或欢迎语，不含 `localhost` / `Ubuntu` 字样。
     若含上游信息，由 6010 钩子移除对应 drop-in 文件：
     ```sh
     sudo rm -f /etc/update-motd.d/00-header /etc/update-motd.d/10-help-text
     # 重新验证 33 项断言（在仓库目录里跑，不是在镜像里跑）
     bash tools/verify-identity.sh
     ```

  4. **确认 legal 免责声明就位**
     ```sh
     cat /etc/legal
     ```
     预期：包含「ABSOLUTELY NO WARRANTY」类免责声明，而非纯粹的 Debian/Ubuntu 文本。

**桌面视觉层**：

- **预期效果**：
  - 桌面配色 `FurryOS.colors` 已应用（系统主题自动生效）
  - 壁纸 `FurryOS`（1920×1080，蓝白渐变 + 爪印）在登录后桌面显示
  - 爪印在壁纸左上角深色区、底部浅色带内可辨认（脚趾互不重叠）
  - KWin 点击特效与启动画面已见上节

- **若看不到上述效果，按顺序执行**：

  1. **确认配色已注入**
     ```sh
     ls -l /usr/share/color-schemes/FurryOS.colors
     grep -A2 '^\[General\]' /etc/skel/.config/kdeglobals | grep ColorScheme
     ```
     预期：文件存在，且 `ColorScheme=FurryOS`（只放文件不改 `kdeglobals` 不会生效）。
     若缺失，说明资产没同步到构建树，由 `6110` 钩子重新注入：
     ```sh
     # 把 assets/ 同步到 build/config/assets/（钩子读的就是这份），然后重跑该阶段
     bash tools/sync-assets.sh
     cd build && bash ../tools/lb.sh clean && bash ../tools/lb.sh build
     ```

  2. **确认壁纸已安装**
     ```sh
     ls /usr/share/wallpapers/FurryOS/contents/images/
     ```
     预期：`1920x1080.png` 与 `1920x1080.svg` 均存在（KDE 按 `contents/images/`
     下的分辨率文件名选图，`metadata.desktop` 提供标题）。
     若缺失，检查 `skel/.config/plasmarc` 是否正确引用：
     ```sh
     grep -A3 'Wallpaper' /etc/skel/.config/plasmarc
     ```

  3. **确认爪印可辨认**
     - 打开「桌面设置」→「背景」，查看壁纸
     - 爪印 5 个部件全部命中 `#1A6FD4`，0 个部件应为其他色值
     - 若脚趾间隙偏差 > 8 或互相重叠，说明壁纸构图需重新审视（见 effects/README.md 中的几何校验细节）

**交互动效层**：

- **预期效果**：
  - 点击特效：见 3.1 章节的 ⑦ 目视确认步骤
  - 启动画面：见 3.1 章节的验收步骤

- **若看不到上述效果，按顺序执行**：

  1. **确认 kwinrc 与 kdeglobals 双配置就位**
     ```sh
     grep -A8 '\[Effect-mouseclick\]' /etc/skel/.config/kwinrc
     grep -A6 '\[Effects\]' /etc/skel/.config/kdeglobals
     ```
     预期：两个文件的 8 个色值完全一致，且 kwinrc 中含 `[Plugins] mouseclickEnabled=true`。

  2. **若缺失，由 desktop-visual 重新合并配置**
     - 将 desktop-visual 产出的 `skel/.config/kdeglobals` 与 `skel/.config/kwinrc` 复制至 `/etc/skel/.config/`
     ```sh
     sudo cp /root/furryos/assets/desktop/skel/.config/kdeglobals /etc/skel/.config/
     sudo cp /root/furryos/assets/desktop/skel/.config/kwinrc /etc/skel/.config/
     ```

  3. **重新登录或重启 KWin**
     ```sh
     qdbus org.kde.KWin /KWin restart
     ```

---

## 4. 验收

逐项验收由 t8 负责。登录体验层的关键校验点：

```sh
grep '^Current' /etc/sddm.conf                          # → Current=furryos
ls /usr/share/sddm/themes/furryos/{Main.qml,metadata.desktop,theme.conf}
ls /usr/share/sddm/themes/furryos/components/           # 6 个文件
ls /usr/share/sddm/themes/furryos/assets/paw.svg
```

完整构建日志：`docs/BUILD-LOG.md`（由 build-verify 维护）。

ISO 产出验收清单（由 build-verify 完成后填入）：

- [ ] ISO 卷标：`FurryOS`（`LB_ISO_VOLUME`；用 `blkid -p build/*.iso` 或 `isoinfo -d` 核对）
- [ ] ISO 应用名：`FurryOS`
- [ ] 启动菜单文字：`FurryOS`
- [ ] SSH 横幅：无 Ubuntu 商标/Logo
- [ ] 登录界面：SDDM 主题蓝白+爪印，动画 140/200/320ms
- [ ] 桌面壁纸：爪印可辨认，9 个色值一致
- [ ] 点击特效：出现蓝白同心圆环（涟漪）扩散（`RingCount=2` / `RingLife=250` / `RingSize=32`），两处配置颜色一致
- [ ] ISO 内 NAME="FurryOS" 且 /etc/os-release 符号链接正常
- [ ] **rootfs 内 os-release 为 FurryOS**：`grep '^NAME=' build/chroot/usr/lib/os-release`
      应为 `NAME="FurryOS"`，且 `build/chroot/etc/os-release` 是指向 `../usr/lib/os-release`
      的符号链接（钩子 6010 的产物；上游 base-files 的 postinst 会重写这个文件，
      所以必须验证钩子跑完之后的状态，而不是只看 assets 里的源文件）
- [ ] `grep '^Theme=' build/chroot/etc/xdg/ksplashrc` 为 `org.furryos.desktop`，
      且 `build/chroot/usr/share/plasma/look-and-feel/org.furryos.desktop/contents/splash/Splash.qml` 存在

---

## 5. 已知环境限制（开发期如实记录）

构建/验证在 Debian 12 宿主上进行，与目标 Ubuntu LTS 存在差异：

| 限制 | 影响 | 已采取的替代验证 |
|---|---|---|
| 宿主无 GL 上下文（`QOpenGLContext::create()` 失败，无 llvmpipe 注册） | 默认（OpenGL）后端起不来 | 改用软件后端仍可**真实加载**整个主题场景：`QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software qmlscene Main.qml`（实测 exit 0，无 QML 警告）。离屏截图仍按真实坐标用 QtGui 2D 绘制 |
| 个别宿主上 `/usr/bin/qmllint` 可能是 qtchooser 坏链（指向不存在的 `/usr/lib/qt5/bin/qmllint`） | 该机无法直接调用 | 本机实测 `/usr/bin/qmllint` 可用（`qmllint -I . --qmldirs /usr/lib/x86_64-linux-gnu/qt5/qml Main.qml components/*.qml` exit 0）；确实坏链时再从 bookworm 取 `qtdeclarative5-dev-tools_5.15.8+dfsg-3` 解出二进制 |
| 宿主非目标 Ubuntu LTS | 无法启动真实 SDDM 会话 | 提供 `install-sddm-theme.sh` 供 live-build 注入；真实目视确认步骤见 3.1 ⑦ |
| 容器 `container="lxc"` 导致 setup_devices 路径错误 | bootstrap 阶段设备节点不可写 | 已在 lb.sh 中移除 `export container="lxc"`，改为无条件 `setup_devices_bind()` 路径 |
| `/etc/mtab` 是指向只读 `/proc` 的 symlink | mount 成功却返回非零 | 各挂载脚本(chroot_proc chroot_sysfs chroot_devpts)全部加 `|| true` 容错 |
| `/dev/null` 被写成普通文件 | `echo test > /dev/null` 会创建普通文件，导致 apt-key 等工具失败 | lb.sh 在每次 invocation 前重新 bind-mount 宿主 `/dev` 进入 chroot；chroot 内 `setup_devices_bind` + `FURRYOS_BIND_DEVICES=1` 共同保证 |
| apt 的 sandbox 用户 `_apt` 无法看到 bind-mount 的 /dev | apt-key / apt-get update 因 `/dev/null` 权限错误 中断 | 配置 `APT::Sandbox::User "root"` 禁用沙箱降权 |
| live-build 把内核元包名拼成 `${LB_LINUX_PACKAGES}-${LB_LINUX_FLAVOURS_WITH_ARCH}`（= `linux-generic-amd64`），noble 的 generic 元包没有 `-amd64` 后缀 | 直接装会 `No such package` | `tools/prepare-toolchain.sh` 给 `chroot_install-packages` 打补丁：在 apt 消费队列前把 `linux-{image-,}generic-amd64` 改写成 `linux-generic`（早先文档说的「6200 钩子」并不存在，实际实现点在这里） |
| 爪印是 SVG，需要 Qt 的 SVG 图像格式插件 | 缺 `libqt5svg5` 时爪印静默消失（无错误弹窗） | `apt-get install -y libqt5svg5`；自检命令见 3.1 ④。注：noble 无 `qt5-image-formats` 二进制包，提供 `libqsvg.so` 的是 `libqt5svg5` |
| `debian-archive-keyring` 在 Ubuntu 中不存在 | gpgv 信任链验证失败 | config/environment.chroot 中设为 `ubuntu-keyring`；并在 chroot_install-packages 前提前安装 |
