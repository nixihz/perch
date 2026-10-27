# 栖集 0.0.1 (13) 发布记录

状态：构建与本地 Sparkle 产物已完成；等待恢复 `APP-Notary-2026` 后公证，再发布至 `https://app.u1.fan`。线上仍为 build 12。

本次递增 Sparkle 构建号，沿用 `com.xiezhixin.perch`、原公钥和新平台 feed；将黑曜、雪白、雾灰主题随新版通用包分发。项目新增 mattpocock/skills 的 handoff 技能链接。

发布 CLI 已升级到 0.1.3，管理员会话有效；约 29 MB 的旧发布包打包通过，预检报告为上传 200 MiB、解压 100 MiB。发布目录仅包含清单、官网、品牌图、本次 DMG 和 appcast，以及 CLI 生成的来源元数据。

最终产物、公证 ID、平台 release ID 与匿名公网校验结果在发布后补录。跨版本应用内安装、重启与数据保留仍须独立验收，文件校验不代表完成安装升级。


本地构建结果：

- Release 通用 App：`dist/release-v0.0.1-13/app/栖集.app`；内置与独立 CLI 的 MCP 打包验证通过，各发现 59 个工具。
- DMG：`dist/Perch-0.0.1-13-universal.dmg`，31,340,636 bytes，SHA-256 `0131ebd0d450c2aff5f7a27958a28afe99c4e541151e5ca53fda216dac8d879d`。Developer ID 签名校验通过，但尚未装订公证票据。
- Sparkle：`dist/sparkle-release-0.0.1-13/appcast.xml`，837 bytes；DMG SHA-256 与上项一致，appcast SHA-256 待最终公证 DMG 重新生成后确定；`sign_update --verify` 通过。
- 平台包：`dist/perch-app-platform-v0.0.1-13.zip`，28,793,582 bytes；内容 32,422,283 bytes，CLI 报告 `maxUploadBytes=209715200`、`maxExtractBytes=104857600`，打包成功。
- 阻塞：`xcrun notarytool ... --keychain-profile APP-Notary-2026` 返回 `No Keychain password item found for profile`。恢复凭据后需重新公证 App 和 DMG、重新生成 appcast、重建平台包，再执行 `publish --update`。
