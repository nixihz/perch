# 栖集 0.0.1 (8) 发布记录

状态：已发布。平台 release ID：`c46352b8-933c-44b7-a648-ad00417aab37`；官网和 Sparkle 清单已切换到 build 8，build 7 保留在发布历史中。

项目与全局技能行新增 Codex、Claude Code 独立 Logo 开关，分别保存两个宿主的草稿。图标使用随包分发的本地资源，并附 LobeHub 来源及 MIT 许可。已安装技能扫描改为后台加载，补充搜索、状态与目录恢复入口；扫描目录软链时枚举真实目录、保留原安装路径，单个坏目录不阻断其他结果。

审查修复了项目开关发生同名冲突、阻塞或保存失败时缺少反馈的问题，成功重试后清除错误提示；扫描刷新失败时保留上次成功结果与勾选，恢复后可以重新扫描。行为测试覆盖真实失败、恢复重试、双宿主持久化、损坏索引及新技能发现；另补齐“清空筛选”的英文，并统一 DESIGN 中的目录恢复约定。

源码提交：`0bebe357854e5c9e1ffd2acaaa10763cb22e9a0f`。已推送 annotated tag：`perch-v0.0.1-build.8`，解引用提交为该源码提交。

完整回归通过：149 项 Swift Testing、11 项核心 XCTest、113 项应用 XCTest、406 项 BDD target XCTest，零失败、零跳过。BDD 包含 31 个 Gherkin 场景的 398 个动态步骤、7 项原生 UI XCTest 和 1 项 Cucumber bootstrap；完整日志为 `dist/release-v0.0.1-8/swift-tests-full.log`。Python 31 项、Node 5 项、12 个 skill 结构检查、catalog 指纹和 diff 检查均通过。明暗两种外观下已核对宿主开关，长技能名称未挤掉开关。

Release App、内置 CLI 和独立 CLI 均为 arm64 / x86_64。Developer ID `Developer ID Application: zhixin xie (77TN4427T5)`、hardened runtime、严格递归验签通过；包内与独立 CLI 均在仓库外完成 MCP 握手，各发现 17 个工具。沿用 Bundle ID `com.xiezhixin.perch`、Sparkle 公钥 `3EB2chk/1iPXBBWYoCpL1IMTXf09D0IsFnH9oceg5oI=` 和 feed `https://app.u1.fan/x/perch/updates/macos/appcast.xml`，最低 macOS 14。

使用已有 `APP-Notary-2026` 完成 Apple 公证：App submission ID 为 `127f8479-252e-4cbe-9dd1-3a66b125993d`，DMG submission ID 为 `ca8932c3-f738-403f-bbcf-ec9416d34e8e`，均为 `Accepted`。App 与 DMG 均已装订并通过 `stapler validate`；App 的 Gatekeeper 返回 `Notarized Developer ID`。

正式 DMG `Perch-0.0.1-8-universal.dmg` 为 `25,093,316` 字节，SHA-256 为 `13d6afa6118400355077970344977689f41ec6682f62b348cf0d25bc051e5ac4`。Sparkle appcast 为 835 字节，SHA-256 为 `29662ebb30801af5c00016017ee0e534916fb710a7fcbae1ce706abf477c57c7`；本地官方 `sign_update --verify` 通过。从已装订 App 重新生成的 ZIP 仅保留为本地离线产物。

平台包为 `23,823,798` 字节，低于 25 MiB 上限，SHA-256 为 `d25c6bcec160aa5315f04bf256ca65e0372fb108155fa5c48d0bb7652fc49a6a`。目录精确包含清单、首页、品牌图、appcast 和正式 DMG 五个来源文件，ZIP 仅额外包含 `app-platform-source.json`；元数据与干净 main 源码、提交和远端一致。隔离预览验证通过，退出后临时数据已清理。

公网匿名 GET、Range、首页、品牌图、appcast 和 DMG 均通过字节与 SHA-256 核对；HEAD 状态、长度和缓存头符合预期，公网 DMG 的官方 Sparkle 验签通过。挂载路径经 HTTPS 跳转到 `perch.u1.fan`；appcast 为 RSS XML，返回 `Cache-Control: no-cache`，DMG 使用 immutable 缓存。平台 `manifest.access` 与实例 `visibility` 均为 `public`。Range 当前返回完整 200，不提供分段 206。

产物、日志和机器可读报告位于 `dist/release-v0.0.1-8/`。真实 build 7 → 8 的应用内安装、重启与数据保留仍需独立 macOS 图形用户会话或 VM 验收；本次公网文件和签名校验不等同于该项完成。
