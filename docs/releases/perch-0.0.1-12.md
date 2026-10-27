# 栖集 0.0.1 (12) 发布准备记录

状态：App 与 DMG 已完成 Developer ID 签名、Apple 公证和装订；Sparkle appcast 已在本地生成并通过官方签名校验，尚未上传平台。线上仍为 build 11，官网入口继续指向 build 11。

本版加入黑曜、雪白、雾灰三种黑白灰主题色调，设置页提供即时切换并持久化选择；同时保留 Sparkle Bundle ID、公钥、清单地址和最低 macOS 14 约束。

验证结果：`swift test --filter SkillSetAppTests` 通过 200 项应用测试；主题对比度、设置持久化和侧栏选中态专项测试通过；`swift build --product SkillSetDesktop` 通过。Release App 与内置、独立 CLI 均为 arm64 / x86_64，MCP 打包验证各发现 59 个工具；App 与 DMG 的 `stapler validate`、Gatekeeper 检查和严格签名验证通过。

公证记录：App submission ID `1d54c1cd-0026-403c-b0af-e0b6a0a7ae5a`，DMG submission ID `633eb45e-f981-4d7d-b140-6fa771a68dcf`，状态均为 `Accepted`。首次 DMG submission `9ba1eb00-6d3a-4d58-883a-6cccc39aa761` 因 staging 复制导致签名无效而失败，失败日志保留。

本地 Sparkle 产物：`dist/Perch-0.0.1-12-universal.dmg`，31,846,978 字节，SHA-256 `2892eb3ed62c68ad1b8e4690be69b0fd941fea751c78b1e0b13ca150d4b725b7`；`dist/sparkle-release-0.0.1-12/appcast.xml`，837 字节，SHA-256 `a1d4692c586f8a1c1b6c2bc0abe3c923770c6089ad87a8163697ea86b74e8a43`。`sign_update --verify` 已通过，清单绑定 build 12、DMG 长度、公钥和 macOS 14。

待完成：按网站部署说明把唯一命名 DMG 与 appcast 上传到平台，核对匿名公网文件字节与 Sparkle 验签，再完成 build 11 → 12 的应用内下载、安装、重启和数据保留验收。
