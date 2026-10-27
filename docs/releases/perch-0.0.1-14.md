# 栖集 0.0.1 (14) 发布记录

状态：主题修正后的 Sparkle build 14 已完成 Release 构建与签名校验；等待恢复 `APP-Notary-2026` 后公证，再生成 DMG、Sparkle 清单并发布。线上仍为 build 12。

本版恢复原陶土红主题，保留黑曜与雪白，移除雾灰；旧的 `mist` 偏好值回退到黑曜。沿用原 Bundle ID、公钥、feed 与最低 macOS 14。

发布后补录构建产物、公证 ID、Sparkle 清单校验、平台 release ID 和匿名公网验证。


本地构建结果：

- Release 通用 App：`dist/release-v0.0.1-14/app/栖集.app`；内置与独立 CLI 的 MCP 打包验证通过，各发现 59 个工具。
- App ZIP 已生成：`dist/release-v0.0.1-14/Perch-0.0.1-14-app.zip`。
- 公证阻塞：`xcrun notarytool submit --keychain-profile APP-Notary-2026` 返回 `No Keychain password item found for profile`。
- 恢复凭据后需重新提交 App，装订并验证 App，再制作并提交 DMG；最后重新生成 Sparkle appcast、平台包并执行 `publish --update`。
