# 栖集 0.0.1 (7) 发布记录

状态：已发布。平台 release ID：`7735e864-a8ff-4983-b310-552f2deaae0d`；线上清单和官网已切换到 build 7，build 6 保留在发布历史中。

本次为 Codex 增加项目级 MCP，目标为项目 `.codex/config.toml`。配置扫描、配置库、预设和 AI 接入均使用所选项目与范围，保留计划预览和本机批准。Codex 项目须由用户设为受信任，栖集不修改信任设置。

审查修复了共同事务根为 `/` 时父目录软链检查被跳过的问题。行为回归验证正常目录能够写入、被换成目录软链时拒绝且外部配置不落盘。并行会话中的双 Logo 草稿未纳入本次发布。

源码提交：`f9910da1efd94fccd2cb737b74c65aef32639c83`。已推送 annotated tag：`perch-v0.0.1-build.7`，tag 的解引用提交仍为该源码提交。

验证通过：148 项 Swift Testing、11 项核心 XCTest、102 项应用 XCTest；安全路径专项 54 项；Python 31 项、Node 5 项；12 个 skill 结构检查、目录指纹和 diff 检查通过。初次全套 BDD 停在原生 UI 进程后中止，未将其计为成功；本次未修改 BDD 代码。

Release App 与内置、独立 CLI 均为 arm64 / x86_64。Developer ID、hardened runtime、递归验签通过，包内与独立 CLI 均在仓库外发现 17 个 MCP 工具。沿用 Bundle ID `com.xiezhixin.perch`、Sparkle 公钥 `3EB2chk/1iPXBBWYoCpL1IMTXf09D0IsFnH9oceg5oI=` 和 feed `https://app.u1.fan/x/perch/updates/macos/appcast.xml`。

Apple 公证已完成：App submission ID `58ac1c4e-56d1-44bc-a61b-887c1d7cd074`、DMG submission ID `1a6b15e2-f304-4470-a077-7dd3e95004b3`，状态均为 `Accepted`。此前一次提交返回 profile lookup failure；后续使用 `APP-Notary-2026` 的 history 与 submit 均成功，最初读取失败的具体原因尚未确认。撤回此前“缺少 profile”的结论。

正式 DMG：`26,833,798` 字节，SHA-256 `136d435431eddbbe205643c8b1f8a5eb0a7bdd58d34a3a465af3c07c7baeee92`。Sparkle appcast：835 字节，SHA-256 `e60deb47e5cdb03f8d51ebff827d03601f97dc2b4164e68d3c7555f389505f90`；官方 `sign_update --verify` 和公开公钥 Ed25519 验证均通过。

平台发布目录包含 `apps.yaml`、首页、品牌图、appcast 和正式 DMG；ZIP 为 `24,591,348` 字节，低于 25 MiB 上限，包含 5 个来源文件及唯一的 `app-platform-source.json` 元数据。源码元数据核对 main、clean、提交 `f9910da1efd94fccd2cb737b74c65aef32639c83` 和远端；预览已退出且临时数据已清理。

公网匿名 GET、HEAD、Range、首页、品牌图、appcast 和 DMG 均通过逐字节校验；公网 DMG 和 appcast 与本地 Sparkle 输出一致，官方 Sparkle 验签通过。appcast 返回 `Cache-Control: no-cache`；平台 `manifest.access` 与实例 `visibility` 均为 `public`。Range 当前返回完整 200，不提供分段 206。

本地产物和日志位于 `dist/release-v0.0.1-7/`；未公证 DMG 草稿保留为明确标记的诊断文件，不参与发布。真实 build 6 → 7 的安装、重启和数据保留仍需独立 macOS 图形用户会话或 VM 验收，当前不将公网下载验收等同于该项完成。
