# 本地桌面 Skill、MCP 与 Plugin 调研

调研日期：2026-10-21（Asia/Shanghai）。目标是 SwiftPM core + 原生 SwiftUI macOS 桌面端，CLI/MCP 共用核心；本文件只记录官方事实与可审计边界，不执行安装、登录、启停或修改宿主配置。

## 取证边界

- 只读核验本机 `codex-cli 0.163.0`、`Claude Code 2.1.306` 的 `--help`，未传 token、未调用会改配置的命令。生命周期实现按当前 help 的 `plugin install/update/enable/disable/uninstall` 与 `plugin add/remove` 建白名单。
- 使用临时 `/tmp/skillset-upstream-venv` 的 Scrapling 0.5 抓取 Claude 官方 MCP/Plugin 文档；Codex 页面因 Scrapling 的 SSRF 重定向保护拒绝，未关闭保护，使用官方 URL 的 curl 内容做证据并记录限制。
- Swift SDK 用官方 `modelcontextprotocol/swift-sdk` shallow clone；快照 commit `a0ae212ebf6eab5f754c3129608bc5557637e605`（2026-04-29）。该 README 明确写的是 MCP 2025-11-25、Swift 6/Xcode 16、SPM `from: 0.11.0`，不能据此声称支持最新 2026-07-28 modern 协议。[仓库](https://github.com/modelcontextprotocol/swift-sdk/tree/a0ae212ebf6eab5f754c3129608bc5557637e605)

## 宿主命令实测矩阵

| 能力 | Codex CLI 0.163.0 | Claude Code 2.1.306 | 本地管理器边界 |
| --- | --- | --- | --- |
| MCP stdio 添加 | `codex mcp add NAME -- COMMAND...`，可 `--env KEY=VALUE` | `claude mcp add NAME -e KEY=VALUE -- COMMAND...` | 只生成可审计 plan，用户确认后写配置 |
| MCP Streamable HTTP | `codex mcp add NAME --url URL`，支持 bearer env、OAuth client ID/secret、auto/CIMD/DCR、resource | `claude mcp add --transport http NAME URL`，也支持 SSE/HTTP/WS JSON | 首版只做 stdio，HTTP 仅记录配置并提示宿主信任/网络风险 |
| OAuth | Codex CLI `mcp login/logout`，OAuth 选项在 add help；Claude `mcp login/logout`，HTTP/SSE/connector | 不读取或复制 token；仅显示是否配置、凭据引用和状态 | token 交给宿主/Keychain；管理器不保存明文 |
| 查看/启停 | Codex `mcp list/get`；未见独立 enable/disable 参数 | Claude `mcp list/get`；项目服务器有 approval/pending，且可 `enabled:false`/工具 allow/deny | desired 与 observed 分开；“禁用”不能删除未知来源 |
| Plugin marketplace | `codex plugin marketplace add/list/upgrade/remove`；`plugin add/remove/list`，支持本地或 Git marketplace | `plugin marketplace add/list/update/remove`；install/update/uninstall，scope user/project/local/managed | 当前只管理本机已发现插件；不绕过宿主市场确认，也不浏览 marketplace |
| Plugin 版本 | help 暴露 install/remove，无足够证据支持本地管理器推断 Codex manifest 版本语义 | `plugin update`；manifest `version` 是字符串，插件可锁至改变版本；非 SemVer 强制 | 内部必须使用严格 revision/digest；宿主 version 仅兼容提示 |
| Plugin 启停 | help 未提供 enable/disable | `plugin enable/disable`，启用后通常需重启；更新也提示 restart | 固定命令白名单、人工批准、before state 复核、执行后回读；外部副作用不用文件 rollback 冒充恢复 |

官方证据：[Codex plugin help / MCP help](https://developers.openai.com/codex/plugins/)、[Codex MCP](https://developers.openai.com/codex/mcp/)、[Claude MCP](https://code.claude.com/docs/en/mcp)、[Claude Plugin reference](https://code.claude.com/docs/en/plugins/plugin-reference)。Codex 本机 help 是确切版本事实，网页行为可能晚于 CLI。

## Claude Plugin：manifest、来源、依赖

Claude 官方插件 manifest 是插件根目录 `.claude-plugin/plugin.json`，其它组件在根目录，不放进 `.claude-plugin/`。manifest 支持 `version`、`dependencies`、`skills`/commands/agents、`hooks`、`mcpServers`、`userConfig` 等；严格校验会拒绝错误类型、越界路径和 userConfig 等严格对象未知键，`validate --strict` 将警告变失败。[manifest reference](https://code.claude.com/docs/en/plugins/plugin-reference)

- `version` 是字符串，官方说明不强制 SemVer；对有 version 的插件可保持在该版本直到变更。插件依赖可写裸名、`name@marketplace`，或带 `version` 的对象；约束可用 SemVer 范围。[依赖](https://code.claude.com/docs/en/plugins/dependencies)
- marketplace 条目把每个插件映射到 source；source 可是相对路径、GitHub、URL、git-subdir、npm、archive 或 command。marketplace 自身来源也可 URL/path/GitHub。[marketplace reference](https://code.claude.com/docs/en/plugins/marketplace-reference)
- plugin 可把 hooks、MCP server 配置和 skills 组合在一个包；MCP 也支持 `.mcp.json`、内联配置、`.mcpb`/`.dxt` bundle。组件加载顺序和同名服务器后者覆盖必须在预览中明确展示。[manifest reference](https://code.claude.com/docs/en/plugins/plugin-reference)
- 依赖会跟随 marketplace 最新版本移动，除非显式约束；官方文档明确警告未约束依赖变更可能重命名工具导致插件断裂。依赖安装、解析、prune、循环/无解错误必须由宿主负责，管理器不要假设可自行替换依赖。[依赖](https://code.claude.com/docs/en/plugins/dependencies)
- marketplace auto-update 受多个设置和来源策略影响；更新可能导致当前会话 hook/MCP/LSP 仍指向旧路径，需重启或 reload。不同来源同名插件有明确 precedence，不能用裸 plugin name 做全局唯一键。[loading](https://code.claude.com/docs/en/plugins/loading)

**本项目建议：** catalog key 使用 `(host, marketplaceID, pluginName, sourceRevision)`；依赖图单独解析并检测 cycle、范围无解、同名遮蔽。安装前展示 skills/agents/hooks/MCP 的完整 inventory 与命令；默认禁止 command-source、hooks、可执行脚本自动运行，除非每次显式授权。

## MCP 配置、OAuth 与本地凭据

- Codex 项目/用户配置写在 TOML 的 `[mcp_servers.<name>]`；Claude 项目写 `.mcp.json`，用户写 `~/.claude.json`。二者不是同一格式，不能把一份配置文件跨宿主复制。[Codex MCP](https://developers.openai.com/codex/mcp/)、[Claude MCP](https://code.claude.com/docs/en/mcp)
- Claude 项目 `.mcp.json` 服务器首次为 Pending approval，宿主显示并等待用户批准；仓库提交的 settings 不能自行完成信任。管理器只能生成文件和 approval 提示，不能伪造批准。[Claude MCP](https://code.claude.com/docs/en/mcp)
- Claude 支持 `${CLAUDE_PROJECT_DIR}` 与环境变量扩展，Codex 支持 env/bearer-token-env-var。管理器保存变量名，不读取值，不回显 shell 环境。
- Swift SDK README 提供 OAuth client credentials、authorization code、custom token provider 和 custom token storage；默认 token 仅内存，进程退出即丢失，持久化应由实现接入 Keychain。OAuth server 应验证 token `aud` 防止 token substitution。管理器只负责 Keychain 引用/状态，不自行实现浏览器登录或保存明文。[Swift SDK README](https://github.com/modelcontextprotocol/swift-sdk/blob/a0ae212ebf6eab5f754c3129608bc5557637e605/README.md)
- 本机 desktop app 使用子进程 stdio MCP server：服务端 stdout 只能输出合法 JSON-RPC，日志写 stderr；子进程环境继承应采用最小 allowlist。不要为“本机 MCP”额外监听 HTTP 端口。若未来 HTTP，必须实施 Origin 校验、loopback bind、认证、SSRF/DNS rebinding 防护。[stdio](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/stdio)、[安全最佳实践](https://modelcontextprotocol.io/specification/2025-11-25/basic/security_best_practices)

## 支持、未知、不应自动化

### 当前可支持

1. 读取本地 source、Git revision、manifest、SKILL.md frontmatter，计算内容 digest，生成 project/preset/plugin/MCP plan。
2. 仅在用户确认后，以受管目标写入 Codex/Claude 配置；备份、冲突预览、old hash 校验、可回滚。
3. SwiftUI 预览 plugin inventory、依赖图、权限/脚本/MCP 风险；SwiftPM core 供 CLI 与 stdio MCP 复用。
4. 对 stdio MCP 进行启动、initialize/版本探测、tools/list 健康检查，超时、stderr、退出码可见。

### 保持未知并阻断默认安装

- Codex plugin manifest 的完整 schema、依赖解析、hooks/MCP 组合和版本更新语义，当前官方公开 CLI help/页面证据不足；不要从 Claude manifest 推断 Codex 支持同样字段。
- 任意 plugin 的 command source、archive headersHelper、安装脚本、第三方 hooks、`.mcpb`/`.dxt` 二进制包、私有 marketplace 认证、自动更新。必须显示需人工信任并提供 dry-run。
- HTTP MCP 的 OAuth client registration、远端凭据代理、工作区策略和云端 hooks；只配置，不替用户登录或监听端口。

### 明确不自动化

- 不复制、打印、上传 API key/OAuth token，不调用 `gh auth token` 或从 keychain 导出凭据。
- 不执行 plugin/skill 内脚本、hooks、command source、npm postinstall、archive 解包后的程序。
- 不让 AI 单独传 `confirmed=true` 即写入；approval token 绑定 plan digest、目标 realpath、old hash、短时过期且一次性。
- 不静默启用、停用、删除宿主已有插件/MCP；仅处理 manifest 由本管理器声明且未被用户修改的条目。

## P0 验收

- **配置隔离：** Codex TOML、Claude `.mcp.json`/`~/.claude.json` round-trip 解析，保留未知字段、变量引用和其他服务器；不写凭据值。
- **安全 apply：** realpath allowlist、路径穿越/越界软链/归档 traversal 拒绝；plan 后文件变化、并发锁、过期/重放 approval、进程中断均拒绝或可恢复；删除只触碰自有且 hash 未变条目。
- **来源可复现：** Git commit/tree digest、archive digest、license、软链解析状态完整锁定；branch/tag 漂移被报告，不能冒充已锁定版本。
- **插件依赖：** manifest schema 版本化，依赖范围无解、循环、同名 precedence、组件 inventory、hooks/command/MCP 风险均在 UI 中可见；未知宿主字段不自动转义。
- **MCP stdio：** stdout 纯 JSON-RPC、stderr 日志隔离、启动超时、崩溃/退出、工具列表和协议版本错误有可诊断记录；无 HTTP 监听。
- **宿主回归：** 在当前 Codex 0.163.0 与 Claude 2.1.306 上，仅用临时 fixture 运行 list/get/validate/health；不运行真实来源、不触达用户配置。
- **凭据：** Keychain access group、OAuth callback、token audience、注销擦除和进程退出行为需实机测试；单元测试不能用“断言写入后再读相同值”的同义反复测试。
