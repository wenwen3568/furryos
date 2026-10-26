# FurryOS 构建说明与降级方案

> 本文件由构建交付层（build-verify）维护，**所有层的降级方案汇总于此**。
> 用户遇到「装了 FurryOS 但看不到效果」时，**只看这一份文件**。
>
> 当前状态：构建交付层正在搭建 live-build 工程骨架（bootstrap 已成功，220 包）。
> 各层资产已就位，注入 hook 见下方「资产注入」。
> 标注「由 build-verify 补充」的小节是其负责内容。

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

四层资产的落盘路径由 `docs/CONTRACTS.md` 规定。登录体验层的注入脚本可直接作为
live-build hook 使用：

```sh
# build/config/hooks/9999-furryos-sddm.chroot  （需可执行）
#!/bin/sh
/root/furryos/assets/sddm/install-sddm-theme.sh /root/furryos/assets/sddm/furryos "$1"
```

该脚本做三件事：
1. 复制主题到 `<前缀>/usr/share/sddm/themes/furryos/`
2. `chmod -R a+rX` 确保 `sddm` 用户可读
3. 写入 `<前缀>/etc/sddm.conf`，含 `Current=furryos` 与 `ThemeDir=/usr/share/sddm/themes`

其余各层的注入方式：由 build-verify 补充。

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
dpkg -l | grep -E 'qml-module-qtquick2|libqt5quick5|qt5-image-formats|libqt5qml5|qml-module-qtquick-layouts'
```
预期：五个包均为 `ii`。

**这是最难查的失败模式，请务必单独确认 `qt5-image-formats`：**

| 缺失的包 | 现象 |
|---|---|
| `qt5-image-formats` | **只有爪印消失**。界面、蓝白配色、按钮动画全部正常；Qt 不弹错误对话框，只在 SDDM 日志里留一行 `QML Image: Cannot open: .../paw.svg`。极易误判为「主题没做爪印」 |
| `qml-module-qtquick2` / `libqt5quick5` | 主题整体无法加载，SDDM **静默回退**到默认主题（连蓝白配色都不会出现） |

修复：
```sh
sudo apt-get install -y qt5-image-formats qml-module-qtquick2 libqt5quick5
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
     手动修复（由 6010 钩子完成）：
     ```sh
     sudo bash -c 'cat /usr/lib/os-release > /etc/os-release && ln -sf ../usr/lib/os-release /etc/os-release'
     ```

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
     sudo bash /root/furryos/tools/verify-identity.sh  # 重新验证 33 项断言
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
     color schemes 中是否有 FurryOS.colors
     ```
     若无，由 build-verify 通过 6110 钩子重新注入：
     ```sh
     # live-build hook 会自动处理，手动触发同步资产
     sh /root/furryos/tools/sync-assets.sh
     ```

  2. **确认壁纸已安装**
     ```sh
     ls /usr/share/wallpapers/FurryOS/
     ```
     预期：`wallpaper.png` 与 `wallpaper.svg` 均存在。
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

- [ ] ISO 卷标：`FURRYOS`
- [ ] ISO 应用名：`FurryOS`
- [ ] 启动菜单文字：`FurryOS`
- [ ] SSH 横幅：无 Ubuntu 商标/Logo
- [ ] 登录界面：SDDM 主题蓝白+爪印，动画 140/200/320ms
- [ ] 桌面壁纸：爪印可辨认，9 个色值一致
- [ ] 点击特效：出现彩带扩散，颜色一致
- [ ] ISO 内 NAME="FurryOS" 且 /etc/os-release 符号链接正常

---

## 5. 已知环境限制（开发期如实记录）

构建/验证在 Debian 12 宿主上进行，与目标 Ubuntu LTS 存在差异：

| 限制 | 影响 | 已采取的替代验证 |
|---|---|---|
| 宿主无 GL 上下文（`QOpenGLContext::create()` 失败，无 llvmpipe 注册） | 无法用 `qmlscene`/`QQuickView::grabWindow()` 真实渲染 QML 场景，**无法在宿主机跑出 SDDM 真实截图** | 用 `QQmlComponent` 在无 GL 的 QML 引擎中实例化完整主题对象树，读取真实属性断言；另按真实坐标用 QtGui 2D 绘制四状态预览图 |
| 宿主 `/usr/bin/qmllint` 是 qtchooser 符号链接，指向不存在的 `/usr/lib/qt5/bin/qmllint` | 无法直接调用 | 从 Debian bookworm 取 `qtdeclarative5-dev-tools_5.15.8+dfsg-3` 解出真实二进制 |
| 宿主非目标 Ubuntu LTS | 无法启动真实 SDDM 会话 | 提供 `install-sddm-theme.sh` 供 live-build 注入；真实目视确认步骤见 3.1 ⑦ |
| 容器 `container="lxc"` 导致 setup_devices 路径错误 | bootstrap 阶段设备节点不可写 | 已在 lb.sh 中移除 `export container="lxc"`，改为无条件 `setup_devices_bind()` 路径 |
| `/etc/mtab` 是指向只读 `/proc` 的 symlink | mount 成功却返回非零 | 各挂载脚本(chroot_proc chroot_sysfs chroot_devpts)全部加 `|| true` 容错 |
| `/dev/null` 被写成普通文件 | `echo test > /dev/null` 会创建普通文件，导致 apt-key 等工具失败 | lb.sh 在每次 invocation 前重新 bind-mount 宿主 `/dev` 进入 chroot；chroot 内 `setup_devices_bind` + `FURRYOS_BIND_DEVICES=1` 共同保证 |
| apt 的 sandbox 用户 `_apt` 无法看到 bind-mount 的 /dev | apt-key / apt-get update 因 `/dev/null` 权限错误 中断 | 配置 `APT::Sandbox::User "root"` 禁用沙箱降权 |
| live-build 的 `LB_LINUX_PACKAGES` / `LB_LINUX_FLAVOURS_WITH_ARCH` 在 noble 中不兼容 | `linux-image-generic-amd64` 在 noble index 不存在 | config/chroot 中设为 `linux-generic` 并配合 6200 钩子在 chroot_install-packages 前重写包名 |
| `qt5-image-formats` 在 noble 已移除至源包 | 若不安装，爪印将静默消失（无错误弹窗） | 建议始终 `apt-get install -y qt5-image-formats`；或在 BUILD.md 3.1 ④ 提供修复命令 |
| `debian-archive-keyring` 在 Ubuntu 中不存在 | gpgv 信任链验证失败 | config/environment.chroot 中设为 `ubuntu-keyring`；并在 chroot_install-packages 前提前安装 |

## 4. 验收

逐项验收由 t8 负责。登录体验层的关键校验点：

```sh
grep '^Current' /etc/sddm.conf                          # → Current=furryos
ls /usr/share/sddm/themes/furryos/{Main.qml,metadata.desktop,theme.conf}
ls /usr/share/sddm/themes/furryos/components/           # 6 个文件
ls /usr/share/sddm/themes/furryos/assets/paw.svg
```

完整构建日志：`docs/BUILD-LOG.md`（由 build-verify 维护）。

---

## 5. 已知环境限制（开发期如实记录）

构建/验证在 Debian 12 宿主上进行，与目标 Ubuntu LTS 存在差异：

| 限制 | 影响 | 已采取的替代验证 |
|---|---|---|
| 宿主无 GL 上下文（`QOpenGLContext::create()` 失败，无 llvmpipe 注册） | 无法用 `qmlscene`/`QQuickView::grabWindow()` 真实渲染 QML 场景，**无法在宿主机跑出 SDDM 真实截图** | 用 `QQmlComponent` 在无 GL 的 QML 引擎中实例化完整主题对象树，读取真实属性断言；另按真实坐标用 QtGui 2D 绘制四状态预览图 |
| 宿主 `/usr/bin/qmllint` 是 qtchooser 符号链接，指向不存在的 `/usr/lib/qt5/bin/qmllint` | 无法直接调用 | 从 Debian bookworm 取 `qtdeclarative5-dev-tools_5.15.8+dfsg-3` 解出真实二进制 |
| 宿主非目标 Ubuntu LTS | 无法启动真实 SDDM 会话 | 提供 `install-sddm-theme.sh` 供 live-build 注入；真实目视确认步骤见 3.1 ⑦ |
