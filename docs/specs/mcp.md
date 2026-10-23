# CLI 与本机 MCP 契约

状态：Alpha 已实现 `skillset` CLI、stdio MCP legacy `2025-11-25`、Codex / Claude MCP 配置与 Plugin 生命周期；尚未实现 modern MCP、HTTP transport、跨进程项目锁、marketplace 浏览和真实宿主加载验证。

## 1. 运行边界

- 产品入口是原生 macOS `.app`、`skillset` CLI 和 stdio MCP，不启动 HTTP server。
- stdio 的 stdout 只写 JSON-RPC 消息，诊断应在 stderr；当前集成测试会解析每一行 stdout。
- 首版实现 legacy initialize 生命周期。modern MCP 需要独立完成每请求版本元数据和真实客户端验证，不能靠修改协议字符串宣称兼容。
- 服务在收到 EOF 后退出；不常驻后台，不自动重连宿主。

## 2. 已实现工具

所有输入 schema 都是严格对象：`additionalProperties: false`。只读查询不写项目；来源预览只写 Application Support 隔离缓存；计划工具写 pending plan，但不写项目文件。

| 工具 | 关键输入 | 行为 | readOnly / destructive / openWorld |
| --- | --- | --- | --- |
| `projects_list` | 无 | 列出注册项目、desired、observed 和问题 | true / false / false |
| `presets_list` | `query?` | 列出或搜索内置与本机预设，返回完整组件和 revision | true / false / false |
| `skills_install` | `projectId` 或 `projectPath`、`skillIds`、`agents?` | 为已登记项目追加技能，返回待批准安装计划；批准后用 `deployment_apply` 写入 | false / false / false |
| `presets_install` | `projectId` 或 `projectPath`、`presetId`、`agents?` | 展开预设的技能与规则并追加到项目，返回待批准计划；混合预设转本机完整审阅 | false / false / false |
| `skills_search` | `query`、`sourceId?`、`limit?` | 搜索本机 catalog，返回 namespace、hash、许可和阻塞态 | true / false / false |
| `sources_list` | 无 | 列出已保存来源预览、固定 commit 和候选数量 | true / false / false |
| `sources_preview` | `url`、`ref?` | 隔离 clone 受信任 GitHub 仓库根，保存预览；不收录、不启用 | false / false / true |
| `projects_inspect` | `projectId` | 读取项目摘要和观察问题 | true / false / false |
| `deployment_plan` | `projectId`、`skillIds`、`instructionIds?`、`agents?`、`ruleBlockId?` | 生成 10 分钟 pending plan 和完整 digest；不写项目 | false / false / false |
| `plans_pending` | 无 | 列出未执行且未过期的计划 | true / false / false |
| `deployment_apply` | `planId`、`planDigest` | 只执行已由 UI/CLI 批准且 digest 一致的计划 | false / true / false |
| `operations_get` | `operationId` | 读取 journal、步骤状态和恢复信息 | true / false / false |
| `objects_verify` | `projectId?` | 核验项目锁引用的离线对象与 hash | true / false / false |
| `mcp_servers_list` | `projectId?` | 读取 Codex / Claude MCP 配置、名称、transport 和变量名 | true / false / false |
| `mcp_config_plan` | `projectId?`、host、scope、name、transport、commandOrURL、args?、envKeys? | 生成 MCP 受管写入计划；不读取凭据值 | false / false / false |
| `plugins_list` | `projectId?` | 读取插件缓存、安装索引、组件和 hooks 风险；不执行代码 | true / false / false |
| `plugin_lifecycle_plan` | `host`、`pluginId`、`action`、`projectId?`、`scope?`、`manifestDigest?`、`keepData?` | 为已发现的本机插件生成固定宿主命令计划；风险和批准仍留在本机 | false / false / false |

工具数量与名称由 `tools/list` 决定，文档不替代运行时 schema。`sources_preview` 的幂等提示为 false，因为远端 ref 可能移动；保存的记录仍固定 resolved commit。

项目摘要新增 `skillObservations`，逐项记录宿主、项目相对路径、可确定的技能 ID、`managed` / `existing` 归属及内容状态。观察不代表宿主已加载；旧锁缺少本机归属记录时按已有内容处理。`deployment_plan` 会生成取消选择后的受管移除步骤，未受管同路径冲突与受管漂移会阻塞；`SKILL_TARGET_CONFLICT`、`SKILL_MANAGED_DRIFT`、`RULE_TARGET_CONFLICT`、`RULE_MANAGED_DRIFT` 在 CLI 返回退出码 3。升级前缺少归属及读取依赖的待执行技能部署计划须重新生成。
当前共 17 个工具，服务握手名称与新接入配置名称均为 `perch`；CLI 可执行文件仍为 `skillset`。`plugin_lifecycle_plan` 不提供“风险确认”参数；安装或更新可能由宿主解析新包，因此 MCP 调用会返回 `PLUGIN_RISK_APPROVAL_REQUIRED`，必须转由本机 UI/CLI 生成计划。

同一 `pluginId` 和 scope 有多个缓存版本时，AI 应先调用 `plugins_list`，再把目标记录的 `manifestDigest` 传给计划工具。缺失摘要返回 `PLUGIN_VERSION_AMBIGUOUS`，不会按目录顺序猜测。

## 3. 计划与人工授权

项目安装工作流：`presets_list` / `skills_search` → `presets_install` / `skills_install` → 本机批准 → `deployment_apply`。安装参数必须提供已登记项目的 `projectId` 或绝对路径 `projectPath`，二选一；路径匹配 canonical realpath，不使用 MCP 服务工作目录推断当前项目。未登记返回 `PROJECT_NOT_REGISTERED` 并给出 App / CLI 登记入口，MCP 不自行添加写入根。两个安装工具将选定组件追加到应用数据目录内已落盘的项目安装选择，保留原有技能、规则、ruleBlockID 和宿主，不载入未部署草稿。结果包含 `status: awaiting-approval`、完整 digest 和 `nextTool` / `nextArguments`，不得据此报告已经安装。

服务 `initialize.serverInfo.name` 和 AI 接入向导的新配置键均为 `perch`。已有旧名称配置保留，避免擅自覆盖外部配置；使用向导前应在 MCP 服务页审阅旧连接并通过计划移除，然后生成 `perch` 接入计划。宿主重新加载后才可确认发现 17 个工具。

AGENTS 片段的新建、编辑和删除只开放在本机 UI，保存到本机 `templates.json`；正常启动不提供程序自带片段或预设，仅加载用户本机保存的条目；旧版用户修改过的同标识条目保留，删除记录在重启后继续生效。App、CLI 和 MCP 的部署计划共用合并后的片段库，长运行的 stdio 服务需重启以读取片段变更。本机 UI 的所有片段均可删除，引用和盘点失败不锁定删除操作；确认时说明引用将显示为不可用，需移除或替换后再部署。删除本身不修改项目文件，也不静默移除引用；旧版本或外部操作留下的失效引用在下次计划时仍拒绝。已经生成的计划保留生成时的内容和 digest，库编辑不改写既有计划；写项目仍需逐份预览和批准。本机片段页可以选择项目或全局目标，查看合成正文并生成正式计划；审批页展示规则前后内容和差异，复用同一事务与回读，不新增 MCP 片段写入工具。

原生预设的新建与编辑只开放在本机 UI。MCP 的 `presets_list` 每次合并内置与本机预设，按标识使用本机覆盖；`presets_install` 为技能与规则生成追加安装计划。包含插件或 MCP 的混合预设返回 `PRESET_REQUIRES_LOCAL_PLAN`，不生成部分计划，转本机完整载入并分别审阅组件计划。插件与 MCP 组件仍分别通过既有计划工具和本机审批处理。

原生技能库的新增、编辑与移除只开放在本机 UI，不新增 MCP 技能库写入工具。`skills_search`、`skills_install` 与 `presets_install` 每次读取最新本机技能索引；不要求重启服务才能查询和安装新技能。其他原有部署工具仍使用初始化快照。技能保存不授予项目写入权限，部署仍须经过下述审批流程。

```text
AI 调用 deployment_plan / mcp_config_plan / plugin_lifecycle_plan
    ↓
本机磁盘生成 pending plan + digest，有效期 10 分钟
    ↓
用户在本机 App 的 plan sheet 或终端执行 skillset approve
    ↓
AI 调用 deployment_apply(planId, planDigest)
    ↓
核心复核 approved、digest、旧 hash / before observation、staging 和目标路径
    ↓
文件事务或固定宿主 CLI 执行；写 journal、回读、markApplied
```

边界：

- MCP 没有 `approve` 工具，也不接受 `confirmed: true`、自然语言同意或 MCP annotation 作为审批。
- `deployment_apply` 必须收到完整 64 字符 digest；短 hash 会失败。
- 计划过期、digest 不一致、未审批、已执行、目标漂移或 staging 越界都会被拒绝。
- Plugin 计划还会复核安装事实、manifest digest、scope、CLI realpath 和 staging 命令描述；状态变化返回 `PLUGIN_STATE_STALE`。
- approve 状态由本机计划存储持有，不通过 MCP 返回值签发可伪造 token。
- 当前没有跨进程锁。两个进程同时 apply 的竞争仍需在正式版本中补齐。

## 4. 来源预览契约

`sources_preview` 和 CLI `sources preview` 共用 `SourcePreviewService`：

- 接受 HTTPS/SSH Git 仓库 URL、GitHub `owner/repo` 简写及 GitLab 子组等多级路径；拒绝 URL 凭据、查询片段、路径穿越和不受支持的 scheme。
- clone 使用 `--depth 1 --single-branch --no-recurse-submodules`，关闭 hooks 和 fsmonitor，跳过 LFS smudge。
- 可选 ref 通过 `git fetch --depth 1 origin <ref>` 和 detached checkout 固定；ref 拒绝控制字符和以 `-` 开头的值。
- 扫描最多 12,000 个文件、512 MiB；解引用仍位于 checkout 根内的目录软链，越界和循环不跟随。
- 只读取文本和计算内容指纹，不执行 scripts、hooks、postinstall、子模块或 archive 内容。
- 预览记录兼容早期候选分类字段；原生 UI 按实际文件夹展示技能，不把目录名解释为成熟度或启用状态。许可文件只给迹象，不自动判定合规。
- 预览保存到 Application Support `previews/<uuid>/`，不会修改 `registry/`、`vendor/` 或项目。

原生 UI 另提供隔离预览的编辑与删除；编辑成功后替换旧预览，读取失败时保留旧记录。此交互没有新增 CLI 命令或 MCP 工具。

原生 UI 已支持把逐项选择的来源技能完整加入本机技能库，保存独立版本和来源证据，不修改仓库 catalog/vendor。导入后通过项目计划选择、批准和写入，收录与项目使用分别操作。CLI / MCP 暂不提供来源导入工具；现有 `skills_search` 可在下一次服务初始化后读到本机导入条目。来源自动更新与共享仓的正式 revision 发布仍待实现。

## 5. CLI

```bash
skillset doctor [--json]
skillset projects list|add|remove
skillset skills search <query> [--source ID] [--limit N]
skillset sources preview <url> [--ref REF]
skillset sources list|show <preview-id>
skillset objects verify [--project ID]
skillset plugins list [--project ID]
skillset plugins plan --host claude-code|codex --plugin ID --action install|update|enable|disable|uninstall [--scope user|project|local] [--project ID] [--manifest-digest SHA256] [--acknowledge-executable-components] [--remove-data]
skillset inspect <project-id>
skillset plan <project-id> --skills id1,id2 --instructions snippet-id [--agents codex,claude-code]
skillset plans list
skillset approve <plan-id> [--digest DIGEST]
skillset apply <plan-id> [--digest DIGEST]
skillset operations get <operation-id>
skillset rollback <operation-id>
skillset mcp serve --transport stdio
skillset mcp servers [--project ID]
skillset mcp plan --host codex|claude-code --scope project|user --name NAME --transport stdio|streamable-http --command CMD|--url URL
```

全局参数 `--repository` 和 `--state` 用于显式指定仓根与 Application Support 替代目录；测试和隔离演示必须使用临时 state，不能写入真实项目。

默认输出中文人类可读文本；`--json` 时 stdout 只输出一个结构化对象。退出码：

- `0`：成功。
- `1`：执行失败。
- `2`：参数错误或来源 URL/ref 被拒绝。
- `3`：计划失效、漂移、已执行或需要恢复。
- `4`：需要审批/审批过期。
- `5`：缺少 repository 或 Skill 来源。

稳定错误码包括 `APPROVAL_REQUIRED`、`PLAN_EXPIRED`、`PLAN_STALE`、`PLAN_DIGEST_MISMATCH`、`PLAN_ALREADY_APPLIED`、`RECOVERY_REQUIRED`、`SOURCE_INVALID_URL`、`SOURCE_INVALID_REF`、`SOURCE_CREDENTIALS_REJECTED`、`SOURCE_HOST_NOT_ALLOWED`、`REPOSITORY_NOT_FOUND`、`PLUGIN_RISK_APPROVAL_REQUIRED`、`PLUGIN_STATE_STALE`、`PLUGIN_VERSION_AMBIGUOUS`、`PLUGIN_VERSION_NOT_FOUND`、`PLUGIN_MANIFEST_DIGEST_INVALID` 和 `PLUGIN_EXECUTION_UNCERTAIN`。

## 6. 宿主接入

原生 App 的“AI 接入”页检查 MCP 命令及其资源、提供各宿主的用户／项目范围与已登记项目选择，显示真实配置目标，并提供“生成接入计划”。向导使用绝对命令路径，参数显式绑定与 App 相同的本机状态目录，找到仓库时一并绑定仓库路径；路径包含空格时仍保留独立参数。配置写入复用下述计划与批准流程，不自动安装全局命令，也不自动启动 MCP。页面可直接审阅 MCP 生成的待批准计划；配置存在只显示“宿主加载待验证”，真实宿主加载仍由用户重新加载后核对。

App 内的 CLI 位于 `Contents/Helpers/skillset`，同目录包含 `SkillSet_SkillSetCore.bundle`；不得把 CLI 放在 `Contents/MacOS/skillset`，该路径在大小写不敏感文件系统上会命中 GUI 主程序 `SkillSet`。开发构建另提供 `dist/skillset` 及同级资源包。构建脚本通过 `script/verify_mcp_package.py` 将两种打包命令分别移至仓库外，清除资源覆盖变量，在含空格路径与隔离 state 下验证 initialize / tools/list。只检查文件存在不能替代运行验证。

`mcp plan` 只生成 pending plan。用户在本机 App 或 CLI 批准后，apply 才会写宿主配置；Codex TOML 保留受管块外文本，Claude JSON 保留未知键和其他 server，`env` 只写 `${NAME}` 引用。管理器不会启动 MCP 进程或读取 token。Codex：

```toml
[mcp_servers.perch]
command = "/absolute/path/to/skillset"
args = ["mcp", "serve", "--transport", "stdio"]
```

Codex 用户级目标为 `$CODEX_HOME/config.toml`（默认 `~/.codex/config.toml`），项目级目标为 `<project>/.codex/config.toml`。项目级加载须在 Codex 中信任项目；向导不写 `trust_level`，也不自动启用全局接入。

Claude 项目 `.mcp.json` 使用等价的 `mcpServers.perch.command/args` 结构。示例中的 executable 最好使用绝对路径；`skillset` 默认从可执行文件位置、`SKILLSET_REPOSITORY_ROOT` 或当前目录向上查找 `registry/catalog.json`。

同名 server 若不属于本管理器，会返回 `MCP_CONFIG_CONFLICT`，不会覆盖已有配置。凭据只保留变量名或 Keychain 引用，不回显 token。

## 7. 验证与缺口

已自动验证：

- `initialize`、`notifications/initialized`、`tools/list`、`sources_list` 的 stdout 全部是合法 JSON-RPC。
- 未审批 apply 返回退出码 4 和 `APPROVAL_REQUIRED`。
- 审批后 apply 只在项目写预期 Skill 和规则文件，安装选择与项目锁写入应用数据目录，并可通过同一 plan digest 完成。
- `objects verify` 能从内容寻址对象核验项目锁；MCP Codex/Claude 配置 round-trip 与 ownership 有行为测试。
- `plugins list` 能合并 Claude 安装索引与 Codex 配置，不跟随缓存软链；stdio `tools/list` 的 JSON-RPC 输出有集成测试。
- `plugins plan` 在未审批时零宿主调用；批准后通过隔离假 CLI 验证固定参数、operation 回读和 `applied-verification-pending` 状态。状态漂移与风险组件分别有拒绝路径测试。
- 真实 GitHub 预览固定到 Matt 仓库 commit，识别 38 个 SKILL.md 候选。

未完成：

- modern MCP、真实 Codex/Claude 客户端版本矩阵、重连和 progress notification。
- 跨进程项目锁、approval handle、idempotency key 和 operation 去重。
- Plugin marketplace 搜索/浏览、依赖图求解、command-source 逐项确认和跨宿主 enable/update 能力矩阵；当前只操作本机已发现插件。
- MCP 配置 ownership 漂移检测、OAuth / Keychain 健康检查和真实客户端加载验证。

MCP 发现列表不展示 Codex 内部运行组件 `computer-use`、`node_repl`，也不把 TOML 的环境变量子表当作独立服务。过滤不删除配置，写入计划仍检查所有原始表的同名冲突；普通文档与第三方 MCP 服务继续展示。

原生 MCP 页支持搜索、新增、编辑已有连接和删除。已有连接的编辑与删除是显式选择目标后的本机操作，允许处理非栖集写入的配置，仍须生成并批准文件计划；原 CLI/MCP 新增接口保持同名冲突保护。编辑固定名称、宿主、范围和 transport，保留未知键及凭据字段，参数默认保留、按需替换；暂不提供已有连接重命名、切换 transport 或凭据编辑。多行 TOML 参数替换无法安全处理时拒绝生成计划。删除移除对应 TOML 服务及其子表或 JSON 服务节点，保留其他服务；应用时沿用整文件旧 hash 校验。


## 原生 MCP 配置库

原生 MCP 页默认维护本机配置库，支持手动新增、编辑、删除和扫描已有配置入库。扫描包含两个宿主的用户配置与已登记项目，显示来源路径并逐项勾选；不扫描任意未登记目录，不启动服务。只导入命令、可解析字符串参数、无凭据地址和环境变量名，凭据值、未知字段与扩展配置不复制；不支持或疑含敏感信息的连接需手动配置。入库提交重新扫描候选，批量重名或校验失败不部分写库。

全局配置与项目从同一库选择服务，草稿按宿主与范围独立持久化。MCP 变更使用单独计划，把该目标全部选择与先前库部署记录比较；取消勾选经过批准后仅删除库拥有且没有节点修改的连接。外部同名连接不自动接管；扫描入库也不改变原宿主归属。Codex 项目范围写入 `<project>/.codex/config.toml`，与用户级配置及其他项目独立保存、扫描和计划；项目必须在 Codex 中设为受信任，否则 Codex 跳过项目配置。写入计划和界面提示该条件，不更改信任设置；全局连接仍可能生效。原「已有连接」编辑/删除和预设结构化 MCP 计划保留。库 CRUD 和扫描入库仅开放本机 UI，本轮不新增 CLI 命令或 MCP 工具。
