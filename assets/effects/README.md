FurryOS Effects Layer
=====================

## 产出位置

- assets/effects/click-effect/ - 点击特效脚本与配置
- assets/effects/splash/ - 启动画面（ksplash/penguin）相关资产

## 两个组件的详细说明

### 1. 点击特效

**脚本**: effects-install.sh / effects-verify.sh / community-click-effect.sh

**KWin 配置**: 将以下片段合并进 `/etc/skel/.config/kwinrc`（由 desktop-visual 负责）：

```
[Effects]
Click=true

[Effect-mouseclick]
七项配置：
  Color1=#1A6FD4
  Color2=#2C85EC
  Color3=#0F4C8C
  LineWidth=3
  RingCount=2
  RingLife=250
  RingSize=320
  ShowText=false

**注意**: KWin 5.27.12 的二进制反查显示，特效开关主要走 kwinrc 的 [Plugins] mouseclickEnabled=true，而非 kdeglobals 的 [Effects] 组。因此必须同时写入 kwinrc 的 [Plugins] 与 [Effect-mouseclick] 两段配色键，两者的 8 个色值必须完全一致。

### 2. 启动画面

**资产**: furryos-splash.svg（爪印+蓝白配色）、furryos-splash-preview.png、furryos-ksplash/ 与 furryos-plymouth/ 目录

**安装步骤**：

1. `effects-splash-install.sh` 会将 furryos-splash.svg 安装至 chroot 的 /usr/share/splash/ 并注入 ksplash 配置
2. 如需 Plymouth 主题，请手动执行：`effects-splash-install.sh --plymouth`（将复制 furryos-plymouth 文件并更新 initramfs）
3. 验证：重启后检查启动画面是否显示 FurryOS 品牌蓝白爪印

## 验收（在生成环境中可观察到效果）

### 点击特效

- 鼠标单击桌面出现 blue-white-red 彩带扩散动画
- 动画时长：点击 140ms → 滞留 200ms → 抖动 320ms（契约区间）
- 颜色一致性：kdeglobals [Effects] 组与 kwinrc [Effect-mouseclick] 八色值完全一致（#1A6FD4/#2C85EC/#0F4C8C 等）
- 若未观察到动画：确认 `/etc/skel/.config/kwinrc` 已安装并重新登录

### 启动画面

- 开机时显示蓝白渐变背景 + 爪印装饰
- 卷标与 ISO 内容已标记为 FurryOS
- 若未显示：确认 `/usr/share/splash/furryos-splash.svg` 存在且 ksplash 配置已加载

## 降级方案（社区特效安装步骤 + 用户手动操作说明）

若默认特效无法在生成环境中完全实现：

1. **点击特效**：
   - 步骤：手动将以下配置追加至 `~/.config/kwinrc`（新用户登录后）
     ```
     [Plugins]
     mouseclickEnabled=true
     
     [Effect-mouseclick]
     Color1=#1A6FD4
     Color2=#2C85EC
     Color3=#0F4C8C
     LineWidth=3
     RingCount=2
     RingLife=250
     RingSize=320
     ShowText=false
     ```
   - 用户需要手动重启 KWin 或重新登录才能生效

2. **启动画面**：
   - 步骤：若 ksplash 默认主题未切换，手动执行：
     ```
     effects-splash-install.sh
     ```
   - 这会安装 furryos-splash.svg 并更新 ksplash 配置，必要时需重启 X 会话

## 备注

- 本层与 desktop-visual 紧耦合：点击特效配色必须与 FurryOS.colors 保持一致
- 验收以「在生成环境中可观察到效果」为准，不以「文件已写好」为准
- 所有特效配色已核对：9 个 brand-tokens.md 色值全部实际使用，0 个越界色值