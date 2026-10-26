#!/bin/sh
# FurryOS 交互动效层 —— 社区点击特效包（降级方案 B）安装脚本
#
# 触发条件：仅当「内置 Mouse Click Animation 不可用」时才需要本脚本，例如：
#   - 目标环境的 kwin 版本过旧/过新，内置 mouseclick 特效被移除或改名；
#   - 需要更花哨的点击特效（如 SVG 图案、自定义图片涟漪）。
#
# 首选仍是 KDE 内置特效（无需联网、无额外包、与系统同版本、零维护成本），
# 因此本脚本默认不执行，仅作为降级路径记录在此，供 docs/BUILD.md 引用。
#
# 社区特效方案（按推荐度）：
#
# 方案 1（推荐降级）：KDE Store 的「Mouse Click Animation」增强包
#   上游项目：https://store.kde.org/browse?cat=584&ord=latest
#   说明：部分第三方包是内置特效的「替换版/皮肤版」，安装到
#        ~/.local/share/kwin/effects/ 或 /usr/share/kwin/effects/。
#   局限：KDE Store 无稳定 API，无法在构建期无人值守下载；
#         故本方案只能是「用户侧手动操作」，不能进 live-build 自动注入。
#
# 方案 2（可自动注入）：自建 scripted effect 包（QML/KPackage）
#   交互动效层未在资产中内置该包，原因是：
#     a) Ubuntu noble 的 kwin 5.27 已内置成熟的 mouseclick 特效；
#     b) 自建 QML 特效需针对 kwin 版本反复验证，宿主无 Plasma 无法实测；
#     c) 引入第三方二进制/脚本会增加发行版的维护与审计面。
#   若未来确需，目录结构为：
#        ~/.local/share/kwin/effects/mouseclick/
#            metadata.json      {"KPlugin":{"Id":"mouseclick","EnabledByDefault":true,...}}
#            contents/ui/main.qml
#   然后用 kwriteconfig5 --file kwinrc --group Plugins --key mouseclickEnabled true 启用。
#
# 方案 3（最低限降级）：完全不用特效
#   见 assets/effects/README.md「降级方案」一节的影响说明。

set -eu

log() { printf '[furryos-effects-community] %s\n' "$*"; }

if [ "${1:-}" != "--i-know-what-i-am-doing" ]; then
    log "本脚本默认不执行。内置 KDE 特效（kwinrc [Plugins] mouseclickEnabled=true）"
    log "已是 FurryOS 的默认方案，无需社区特效包。"
    log
    log "若你确认内置特效在目标环境不可用，请阅读本文件头部的三种降级方案，"
    log "并按需手动执行；确认要强制运行社区方案请加 --i-know-what-i-am-doing。"
    exit 0
fi

log "未实现在线下载逻辑（KDE Store 无稳定无人值守接口）。"
log "请按本脚本头部注释中的方案 1/2/3 手动处理。"
exit 0
