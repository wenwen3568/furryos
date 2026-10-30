# FurryOS 代码审核报告（t1 / 静态审核）

- 审核对象：`/root/furryos`（HEAD `2da8add`，分支 `main`）
- 审核方式：只读静态审核 + 可执行验证（shell 语法检查、qmllint、qmlscene 离屏实例化、Python 校验脚本正负向对照、mtools 复现）
- 审核范围：`build/config/hooks/**`、`tools/*.sh`、`assets/sddm/furryos/**`、`assets/desktop/.tools/verify-*.py`、`assets/effects/**` 校验脚本、`README.md` / `docs/**` / 各层 `README.md`
- 约束：本报告是唯一写入文件；未修改任何被审文件（`git status --short` 中 `docs/REVIEW.md` 为本次新增；其余未跟踪项 `docs/TEST-REPORT.md`、`build/config/assets/effects/README.md` 非本次审核产生）
- 严重度定义：**blocker** 会破坏产物/启动/数据；**high** 使契约要求整体落空或使构建不可复现；**medium** 局部功能失效、校验失效或文档误导；**low** 卫生问题/死代码/注释陈旧
- 后续状态：本报告保留 t1 的历史发现；修复见 `docs/FIXES.md`、`docs/FIXES-ROUND2.md`，最终构建与虚拟机验收见 `docs/BUILD-LOG.md`、`docs/VM-VERIFY.md`

## 0. 结论摘要

| 严重度 | 数量 | 要点 |
|---|---|---|
| blocker | 1 | `8000-brand-boot-menu.binary` 覆写 ESP 里的 grub 引导桩，破坏 UEFI 启动 |
| high | 7 | 6110/6120/6130 静默 `exit 0`；6120 吞掉安装器失败；启动画面（ksplash/plymouth）完全未接入构建；构建依赖未入库的工具链；文档给出的 os-release「修复」命令会清空文件；`build/config/assets` 重复入库；BUILD.md §2 注入方式与实现矛盾 |
| medium | 13 | 校验脚本空断言/弱断言、探针逻辑不统一、重跑嵌套、PNG 解析健壮性、文档命令跑不通、包名错误等 |
| low | 13 | 死代码、陈旧注释、`.pyc` 入库、`/etc/skel/README.md` 泄漏到新用户家目录、文档小错等 |

历史问题核实（详见 §5）：**FURRYOS_ASSETS 与 6000 STAGING 已一致**（均为 `/opt/furryos/assets`）；**6110/6120/6130 在资产目录缺失时是 `exit 0`（静默降级）**，与 6000/6010 的 `exit 1` 不统一；**6010 的本地探针未与 6110/6120/6130 统一**。

---

## 1. blocker

| 严重度 | 文件:行 | 问题 | 影响 | 建议修法 | 复现方式 |
|---|---|---|---|---|---|
| blocker | `build/config/hooks/normal/8000-brand-boot-menu.binary:89-109`（`mdel` 在 :99，`mcopy` 在 :100） | 钩子假设 `boot/grub/efi.img` 内嵌的是 ISO `grub.cfg` 的**副本**（:31-37 注释），于是先 `mdel` 删掉 ESP 内的 `::boot/grub/grub.cfg`，再把整份 ISO `grub.cfg` `mcopy` 进去。实际 live-build 在 ESP 内放的是**3 行引导桩**：`search --set=root --file /.disk/info` / `set prefix=($root)/boot/grub` / `configfile ($root)/boot/grub/grub.cfg`（`tools/lbroot/usr/lib/live/scripts/build/binary_grub-efi:232-235`，上游同一份 `/usr/lib/live/scripts/build/binary_grub-efi`）。桩的唯一作用就是把 `$root` 从 ESP 重定位到 ISO 分区；被整份配置替换后，`source /boot/grub/config.cfg`（`tools/rootfs/usr/share/live/build/bootloaders/grub-pc/grub.cfg:1`）与 `linux /live/vmlinuz-*` 都相对 ESP 解析而找不到文件 | UEFI 启动：菜单可能出现但任何条目都无法引导（`file not found`），即 ISO 在 UEFI 下不可启动；更坏的情况是 `mdel` 已执行而 `mcopy` 因 ESP 空间不足失败（ESP 只按桩大小预留，见 `binary_grub-efi:245-262`），此时 ESP 内**没有任何 grub.cfg**，直接落到 `grub>` 提示符，而钩子只打一条 WARNING（:104）后构建继续，产物"构建成功但 UEFI 不可启动" | 删除整段 efi.img 再注入逻辑（:89-109）。桩已经 `configfile` 到 ISO 的 `/boot/grub/grub.cfg`，只要保留 §「grub」小节对 `binary/boot/grub/grub.cfg` 的 sed（:70-78），UEFI 与 BIOS 都会看到 FurryOS 文案。若确需改 ESP，只能改桩本身（例如给桩里的 label 加注释），绝不能替换成整份配置 | 见 §R1（mtools 复现，实测替换后 ESP 内 `grub.cfg` 内容变为 `source /boot/grub/config.cfg` + menuentry） |

---

## 2. high

| 严重度 | 文件:行 | 问题 | 影响 | 建议修法 | 复现方式 |
|---|---|---|---|---|---|
| high | `6110:30-34`、`6120:33-37`、`6130:55-59`（对照 `6000:51-56`、`6010:64-69`） | 资产层目录缺失时，6110/6120/6130 走 `furryos_warn …; exit 0`（静默降级），而 6000 与 6010 是 `exit 1`（fail-fast）。历史 bug（6000 曾 `exit 0` 导致无品牌 ISO 仍"构建成功"，见 `furryos-common.sh:27-33` 注释）在 6110/6120/6130 仍然存在 | 只要 `tools/sync-assets.sh` 漏跑或某个层目录被删，桌面/登录/动效三层会全部静默跳过，ISO 仍报构建成功、无任何品牌，验收只能在启动后才发现。三处判定同一事实却给出三种结果，后续无法靠钩子自检兜底 | 统一策略：由 6000 作为唯一 fail-fast 点（它已经断言 5 个层目录齐全），6110/6120/6130 的"目录缺失"分支改为 `furryos_need_file`/`exit 1`；确实允许降级的子项（如 plymouth 控制文件缺失）保留 warn | `grep -n 'exit 0' build/config/hooks/normal/6*.chroot`；对照 `grep -n 'exit 1' build/config/hooks/normal/6000-*.chroot build/config/hooks/normal/6010-*.chroot` |
| high | `6120:68-78` | 层自带安装器 `install-sddm-theme.sh` 失败时用 `\|\| furryos_warn` 吞掉，钩子随后只做"存在性"提示（:104-117），不会失败 | 主题复制失败/`/etc/sddm.conf` 未写入时构建照样成功，登录界面回退到 Breeze，验收项"登录界面为 FurryOS 主题"无法在构建期被发现 | 安装器非零退出应 `exit 1`；末尾的 `[ -f /usr/share/sddm/themes/furryos/Main.qml ]`、`grep '^Current=furryos' /etc/sddm.conf` 应作为断言（`furryos_need_file` 风格）而非 `furryos_warn` | `sed -n '68,118p' build/config/hooks/normal/6120-integrate-sddm-assets.chroot` |
| high | `6130:117-145`（对照 `assets/effects/splash/effects-splash-install.sh`、`build/config/package-lists/furryos-desktop.list.chroot`） | 启动画面整体未接入构建：① `effects-splash-install.sh`（唯一同时安装 plymouth + ksplash 的脚本）**没有任何钩子调用**（`grep -rn effects-splash-install build/config/hooks` 无命中）；② `furryos-ksplash`（`contents/splash/Splash.qml` + `metadata.json` + `contents/defaults`，共 5 个文件）从未被安装，登录后无 KSplash；③ plymouth 不在包列表（`grep -i plymouth package-lists/*` 无命中），即使主题被复制也不会生效 | README:38 与 `assets/effects/README.md` 宣称的"启动画面（plymouth / ksplash）"在 ISO 中一条都不存在；契约（`docs/CONTRACTS.md` 成员四"启动画面：蓝白底 + 爪印"）整体落空 | 二选一：把 plymouth 加进包列表并在 6130 调用 `effects-splash-install.sh`（含 `update-initramfs` 与 `plymouthd.conf` 的 `DefaultTheme`），或明确降级并在 README/BUILD.md 写清"本镜像不含启动画面"。ksplash 部分与 plymouth 无关，应当无条件安装：`cp -a ${SRC}/splash/furryos-ksplash/. /usr/share/plasma/look-and-feel/org.furryos.desktop/` 并断言 `contents/splash/Splash.qml` 存在 | 见 §R2 |
| high | `docs/BUILD.md:179` | 文档给出的 os-release "手动修复"命令 `sudo bash -c 'cat /usr/lib/os-release > /etc/os-release && ln -sf ../usr/lib/os-release /etc/os-release'` 是自毁命令：`/etc/os-release` 是指向 `/usr/lib/os-release` 的符号链接，重定向先截断目标，`cat` 再读已被截断的同一 inode，结果把 `/usr/lib/os-release` 清空成 0 字节 | 按文档排障的用户会把系统身份文件清空（`NAME=`/`PRETTY_NAME=` 全丢），`verify-identity.sh` 与 `hostnamectl`/KInfoCenter 全部失效，且与"修复"意图完全相反 | 改为 `sudo ln -sfn ../usr/lib/os-release /etc/os-release`；若必须写内容，用 `install -m644 /tmp/os-release.new /usr/lib/os-release`（先写临时文件再 rename），禁止 `cat A > A` | 见 §R3（实测 41 字节 → 0 字节） |
| high | `tools/lb.sh:27-50`、`.gitignore:33-36`、`docs/BUILD.md`（全文） | 构建入口依赖未入库的工具链：`tools/lb.sh` 需要 `tools/rootfs/usr/bin/lb`、`tools/rootfs/usr/share/debootstrap`、`tools/lbroot/usr/lib/live`、`tools/shim/{cat,mount}`；`.gitignore:33-36` 把这些目录全部排除，且注释称"由 BUILD.md 说明的方法重新获取"，但 `grep -n 'rootfs\|lbroot\|shim\|debootstrap' docs/BUILD.md` **零命中**（BUILD.md 完全没有获取方法）。更关键：`tools/shim/mount`（mtab 只读绕法，`lb.sh` 头部注释 :9-25 依赖它）**没有任何入库脚本生成它**，`lb.sh` 自己只生成 `shim/cat`（:37-47） | 全新 clone 无法复现构建：`lb build` 在第一个 `mount` 调用即以 exit 16 失败（mtab 只读）；且 `tools/lb.sh:27` 注释写"live-build 解包到 tools/rootfs/usr/lib/live"，实际用的是 `tools/lbroot`（:50），进一步误导排障 | ① 在 BUILD.md 增加"工具链获取"一节（`apt-get download live-build debootstrap ubuntu-keyring` + `dpkg-deb -x` 到 tools/rootfs、tools/lbroot，并说明为何需要两份）；② 把 `shim/mount`、`shim/cat` 生成逻辑写进入库脚本（例如 `tools/make-shim.sh`）或直接入库（它们是纯文本，无密钥）；③ 修正 `lb.sh:27` 注释路径 | `git check-ignore -v tools/rootfs/usr/bin/lb tools/lbroot/usr/lib/live tools/shim; grep -n 'rootfs\|lbroot\|shim' docs/BUILD.md`（无输出）；`ls -l tools/rootfs/usr/bin/lb tools/shim/mount`（存在但未跟踪） |
| high | `build/config/assets/**`（159 个文件，1.5 MB） | `tools/sync-assets.sh` 的**产物**被整体入库（`git ls-files build/config/assets \| wc -l` = 159），与源 `assets/` 内容逐字节相同（`diff -rq assets build/config/assets` 无差异），占已跟踪文件数（381）的 42%；副本与源的关系已经出现不一致：`assets/effects/README.md` 已入库，其副本 `build/config/assets/effects/README.md` 却在磁盘上存在而未入库（`git ls-files build/config/assets/effects/README.md` 无输出），说明这份"生成物"靠人工维护必然漂移 | ① 仓库体积翻倍，与 README:90-91"仓库保持在数 MB 量级/只包含源码与配置"的定位不符；② 两份副本可静默漂移：修 fixer 改 `assets/` 后若忘记跑 `sync-assets.sh`，钩子读到的仍是旧副本，而 `git status` 干净、`git diff` 看不到任何问题；③ 每次资产变更都要提交一份二进制副本（壁纸 PNG、spinner 帧），review 噪声大 | 将 `build/config/assets/` 加入 `.gitignore` 并在 README/BUILD.md 把 `tools/sync-assets.sh` 写成构建的**必需**前置步骤（`6000` 已经会在缺目录时 `exit 1`，安全）；同时 `git rm -r --cached build/config/assets` 并保留工作区文件 | `git ls-files build/config/assets \| wc -l; diff -rq assets build/config/assets; du -sh assets build/config/assets` |
| high | `docs/BUILD.md:26-42`（:32-35 代码块，:42） | §2「资产注入」给出的注入方式与实现完全不符：让用户创建 `build/config/hooks/9999-furryos-sddm.chroot` 并调用 `/root/furryos/assets/sddm/install-sddm-theme.sh`。chroot 内 `/root/furryos/...` 不存在（`lb chroot_hooks` 只 bind-mount `config/` 到 `/live-build/config`，见 `furryos-common.sh:20-33`），且 9999 排在 `8990-furryos-cleanup` 之后（后者已删除 `/opt/furryos/assets`）；`9999-*` 钩子也不存在于仓库 | 照文档操作会得到一个必然失败（或"看似成功但什么都没装"）的钩子；同时 §2 仍写着"其余各层的注入方式：由 build-verify 补充"（:42）和"构建交付层正在搭建…骨架"（:6），与已存在的 6000/6010/6110/6120/6130 钩子矛盾，读者无法判断哪份文档才是权威 | 重写 §2：直接指向 `build/config/hooks/normal/{6000,6010,6110,6120,6130}`，说明"资产源 `assets/` → `tools/sync-assets.sh` → `config/assets/` → 6000 暂存 `/opt/furryos/assets` → 各层钩子注入"这条真实链路；删除 9999 示例与"由 build-verify 补充"的占位语 | `sed -n '26,44p' docs/BUILD.md`；`ls build/config/hooks/normal/ \| grep -c 9999`（0） |

---

## 3. medium

| 严重度 | 文件:行 | 问题 | 影响 | 建议修法 | 复现方式 |
|---|---|---|---|---|---|
| medium | `tools/verify-identity.sh:212-221`、`:177-195` | 存在"文件不存在即通过"的空断言：`grep -v … "${SIM}/etc/update-motd.d/00-header" 2>/dev/null \| grep -qi ubuntu` 在文件缺失时两条 grep 都失败，`if` 为假 → 走 `ok "00-header 已替换为 FurryOS 版…"`。同样的模式用于 `10-help-text`、`issue`、`motd`、`legal`（经 `issue_usertext()`） | 任何被删除/漏装的资产都会被报告为"已替换"，校验给出假 PASS；而钩子 6010 对同名文件缺失只 `furryos_warn`（:90、:100），两处弱化叠加后整条链路可以"全绿但无内容" | 每个断言前先断言存在：`[ -f "${SIM}/etc/update-motd.d/00-header" ] \|\| bad "00-header 缺失"`，或统一封装 `need_file`；把"文件存在"作为独立断言计数 | 见 §R4（最小复现：文件不存在仍打印 ok 分支） |
| medium | `tools/verify-identity.sh:340-342` | 汇总只看 `FAIL -eq 0`，不断言实际执行的断言数（脚本有 53 个 `ok`/`bad` 调用点，当前执行 33 个，README:86/172 与 BUILD.md:196 都宣称"33 项"） | 只要某个条件分支不再执行（例如上面那些空断言的文件消失、循环体跳过），PASS 数会从 33 悄悄下降，退出码仍为 0，"33 项断言"的承诺无法被自动发现 | 增加期望计数：`[ "${PASS}" -eq 33 ] \|\| { bad "断言数 ${PASS} != 33（有检查被跳过）"; }`；或把断言注册成列表按名执行并核对条数 | `grep -cE '\bok "\|\bbad "' tools/verify-identity.sh`（53）；`bash tools/verify-identity.sh \| tail -3`（PASS=33 FAIL=0） |
| medium | `tools/verify-identity.sh:100`（对照 `6010:219-231`） | 校验脚本模拟的注入行为与真实钩子不一致：`[ -r "${BRAND}/paw.png" ] && install_into … furryos-logo.png` 会安装 `furryos-logo.png`，而 6010 **从不安装**任何 `furryos-logo.png`（只用 `identity/furryos-logo.svg` 或 `brand/paw.svg`，见 6010:219-231）。该 png 又恰好能满足 `:257-258` 的 `LOGO=` 解析断言 | 校验可以在"真实钩子不会产生的文件布局"上通过：例如 `assets/identity/furryos-logo.svg` 被误删时，模拟仍因 png 存在而报 LOGO 可解析，与产物实际状态不符 | 让模拟严格照抄 6010 的分支顺序（svg → brand/paw.svg，不引入 png）；若确实需要 png 兜底，则在 6010 里同步实现 | `grep -n 'paw.png' tools/verify-identity.sh`（:100）；`grep -n 'paw\.' build/config/hooks/normal/6010-integrate-identity-assets.chroot`（仅 paw.svg，:224-228） |
| medium | `assets/desktop/.tools/verify-consistency.py:186-201` | 对比度"校验"与注释自相矛盾且不校验注释声称的结论：注释写 "what matters is that every pair stays AAA (>= 7:1)"，代码却是 `ok = got >= claimed - 0.3`，而 `claimed` 是**硬编码**在脚本里的数字，不读 `assets/brand/brand-tokens.md`。其中 `furryos-white on furryos-blue` 实测 4.92:1（AAA 需 ≥7），脚本仍判 OK | ① 达不到 AAA 的组合被注释描述为 AAA（brand-tokens.md 本身标的是 AA，注释与文档冲突）；② 文档里的对比度数字改动后脚本仍按旧硬编码值判定，无法发现漂移 | 要么解析 brand-tokens.md 的 claimed 值再比较（真断言），要么把断言改成明确的阈值 `got >= 4.5`（AA）并删掉 AAA 说法；注释与阈值必须一致 | `cd assets/desktop && python3 .tools/verify-consistency.py \| sed -n '/WCAG/,/shipped/p'`（输出 claimed 4.7 / computed 4.92 / OK） |
| medium | `assets/desktop/.tools/verify-wallpaper.py:36-52`、`:55-105`、`:68` | ① 注释称 PAD/TOES/INNER_TOE_GAP "taken verbatim from assets/brand/paw.svg"，实际是硬编码常量，脚本从不解析 `paw.svg`——爪印 SVG 改了脚本仍按旧几何判定；② 自带 PNG 解码器只支持 `ct ∈ {0,2,4,6}` 且把 `ct=3`（调色板）映射成 `nch=1`，随后 `px()` 直接按 RGB 取字节 → 调色板 PNG 会被读成乱码/断言崩溃；③ `:68 assert inter == 0 and bd in (8,16)` 抛出未捕获的 `AssertionError`，失败表现为 traceback 而不是可读的 FAIL 摘要 | 壁纸若被重新生成为索引色 PNG（ImageMagick 默认对少色图会这么做），校验会崩溃或给出无意义的通过/失败；几何断言无法发现"爪印 SVG 与壁纸不一致"这类真实回归 | 用 `xml.etree` 解析 `paw.svg` 取几何；PNG 分支支持 `ct=3`（读 PLTE）或先断言 `ct in (2,6)` 并给出清晰错误；把 `assert` 换成 `failures.append(...)` + 正常返回 1 | 见 §R5（`convert -size 1920x1080 xc:'#1A6FD4' wallpaper.png` 触发 `AssertionError`） |
| medium | `build/config/hooks/normal/6010-integrate-identity-assets.chroot:41-69` | 6010 用私有双候选探针（`/opt/furryos/assets/identity`、`/live-build/assets/identity`）并自带 `exit 1`，而 6110/6120/6130 直接用 `${FURRYOS_ASSETS}`。注释（:41-49）还声称"furryos-common.sh 历史上定义 FURRYOS_ASSETS=/live-build/assets"，但当前 `furryos-common.sh:38` 已是 `/opt/furryos/assets`（历史 bug 已修） | 同一事实（资产在哪）有 2 套实现，其中 6010 的 `/live-build/assets/identity` 永远不存在（`chroot_hooks` 只挂 `config`），是死分支；注释描述的"当前风险"已不存在，误导后续维护者以为 common.sh 仍不可信 | 6010 改为 `SRC="${FURRYOS_ASSETS}/identity"`，与 6110/6120/6130 一致，并把缺失处理统一为 `exit 1`（见 §2 第一条）；同步删除 :41-49 的过时说明 | `grep -n 'FURRYOS_ASSETS=' build/config/hooks/normal/furryos-common.sh`（:38 = `/opt/furryos/assets`）；`sed -n '39,69p' build/config/hooks/normal/6010-integrate-identity-assets.chroot` |
| medium | `build/config/hooks/normal/6000-stage-furryos-assets.chroot:62-71` | 重复执行不安全：`cp -a "${SOURCE}/${LAYER}" "${STAGING}/${LAYER}"` 在目标已存在时会把源目录**嵌套**进去（生成 `/opt/furryos/assets/identity/identity/…`）。`lb chroot_hooks` 可被单独重跑（钩子失败后修复再跑是常规操作），此时 8990 的清理还没执行 | 重跑后暂存目录结构错乱、体积翻倍；后续 6010/6110 仍能找到 `${STAGING}/${LAYER}` 所以不会报错，问题被完全掩盖（只有 8990 清理时才消失） | 复制前 `rm -rf "${STAGING}/${LAYER}"`，或用 `cp -a "${SOURCE}/${LAYER}/." "${STAGING}/${LAYER}/"`（先 `install -d`） | 见 §R6（实测生成 `identity/identity`） |
| medium | `docs/BUILD.md:94`、`:98`、`:107`、`:309`；`README.md:201` | 包名错误：文档反复让用户 `apt-get install qt5-image-formats`，而该名字在 Debian/Ubuntu 家族里不存在（正确包名是 `qt5-image-formats-plugins`，仓库自己的 `build/config/package-lists/furryos-desktop.list.chroot:76` 用的就是正确名）。:309 还有一句语义不明的"`qt5-image-formats` 在 noble 已移除至源包" | 用户按文档排障时 `apt-get install` 直接报 `Unable to locate package`，而这一步正是文档标记为"最难查的失败模式（爪印静默消失）"的修复手段 | 全文替换为 `qt5-image-formats-plugins`；:309 改写为"该插件在 noble 由 `qt5-image-formats-plugins` 提供（`qt5-image-formats` 只是源码包名）" | `apt-cache search --names-only 'qt5-image-formats'`（只有 `qt5-image-formats-plugins`、`…-plugin-pdf`）；`grep -n 'qt5-image-formats' README.md docs/BUILD.md build/config/package-lists/*` |
| medium | `docs/BUILD.md:280`、`docs/CONTRACTS.md:32` | 引用了不存在的 `docs/BUILD-LOG.md`（契约甚至把它列为成员五的交付物） | 用户/验收方按图索骥找不到构建日志；契约交付物缺失 | 要么补上构建日志（可脱敏后入库），要么从 BUILD.md/CONTRACTS.md 删除该引用，改为指向 `docs/REVIEW.md`/实际存在的证据文件 | `ls docs/BUILD-LOG.md`（No such file） |
| medium | `docs/BUILD.md:308` | 提到"配合 6200 钩子在 chroot_install-packages 前重写包名"，仓库里不存在 6200 钩子（`ls build/config/hooks/normal \| grep 6200` 为空） | 读者会以为内核包名重写已由某个钩子实现，实际只靠 `build/config/chroot:25` 的 `LB_LINUX_PACKAGES="linux-generic"`；排障方向错误 | 改为描述真实机制（`config/chroot` 里 `LB_LINUX_PACKAGES`/`LB_LINUX_FLAVOURS_WITH_ARCH` 的取值），删除 6200 的说法 | `ls build/config/hooks/*/ \| grep -i 6200`（无）；`grep -n 'LINUX' build/config/chroot`（:22、:25） |
| medium | `docs/BUILD.md:301-302`、`assets/sddm/README.md:379-380` | 两条"环境限制"与本机事实不符：① 称 `/usr/bin/qmllint` 是"qtchooser 符号链接，指向不存在的 `/usr/lib/qt5/bin/qmllint`"——该文件实际存在且可执行（`qmllint 1.0` 正常输出）；② 称"宿主无 GL 上下文 → 无法用 qmlscene 真实渲染 QML 场景"——`QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software qmlscene` 可以完整加载 `Main.qml`（无任何 QML 警告），可做真实绑定/动画验证 | 文档把可用工具说成不可用，导致后续验证只能退化为静态断言；同时"无法渲染"被当作既定限制写进报告，掩盖了本可执行的运行时验证手段 | 用 `QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software /usr/lib/qt5/bin/qmlscene` 替代"无法渲染"的说法，并在 `docs/sddm-verification/` 补一条可复跑的离屏运行证据 | 见 §R7（qmllint 正常、qmlscene 离屏加载成功、shake 实测） |
| medium | `docs/BUILD.md:227-229` | 排障预期与 6110 实现不符：文档要求 `ls /usr/share/wallpapers/FurryOS/` 看到 `wallpaper.png` 与 `wallpaper.svg`，但 6110 装的是 `contents/images/1920x1080.png`、`contents/images/1920x1080.svg` 与 `metadata.desktop`（6110:51-54，走 `assets/desktop/wallpapers` 分支），顶层没有 `wallpaper.png` | 按文档检查的用户会认为壁纸安装失败，进而执行不必要的"修复"，可能反而破坏 `metadata.desktop` | 把预期改为 `ls /usr/share/wallpapers/FurryOS/{metadata.desktop,contents/images/1920x1080.png}` | `sed -n '46,80p' build/config/hooks/normal/6110-integrate-desktop-assets.chroot`；`find assets/desktop/wallpapers -type f` |
| medium | `assets/effects/README.md:40-41`、`:57`、`:82-86` | 文档描述的脚本行为与脚本实现不符：① 称 `effects-splash-install.sh --plymouth` 存在——脚本参数只有 `--prefix`/`--initramfs`/`-h`，`--plymouth` 会 `exit 1`（实测）；② 称脚本把 `furryos-splash.svg` 装到 `/usr/share/splash/` 并"注入 ksplash 配置"——脚本只写 `/usr/share/plymouth/themes/furryos/` 与 `/usr/share/plasma/look-and-feel/org.furryos.desktop/`，全文没有 `/usr/share/splash` | 用户执行文档命令得到 `ERROR: unknown option: --plymouth`；按"确认 `/usr/share/splash/furryos-splash.svg` 存在"排障永远不可能成功 | 按脚本真实行为重写该节（`--prefix`/`--initramfs`、两个安装目标），删除 `/usr/share/splash` 相关描述 | `cd assets/effects/splash && ./effects-splash-install.sh --plymouth --prefix /tmp/x; echo $?`（→ 1）；`grep -rn 'usr/share/splash' assets/effects`（仅 README 命中） |

---

## 4. low

| 严重度 | 文件:行 | 问题 | 影响 | 建议修法 | 复现方式 |
|---|---|---|---|---|---|
| low | `README.md:19` | "KDE Plasma 5.27.12" 与仓库内其它两处证据冲突：`package-lists/furryos-desktop.list.chroot:26`（`kde-style-breeze_5.27.11-0ubuntu3`）、`verify-consistency.py:152`（`libkwin.so.5.27.11`）。仓库内自相矛盾，需统一为 noble 实际版本 | 版本号是可验收事实项，写错会被当作"文档造假" | 按 noble 实际包版本统一（仓库内两处旁证均为 5.27.11），或改成不写小版本（"KDE Plasma 5.27"） | `grep -rn '5\.27\.' README.md build/config assets/desktop/.tools` |
| low | `docs/BUILD.md:284` | ISO 卷标写成 `FURRYOS`，与 `build/config/binary` 的 `LB_ISO_VOLUME="FurryOS"`、README:23/217 的 `FurryOS` 不一致 | 验收清单与实际参数冲突，验收时无法判定哪个正确 | 统一为 `FurryOS`；若指 ISO9660 卷标被大写化，需在括号里说明 | `grep -n 'LB_ISO_VOLUME' build/config/binary`；`grep -n 'FURRYOS' docs/BUILD.md` |
| low | `build/config/hooks/normal/8000-brand-boot-menu.binary:115-118` | 死代码：`if [ -f /tmp/furryos-iso-volume-check ]` 块内只有 `:`，且 `/tmp/furryos-iso-volume-check` 无人创建（注释说要"断言 LB_ISO_VOLUME"，实际什么也没断言） | 注释宣称的"构建期断言卷标"不存在，回归不会被发现 | 真正实现断言（例如在 binary 阶段检查 `binary/.disk/info`/ISO 参数）或删除该块与注释 | `sed -n '111,120p' build/config/hooks/normal/8000-brand-boot-menu.binary`；`grep -rn 'furryos-iso-volume-check' . --exclude-dir=.git` |
| low | `build/config/hooks/normal/8990-furryos-cleanup.chroot:31`、`:34` | 死代码/无效操作：① `rm -f /etc/sddm.conf.pre-furryos`——全仓库没有任何地方创建该备份（`grep -rn 'pre-furryos' .` 只命中本行与注释）；② `rm -rf /live-build`——`/live-build/config` 是只读 bind mount（`chroot_hooks` 里 `mount -o remount,ro,bind`），删除必然失败，被 `\|\| true` 吞掉；若哪天真的成功，后续 `hooks/live/*.chroot`（0010/0050/0100）就再也 source 不到 `furryos-common.sh` | 让人误以为清理与挂载点回收已处理；维护者改动 live/ 钩子顺序时可能踩坑 | 删除这两行与相关注释（挂载点由 `chroot_hooks` 自己 `umount`+`rmdir`） | `grep -rn 'pre-furryos' . --exclude-dir=.git`；`sed -n '45,80p' tools/lbroot/usr/lib/live/scripts/build/chroot_hooks` |
| low | `build/config/hooks/normal/6130-integrate-effects-assets.chroot:13-14`、`:42-45`、`:120-121` | 注释与资产现状矛盾：称 `furryos-ksplash/`"(currently empty)"（实际 5 个文件）、称 `furryos-plymouth/`"has NO .plymouth file"（实际 `furryos.plymouth`/`furryos.script`/`furryos.grub` 都在）。因此 :127 的 `ls *.plymouth` 分支**现在会命中**，钩子会为一个未安装的 plymouth 复制主题并执行 `update-alternatives --install`（:133-139），与注释描述的"什么都不做"完全相反 | 维护者按注释理解行为会误判；`update-alternatives` 会为不存在的 plymouth 留下 alternative 项 | 先定策略（见 §2 启动画面条目）：要 plymouth 就装包并调用层脚本，不要就删掉整段 plymouth 处理与相关注释 | `ls assets/effects/splash/furryos-plymouth/*.plymouth assets/effects/splash/furryos-ksplash/contents/splash/Splash.qml`；`sed -n '117,146p' build/config/hooks/normal/6130-integrate-effects-assets.chroot` |
| low | `build/config/hooks/normal/6000-stage-furryos-assets.chroot:75-88` | 缺失层被重复计数：第一轮循环每缺一层 `MISSING+1`，第二轮"暂存后断言"对同一缺失层再 `+1`，实测 5 层全缺时报"10 asset layer(s) missing" | 错误信息误导排障（数量翻倍，看着像两层问题） | 第二轮只在"第一轮成功复制但暂存后仍不存在"时计数，或直接统计 `MISSING` 的去重集合 | 见 §R8 |
| low | `assets/desktop/skel/README.md` → `build/config/hooks/normal/6110-integrate-desktop-assets.chroot:99-102` | `furryos_install_dir "${SRC}/skel" /etc/skel` 会把 `assets/desktop/skel/README.md`（2.9 KB 的开发说明）一并装进 `/etc/skel/`，于是每个新用户家目录都会多出一份 `~/README.md` | 新用户首次登录即看到一份构建方内部说明文件，观感/合规都不合适 | 把该 README 移出 `skel/`（例如 `assets/desktop/skel.README.md`），或在 6110 里用显式白名单复制 `.config/` 子树 | `ls assets/desktop/skel/README.md`；`grep -n 'furryos_install_dir "${SRC}/skel"' build/config/hooks/normal/6110-integrate-desktop-assets.chroot` |
| low | `assets/sddm/furryos/metadata.desktop:11`、`:12`、`:15` | 元数据指向不存在的资源：`Screenshot=preview.png`（主题目录无此文件）、`TranslationsDirectory=translations`（无此目录）、`Website=https://github.com/sddm/sddm`（上游 SDDM 项目地址，不是本主题的地址） | SDDM 主题选择器显示破图；元数据把上游项目写成本主题官网，与"品牌合规"章节的自我要求不一致 | 补一张真实 `preview.png`（可由离屏渲染生成）或删除该键；删除 `TranslationsDirectory` 或建目录；`Website` 改为 FurryOS 项目地址 | `ls assets/sddm/furryos/`；`grep -n 'Screenshot\|Website\|Translations' assets/sddm/furryos/metadata.desktop` |
| low | `assets/desktop/.tools/__pycache__/pngsample.cpython-311.pyc`（已入库） | 编译产物被 git 跟踪（`git ls-files assets \| grep pycache` 命中），`.gitignore` 没有 `__pycache__/`/`*.pyc` 规则 | 仓库卫生问题：每次运行 `verify-all.py` 都可能引入变更噪声，且与 README"只包含源码与配置"不符 | `git rm -r --cached assets/desktop/.tools/__pycache__`；`.gitignore` 增加 `__pycache__/`、`*.pyc` | `git ls-files assets \| grep pycache`；`grep -n 'pyc\|pycache' .gitignore`（无） |
| low | `assets/sddm/furryos/components/FurryField.qml:37` | `property real restX: x` 是死代码：`FurryField` 既没有 `shake()`，也没有任何动画引用 `restX`（只有 `FurryButton` 实现了抖动） | 读代码时误以为输入框也会抖动（BUILD.md:143 的验收只要求按钮抖动，两者不一致） | 删除 `restX`，或按契约补上输入框抖动实现 | `grep -n 'restX' assets/sddm/furryos/components/*.qml`（FurryField 仅 :37，无引用） |
| low | `build/config/bootloaders/syslinux_common/live.cfg.in:21` | 注释把启动菜单钩子写成 `hooks/6210-brand-boot-menu.*`，实际文件是 `build/config/hooks/normal/8000-brand-boot-menu.binary` | 排障时按注释找不到文件 | 改为 `hooks/normal/8000-brand-boot-menu.binary` | `grep -rn '6210' build/config/`；`ls build/config/hooks/normal/ \| grep brand-boot` |
| low | `README.md:38`、`docs/BUILD.md:290` | 把点击特效描述成"彩带扩散"，而实现是 KWin `mouseclick` 特效（同心圆环：`RingCount=2`/`RingLife=250`/`RingSize=32`，见 `assets/effects/click-effect/effects-install.sh:90`） | 验收时按"彩带"去找会误判为未实现 | 改为"点击涟漪（同心圆环）" | `grep -n 'Ring' assets/effects/click-effect/effects-install.sh \| head -3`；`grep -n '彩带' README.md docs/BUILD.md` |
| low | `docs/BUILD.md:217` | 在 sh 代码块里放了一句中文描述 `color schemes 中是否有 FurryOS.colors`，不是可执行命令 | 复制粘贴即报 `command not found` | 改为 `ls /usr/share/color-schemes/FurryOS.colors` | `sed -n '214,224p' docs/BUILD.md` |

---

## 5. 历史问题核实结论（队长指定的两项）

### 5.1 `FURRYOS_ASSETS` 与 6000 的 `STAGING` 是否仍不一致？

**已修复，当前一致。**

```
$ grep -n 'FURRYOS_ASSETS=' build/config/hooks/normal/furryos-common.sh
38:FURRYOS_ASSETS="/opt/furryos/assets"

$ grep -n 'STAGING=' build/config/hooks/normal/6000-stage-furryos-assets.chroot
47:STAGING="/opt/furryos/assets"

$ grep -rn 'FURRYOS_ASSETS' build/config/hooks/normal/*.chroot
build/config/hooks/normal/6000-stage-furryos-assets.chroot:32:# must use FURRYOS_ASSETS (= the staging directory) and never the bind mount,
build/config/hooks/normal/6010-integrate-identity-assets.chroot:41:# NOTE (brand-identity): do NOT rely on ${FURRYOS_ASSETS} here.
build/config/hooks/normal/6010-integrate-identity-assets.chroot:44:#   FURRYOS_ASSETS=/live-build/assets, which nothing ever creates. When the two
build/config/hooks/normal/6110-integrate-desktop-assets.chroot:26:SRC="${FURRYOS_ASSETS}/desktop"
build/config/hooks/normal/6120-integrate-sddm-assets.chroot:29:SRC="${FURRYOS_ASSETS}/sddm"
build/config/hooks/normal/6130-integrate-effects-assets.chroot:51:SRC="${FURRYOS_ASSETS}/effects"
```

即：三个"使用方"取的都是 `/opt/furryos/assets`；只有 6010 是例外（不引用该变量，自带探针，见 §5.3）。

补充事实：6000 现在会在层目录缺失时 `exit 1`（:51-56、:83-88），不再静默 `exit 0`——注释里描述的原始 bug（:37-39）确已修复。**遗留问题**是 6010 仍不信任该变量（自带探针 + 死分支），见 §3 medium 第 6 条。

### 5.2 6110/6120/6130 在资产目录缺失时是 `exit 0` 还是 `exit 1`？

**全部是 `exit 0`（静默降级），与 6000/6010 的 fail-fast 不统一。**

```
$ grep -n 'exit 0\|exit 1' build/config/hooks/normal/6000-*.chroot \
      build/config/hooks/normal/6010-*.chroot build/config/hooks/normal/61[123]0-*.chroot
6000-stage-furryos-assets.chroot:55:	exit 1
6000-stage-furryos-assets.chroot:87:	exit 1
6010-integrate-identity-assets.chroot:68:	exit 1
6110-integrate-desktop-assets.chroot:33:	exit 0
6120-integrate-sddm-assets.chroot:36:	exit 0
6120-integrate-sddm-assets.chroot:62:	exit 0
6130-integrate-effects-assets.chroot:58:	exit 0
```

`set -e` 语义核对：`lb chroot_hooks` 对钩子非零退出会 `Echo_error … ; exit 1`（`tools/lbroot/usr/lib/live/scripts/build/chroot_hooks:83`；`.container` 分支同逻辑在 :79），所以 6000/6010 的 `exit 1` 确实能中止构建——差别是真实的，不是"反正都会继续"。

### 5.3 6010 的本地探测逻辑是否与 6110/6120/6130 统一？

**不统一。** 6010 是"双候选探测 + 显式 `exit 1`"，其余三层是"直接用 `FURRYOS_ASSETS` + `exit 0`"：

```
$ sed -n '50,69p' build/config/hooks/normal/6010-integrate-identity-assets.chroot
_IDENTITY_ASSET_DIRS="/opt/furryos/assets/identity /live-build/assets/identity"
…
if [ -z "${SRC}" ]; then … exit 1; fi
```

其中 `/live-build/assets/identity` 在 chroot 内永远不存在（`chroot_hooks` 只把 `config/` 挂到 `/live-build/config`，见 `chroot_hooks:41-42`），属于死分支。

---

## 6. 已核实「无问题」的项（避免 fixer 返工 / 避免误报）

以下项目是任务书点名怀疑的点，已实测确认**当前是正确的**，修复时不要改动：

| 项 | 结论 | 证据 |
|---|---|---|
| `paw.svg` 引用是否带错误 `../` | **正确**。`Main.qml:100,249` 用 `assets/paw.svg`（相对主题根），`components/*.qml:109,47,32` 用 `../assets/paw.svg`（相对 components/），两者解析后都指向 `/usr/share/sddm/themes/furryos/assets/paw.svg` | 见 §R7：qmlscene 离屏加载 `Main.qml` **零警告**；反向对照（故意写错路径）立刻出现 `QML Image: Cannot open:` |
| `Theme` 单例 / `qmldir` 一致性 | **正确**。`components/qmldir` 声明 `singleton Theme 1.0 Theme.qml` + 4 个组件，`Main.qml` 用 `import "components"` 即可解析 | 同上（零警告加载成功；`qmllint` 6/6 无输出） |
| `FurryButton.shake()` 的 `restX` 是否会漂移 | **不会漂移**。虽然 `restX: x` 是活绑定，但动画 `to` 也随绑定更新，实测抖动区间 `124.11..136.00`（±6px），结束后精确回到 `x=130.00`，连续两次调用同样回到 130 | 见 §R7 的 shake 采样输出 |
| 钩子 shebang 与实际语法 | **一致**（全部 `#!/bin/sh`，无 bash 专有语法） | `for f in build/config/hooks/normal/*.chroot build/config/hooks/normal/*.binary build/config/hooks/normal/furryos-common.sh; do dash -n "$f" \|\| echo "FAIL $f"; done` → 全部通过；`grep -n '\[\[' ...` 无命中 |
| `set -e` 对 `[ … ] && continue` 的语义 | **安全**，不会误中止（`[ … ]` 非 AND-OR 列表末位，`-e` 被忽略） | `dash -c 'set -e; false && echo hi; echo continued'` → 输出 `continued`；bash 同 |
| 8000 钩子的执行时机假设（在 grub/syslinux 生成之后） | **正确** | `tools/lbroot/usr/lib/live/scripts/build/binary`：:58 `binary_grub_cfg` → :59 `binary_syslinux` → :64 `binary_grub-efi` → :65 `binary_hooks` → :76 `binary_iso` |
| `hooks/live/` 配对文件是否必要 | **必要且已具备**（`chroot_hooks:45-48` 要求 normal 与 live 同时存在才会执行任何钩子；`0010/0050/0100` 已存在） | `sed -n '45,48p' tools/lbroot/usr/lib/live/scripts/build/chroot_hooks`；`ls build/config/hooks/live/` |
| `assets/sddm/install-sddm-theme.sh` 的调用签名 | **正确**：`6120:72` 传 `(<主题目录>, /)`，脚本 `$1`=SRC、`$2`=PREFIX（:16-17） | `sed -n '14,26p' assets/sddm/install-sddm-theme.sh` |
| 三个 desktop 校验脚本能否真的失败 | **能**（不是空校验）：人为改坏输入后全部 exit 1 | 见 §R5 |
| `verify-splash-pixels.py` 能否真的失败 | **能**：喂一张纯红图 → 6 项 FAIL、exit 1；喂不存在的文件 → exit 2 | 见 §R5 |
| `tools/verify-identity.sh` 当前结果 | PASS=33 FAIL=0，exit 0（与 README 一致） | `bash tools/verify-identity.sh \| tail -3` |
| 钩子权限位 | **正确**：`6000/6010/6110/6120/6130/8990` 与 `8000-*.binary` 均 0755；`furryos-common.sh` 0644（只被 source，无需可执行） | `ls -l build/config/hooks/normal/` |

---

## 7. 复现命令详解

所有命令均在本仓库 `/root/furryos`、宿主 Debian 12（Qt 5.15.8、mtools、ImageMagick 已装）实测通过。

### R1 — efi.img 引导桩被整份 grub.cfg 替换（blocker）

```sh
# 1) 上游引导桩的真实内容（live-build 20230502）
sed -n '232,235p' tools/lbroot/usr/lib/live/scripts/build/binary_grub-efi
#   search --set=root --file /.disk/info
#   set prefix=($root)/boot/grub
#   configfile ($root)/boot/grub/grub.cfg

# 2) ISO 主配置的第一行（相对 $root 解析，必须 $root 已是 ISO 分区）
sed -n '1,4p' tools/rootfs/usr/share/live/build/bootloaders/grub-pc/grub.cfg
#   source /boot/grub/config.cfg

# 3) 复刻钩子 :99-100 的两条命令，观察 ESP 内 grub.cfg 被替换
cd /tmp && rm -rf efidemo && mkdir efidemo && cd efidemo
mkfs.msdos -C efi.img 1440 >/dev/null 2>&1
mmd -i efi.img ::boot; mmd -i efi.img ::boot/grub
printf 'search --set=root --file /.disk/info\nset prefix=($root)/boot/grub\nconfigfile ($root)/boot/grub/grub.cfg\n' > stub.cfg
mcopy -i efi.img stub.cfg ::boot/grub/grub.cfg
mkdir -p boot/grub
printf 'source /boot/grub/config.cfg\nmenuentry "FurryOS Live (amd64)" {\n linux /live/vmlinuz-6.8.0-31-generic\n}\n' > boot/grub/grub.cfg
mdel -i efi.img ::boot/grub/grub.cfg 2>/dev/null || true
mcopy -o -i efi.img boot/grub/grub.cfg ::boot/grub
mtype -i efi.img ::boot/grub/grub.cfg
# → 输出 source /boot/grub/config.cfg + menuentry …（引导桩已消失）
```

### R2 — 启动画面未接入构建（high）

```sh
grep -rn 'effects-splash-install' build/config/hooks/            # 无输出：层脚本从未被调用
grep -rn 'ksplash\|look-and-feel/org.furryos' build/config/hooks/normal/6130-*.chroot
#   → 只在注释里出现；没有任何 cp 到 /usr/share/plasma/look-and-feel 的语句
find assets/effects/splash/furryos-ksplash -type f               # 5 个文件，实际未安装
grep -rn -i 'plymouth' build/config/package-lists/               # 无输出：plymouth 不在包列表
ls assets/effects/splash/furryos-plymouth/*.plymouth             # 存在 → 6130:127 分支会命中
```

### R3 — BUILD.md 的 os-release「修复」命令会清空文件（high）

```sh
cd /tmp && rm -rf catprobe && mkdir -p catprobe/usr/lib catprobe/etc
printf 'NAME="Ubuntu"\nPRETTY_NAME="Ubuntu 24.04"\n' > catprobe/usr/lib/os-release
ln -s ../usr/lib/os-release catprobe/etc/os-release
wc -c catprobe/usr/lib/os-release          # 41
bash -c 'cat /tmp/catprobe/usr/lib/os-release > /tmp/catprobe/etc/os-release && \
         ln -sf ../usr/lib/os-release /tmp/catprobe/etc/os-release'
wc -c catprobe/usr/lib/os-release          # 0  ← 文件被清空
```

### R4 — `verify-identity.sh` 的空断言（medium）

```sh
rm -f /tmp/missing-motd
dash -c 'if grep -vE "^[[:space:]]*#" /tmp/missing-motd 2>/dev/null | grep -qi "ubuntu"; \
         then echo BAD; else echo "ok: 00-header 已替换为 FurryOS 版…（文件不存在也算通过）"; fi'
# 对照 tools/verify-identity.sh:212-221 的同一模式
sed -n '211,221p' tools/verify-identity.sh
```

### R5 — 校验脚本的正/负向对照（medium，用于确认哪些是真断言）

```sh
rm -rf /tmp/negctl && mkdir -p /tmp/negctl && cp -a assets /tmp/negctl/assets
cd /tmp/negctl/assets/desktop
python3 .tools/verify-all.py >/dev/null 2>&1; echo "baseline=$?"          # 0

sed -i 's/^BackgroundNormal=234,242,255/BackgroundNormal=234,242,254/' FurryOS.colors
python3 .tools/verify-colors.py >/dev/null 2>&1; echo "colors=$?"          # 1（真断言）
sed -i 's/^ColorScheme=FurryOS/ColorScheme=BreezeLight/' FurryOS.colors
python3 .tools/verify-consistency.py >/dev/null 2>&1; echo "consistency=$?" # 1（真断言）

convert -size 1920x1080 xc:'#1A6FD4' wallpaper.png
python3 .tools/verify-wallpaper.py 2>&1 | tail -3                          # AssertionError（健壮性问题）
cp -a /root/furryos/assets/desktop/wallpaper.png .

cd /root/furryos/assets/effects/splash
convert -size 640x360 xc:'#FF0000' /tmp/bad-splash.png
python3 verify-splash-pixels.py /tmp/bad-splash.png >/dev/null 2>&1; echo "splash=$?"   # 1
python3 verify-splash-pixels.py /tmp/nonexistent.png >/dev/null 2>&1; echo "missing=$?" # 2
```

### R6 — 6000 重跑会把层目录嵌套（medium）

```sh
rm -rf /tmp/cpnest && mkdir -p /tmp/cpnest/src/identity /tmp/cpnest/staging
touch /tmp/cpnest/src/identity/f1
cp -a /tmp/cpnest/src/identity /tmp/cpnest/staging/identity
cp -a /tmp/cpnest/src/identity /tmp/cpnest/staging/identity   # 模拟钩子第二次运行
find /tmp/cpnest/staging | sort
# → staging/identity/identity/f1   （嵌套）
```

### R7 — QML 离屏运行验证（medium + §6 证据）

```sh
cd /root/furryos/assets/sddm/furryos

# 语法：6 个文件全部无输出即通过
for f in Main.qml components/*.qml; do /usr/lib/qt5/bin/qmllint -I . "$f"; done

# 运行时：离屏 + 软件渲染加载整棵对象树（零警告 = 单例/组件/图片路径全部解析成功）
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  /usr/lib/qt5/bin/qmlscene --quit Main.qml

# 反向对照：故意写错图片路径时立刻出现警告，证明"零警告"是有意义的
printf 'import QtQuick 2.15\nItem{Image{source:"assets/definitely-missing.svg"}\nComponent.onCompleted:Qt.quit()}\n' > /tmp/negimg.qml
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software /usr/lib/qt5/bin/qmlscene --quit /tmp/negimg.qml
# → QML Image: Cannot open: file:///tmp/assets/definitely-missing.svg

# shake() 实测：±6px、320ms、结束回到原位、可重复
rm -rf /tmp/qt && mkdir -p /tmp/qt/assets
cp -a /root/furryos/assets/sddm/furryos/components /tmp/qt/
cp -a /root/furryos/assets/sddm/furryos/assets/paw.svg /tmp/qt/assets/
cat > /tmp/qt/shake3.qml <<'EOF'
import QtQuick 2.15
import "components"
Item { id: root; width: 600; height: 200
  property real minX: 9999; property real maxX: -9999; property int n: 0
  FurryButton { id: btn; x: 130; y: 50; width: 280; height: 48; text: "登 录" }
  Component.onCompleted: btn.shake()
  Timer { interval: 16; running: true; repeat: true
    onTriggered: { root.n++; root.minX = Math.min(root.minX, btn.x); root.maxX = Math.max(root.maxX, btn.x)
      if (root.n >= 25) { console.log("min=" + root.minX.toFixed(2) + " max=" + root.maxX.toFixed(2) + " final=" + btn.x.toFixed(2)); Qt.quit() } } }
}
EOF
cd /tmp/qt && QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software /usr/lib/qt5/bin/qmlscene shake3.qml
# → qml: min=124.11 max=136.00 final=130.00
```

### R8 — 6000 缺失层重复计数（low）

```sh
dash -c '
SOURCE=/nonexistent; STAGING=/tmp/stg-demo; rm -rf $STAGING; mkdir -p $STAGING; MISSING=0
for L in identity desktop sddm effects brand; do [ -d "$SOURCE/$L" ] || MISSING=$((MISSING+1)); done
echo "loop1=$MISSING"
for L in identity desktop sddm effects brand; do [ -d "$STAGING/$L" ] || MISSING=$((MISSING+1)); done
echo "loop2=$MISSING  ← 实际只缺 5 层"'
# → loop1=5 / loop2=10
```

### R9 — 仓库卫生（high/medium/low 的公共证据）

```sh
git ls-files build/config/assets | wc -l     # 159（sync-assets.sh 的产物）
diff -rq assets build/config/assets          # 无差异 → 纯重复
du -sh assets build/config/assets            # 各 1.5M
git ls-files assets | grep pycache           # __pycache__/*.pyc 已入库
git check-ignore -v tools/rootfs/usr/bin/lb tools/lbroot/usr/lib/live tools/shim
git ls-files tools/                          # 只有 lb.sh / sync-assets.sh / verify-identity.sh
grep -n 'rootfs\|lbroot\|shim' docs/BUILD.md   # 无输出：BUILD.md 未说明如何获取
```

---

## 8. 建议修复顺序（给 fixer / 队长）

1. **先修 blocker**：`8000` 的 efi.img 段（删除再注入逻辑）——这是唯一会导致"产物不可启动"的问题，且改动面小。
2. **再统一 fail-fast 语义**：6110/6120/6130 的 `exit 0` → `exit 1`，6010 改用 `FURRYOS_ASSETS`（三处改动共享同一套 `furryos_need_file`，一次改完）。
3. **文档止血**：`docs/BUILD.md:179` 的自毁命令（数据风险）、§2 的错误注入方式、包名 `qt5-image-formats-plugins`、`docs/BUILD-LOG.md`/6200 钩子的死引用、`/usr/share/wallpapers` 预期路径、`qmlscene`/`qmllint` 的"不可用"误述。
4. **启动画面决策**：plymouth 进包列表并调用层脚本，或明确写"本镜像不含 plymouth 启动画面"；ksplash 与 plymouth 无关，建议直接安装（成本低）。
5. **校验脚本加固**：`verify-identity.sh` 的存在性断言 + 期望计数；`verify-consistency.py` 的对比度阈值/AAA 表述；`verify-wallpaper.py` 的 paw.svg 解析与 PNG 调色板支持。
6. **仓库精简**：`build/config/assets/` 与 `__pycache__` 取消跟踪、`.gitignore` 补齐、BUILD.md 增加工具链获取章节、`shim/mount` 入库或由脚本生成。
7. **low 级清理**：死代码（`/tmp/furryos-iso-volume-check`、`pre-furryos`、`rm -rf /live-build`、`FurryField.restX`）、陈旧注释（6130 ksplash/plymouth、`6210` 钩子名）、`/etc/skel/README.md`、`metadata.desktop` 元数据。

> 说明：本报告所有"实测"结论均来自本轮实际执行（命令与输出见 §7）；凡未实际执行、仅依据代码引用的条目，已在"复现方式"列标注为代码引用（如 §1 blocker 的上游桩内容取自 `binary_grub-efi` 源码，并用 mtools 复刻验证了替换效果）。

---

## 9. 队长补充审核（ISO 构建与 QEMU 实测后）

以下是在原审核报告之后，通过干净克隆、完整构建、最终 ISO 与 QEMU 得到的补充结论；不计入 §0 的原始数量统计。

### 9.1 high：写死路径会让干净克隆“假通过”，隔离后立即失败

`tools/verify-identity.sh:26` 与 `tools/lb.sh:30-31` 都写死 `/root/furryos`。在临时干净克隆中直接运行，脚本实际读取的是原工作区，因此会得到假的成功结果。

使用 mount namespace 隐藏原工作区后复测：

```text
verify-identity.sh：缺少 .verify/x/{base,ssh}，exit 2
tools/lb.sh：/root/furryos/tools/rootfs/usr/bin/lb 不存在，exit 127
```

因此 R1/R2 的修复验收必须在隔离环境进行，不能只在原机器的另一个 clone 目录运行。

### 9.2 high：旧 `.verify/fetch-refs.sh` 与校验器目录约定不一致

即使把旧 fetch 脚本直接入库，仍不能解决身份校验：

```text
fetch-refs.sh 生成：x/base-files、x/openssh-server、x/motd-news-config
verify-identity.sh 读取：x/base、x/ssh、x/motd
```

修复时必须统一目录名，并同时移除两个脚本中的 `/root/furryos` 写死路径。

### 9.3 high：本次构建成功的两项工具链修正仍是本机手工状态

完整构建实际遇到并处理了：

1. 本地 live-build 缺 `share/bootloaders/grub-pc` 资源映射。
2. `binary_grub-efi` 用 `stat -c %s` 计算 shim 符号链接，只得到 36 字节，导致 EFI FAT 镜像过小并报 `Disk full`；改为 `stat -L -c %s` 后通过。

这些修改位于 Git 忽略的工具解包目录。必须固化到已跟踪的工具准备/包装流程，否则新构建者无法复现本次成功。

### 9.4 medium：最终 ISO 的 `.disk/info` 仍不是 FurryOS

从最终 binary/ISO 实测：

```text
Debian GNU/Linux 24.04 "Noble" - Official Snapshot amd64 LIVE Binary ...
```

需要在 binary 阶段改成 FurryOS，同时保留该文件作为 GRUB `search --file /.disk/info` 定位标记的功能。

### 9.5 high：UEFI blocker 已确认存在于当前 ISO，修复后必须重出 ISO

当前构建日志实际出现：

```text
[furryos-boot-brand] re-injected branded grub.cfg into boot/grub/efi.img
```

这正好执行了 §1 所述的错误替换。当前 ISO 只完成了 BIOS 启动测试，不能声称 UEFI 可启动。删除该错误逻辑后，需要重新生成 ISO 并补做 UEFI/OVMF 启动验证。

### 9.6 high：QEMU 图形会话已出现，但桌面壁纸品牌未通过验收

对当前 ISO 的 BIOS 实启结果：

- 10 秒截屏 OCR 读到 `FurryOS` 启动菜单。
- 150 秒进入带日期/时钟的图形界面。
- 150 秒截屏主色与 `assets/desktop/wallpaper.png` 的比较不一致。

所以目前只能验收“ISO 可启动到图形会话”，不能验收“FurryOS 蓝白桌面已生效”。t5 必须检查 live 用户实际 Plasma 配置并用新 QEMU 证据复验。

### 9.7 medium：SDDM 仍有两处测试报告已指出的不一致

- `assets/sddm/furryos/Main.qml:174` 硬编码 `#B3261E`，绕过 `Theme.qml`；应登记为 `furryosNegative` 令牌后引用。
- `assets/sddm/sddm.conf` 有 `CursorTheme=Breeze_Snow`，但正常构建调用的 `install-sddm-theme.sh` 不生成该项；两条配置路径必须统一。

### 9.8 medium：`verify-consistency.py` 另有两处硬编码/假参数化

- `:205-208` 的 `shipped pair` 固定为 `(18,40,63)` / `(255,255,255)`，不读取 `FurryOS.colors`，也不参与 failures。
- `:38-46,96` 的 `EXPECT` 只用于打印，真正断言使用另一组字面量。

修复后应做负向测试：故意改坏 `[Colors:View]` 或期望值，脚本必须 exit 1。

### 9.9 low：`verify-splash-pixels.py` 默认路径依赖 CWD

`:19` 使用相对路径 `furryos-splash-preview.png`，从仓库外执行会 exit 2。默认图片应改为相对脚本自身定位，同时保留显式参数。

### 9.10 已解决项：BUILD-LOG 死引用

§3 中“缺少 `docs/BUILD-LOG.md`”已由 t3 解除：该文件现已生成，并记录 ISO、SHA256、构建失败/修复过程与 QEMU 实测。修复时不要再按旧建议删除文档引用。
