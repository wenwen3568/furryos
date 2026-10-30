# FurryOS 预置用户配置（/etc/skel）

本目录内容由 live-build 注入到镜像的 `/etc/skel`，因此安装后新建的每一个
账户（含 live 会话用户）在首次登录前就已具备 FurryOS 外观。

## 文件与归属

| 文件 | 作用 | 内容归属 |
|---|---|---|
| `.config/kdeglobals` | 配色方案、强调色、控件样式、图标、壁纸、点击特效（Plasma 侧镜像） | desktop-visual（配色/壁纸）+ motion-effects（点击特效），由 desktop-visual 合并 |
| `.config/kwinrc` | KWin 特效开关 + 点击特效外观（**权威位置**） | motion-effects 提供，desktop-visual 合并 |
| `.config/plasmarc` | Plasma 外壳主题名与默认壁纸主题 | desktop-visual |
| `.config/plasma-org.kde.plasma.desktop-appletsrc` | 桌面容器的壁纸插件与壁纸路径 | desktop-visual |

`.face` / `.face.icon` 由 build-verify 负责（品牌头像），本目录不写。

## 点击特效为什么写两处

KWin 5.27 实际读的是 `kwinrc`，不读 `kdeglobals` 的 `[Effects]`。已用
`strings -el` 对 noble 的 `libkwin.so.5.27.11` 反查确认：

- 该库只在 `Colors:Window` 组读 `kdeglobals`，**完全没有** `Effects` 组字符串
  （`grep -cx "Effects"` → 0）；
- 特效开关走 `Plugins` 组 + `Enabled` 后缀，文件 `kwinrc`；
- 外观组名由模板 `Effect-%1` 生成（即 `Effect-mouseclick`），键
  `Color1/Color2/Color3/LineWidth/RingCount/RingLife/RingSize/ShowText`
  由 `kwin_mouseclick_config.so` 提供（该 KCM 由
  `/usr/share/kwin/builtin-effects/kwin4_effect_mouseclick/metadata.json` 的
  `X-KDE-ConfigModule` 声明），且不显式指定配置文件名，走 KConfig 对
  `kwin` 组件的默认值 `kwinrc`。

因此 `.config/kwinrc` 是开关与外观的**权威位置**；`.config/kdeglobals` 里的
`[Effects]`/`[Effect-mouseclick]` 是给 Plasma 侧工具链的镜像副本，两处的
`[Effect-mouseclick]` 8 个键值完全相同（由 `.tools/verify-consistency.py`
断言）。

## 生效方式

live-build 的 `includes.chroot_after_packages` 阶段把本目录复制为
`/etc/skel`。KDE 会话启动时读取 `~/.config/kdeglobals`，其中：

- `[General] ColorScheme=FurryOS` → 指向 `/usr/share/color-schemes/FurryOS.colors`
- `[Wallpaper] Image=FurryOS` → 指向 `/usr/share/wallpapers/FurryOS/` 壁纸包
- `[Effects] Click=true` → 启用鼠标点击涟漪特效（Plasma 侧镜像；KWin 原生开关在
  `~/.config/kwinrc` 的 `[Plugins] mouseclickEnabled=true`）
- `[Icons] Theme=FurryOS` → 图标主题指向 `/usr/share/icons/FurryOS`
  （`Inherits=breeze,hicolor`，自身不含图标文件，因此只做品牌层不减少覆盖）
- `[KDE] widgetStyle=Breeze` → 控件样式用系统自带 Breeze
  （KDE 的控件样式名首字母大写，`breeze` 会回落默认值）
- `[General] font=Noto Sans,10,…` / `fixed=Hack,10,…` → 钉死正文字体与等宽字体
  （两者都随镜像安装；不写则由 KDE Frameworks 的编译期默认值决定，可能出现
  与其他界面不一致的字体）
- `[Plugins] glideEnabled=true`（在 `kwinrc`）→ 开启窗口打开/关闭动画。
  KWin 5.27 的 `glide` 效果 `EnabledByDefault=false`，不写这一行窗口会「硬弹出」

## 与全局主题的一致性

`assets/desktop/look-and-feel/com.furryos.lookandfeel/contents/defaults` 写的是
同一组值（ColorScheme=FurryOS、widgetStyle=Breeze、`[Icons] Theme=FurryOS`、
`[plasmarc][Theme] name=furryos`、Image=FurryOS、font/fixed、KSplash）。
两条路径（全局主题 + /etc/skel）指向相同结果，因此无论用户在「首次登录」还是
之后手动切换全局主题，外观都不会分裂。

> t5 修正：这里原来是 `[plasmarc][Theme] name=breeze`。Plasma 5.27 **没有**
> 名为 `breeze` 的桌面主题（`plasma-apply-desktoptheme breeze` 会报
> "Could not find theme"，合法值是 air/default/breeze-dark/breeze-light/furryos/
> oxygen），于是面板静默回落到 Breeze，而窗口已经是 FurryOS —— 正是「一半
> FurryOS 一半 Breeze」的来源。现改为 `name=furryos`，并由
> `tools/verify-visual.sh` 在沙箱里真跑 `plasma-apply-lookandfeel` 复核 KDE
> 自己写出的 `kdedefaults/plasmarc`。

> 另注：`glide` 不能写在全局主题里 —— 实测 `plasma-apply-lookandfeel` 只应用
> `[kwinrc][org.kde.kdecoration2]`，`[kwinrc][Plugins]` 会被丢弃，所以它只在
> `/etc/skel/.config/kwinrc` 里设置。
