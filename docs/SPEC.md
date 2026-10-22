# Skill Set SPEC

状态：Alpha 本地工作流切片（2026-10-22）。已覆盖项目锁与离线对象、双宿主项目写入、来源预览与本机技能库导入、MCP 配置、Plugin 盘点与审批门控生命周期、CLI 与 stdio MCP；marketplace 浏览、跨进程锁和来源自动更新仍未完成。

## 1. 产品定义

Skill Set 是一个**本地 macOS 桌面应用**和 Git 大仓，不是 Web 软件，也不以浏览器页面或 loopback 服务作为产品入口。它把三类可组合能力放在同一套可追溯模型里：

- **Skills**：正文、辅助资源、来源、不可变内容修订和项目选择。
- **MCP Servers**：Codex、Claude Code 以及其他宿主里的连接配置、作用域、transport、环境变量引用、健康观察。
- **Plugins**：marketplace/本地来源、宿主版本、依赖、贡献的 skills/MCP/commands/agents/hooks 和风险。

用户要回答的问题是：

> 这个项目给哪些 agent 使用哪些能力？每项来自哪里、锁在哪个 revision、会写什么文件？AI 能帮我准备到哪一步，哪一步必须由我在本机批准？

第一目标是 Brian 的单用户、多项目、本机工作流；团队协作通过 Git 仓库、清单和锁文件完成，不建设 SaaS、账号体系或技能市场。

## 2. 已确认库存

| 项 | 事实 |
| --- | --- |
| 自维护 skill | `skills/` 下 11 个 |
| 外部快照 | `/opt/case/brian/skills` 下 139 个：115 个实体目录、24 个顶层软链 |
| 本轮实体化 | `vendor/local-brian/`，139 包、916 文件、13,502,512 字节 |
| 来源化记录 | `workspace/<slug>` 11 条 + `local-brian/<slug>` 139 条，共 150 条 |
| 重名 | 6 组；同内容也保留不同 namespace |
| 阻塞 | `local-brian/ponytail-review` 中 5 条断链，完整性为 `blocked`，禁止部署 |
| 旧入口 | `.agents/skills` 和 `.claude/skills` 仍只有原来的 11 条；没有全量启用 |
| 外部版本 | 旧库 Git HEAD `4536bbd…`，工作区 dirty；本轮以逐文件 manifest/hash 作为快照事实 |

`registry/catalog.json`、`registry/local-import.json` 和 `docs/research/local-inventory.md` 是本轮迁移证据。指纹通过不等于许可、安全或模型行为审核；外部内容先私用，公开发布前必须逐来源核查授权。

## 3. 研究决策

1. **借鉴 Matt，不复制其安装副作用。** 采用 promoted / in-progress / deprecated 生命周期，但不执行会删除既有目标的软链脚本。
2. **三个版本层次互不替代。** 整仓发布版本、skill/plugin/MCP 的不可变 revision、项目锁文件分别管理。
3. **namespace 是强制的。** `workspace/stc` 与 `local-brian/stc` 可以共存；部署到同一宿主的裸目录名冲突必须人工解决。
4. **共享事实进 Git，本机观察留在用户数据目录。** 绝对路径、备份、审批、凭据状态和进程日志不进入项目锁。
5. **应用、CLI 和 stdio MCP 共用 Swift core。** 不允许 UI、CLI、MCP 各写一套文件安装逻辑。
6. **先适配 Codex 与 Claude Code。** 其他宿主只显示未知或待适配，不从一个宿主的 manifest 推断另一个宿主的能力。
7. **本机应用不监听 HTTP。** 应用自身的 AI 接入首发为 stdio；远端 HTTP MCP 只配置和观察，OAuth token 委托宿主或 Keychain。

证据见 [上游调研](research/upstream.md)、[MCP 与 Plugin 调研](research/mcp-plugins.md)。

## 4. 交付范围

### 已实现（Alpha）

- 技能库新增、搜索、完整 `SKILL.md` 阅读、本地编辑和移除；附属文件通过列表按需只读预览，支持 UTF-8 文本，二进制和超过 2 MiB 的文件提供 Finder 定位入口。来源与内容指纹默认折叠，不增加常驻文件树。外部来源“复制并编辑”、隐藏及恢复。内容写入本机 `personal` 库，版本包保留，保存后可在项目草稿中选择并通过既有计划审批部署。

- SwiftPM + SwiftUI 原生 macOS 应用，SwiftPM 产品名为 `SkillSetDesktop`，入口为 `script/build_and_run.sh` 生成并启动 `dist/SkillSet.app`。
- 原生导航：项目、Skills、MCP Servers、Plugins、来源、预设、AGENTS 片段、AI 接入。
- 载入真实 150 条 catalog、3 个预设、3 个 AGENTS 片段和 Matt 固定调研快照；搜索、详情、阻塞态、同名 namespace 可见。
- 项目 canonical path 登记、草稿持久化、preset 载入、项目观察、plan → 本机审批 → apply → journal → rollback；可同时写 Codex `.agents/skills` + `AGENTS.md` 与 Claude Code `.claude/skills` + `CLAUDE.md`。
- 项目接入第一阶段：同时盘点两个宿主的项目技能，展示已有/受管归属；同内容不自动接管，不同内容同路径冲突与受管漂移阻塞。取消技能或宿主时只移除有本机记录且未漂移的受管技能与规则块；删除可撤销，规则块外编辑保留，空文件还原与恢复预检有行为覆盖。
- 项目 `skillset.json` / `skillset.lock.json`、manifest digest、逐文件清单和内容寻址离线对象；源目录缺失时可以从锁与对象核验、恢复。
- 计划绑定项目 realpath、旧/新 hash、digest 和 10 分钟有效期；未审批、过期、漂移、重放、软链置换和 rollback 冲突会拒绝。
- GitHub 仓库根隔离预览，支持 branch/tag/commit ref，拒绝 URL 凭据和非 allowlist host，限制 12,000 文件 / 512 MiB；保存固定 commit、候选分类、内容指纹和许可迹象。
- Codex TOML、Claude 项目 `.mcp.json` 与用户 `~/.claude.json` 的真实 MCP 扫描和受管写入计划；保留未知键和其他 server，环境变量只写 `${NAME}` 引用。
- Claude Code / Codex 插件缓存与 manifest、Claude 安装索引、Codex plugin 配置的真实盘点；展示 marketplace、安装状态、revision、组件和 hooks 风险。
- Plugin 生命周期计划：操作本机已发现的插件；Claude install/update/enable/disable/uninstall，Codex install/uninstall。计划绑定 host、plugin id、scope、manifest digest、CLI realpath 和固定 argv；多缓存版本必须精确选择，执行前复核状态，执行后回读并记录 operation。
- `skillset` CLI：doctor、projects、skills、sources、objects、plugins（list/plan）、inspect、plan、plans、approve、apply、operations、rollback、mcp。
- stdio MCP legacy `2025-11-25`：项目、Skill、来源、对象、MCP 配置、Plugin 盘点与生命周期计划，pending plans、apply 和 operation。MCP 不能批准计划，也不能为高风险安装/更新作风险确认。
- Swift core 行为测试、CLI/MCP 集成测试、真实 GitHub 预览和原生 bundle 构建验证。

### 下一阶段 P0

- 项目接入与退出管理后续：明确接管已有内容、接入基线、恢复接入前状态、停止管理和操作历史界面；第一阶段的归属、冲突、取消选择清理与恢复预检已实现。完整边界见 [项目接入、配置落地与退出管理](specs/project-integration.md)。默认实体复制不变，软链接需单独验收。
- 来源预览已可逐项导入独立的本机技能库版本并参与项目部署；后续补充共享仓 Source / Revision 发布与来源更新管理，仍不直接改 catalog/vendor。
- Plugin marketplace 搜索、依赖图求解、command-source 逐项确认，以及真实宿主 reload / 当前会话加载验证。
- 祖先规则、`AGENTS.override.md`、Claude 规则加载链和有效规则遮蔽提示。
- apply 后真实宿主重载与能力验证；当前只验证落盘、hash、受管块和 MCP 配置回读。

### 后续 P1

- 三方更新/fork、来源升级、预设 revision 升级和多项目批量计划。
- operation 幂等键、跨进程项目锁、更多故障注入和缓存 GC。
- 在指定 Codex CLI、Claude Code 版本上完成 fixture 回归，不触达用户真实凭据。

### 后续 P2

- 多项目批量计划、缓存 GC、发布辅助、更多宿主、modern MCP、受控 marketplace 自动更新。
- 只有在能力矩阵和实机证据齐全后，才把某宿主标为“可部署”。

## 5. 明确不做

- 不做浏览器 Web UI、localhost API、云端同步、账号、支付或公开技能市场。
- 不把整份 `vendor/` 当默认安装包，不把收录直接等同于启用。
- 不自动运行 skill/plugin 脚本、hooks、command source、npm postinstall、archive 内程序或子模块过滤器。
- 不读取、打印、上传 API key/OAuth token，不从 Keychain 导出明文。
- 不允许 AI 通过 `confirmed=true`、自然语言或 MCP annotation 自行授权；不静默改全局入口、宿主信任或未知插件。
- 不承诺跨文件原子提交；批量操作允许部分成功，必须有 journal 和恢复路径。

## 6. 核心用户故事与验收

| 编号 | 用户故事 | 必须观察到 |
| --- | --- | --- |
| S1 | 导入散落实体和软链 | 解引用后仍可离线读取；断链/循环/越界条目 blocked，不猜目标 |
| S2 | 给不同项目选择不同能力 | desired、managed observed、inherited observed 分开；全局继承不被误报为关闭 |
| S3 | 粘贴 Matt 或其他来源链接 | 按文件夹查看技能、许可与固定 commit；逐项加入本机技能库，再到项目页选择、预览并批准写入 |
| S4 | 保存日常工程/界面/研究预设 | 预设展开为具体 revision；升级预设不改变项目锁 |
| S5 | 让 AI 帮忙设置 | AI 能检索和生成 plan；写入需要可信 UI/CLI 同一 digest 的审批 |
| S6 | 管理 MCP 与 Plugin | 宿主配置格式分开；env 只保存引用；组件、依赖、hooks 风险全量可见 |
| S7 | 出错后恢复 | plan 后漂移、并发、软链置换、审批重放均拒绝或进入恢复，不覆盖新编辑 |

性能是待测目标，不是当前承诺：固定基准机上 1,000 条本地检索 p95 < 150ms、离线 plan p95 < 1s。

## 7. 领域模型

- `Source`：来源身份、canonical URL、requested ref、resolved commit、子路径、许可和信任状态。
- `SkillRevision`：skill ID、完整 Git commit 或 local snapshot、contentHash、文件清单、声明版本。
- `MCPServerRevision`：宿主、名称、transport、scope、command/URL、args、环境变量名称、配置节点 owner、健康记录。
- `PluginRevision`：`(host, marketplaceID, pluginName, sourceRevision)`，manifest digest、version、依赖图、组件清单、风险审查。
- `PresetRevision`：具体 Skill/Plugin/MCP revision 和规则片段，禁止浮动 `latest`。
- `ProjectBinding`：canonical realpath、目标 agent、scope、desired selections、managed/inherited observed。
- `Plan`：不可变 digest、目标路径、旧/新 hash、diff、风险、有效期和 approval 状态。
- `Operation`：journal、backup、逐步结果、恢复状态和脱敏审计。

生命周期：`draft → reviewed → promoted → deprecated → archived`。`integrity`、`licenseReview`、`trust` 与生命周期独立保存。

## 8. 共享仓与本机边界

```text
skills/                         自维护正文
vendor/<source>/<skill>/         外部实体快照
registry/                        来源、目录、manifest、导入凭证
objects/                         按内容寻址的 Skill 文件与 manifest
presets/                         可复现预设 revision
templates/agents/                AGENTS/CLAUDE 片段
Sources/SkillSetCore/            Swift 领域模型与资源快照
Sources/SkillSetApp/             原生 SwiftUI 应用
Sources/SkillSetCLI/             CLI 与 stdio MCP

~/Library/Application Support/Skill Set/
  projects.json                  本机注册项目与绝对路径
  project-drafts.json            本机项目草稿
  plans/                         待审与已执行计划
  staging/                       计划新的受管内容
  operations/                    审批、journal、backup、审计
  previews/                      隔离来源 checkout 与预览记录
```

项目 `skillset.json` 表达期望，`skillset.lock.json` 锁定具体 object、目标宿主和逐文件 hash；本机 `.skillset-local/` 只记录观察和恢复信息。迁移凭证中的私有绝对路径仅限本仓私有使用，公开导出必须剥离。

## 9. 当前交互边界

项目页会真实登记项目、保存草稿并在二次确认后写入所选宿主的 skills 与规则文件，同时生成项目锁。来源页会真实 clone 到 Application Support 隔离区并保存预览，用户逐项确认后可将完整技能包导入本机技能库，不修改仓库 catalog/vendor；导入后的项目使用仍需独立生成计划和批准。MCP 页会读取真实配置并生成受管写入计划；Plugin 页会读取真实缓存、安装索引和风险，并为本机已发现插件生成生命周期计划。盘点不启动 Plugin 进程或执行 hooks/commands；生命周期计划只有本机人工批准后才调用固定宿主 CLI。AI 接入页与实际 stdio MCP 共用服务边界，但不提供自我审批或风险代确认。

浏览器实现不是运行入口；产品只走原生 `.app`、`skillset` CLI 和 stdio MCP。

## 10. 待决策

- M1 使用 copy 还是只指向应用不可变 store 的 link：默认 copy，link 需先做宿主和备份验证。
- 是否把旧 `/opt/case/brian/skills` 归档：不自动修改，先完成许可和阻塞审查。
- MCP modern 与 legacy 的 SDK 锁版本：必须以当前目标客户端的端到端证据决定。
- 是否支持 Codex Plugin manifest：当前官方 schema 证据不足，先只显示 marketplace 和能力矩阵。
- 公开发布范围：完成许可、脱敏、可执行内容审查前不发布外部快照。
