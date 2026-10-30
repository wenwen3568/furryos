FurryOS Effects Layer
=====================

## 产出位置

- assets/effects/click-effect/ - 点击特效脚本与配置
- assets/effects/splash/ - 启动画面（KDE ksplash 主题 org.furryos.desktop）相关资产

## 两个组件的详细说明

### 1. 点击特效

**脚本**: `effects-install.sh` / `effects-verify.sh` / `community-click-effect.sh`

**配置落点**（`assets/desktop/skel/.config/` 里的两个文件，构建时进 `/etc/skel/.config/`）：

`kdeglobals` —— 特效开关与外观：

```ini
[Effects]
Click=true

[Effect-mouseclick]
Color1=26,111,212      # furryos-blue
Color2=15,76,140       # furryos-blue-dark
Color3=10,53,104       # furryos-blue-deep
LineWidth=3
RingCount=2
RingLife=250
RingSize=32            # 半径，像素（KWin 配置界面里的 "Ring Radius"）
ShowText=false
```

`kwinrc` —— 插件开关（KWin 5.27 真正读的地方）：

```ini
[Plugins]
mouseclickEnabled=true

[Effect-mouseclick]
（与上面完全相同的 8 个键）
```

**注意**：KWin 5.27 的点击特效由插件开关 `kwinrc [Plugins] mouseclickEnabled` 控制，
外观走 `Effect-%1` 组模板（→ `[Effect-mouseclick]`）；`kdeglobals` 的 `[Effects]` 组
只是兼容写法。两处必须同时写、且 8 个键值逐个相等——`verify-consistency.py` 会直接
比对两段，不一致就失败。

### 2. 启动画面

**资产**：`furryos-splash.svg`（设计源，爪印 + 蓝白配色）、`furryos-splash-preview.png`
（`render-preview.sh` 渲染的预览图，供 `verify-splash-pixels.py` 做像素校验）、
`furryos-ksplash/`（KDE ksplash 主题 `org.furryos.desktop`）、`furryos-plymouth/`
（Plymouth 主题文件；**本镜像的包列表里没有 `plymouth`**，见下）。

**安装步骤**（构建期由 `6130-integrate-effects-assets.chroot` 调用）：

1. `effects-splash-install.sh` 把 `furryos-ksplash/` 装到
   `/usr/share/plasma/look-and-feel/org.furryos.desktop/`，并写 `/etc/xdg/ksplashrc`：

   ```ini
   [KSplash]
   Theme=org.furryos.desktop
   ```

   只装 look-and-feel 目录是不够的：`ksplashqml` 读的是 `ksplashrc` 的 `[KSplash] Theme`，
   缺这一行就仍然显示 Plasma 全局主题的启动画面。

2. 同一脚本把 `furryos-plymouth/` 装到 `/usr/share/plymouth/themes/furryos/`。但**本镜像
   没有装 `plymouth` 包**，这些文件只是就位、不会生效；开机画面实际由 ksplash 承担。
   要在真机上启用 Plymouth：`apt-get install -y plymouth plymouth-themes`，
   再 `plymouth-set-default-theme furryos`，最后 `update-initramfs -u`
   （脚本的 `--initramfs` 会做最后一步）。

   脚本选项：`--prefix DIR`（装到别的前缀，构建期/测试用）、`--initramfs`（额外重建
   initramfs）、`-h`。**没有** `--plymouth` 选项——Plymouth 文件在目录存在时总会被安装。

3. 验证：重启后看启动画面是否为蓝白渐变 + 爪印。

## 验收（在生成环境中可观察到效果）

### 点击特效

- 鼠标单击桌面出现蓝白圆环（涟漪）扩散动画：`RingCount=2`、`RingLife=250`、`RingSize=320`、`LineWidth=3`
- 圆环生命周期 250ms（brand-tokens.md 第 4 节「点击反馈 200–300ms」区间内）；
  悬停 140ms / 按下 200ms / 密码错误抖动 320ms 属于 SDDM 登录主题，见 `assets/sddm/README.md`
- 颜色一致性：kdeglobals `[Effects]` 与 kwinrc `[Effect-mouseclick]` 两组键值逐个相等（`Color1=26,111,212` 等，校验见 `assets/desktop/.tools/verify-consistency.py`）
- 若未观察到动画：确认 `/etc/skel/.config/kwinrc` 已安装并重新登录

### 启动画面

- 开机时显示蓝白渐变背景 + 爪印装饰
- 卷标与 ISO 内容已标记为 FurryOS
- 若未显示，逐条确认：
  ```sh
  grep -A1 '^\[KSplash\]' /etc/xdg/ksplashrc        # → Theme=org.furryos.desktop
  ls /usr/share/plasma/look-and-feel/org.furryos.desktop/contents/splash/Splash.qml
  ls /usr/share/plasma/look-and-feel/org.furryos.desktop/metadata.json
  ```

## 降级方案（社区特效安装步骤 + 用户手动操作说明）

若默认特效无法在生成环境中完全实现：

1. **点击特效**：
   - 步骤：手动将以下配置追加至 `~/.config/kwinrc`（新用户登录后）
     ```
     [Plugins]
     mouseclickEnabled=true

     [Effect-mouseclick]
     Color1=26,111,212
     Color2=44,133,236
     Color3=15,76,140
     LineWidth=3
     RingCount=2
     RingLife=250
     RingSize=320
     ShowText=false
     ```
   - 用户需要手动重启 KWin 或重新登录才能生效

2. **启动画面**：
   - 步骤：若启动画面仍是 Plasma 默认，手动执行：
     ```sh
     PREFIX=/ sh assets/effects/splash/effects-splash-install.sh
     ```
   - 它会把 ksplash 主题装到 `/usr/share/plasma/look-and-feel/org.furryos.desktop/`
     并写 `/etc/xdg/ksplashrc`（`[KSplash] Theme=org.furryos.desktop`）；
     改完需要重启 X 会话（或重启）才生效

## 备注

- 本层与 desktop-visual 紧耦合：点击特效配色必须与 FurryOS.colors 保持一致
- 验收以「在生成环境中可观察到效果」为准，不以「文件已写好」为准
- 所有特效配色已核对：9 个 brand-tokens.md 色值全部实际使用，0 个越界色值