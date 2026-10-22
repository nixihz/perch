# 栖集在线更新

已接入 Sparkle 2.10.0，参考 `/opt/case/iamx/tod/apple/Sources/MacUpdates.swift` 的单更新器与设置交互。从迁移版 `0.0.1 (4)` 起，[官网](https://app.u1.fan/x/perch/)、下载包和更新清单均迁至 `app.u1.fan`，不再更新 keli.tech。旧版内置旧清单地址，须从新官网手动安装一次迁移版；之后使用新清单检查更新。下方 build 2 / 3 的 keli.tech 验收记录保留为历史，不作为后续发布入口。

首次启用的配置：

- 当前清单：`https://app.u1.fan/x/perch/updates/macos/appcast.xml`。
- 公钥：`3EB2chk/1iPXBBWYoCpL1IMTXf09D0IsFnH9oceg5oI=`；私钥保存在发布机登录钥匙串的 `com.xiezhixin.perch` account。
- 已发布的 `0.0.1 (1)` 未包含 `SUFeedURL`、`SUPublicEDKey`，须手动安装一次启用版。旧下载地址继续保留，不覆盖原包。
- 新平台单次发布包上限为 25 MiB，官网与 Sparkle 统一使用 DMG；ZIP 仅保留为本地离线分发产物。见[网站部署说明](../website/perch/README.md)。清单引用同一应用挂载路径下唯一命名的 DMG。
- 不能仅凭 HTTP 200 判定 appcast 可用，必须核对 RSS XML 内容、enclosure、签名和实际下载字节；缺失静态路径可能回退到 HTML 首页。

## 客户端行为

- 应用菜单与设置页共用一个更新器。设置显示版本、构建号、自动检查开关与“检查更新…”。
- 自动检查的授权、开关持久化和检查周期由 Sparkle 管理；自动安装关闭，用户决定安装时间。
- 地址和公钥同时留空时，不启动更新器，显示“此版本尚未开启在线更新。”；缺失一项或配置无效时，打包脚本直接失败。
- 更新地址只接受无凭据、无片段的 HTTPS URL，公钥必须是 Base64 编码的 32 字节 Ed25519 公钥。下载包在解压前验签。
- 更新只替换应用包。项目文件、技能目录、宿主配置的修改仍经过原有计划与本机批准流程。

## 配置与构建

公开配置放在 `config/updates.json`。当前发布构建为 `0.0.1 (5)`，保留原 Bundle ID 与 Sparkle 公钥，使用新平台清单地址重新签名、公证；每次正式发包都递增 `build`，同一个构建号不能重发不同内容。此版本是桌面整包版本，与 skill revision、项目锁版本无关。

可直接修改该 JSON，或通过以下环境变量覆盖：

| 配置 | 环境变量 | 含义 |
| --- | --- | --- |
| `version` | `PERCH_VERSION` | 三段产品版本 |
| `build` | `PERCH_BUILD_NUMBER` | 递增的正整数构建号 |
| `feedURL` | `PERCH_SPARKLE_FEED_URL` | 栖集独立的 appcast HTTPS 地址 |
| `publicEDKey` | `PERCH_SPARKLE_PUBLIC_KEY` | 栖集独立的公开验签密钥 |

`PERCH_UPDATE_CONFIG` 可指定另一个 JSON 文件；私钥不得写进配置、环境变量、源码或应用包。不要复用 Samantha 的 appcast 或密钥。

```bash
# 仅打包开发版本，不关闭或打开应用。
./script/build_and_run.sh --no-open

# Release 通用包；不传签名身份时仅使用 ad-hoc 签名，供本机验证。
PERCH_SIGNING_IDENTITY='Developer ID Application: <name> (<team>)' \
  ./script/build_and_run.sh --release --universal --no-open
```

输出默认是 `dist/栖集.app`。`PERCH_BUILD_PATH` 可指定独立 SwiftPM 构建目录；`PERCH_DIST_DIR` 可指定独立输出目录。框架来自已锁定的 SwiftPM artifact，用 `ditto` 保留软链与权限，应用通过包内 Frameworks runpath 加载。打包脚本按 XPC、Autoupdate、Updater.app、framework、Helpers 资源包、内置 CLI、主应用的顺序签名，并执行严格递归验签和仓库外 CLI/MCP 握手验证。

当前发布 Bundle ID 为 `com.xiezhixin.perch`，内置 CLI 位于 `Contents/Helpers/skillset`。后续更新保持同一 Bundle ID 和稳定的安装路径，使宿主配置引用的内置 CLI 路径持续有效。

## 后续发版步骤

Sparkle 工具随依赖下载至 `<构建目录>/artifacts/sparkle/Sparkle/bin/`。发布机已有可用公证 profile：`APP-Notary-2026`；它由 notarytool 从钥匙串读取，不在仓库保存凭据。

1. 先核对发布机是否已有栖集专用的 Sparkle 密钥；有则沿用。尚未创建时，使用 `generate_keys --account com.xiezhixin.perch` 创建独立密钥。私钥保留在发布机 Keychain，并安排安全的独立备份；仅把输出公钥写入配置。之后 `generate_appcast` 使用同一 account。
2. 配置独立 appcast 地址，递增构建号，以 Developer ID 签名构建 Release 通用包。核对 `codesign -dv --verbose=4` 的 TeamIdentifier、hardened runtime、包版本和公钥。
3. 将应用打成 ZIP，使用 `xcrun notarytool submit --keychain-profile APP-Notary-2026 --wait` 完成 Apple 公证；执行 `xcrun stapler staple`、`xcrun stapler validate` 和 `spctl --assess --type execute --verbose=4`。将已装订应用与 `/Applications` 链接制作成 DMG，Developer ID 签名后再提交 DMG 公证并装订。官网下载 ZIP 从已装订应用重新生成。
4. 使用 `python3 script/prepare_sparkle_update.py <已公证DMG> <新的输出目录>` 生成签名 appcast。脚本验证应用版本、公钥、地址、公证和系统信任，再调用 `generate_appcast --account com.xiezhixin.perch` 与 `sign_update --verify`，核对 enclosure URL、版本、长度、Ed25519 签名和最低 macOS 14。签名覆盖最终 DMG 字节，之后不能修改包；脚本拒绝覆盖既有输出目录，也不自动上传。
5. 先上传唯一 DMG，核对公网完整下载 SHA-256、长度以及 GET/HEAD/Range；备份旧 appcast，再替换清单。清单应返回 `Cache-Control: no-cache`，保留旧包，不覆盖已经公开的构建。
6. 用前一版正式安装包检查更新，完成下载、安装、重启，并验证项目数据与包内 CLI/MCP。记录签名、公证和线上校验结果后再宣称更新可用。

首次启用需手动安装一个已经内置公钥与地址的版本；先前未包含 Sparkle 的应用无法自行发现此次更新。丢失私钥会影响旧客户端验签，不应直接生成新密钥并覆盖线上公钥。

钥匙串排查：新创建的密钥可能只信任 `generate_keys`。此时即使钥匙串已解锁、`generate_keys -p` 成功，`generate_appcast` 和 `sign_update` 仍可能返回 `-25308`。在“钥匙串访问”中按 account 找到栖集专用项，经用户授权后，仅把当前 Sparkle artifact 中的这两个官方工具加入访问控制列表。若仍失败，核对该项的 partition 列表是否只包含创建工具的 cdhash；使用 `security set-generic-password-partition-list`，按栖集 account 和 Sparkle service 精确匹配该项，仅添加已批准工具各架构的实际 cdhash。密码由用户在本机终端提示中输入，不通过 `-k` 参数、聊天或日志传递。工具升级后重新核对 hash；无需导出私钥、重建密钥或开放给所有应用。

## 本地验证

```bash
swift test --filter 'UpdateConfigurationTests|SettingsTests|LocalizationTests|NavigationLayoutTests'
python3 -m unittest tests.test_update_packaging tests.test_ui_localization -v
./script/build_and_run.sh --no-open
```

配置测试覆盖有效公钥、缺失配置、危险地址、无效密钥、版本号、环境变量覆盖和失败不修改 plist；应用测试覆盖未配置时的禁用状态。真实在线安装升级须在发布服务与签名配置完成后单独验收。

上游依据：[Sparkle 接入文档](https://sparkle-project.org/documentation/)、[配置选项](https://sparkle-project.org/documentation/customization/)。

2026-10-22 接入验证：13 项 Swift 配置、设置、翻译与原生布局检查，以及 8 项 Python 配置与文案检查通过；Debug 包和 Release arm64 / x86_64 通用包严格递归验签通过，两种包内 CLI 与独立 CLI 均在仓库外完成 MCP 握手（14 个工具）。Debug 应用复制到仓库外的含空格路径后可启动，动态加载日志确认使用包内 Sparkle。产物为 ad-hoc 签名，未验证 Developer ID、公证、线上更新或跨版本安装。

2026-10-22 构建 `0.0.1 (2)` 验证：

- `Developer ID Application: zhixin xie (77TN4427T5)` 签名、hardened runtime 与 arm64 / x86_64 通用架构通过；应用和 DMG 均已公证并装订。应用公证 ID：`8160325a-d3b0-4e5f-b7a4-569a6bbfb4f5`；DMG 公证 ID：`9b8bfc3f-9e6f-4ffc-ae71-3858a2cf75d0`。
- 严格递归验签、`stapler validate`、`spctl`（`Notarized Developer ID`）通过；应用内 CLI 和独立 CLI 分别通过仓库外 MCP 握手（17 个工具）。14 项 Swift 更新、设置、翻译与布局检查及 8 项 Python 配置与清单检查通过。
- DMG：`Perch-0.0.1-2-universal.dmg`，25,097,611 字节，SHA-256：`46ba7ba9a4f3fabc8d058911e9d2efad2c02e4d2dbbebe114ba7fca21ce1c4db`。ZIP：20,869,967 字节，SHA-256：`a327f42ace8ba63d0ec190618abc54bc7e870d31d023c60bb7ccfa1011dc1729`。本地报告位于 `dist/release-v0.0.1-2/release-verification.json`。
- 站点整包超过平台 25 MiB 上传上限；已改用既有 SSH 发布通道增量上传唯一命名 DMG 与 ZIP，服务器和公网完整下载的 SHA-256、长度一致，HEAD 返回 200，旧文件保留。站点对 Range 请求返回完整文件（200），当前不支持分段续传。公网下载检查报告保存在 `dist/release-v0.0.1-2/public-download-verification.json`。
- 用户已批准两个签名工具访问栖集密钥，并在本机完成精确的 partition 授权修复；私钥未导出。`generate_appcast` 与 `sign_update --verify` 均成功。
- 已发布签名 enclosure 的 [RSS 清单](https://perch.keli.tech/updates/macos/appcast.xml)，公网响应为 XML 内容并返回 `Cache-Control: no-cache`；清单字节与本地一致，SHA-256：`871bfc3897fcafc22eb35a260adae3599fd79144686dec2101ec174d369b9cc9`。官网已切换到 build 2 的 DMG 和 ZIP。验证报告：`dist/release-v0.0.1-2/public-appcast-verification.json`。
- 在仓库外、隔离的 `CFFIXED_USER_HOME` 中启动正式应用 `0.0.1 (2)`，设置页更新按钮可用；实际检查公网清单后，Sparkle 显示 “You’re up to date!”。未修改真实项目或宿主配置。
- 待完成：两个正式版本之间的下载、安装、重启与数据保留验收；首次启用版不将旧 build 1 视为已具备更新能力。

2026-10-22 构建 `0.0.1 (3)` 本地发包验证：

- 沿用栖集专用 Bundle ID、公钥、Developer ID 和公证 profile。App 与内置 CLI 均包含 arm64 / x86_64，hardened runtime、严格递归验签通过；应用和 DMG 均已公证并装订，Gatekeeper 返回 `Notarized Developer ID`。应用公证 ID：`39a2f686-a017-4024-8276-e106f4d5fa62`；DMG 公证 ID：`0fb324ba-8529-407e-8c1d-d9cfa2c7081e`。
- `swift test` 通过：116 项 Swift Testing、69 项 XCTest 和 315 项 BDD 步骤；Python 31 项、Node 5 项通过，技能结构和目录指纹检查通过。包内 CLI 与独立 CLI 均在仓库外通过 MCP 握手和安装审批链路验证（17 个工具）。
- DMG：`Perch-0.0.1-3-universal.dmg`，24,584,847 字节，SHA-256：`9a1030d9e3a90206f5491b4a65b519f74e774bc28bb867dcca93ea94ac69af9f`。从已装订应用生成的 ZIP：20,896,498 字节，SHA-256：`d834ba3a422cf1eb99f75f50f298ace5e208f1fc4ededf7414de21e15bfc71de`。
- `script/prepare_sparkle_update.py` 成功生成 `dist/sparkle-release-0.0.1-3/`，包含最终 DMG 与签名清单；`sign_update --verify` 通过，清单绑定 build 3、最低 macOS 14、最终包长度及正式下载地址。清单 SHA-256：`0897d5c170aabb16970924b74cc8372026d7099701842ca87069c48fe6072d8b`。完整报告：`dist/release-v0.0.1-3/release-verification.json`。
- 本轮仅生成本地更新包，没有上传或替换线上清单；打包前公网清单仍为 build 2。待发布后验收公网字节、build 2 → build 3 下载、安装、重启与数据保留。

2026-10-22 构建 `0.0.1 (3)` 上传验证：

- 通过既有 SSH 发布通道增量上传唯一命名 DMG 与 ZIP，核对服务器 SHA-256 后发布下载路径，再对公网完整下载核对长度和 SHA-256；与上述已公证本地产物一致，公网 DMG 的 Sparkle 签名验证通过。HEAD 返回 200，但不提供 Content-Length；长度按完整 GET 实际字节核验。Range 返回完整文件（200），仍不支持分段续传。报告：`dist/release-v0.0.1-3/public-download-verification.json`。
- 下载包验证完成后替换清单与官网首页。公网清单字节与本地签名清单一致，build 为 3，返回 `Cache-Control: no-cache`；首页已指向 build 3 的 DMG 和 ZIP。清单报告：`dist/release-v0.0.1-3/public-appcast-verification.json`。
- 旧清单与首页备份在发布服务器 `perch-release-backups/build-3-20261022T055058Z/`；既有安装包逐一复核 SHA-256，全部保持原样。未修改平台上传上限或访问权限。
- 待完成：build 2 → build 3 的应用内下载、安装、重启与数据保留验收；本次上传校验不等同于完成安装升级。

2026-10-22 构建 `0.0.1 (4)` 新平台迁移与发布验证：

- 目标平台为 `https://app.u1.fan`，应用 `perch`，内部挂载路由 `/x/perch/`；清单、enclosure 和官网链接均使用该挂载路径。`script/prepare_sparkle_update.py` 从清单地址计算官网路径，不再硬编码 keli.tech。
- 保留原 Bundle ID 与 Sparkle 公钥。应用及内置 CLI 均为 arm64 / x86_64，Developer ID、hardened runtime、严格递归验签、Apple 公证、装订和 Gatekeeper 检查通过。应用公证 ID：`045232b1-a0e9-4cd4-91e7-92bed53de886`；DMG 公证 ID：`c4a09e27-df3c-4155-821e-01c996b33b96`。
- DMG：`Perch-0.0.1-4-universal.dmg`，25,210,037 字节，SHA-256：`e4b2f26e190f8ee89173f17e4a90a67e2e809607dfc9a64d89185506a30843e0`。签名清单 SHA-256：`8a066165f4bdbed3bc3ed149be09be664a53a7c63dd7e868872546f5ecea6ea3`，`sign_update --verify` 通过。ZIP 保留为本地离线产物，不进入新站发布包。
- Python 31 项、Swift 更新与设置 7 项通过；包内及独立 CLI 均完成仓库外 MCP 验证（17 个工具）。`app-platform package` 的完整文件清单和逐文件字节一致；真实隔离预览的首页、图片、DMG、appcast 共 4 个文件 HTTP 与 SHA-256 核验通过，预览退出后临时数据已清理。预览 Range 返回完整文件（200）。
- 平台发布目录：`dist/perch-app-platform-v0.0.1-4/`；上传 ZIP 为 `dist/perch-app-platform-v0.0.1-4.zip`，23,325,935 字节，低于平台 25 MiB 上限。CLI 会排除 `.zip` 文件，改为 `.download` 后 DMG 与 ZIP 合包仍超限，因此官网统一使用 DMG。
- 已通过现有管理员 CLI 登录发布，新平台 release ID 为 `407bf84e-1cfc-4d5e-b5da-83b46d84de57`。登录数据位于本机 `~/data`；CLI 默认按当前工作目录查找 `data`，发布时须显式复用有效目录。旧 keli.tech 站点未修改。完整报告：`dist/release-v0.0.1-4/release-verification.json`。
- 平台设置了独立应用根域，`https://app.u1.fan/x/perch/` 及其资源会以 308 跳转到 `https://perch.u1.fan/`。发布后补齐了 Perch 专用 Nginx 入口，复用已有有效通配证书；未修改平台应用根域、证书或其他应用配置。配置见 `website/perch/perch.u1.fan.nginx.conf`，服务器维护记录：`/root/deploy-backups/perch-hosting-build4-20261022T0655Z/`。
- 匿名 HTTPS 验证首页、图片、appcast 和完整 DMG，最终地址均为 Perch 子域；4 个文件长度与 SHA-256 均与发布目录一致。公网 DMG 的 `sign_update --verify` 通过；清单保持新平台 enclosure、build 4、macOS 14 与原公钥，返回 `Cache-Control: no-cache`。HEAD 返回 200 和长度 25,210,037；Range 返回完整文件（200），不支持分段续传。报告：`dist/release-v0.0.1-4/public-platform-verification.json`。
- Nginx 配置检查及 reload 通过，既有平台与 Capslock Bye 配置逐字节保持原样；平台、Capslock Bye 及同机两个站点的公网首页摘要在变更前后一致。HTTP 到 HTTPS 跳转保留路径与查询参数。浏览器自动化工具超时，未完成本轮浏览器视觉复核；已通过真实公网匿名 HTTP 与文件校验。
- 待完成：手动安装迁移版后，两个正式版本之间的应用内下载、安装、重启与数据保留验收。旧版内置旧 feed，不会自行发现新平台，本次不修改旧清单。通配证书沿用平台现有手工 DNS-01 续期安排，到期时间为 2027-01-20；本次未更改续期策略。
