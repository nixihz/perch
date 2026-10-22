# 栖集 0.0.1 (6)

本次把配置体验按用户任务重新组织：同一项目的 Codex 与 Claude Code 可以分别选择技能和规则；MCP 配方可以从详情直接选择使用目标；配置关系图解释来源、能力库、作用范围和栖集自身接口。旧共享草稿仍可读取，浏览与切换不写入宿主配置。

点击数按源码路径推导：在默认目标正确的条件下，MCP 配置库详情到批准写入由 5 次降至 4 次；尚未进行真实用户点击计时。数据清晰度的设计和验收依据见[配置体验研究](../specs/configuration-experience.md)。同一技能在同一项目仍共用一个内容 revision；需要共同更新时，应显式选择多工具计划。

## Standards

基线为 `b3553bb`，范围包括全部工作区修改与未跟踪源码。独立审查依据 AGENTS.md、DESIGN.md、架构规范及 Fowler smell baseline。

发现 1 项明确规范问题：MCP 使用范围直接回显底层异常。已改为界面层固定提示，并验证损坏配置不回显外部标记、不修改源文件。Core 审查未发现新增审批绕过、跨宿主写入或旧清单兼容缺陷。

另有 1 项非阻断的结构建议：`ProjectRecord` 同时持有当前工具投影和完整选择映射，可后续统一修改入口，减少状态同步负担。

## Spec

发现 1 项需求偏差：片段使用位置合并两个宿主，查看配置可能进入错误工具。现按项目与宿主分别显示状态，跳转保留目标工具；回归覆盖跨项目跳转、独立状态与零写入副作用。

补充边界审查修复 5 项：skills.sh 安装身份受本机重命名影响、切工具或载入预设后旧提示未失效、受阻目录候选错误回退到另一同名技能、MCP 使用目标沿用过期项目上下文、URL 参数中的查询凭据未被识别。对应测试检查实际状态、文件或失败路径。

两轴统计：Standards 1 项明确问题已修复，保留 1 项非阻断结构建议；Spec 1 项偏差已修复。补充行为审查 5 项问题纳入发布前回归。

## 更新内容

- 配置、能力库、来源、对外接口四组导航，加上可直达页面的配置关系图。
- 独立保存 Codex 与 Claude Code 技能、规则与草稿；单工具计划保留另一工具已部署内容及待部署草稿。
- MCP 详情显示连接方式、使用范围及写入记录，支持直接使用；入库和配置写入不再混为一种状态。
- AI 接入主操作前置，明确“AI 工具调用栖集”与“AI 工具连接外部 MCP”两种方向。
- skills.sh 目录浏览与按需收录，来源身份固定，来源脚本不执行；收录后仍需另行选择项目并批准。
- 发布包能定位包内技能快照；无变化与错误结果在项目页就近反馈。

## 验证与发布

已于 2026-10-23 发布到 [app.u1.fan](https://app.u1.fan/x/perch/)，公开入口为 [perch.u1.fan](https://perch.u1.fan/)。平台 release ID：`8175cd1d-0cd5-4de5-9431-eb90e95b8b59`；上一版 `4b4ee2af-fd9c-4ced-8cf0-78f6ff30fbbe` 保留在平台发布历史中供回滚。

| 批次 | 提交 | 内容 |
| --- | --- | --- |
| 1 | `2bc2fa6` | Harness 独立选择、兼容与部署边界 |
| 2 | `583f44f` | skills.sh 收录、来源身份与包内资源定位 |
| 3 | `be26bcf` | 配置导航、MCP 路径、原生 UI 与行为回归 |
| 4 | `5dc9be2` | BDD、隔离夹具及配置体验研究 |
| 5 | `09be0a4` | build 6 配置、官网源码及发布准备 |

已推送 annotated tag：`perch-harness-independent-20261023` 指向核心里程碑；`perch-v0.0.1-build.6` 指向正式产物源码 `09be0a45a93a782ce653ac5296b8615f7ac05b39`。随后提交的发布记录不改变产物。

完整 Swift 回归：31 个 BDD 场景、399 个步骤（BDD target 406 项），核心 XCTest 11 项、Swift Testing 140 项、应用 XCTest 100 项通过。最后的 MCP 与目录边界改动另跑相关专项：应用 XCTest 45 项、Swift Testing 35 项通过。Python 31 项、Node 5 项及目录指纹、diff 检查通过；所有成功回归均零失败、零跳过。

App 与 CLI 均为 arm64 / x86_64；Developer ID、hardened runtime、递归验签、Apple 公证、装订和 Gatekeeper 检查通过。应用公证 ID：`1e8e9077-05d8-414b-b5c2-45a1ff00051b`；DMG 公证 ID：`cd1ef5db-989f-4c66-a352-f8654733bdb6`。包内与独立 CLI 均通过仓库外 MCP 握手，发现 17 个工具。

[正式 DMG](https://app.u1.fan/x/perch/updates/macos/Perch-0.0.1-6-universal.dmg)：26,174,606 字节，SHA-256：`fd673b819a48977401fc2e2f0b15daa98c7834befac2532301f12e32db7f7bdd`。平台 ZIP 为 24,120,417 字节，低于 25 MiB 上限；完整集合为 5 个来源文件和 1 个经核对的 CLI 源码元数据文件，逐文件字节一致，没有额外文件、符号链接或危险路径。

临时 HTTP 预览和匿名公网首页、品牌图、appcast、DMG 均与发布目录逐字节一致；公网下载再次通过官方 Sparkle Ed25519 验签。清单返回 `Cache-Control: no-cache`，build 为 6；HEAD 返回正确长度。Range 仍返回完整 200，当前不支持分段续传。临时预览已退出并删除临时数据。

发布前发现平台 `manifest.access=public` 但实例 `visibility=personal`，旧版清单被引导登录。已只恢复 Perch 的 `visibility=public`，核对旧版首页、清单及安装包与原发布记录一致后再发布 build 6；未修改其他应用或基础设施。

本机报告保存在 `dist/release-v0.0.1-6/`：`release-verification.json`、`platform-preview-verification.json`、`package-verification.json`、`public-platform-verification.json` 及公证、签名日志。

尚未验收：build 5 → 6 的真实安装、重启与数据保留。Sparkle 2.10 重启使用 NSWorkspace，未传递隔离 HOME；同一 macOS 用户下的临时副本不能保证重启隔离，应在独立图形用户会话或 VM 中验证。公网下载验签不替代该验收。真实用户的点击耗时、理解正确率以及 AI 工具加载状态也不在本次自动化验证结论内。
