# macOS 快速发版

栖集沿用 SwiftPM 构建、Developer ID 签名、Apple 公证和 Sparkle DMG 更新。发布流程参考 `/tmp/macos-sparkle-release-handoff.md`，复用现有打包入口，不增加 Xcode 工程，也不改变 Bundle ID、公钥或更新地址。

## 常用命令

首次在发布机上检查依赖和凭据：

```bash
swift package resolve
task macos:release:preflight
```

全量测试独立执行，不随发布准备自动运行：

```bash
task test
```

该任务包含 Node、Python、Swift 与原生 BDD；原生交互需要已解锁的桌面会话及 Accessibility 权限。`macos:release` 不调用此任务，也不检查它此前是否通过；发布包准备成功不代表全量测试通过。

提交源码和本次发布脚本后，生成下一版：

```bash
task macos:release
```

默认版本沿用 `config/updates.json`，构建号取“本地配置与线上清单的最大值 + 1”。线上清单无法读取、返回 HTML 或格式错误时停止，不猜测构建号。命令不会修改仓库中的版本配置，实际发布参数固定在产物目录的 `updates.json`。

也可指定产品版本和构建号；构建号必须高于线上版本：

```bash
task macos:release -- --version 0.0.2 --build 17
```

产物准备成功后，发布到现有的 **`https://app.u1.fan`**：

```bash
task macos:publish -- dist/release-v0.0.2-17
```

发布命令固定使用该平台，更新清单保持 `https://app.u1.fan/x/perch/updates/macos/appcast.xml`。官网与清单可能跳转至 `perch.u1.fan`，脚本允许 HTTPS 跳转，但平台上传目标始终为 `app.u1.fan`。

默认输出为 `dist/release-v<版本>-<构建号>/`，可通过 `--output` 指定新目录。任何失败都保留日志和中间产物；脚本拒绝覆盖已有目录。解决问题后使用新的输出目录重新执行，不复用可能对应旧源码的归档。

## 一次性准备

发布机需要 macOS、Swift 6、Xcode Command Line Tools、Task、Node、Python 3、支持 Ed25519 的 OpenSSL 3，以及现有的 `app-platform` CLI。后者用于离线生成平台包，不会在准备阶段登录或上传。

三类凭据分别检查：

| 用途 | 默认来源 | 可覆盖参数 |
| --- | --- | --- |
| 代码签名 | 唯一有效的 Developer ID Application 证书 | `--signing-identity` 或 `PERCH_SIGNING_IDENTITY` |
| Apple 公证 | Keychain profile `APP-Notary-2026` | `--notary-profile` |
| Sparkle 签名 | Keychain account `com.xiezhixin.perch` | `--account` 或 `--ed-key-file`，二选一 |

现有客户端标识保持为：

- Bundle ID：`com.xiezhixin.perch`。
- 公钥：`3EB2chk/1iPXBBWYoCpL1IMTXf09D0IsFnH9oceg5oI=`。
- 清单：`https://app.u1.fan/x/perch/updates/macos/appcast.xml`。
- 应用：`栖集.app`；内置 CLI：`Contents/Helpers/skillset`。

脚本不调用 `generate_keys`。预检用所选私钥签名临时文件，再分别由 OpenSSL 和官方 Sparkle 工具验签；OpenSSL 使用配置中的客户端公钥，能发现错用其他应用私钥的问题。

如果钥匙串授权不适合自动发布，可使用**已有私钥的安全备份**：

```bash
chmod 600 /private/release/perch-sparkle.key
task macos:release:preflight -- --ed-key-file /private/release/perch-sparkle.key
task macos:release -- --ed-key-file /private/release/perch-sparkle.key
```

文件内容为 Sparkle 官方工具可读取的 Base64 私钥；当前格式和旧格式均由官方工具解析。私钥文件必须只有所有者可访问，且不能是符号链接。不要将私钥正文放进命令行、环境变量、日志、Git、应用包或公开目录。若由秘密存储临时写入文件，任务结束后删除。

`--config` 可指定另一份公开配置，`--sparkle-bin` 可指定官方 Sparkle 工具目录。默认工具路径为 `.build/artifacts/sparkle/Sparkle/bin`。正式发布须保持客户端的原 Bundle ID、公钥与 feed；不要把开发用身份覆盖带入正式版本。

## 自动完成的步骤

1. 读取匿名公网清单，确定递增构建号；检查干净工作区。
2. 检查 Developer ID、公证 profile、Sparkle 工具和私钥签名能力，失败时不开始构建。
3. 保存源码 commit、所有受版本控制文件的内容与权限指纹，以及固定的发布配置。
4. 执行项目已有的 `task check`，检查技能结构、目录指纹并构建原生应用，失败时停止；不运行 `task test` 中的测试套件。
5. 调用 `script/build_and_run.sh --release --universal --no-open`，生成 Developer ID 签名的应用和内置 CLI。既有脚本继续负责嵌套代码签名和仓库外 MCP 握手。
6. 检查版本、Bundle ID、公钥、更新策略、hardened runtime 和 arm64 / x86_64 架构；对应用提交公证并要求 `Accepted`，再装订并执行 Gatekeeper 检查。
7. 从已装订应用创建含 `/Applications` 链接的 DMG，对 DMG 签名、公证、装订。
8. 复用 `prepare_sparkle_update.py` 检查 DMG 内应用、生成单版本 appcast、关闭增量包，校验最终包长度、URL 和两种工具的 Ed25519 验签。
9. 生成与本次版本一致的平台目录及离线 ZIP，最后再次核对源码未变，写入发布记录。未生成 `release.json` 的目录不能进入新发布器。

检查后、构建后或打包后源码发生变化都会停止。发布目录应放在 Git 忽略的 `dist/` 中，或仓库之外，避免中间产物影响干净工作区检查。此命令只准备产物，不修改线上服务或本机安装。

### 测试取舍

测试沿用已有的独立入口 `task test`，`macos:release` 只调用 `task check`，不再自动执行测试，也不增加跳过测试的发布参数。测试套件不按名称过滤，精简只删除无效断言和重复覆盖：

- 不检查测试自己创建且未被操作的不可变值。例如，排序函数返回新数组，检查输入数组的固定正文不能验证排序结果；保留顺序、完整记录、同名次序和空列表测试。
- 不用源码包含 `Text(...)` 等写法证明界面行为；重构写法不应导致失败，未翻译正文也不能仅凭这些字符串宣称通过。
- 翻译键覆盖、英文目录内容与占位符数量统一由 Python 检查；Swift 保留插值、语言切换、用户内容保留、错误恢复与敏感信息隐藏测试，不重复维护背景加载文案清单或已退出正常启动流程的内置示例清单。
- 空技能目录下的预设引用检查与“没有内置技能”重复，只保留后者；用户预设的保存、合并、冲突和失效引用行为继续测试。
- 同类按钮的中心、边缘、控件外和禁用点击集中在命中区域测试，不再另建只覆盖中心点击的测试窗口。

审批、真实文件写入与回读、来源漂移、回滚、签名验签和原生交互测试不因耗时而删除。原生交互仍需要交互式会话和 Accessibility 权限；跳过不等于通过。

输出示例：

```text
dist/release-v0.0.1-16/
  updates.json               固定发布参数
  source-before.json         源码 commit 和逐文件指纹
  app-notary.json            应用公证结果
  dmg-notary.json            DMG 公证结果
  sparkle/                   唯一 DMG 与签名 appcast
  platform/                  原有应用平台可使用的官网发布目录
  platform.zip               平台离线包
  platform-package.json      平台包实际文件和大小报告
  release.json               签名身份、公证 ID、源码及产物 SHA-256
```

## 发布到 app.u1.fan

沿用现有 `app-platform` CLI 登录，运行：

```bash
task macos:publish -- dist/release-v0.0.1-16
```

等价的上传操作是 `app-platform --server https://app.u1.fan publish --update <发布目录>/platform`。如现有登录存放于独立客户端目录，添加 `--client-data <现有登录目录>`。没有有效登录时按 CLI 的错误处理，不输出 token 或自动重新登录。

需要恢复登录时，在本机运行 `app-platform --server https://app.u1.fan login`，通过浏览器完成授权，再重试发布。公证 profile 读取失败时先运行 `xcrun notarytool history --keychain-profile APP-Notary-2026` 排查；不要因为一次 lookup failure 就重建密钥或覆盖公证凭据。

发布器先校验发布目录逐文件 SHA-256 和客户端公钥签名，再读取线上版本；拒绝相同构建号不同清单及版本回退。旧 appcast 备份到本地 `previous-appcast.xml`，官网、品牌图、DMG 和清单作为同一平台版本上传。相同产物重复执行时跳过上传，继续进行公网验收。

发布后自动匿名核对公网 appcast 的全部字节、DMG HEAD、完整 GET 的长度与 SHA-256，以及 Range 前 1024 字节；另外检查前一版包的公开地址。`publication.json` 记录平台提交完成和旧清单备份位置，`public-verification.json` 记录公网检查结果。上传成功但公网校验失败时保留中间状态，不声称公网验收通过；相同命令可重新验收。

## 平台验收边界

本项目继续使用 `app.u1.fan` 的整包发布，不增加 SSH 或服务器挂载目录。2026-11-02 只读核查时，线上清单为 build 15，build 14 的公开 DMG URL 返回 404；平台发布历史不等同于旧文件仍可下载。旧地址检查失败会记录 `previousArchiveAvailable: false` 并输出说明，正在下载旧包的客户端可能需要重新检查更新。

交接文档中的“永久保留旧包、文件系统原子替换 appcast”由此平台的发布能力决定，本脚本不声称已经满足。本次不修改平台实现、服务器路由或保留策略；回滚沿用平台发布历史，旧清单和本次完整产物在本机另有留档。

服务端验收仍需检查 XML/DMG Content-Type、清单的 `Cache-Control: no-cache`、Range 返回 `206`、以及旧包可下载。若服务器忽略 Range 而返回 `200`，脚本会在报告中明确记录 `rangeSupported: false`，不能据此宣称支持分段续传。

最后从前一版正式客户端完成“检查更新 → 下载 → 安装 → 重启”，核对版本、项目数据和内置 CLI/MCP。准备成功或公网字节一致均不替代实际升级验收，报告中的 `clientUpgrade` 保持 `pending`。

上游依据：[Sparkle 发布文档](https://sparkle-project.org/documentation/publishing/)；具体参数以本仓库锁定的 Sparkle 2.10.0 工具 `--help` 为准。

## 本次接入验证（2026-11-02）

- Python 全量测试 60 项、Node 测试 5 项、Swift 更新配置／设置／翻译／布局回归 25 项通过；Python 编译和 `git diff --check` 通过。
- 使用公开测试向量调用实际 Sparkle `sign_update`，私钥文件签名、官方工具验签、OpenSSL 客户端公钥验签通过；错误公钥和被修改的包均被拒绝。
- 使用临时测试包调用实际 `app-platform package`，平台 manifest、官网、品牌图、DMG 和 appcast 共 5 个文件被完整收录；官网两处下载入口和显示版本对应指定发布版本。
- 本机 Developer ID、`APP-Notary-2026` 和原 Sparkle 私钥的完整预检通过；`app.u1.fan` 的 CLI 登录已恢复。
- 首次完整准备在测试阶段发现部分历史测试仍依赖已移除的个人技能。预设与 BDD 测试改用临时生成、具有真实内容指纹的技能夹具，不把个人技能重新放回公开仓库。
- 每次实际构建、公证和发布的结果以产物目录中的 `release.json`、`publication.json` 和 `public-verification.json` 为准；客户端升级验收需另行记录。

## 测试精简验证（2026-11-02）

以下是测试精简阶段的记录，早于后续将 `task test` 从发布流程移除的改动。

- 本轮净减 5 个测试方法，另删除 1 条同义反复断言；未修改产品源码、发布脚本或 Taskfile。
- `task check` 通过，仍有原先的 `.claude/skills` 入口缺失或失效警告；Node 5 项、Python 59 项、Swift Testing 198 项、Core XCTest 18 项和 App XCTest 218 项通过。
- 完整 `task test` 未通过：原生 BDD 有 3 处失败，分别为展开详情后等待“来源标识”、计划确认场景填写规则正文、片段用法场景填写标题；前一轮未精简的完整基线通过。这些交互失败不是同义反复，保留测试，根因尚未确定。
- 使用 `CUCUMBER_TAGS=disclosuretargets swift test` 复跑，展开场景仍在搜索框接受输入时超时，另有预设确认按钮的 AX 操作失败；两个片段文案场景通过。标签只筛选 Cucumber 场景，其余 XCTest 和 Swift Testing 仍执行，不能将该次运行视为全部 BDD 通过。
- 合并后的按钮中心、留白及禁用点击回归通过。原生 UI 自动化问题仍需排查，本轮不声称发布验证通过，也未重新签名、公证或发布。

## 提交前复核

- 审查范围为发布测试分离、重复测试精简及配套文档；未发现本次差异引入的可确认缺陷。`git diff --check` 通过。
- `task test` 中 Node 5 项、Python 60 项、Swift Testing 198 项及 Core、App XCTest 通过；原生 BDD 的 423 个测试步骤及用例中有 2 处失败，因此完整任务仍为失败。
- 两处失败分别为 `InterfaceCopyUITests.testMCPLibraryKeepsUsageScopeCardWithoutRedundantStateExplanation` 等待隔离窗口获得输入焦点超时，以及 `PresetWorkflowUITests.testEveryPresetCanBeEditedAndDuplicatedWithoutChangingOriginalOrProject` 等待名称字段接受输入超时。失败位置均在未修改的 `NativeUIHarness`；未删除测试或放宽断言。
- 未修改代码，使用 `swift test --filter 'InterfaceCopyUITests/testMCPLibraryKeepsUsageScopeCardWithoutRedundantStateExplanation|PresetWorkflowUITests/testEveryPresetCanBeEditedAndDuplicatedWithoutChangingOriginalOrProject'` 定向复跑，两项均通过。现象与焦点或输入时序波动一致，根因尚未确认；复跑通过不替代完整任务的失败记录。
- `swift build --product SkillSetDesktop` 和 `swift build --product skillset` 通过；`ControlHitTargetTests`、`LocalizationTests`、`TemplateSortOrderTests` 定向回归均通过。
- 当前工作区的 `task check` 在技能结构检查阶段失败：Git 忽略的 `.claude/skills` 是独立目录，未复用 `.agents/skills`。未改写本机技能配置；导出受版本控制的源码并叠加当前差异后，结构检查为 0 个错误、1 个缺少发现入口警告，目录指纹核验通过。
- 本次未执行正式签名、公证或发布，不据此宣称发布验收通过。
