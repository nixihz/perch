# 栖集 0.0.1 (14) 发布记录

状态：主题修正后的 Sparkle build 14 已完成构建、公证、Sparkle 清单生成，并已通过 `https://app.u1.fan` 发布。公网匿名下载与本地字节校验一致。

本版恢复原陶土红主题，保留黑曜与雪白，移除雾灰；旧的 `mist` 偏好值回退到黑曜。沿用原 Bundle ID、公钥、feed 与最低 macOS 14。

本地构建结果：

- Release 通用 App：`dist/release-v0.0.1-14/app/栖集.app`；内置与独立 CLI 的 MCP 打包验证通过，各发现 59 个工具。
- App ZIP：`dist/release-v0.0.1-14/Perch-0.0.1-14-app.zip`；App 公证 ID：`04394e56-ce30-4f60-a77a-72e54420ed47`。
- DMG：`dist/Perch-0.0.1-14-universal.dmg`，31,844,588 bytes，SHA-256 `b41adae0ea7c95b6493b676fd6b113e72acb860c25ba631dd3f2d94d8ab4b12a`；DMG 公证 ID：`0e0b3d7a-2365-4004-9c03-458b3de77767`。
- App 与 DMG 均已装订公证票据；严格递归验签、`stapler validate` 和 Gatekeeper `Notarized Developer ID` 检查通过。
- Sparkle：`dist/sparkle-release-0.0.1-14/appcast.xml`，837 bytes，SHA-256 `be454025324947efe3457f2b4363892bd690a3c6be2a0adef5c6e49aac6f4b6a`；`sign_update --verify` 通过。
- 平台包：归档 28,919,775 bytes，解压内容 32,926,235 bytes；CLI 报告 `maxUploadBytes=209715200`（200 MiB）、`maxExtractBytes=104857600`（100 MiB），打包通过。
- 平台发布：`publish --update` 成功，release ID `2ac9cccc-82c7-4311-b8e0-a304297425e5`，公开地址 [https://perch.u1.fan/](https://perch.u1.fan/)。
- 匿名公网验证：首页显示 `0.0.1 (14)` 并链接 build 14；公网 appcast 与本地逐字节一致；公网 DMG 与本地逐字节一致，SHA-256 与上项相同。

测试与主题修正：

- `swift test --filter 'SkillSetAppTests.SettingsTests|SkillSetAppTests.ThemeContrastTests'`：11 项通过。
- `python3 -m unittest tests.test_ui_localization -v`：4 项通过。
- 主题保留陶土红、黑曜、雪白，移除雾灰；历史偏好值 `mist` 自动回退到黑曜。
