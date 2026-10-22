# 栖集在线更新

已接入 Sparkle 2.10.0，参考 `/opt/case/iamx/tod/apple/Sources/MacUpdates.swift` 的单更新器与设置交互。当前交付为客户端与打包接入，尚未配置线上清单、公钥或发布更新包，也未完成两个正式版本之间的安装升级验收。

## 客户端行为

- 应用菜单与设置页共用一个更新器。设置显示版本、构建号、自动检查开关与“检查更新…”。
- 自动检查的授权、开关持久化和检查周期由 Sparkle 管理；自动安装关闭，用户决定安装时间。
- 地址和公钥同时留空时，不启动更新器，显示“此版本尚未开启在线更新。”；缺失一项或配置无效时，打包脚本直接失败。
- 更新地址只接受无凭据、无片段的 HTTPS URL，公钥必须是 Base64 编码的 32 字节 Ed25519 公钥。下载包在解压前验签。
- 更新只替换应用包。项目文件、技能目录、宿主配置的修改仍经过原有计划与本机批准流程。

## 配置与构建

公开配置放在 `config/updates.json`。初始版本为 `0.1.0`，构建号为 `1`；每次正式发包都递增 `build`，同一个构建号不能重发不同内容。此版本是桌面整包版本，与 skill revision、项目锁版本无关。

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

Bundle ID 保持 `com.brian.skillset`，内置 CLI 保持 `Contents/Helpers/skillset`。发布后应维持稳定的安装路径，使宿主配置引用的内置 CLI 路径持续有效。

## 配置发布服务后的步骤

Sparkle 工具随依赖下载至 `<构建目录>/artifacts/sparkle/Sparkle/bin/`。以下步骤需在正式发布时执行；本次接入没有执行密钥生成、公证或上传。

1. 使用 `generate_keys --account com.brian.skillset` 创建独立密钥。私钥保留在发布机 Keychain，并安排安全的独立备份；仅把输出公钥写入配置。之后 `generate_appcast` 使用同一 `--account com.brian.skillset`。
2. 配置独立 appcast 地址，递增构建号，以 Developer ID 签名构建 Release 通用包。核对 `codesign -dv --verbose=4` 的 TeamIdentifier、hardened runtime、包版本和公钥。
3. 将应用打成 ZIP，使用已有的 `xcrun notarytool submit --keychain-profile <profile> --wait` 完成 Apple 公证；执行 `xcrun stapler staple`、`xcrun stapler validate` 和 `spctl --assess --type execute --verbose=4`。装订后用 `ditto -c -k --sequesterRsrc --keepParent` 重新生成唯一命名的发布 ZIP。
4. 使用 Sparkle `generate_appcast --account com.brian.skillset <更新目录>` 生成签名 appcast。用 `--download-url-prefix <HTTPS下载目录/>` 指定实际下载前缀，核对 enclosure URL、版本、长度、签名和最低 macOS 14。先用 `generate_appcast --help` 检查工具参数。签名覆盖最终 ZIP 字节，之后不能重新打包。
5. 先上传唯一 ZIP，核对公网完整下载 SHA-256、长度以及 GET/HEAD/Range；备份旧 appcast，再原子替换清单。清单使用 `Cache-Control: no-cache`，保留旧 ZIP，不覆盖已经公开的构建。
6. 用前一版正式安装包检查更新，完成下载、安装、重启，并验证项目数据与包内 CLI/MCP。记录签名、公证和线上校验结果后再宣称更新可用。

首次启用需手动安装一个已经内置公钥与地址的版本；先前未包含 Sparkle 的应用无法自行发现此次更新。丢失私钥会影响旧客户端验签，不应直接生成新密钥并覆盖线上公钥。

## 本地验证

```bash
swift test --filter 'UpdateConfigurationTests|SettingsTests|LocalizationTests|NavigationLayoutTests'
python3 -m unittest tests.test_update_packaging tests.test_ui_localization -v
./script/build_and_run.sh --no-open
```

配置测试覆盖有效公钥、缺失配置、危险地址、无效密钥、版本号、环境变量覆盖和失败不修改 plist；应用测试覆盖未配置时的禁用状态。真实在线安装升级须在发布服务与签名配置完成后单独验收。

上游依据：[Sparkle 接入文档](https://sparkle-project.org/documentation/)、[配置选项](https://sparkle-project.org/documentation/customization/)。

2026-10-22 接入验证：13 项 Swift 配置、设置、翻译与原生布局检查，以及 8 项 Python 配置与文案检查通过；Debug 包和 Release arm64 / x86_64 通用包严格递归验签通过，两种包内 CLI 与独立 CLI 均在仓库外完成 MCP 握手（14 个工具）。Debug 应用复制到仓库外的含空格路径后可启动，动态加载日志确认使用包内 Sparkle。产物为 ad-hoc 签名，未验证 Developer ID、公证、线上更新或跨版本安装。
