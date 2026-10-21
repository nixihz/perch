# 原生架构与数据契约

状态：Alpha 原生工作流切片（2026-10-21）。项目锁、离线对象、双宿主写入、来源预览、MCP 配置、Plugin 盘点与审批门控生命周期、CLI 与 stdio MCP 已实现；跨进程锁、marketplace 浏览和正式来源收录仍是目标设计。

## 1. 运行形态

产品是 macOS `.app`，由 SwiftPM 构建、由 `script/build_and_run.sh` 生成 bundle 后通过 `/usr/bin/open -n` 启动。没有浏览器页面、WebView、localhost API 或常驻同步守护进程。

```mermaid
flowchart LR
  APP[SwiftUI macOS App] --> CORE[SkillSetCore · Swift domain/store/plan]
  CLI[skillset CLI] --> CORE
  MCP[stdio MCP] --> CORE
  CORE --> GIT[Git 仓 · catalog/presets/templates/objects]
  CORE --> USER[Application Support · 本机状态/审批/journal]
  CORE --> HOST[Codex / Claude 配置适配器]
  CORE --> FS[项目受管文件]
  APP --> HEALTH[MCP 子进程健康探测]
```

SwiftUI 负责导航、预览、差异和人工审批；Swift core 负责来源、版本、manifest、路径安全、计划摘要和事务。正式版禁止 UI 自己读写受管文件，禁止 MCP 旁路 UI 授权。

## 2. SwiftPM 模块边界

```text
Package.swift
Sources/SkillSetCore/
  Models.swift                 Codable 领域对象、快照资源、MCP 草稿校验
  Deployment.swift             计划与 Skill 载荷指纹
  FileTransaction.swift        staging、hash 门、journal、恢复与回滚
  PlanStore.swift              计划、有效期和人工审批
  ProjectInspection.swift      项目观察、漂移和受管块
  ProjectLock.swift            项目 manifest、锁文件与目标宿主
  SkillObjectStore.swift       内容寻址对象、核验与恢复
  MCPConfiguration.swift       Codex TOML / Claude JSON 扫描与受管块
  PluginInventory.swift        插件缓存、安装索引、组件与风险盘点
  PluginLifecycle.swift        固定宿主命令、状态复核与 Plugin operation
  SourcePreview.swift          GitHub 隔离 clone 与候选扫描
  SkillSetService.swift        App/CLI/MCP 共用服务边界
  Resources/                   catalog/sources/presets/templates/matt 快照
Sources/SkillSetApp/
  SkillSetApp.swift             WindowGroup、Commands
  Views/                        NavigationSplitView、页面和审批 sheet
  Stores/AppModel.swift         原生 UI 状态与共享服务调用
  Models/NavigationItem.swift   UI 导航和值对象
  Support/DesignSystem.swift    原生表面、状态徽章和小型布局组件
Sources/SkillSetCLI/
  CLIApplication.swift          CLI 命令与稳定退出码
  MCPStdioServer.swift          legacy stdio MCP 与工具 schema
Tests/SkillSetCoreTests/        Swift Testing 行为测试
```

应用优先从仓库读取 JSON/Markdown，SwiftPM resources 只作回退；150 条 catalog 保持只读。项目草稿、计划、staging、operation 和来源预览写入 Application Support。所有部署写入经过 `SkillSetService`，UI、CLI 和 MCP 不各自实现安装逻辑。

## 3. 共享仓与本机状态

| 数据 | 权威位置 | 是否进入 Git |
| --- | --- | --- |
| Skill/Plugin/MCP 来源和不可变 revision | `registry/`、`vendor/`、对象 store | 是 |
| 预设和规则片段 | `presets/`、`templates/agents/` | 是 |
| 项目期望/锁 | 项目 `skillset.json`、`skillset.lock.json` | 是 |
| 项目 canonical realpath、旧 hash、备份、审批 | `~/Library/Application Support/Skill Set/` | 否 |
| 凭据 | macOS Keychain；仓库只存引用名和状态 | 否 |
| 外部 plugin/MCP 进程日志 | 本机操作目录，脱敏 | 否 |

`registry/local-import.json` 是本仓私有迁移凭证，包含原始绝对路径和 dirty 事实；公开导出必须剥离机器信息、凭据线索和未核准版权内容。

## 4. 领域对象

### Source / SkillRevision

`Source` 使用 `sourceId` 表示身份，字段包括 kind、canonical URL、requested ref、resolved commit、子路径、licenseReview 和 trust。`SkillRevision` 记录 skill ID、完整 commit 或 local snapshot、contentHash、逐文件 manifest、声明版本、许可和完整性。裸 skill name 不能作为唯一键。

内容 hash 算法为 `sha256:path-content-executable:v1`：解引用批准边界内的链接，按相对路径、文件 bytes 和 executable 位排序后对 canonical JSON 求 SHA-256；不包含 mtime、绝对路径或被明确排除的缓存。断链、循环、越界、特殊文件、大小/深度限制和秘密模式进入 blocked 报告。

### MCPServerRevision

字段：`host`、`serverName`、`scope`、`transport`、`command/URL`、`args`、`envKeyReferences`、`configNodeOwner`、`resolvedRevision`、`health`。Codex TOML、Claude `.mcp.json` 和 `~/.claude.json` 是不同格式，适配器必须分开 round-trip，保留未知字段和其他服务器。

MCP env 只记录变量名称或 Keychain 引用，绝不读取值。Codex 使用带标记的 TOML 受管块，Claude 使用 JSON 结构保留未知键；同名外部 server 会冲突阻塞，不会静默覆盖。管理器记录自己写入的 ownership，计划经过同一审批与文件事务。HTTP/OAuth 仍只生成配置；首发本应用的 AI 接入为 stdio，不监听端口。

### PluginRevision

内部键为 `(host, marketplaceID, pluginName, sourceRevision)`。记录 manifest digest、宿主 version、严格的不可变 revision、来源、依赖图、组件清单、hooks/commands/MCP 风险和 license。Claude plugin manifest 可组合 skills、hooks、MCP、commands、agents；Codex plugin schema 证据不足，不能复制 Claude 字段。

插件版本与内容 revision 分开：宿主 `version` 仅兼容提示，内部锁必须有完整 commit/archive digest。依赖范围要检测 cycle、无解、同名遮蔽和 marketplace 更新漂移；命令来源、hooks、二进制 bundle 默认阻塞。

Plugin inventory 扫描项目 `.claude-plugin` / `.codex-plugin`、`~/.claude/plugins/cache` 和 `~/.codex/plugins/cache`，并叠加 Claude `installed_plugins.json` 与 Codex `config.toml` 的安装/启用事实。只读取 manifest 和组件目录，不跟随软链、不执行 hooks/commands、不调用安装器。缓存存在不等于已安装；revision 从宿主安装索引取得，manifest digest 单独计算。

Plugin lifecycle 复用 `DeploymentPlan` / `DeploymentPlanStore`，但执行器不是文件事务。计划在 staging 中保存 `PluginLifecycleCommand`，绑定 host、plugin id、scope、目标 manifest digest、working directory、CLI realpath、固定 argv 和 before observation digest。同一 id 存在多个缓存版本时，调用方必须选定具体 digest；apply 时重新扫描并为该摘要选择记录，任何漂移都返回 `PLUGIN_STATE_STALE`。命令通过 `Process` 直接启动，不经过 shell，不自动使用 `-y`。执行后按动作回读目标状态，并在 `operations/<uuid>/plugin-operation.json` 记录脱敏输出、退出码和结果。外部副作用无法用文件 rollback 撤销，必须生成相反动作计划。

### ProjectBinding / PresetRevision

ProjectBinding 以本机 canonical realpath + UUID 注册，包含目标 agent、scope、desired、managed observed 和 inherited observed。两个 Git worktree 可分别注册。PresetRevision 只引用具体 Skill/Plugin/MCP revision 和规则 fragment，不使用 `latest`；应用预设只生成项目草稿。

### Plan / Operation

Plan 是不可变的 `planId + digest`，绑定目标 realpath、动作、owner、expected old hash / observation、new hash、diff、风险、adapterVersion 和 10 分钟有效期。Operation 记录文件 journal/backup，或 Plugin 的宿主命令、前后观察、退出码和脱敏输出；两者由 `operations_get` 统一读取。

## 5. 项目安装状态机

```text
draft → planned → awaiting-approval → approved → applying → applied
                   ↘ expired       ↘ conflict / failed
failed → recovering → recovered / manual-intervention
applied → rollback-planned → approved → rolled-back / conflict
```

执行顺序：

1. 按 canonical project root 获取跨 UI/CLI/MCP 共用的锁（目标；当前尚未实现跨进程锁）。
2. 复核 plan digest、approval、目标 allowlist、父目录 realpath 和所有 expected old hash（已实现同进程服务校验）。
3. 在同一文件系统准备 staging，校验 new hash，持久化 journal 和 backup（已实现）。
4. 对受管路径逐一原子 rename，记录完成步骤，并在 staging 中生成 `skillset.json` / `skillset.lock.json`（已实现）。
5. 回读实际内容和权限，更新 operation（已实现）。

多文件、多目录不宣称原子。中断后的下一次启动先处理 journal；rollback 只恢复仍等于管理器上次写入值的文件，发现用户新编辑立即停止。

Plugin 状态机：

```text
observed → planned → approved → applying
                                  ├─ applied
                                  ├─ applied-verification-pending
                                  ├─ failed
                                  ├─ failed-before-launch
                                  └─ uncertain-interrupted
```

`uncertain-interrupted` 不自动重试。命令非零退出且未观察到目标状态时计划保持未消费，用户排查后可重新生成；不能把宿主命令视为可回滚文件事务。

## 6. 规则与宿主适配

默认受管块：

```markdown
<!-- skillset:begin id=project-rules schema=1 -->
确定展开内容
<!-- skillset:end id=project-rules -->
```

无标记时 plan 提议追加；一对完整标记只替换块；重复、交叉、缺尾或软链目标阻塞。块外 bytes 保留。当前实现可同时部署 Codex `.agents/skills` / `AGENTS.md` 与 Claude `.claude/skills` / `CLAUDE.md`，项目锁记录两个目标。祖先规则、`AGENTS.override.md`、Claude 加载链和会话重载仍是适配器设计。

默认部署为实体 copy；link 只能指向管理器不可变 store。外部来源、项目目标和宿主配置不允许通过任意 symlink 越界。

## 7. 安全边界

- 来源只在隔离目录读取；不 checkout/执行 hooks、filters、LFS、子模块、postinstall 或 skill scripts。
- URL 拒绝 credentials、未知 scheme、路径穿越、SSRF/DNS rebinding；分支含 `/` 时通过 refs 消歧。
- 目标路径必须在用户注册项目根；不通过 chmod、管理员权限或关闭保护绕过。
- AI、MCP caller、插件 manifest 不能添加新的写入根，不能把 `confirmed=true` 当批准。
- 日志脱敏：不记录 token、认证 URL、源码秘密、完整 approval handle 或全量 `.env`。
- 删除只触碰管理器拥有且未漂移的路径；未知插件/MCP 不静默停用或卸载。
- Plugin 只接受固定动作和宿主 CLI realpath；scope/project 必须绑定已登记 realpath，安装与更新必须由本机 UI/CLI 确认完整包风险。

## 8. 可观测性

UI、CLI 和 MCP 共用稳定错误码，包括 `PLAN_STALE`、`APPROVAL_REQUIRED`、`PLAN_DIGEST_MISMATCH`、`RECOVERY_REQUIRED`、`SOURCE_*`、`PATH_OUTSIDE_ROOT`、`MCP_CONFIG_CONFLICT`、`OFFLINE_OBJECT_MISSING`、`OFFLINE_OBJECT_CORRUPT`、`PLUGIN_RISK_APPROVAL_REQUIRED`、`PLUGIN_STATE_STALE`、`PLUGIN_VERSION_AMBIGUOUS`、`PLUGIN_VERSION_NOT_FOUND`、`PLUGIN_COMMAND_FAILED` 和 `PLUGIN_EXECUTION_UNCERTAIN`。本机 operation 记录计划 digest、结果和恢复路径，不保存秘密。

应用将“文件已写入并回读”与“宿主会话已验证”分开显示；当前只完成前者。
