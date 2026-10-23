# 栖集 0.0.1 (7) 发布准备

状态：等待恢复本机 Apple 公证凭据，尚未发布。线上保持 build 6。

本次为 Codex 增加项目级 MCP，目标为项目 `.codex/config.toml`。配置扫描、配置库、预设和 AI 接入均使用所选项目与范围，保留计划预览和本机批准。Codex 项目须由用户设为受信任，栖集不修改信任设置。

审查修复了共同事务根为 `/` 时父目录软链检查被跳过的问题。行为回归验证正常目录能够写入、被换成目录软链时拒绝且外部配置不落盘。另修正架构文档中“仅用户级接入”的旧限定。独立复核未发现剩余阻断问题；并行会话中的双 Logo 草稿未纳入本次发布。

源码提交：`f9910da1efd94fccd2cb737b74c65aef32639c83`。已推送 annotated tag：`perch-v0.0.1-build.7`，指向该源码提交。标签标识源码版本，不代表线上发布完成。

验证通过：148 项 Swift Testing、11 项核心 XCTest、102 项应用 XCTest；安全路径专项 54 项；Python 31 项、Node 5 项、12 个 skill 结构检查、目录指纹和 diff 检查。初次全套 BDD 停在原生 UI 进程后中止，未将其计为成功；本次未修改 BDD 代码。

Release App 与内置、独立 CLI 均为 arm64 / x86_64。Developer ID、hardened runtime、递归验签通过，包内与独立 CLI 均在仓库外发现 17 个 MCP 工具。沿用 `com.xiezhixin.perch`、原 Sparkle 公钥和新平台 feed。

Apple 公证提交返回：`No Keychain password item found for profile: APP-Notary-2026`。当前登录钥匙串未发现该 profile，因此没有装订 App/DMG、没有生成 Sparkle 签名清单，也没有上传平台。官网源码已准备 build 7 下载链接，但线上首页和 build 6 清单未更改。

本地产物和日志位于 `dist/release-v0.0.1-7/`，包含 `release-verification.json`、`bundle-verification.json`、测试与构建日志、签名 App、`notary-upload.zip` 和明确标记为 `unnotarized` 的草稿 DMG。完整隔离源码与构建缓存位于 `/tmp/perch-build7-review`。

恢复 profile 后，依次公证 ZIP、装订 App、从已装订 App 重新制作正式 DMG、公证并装订 DMG、生成 Sparkle appcast，再从固定源码组装全新平台发布目录。发布前核对 25 MiB 上限、文件集合和源码元数据；发布后匿名核对 RSS、完整 DMG 字节、Sparkle 签名和缓存头。真实 build 6 → 7 的安装、重启、数据保留仍需独立 macOS 图形会话或 VM 验收。凭据只在本机恢复，不进入仓库或聊天。
