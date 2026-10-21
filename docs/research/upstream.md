# Skill 管理上游调研

调研日期：2026-10-21（Asia/Shanghai）。本文件区分官方事实与本项目建议，不代表已安装任何技能或 MCP。

## 取证方法与限制

- Git shallow clone 核查官方仓库当前默认分支源码，临时副本在 `/tmp/skillset-matt-upstream`、`/tmp/skillset-vercel-upstream`，没有运行其安装脚本。
- 按用户要求在独立临时 venv 安装 `scrapling[fetchers]`，实际版本 `0.5`，使用 `Fetcher.get` 抓取 Agent Skills specification、Claude Skills、MCP tools 正文，均 HTTP 200。没有启动浏览器，没有改全局 Python。
- pip 初次连接因代理没有显式传入而出现 SSL EOF；显式传入本机已有代理后成功。Codex 页面经 Scrapling 抓取被其 SSRF 重定向保护拒绝，未关闭保护；改用 curl 获取同一官方页面，再以 Scrapling Selector 提取正文。网页检索工具未配置提供商，直接访问官方页面及官方索引，不以搜索摘要作为证据。
- 文档为抓取时快照。尤其 Claude 功能和 MCP 协议有较新变化，适配器必须记录实际客户端版本；不能把此文当跨版本保证。

## 一、Matt Pocock 仓库：应借鉴什么

官方快照：默认分支 `main`，提交 `5beb35b040e3de97e54fa9e386d7e42d15c295c2`，提交时间 2026-10-19。整包版本 `1.3.1`。[固定提交](https://github.com/mattpocock/skills/tree/5beb35b040e3de97e54fa9e386d7e42d15c295c2)、[package.json](https://github.com/mattpocock/skills/blob/5beb35b040e3de97e54fa9e386d7e42d15c295c2/package.json)

| 官方事实 | 对本项目的启示（设计推断） |
| --- | --- |
| `skills/engineering`、`skills/productivity` 是 promoted；`misc`、`in-progress`、`deprecated` 不进入插件发布集合 | 区分库存、审核、发布、启用，不把所有可发现文件等同于默认启用 |
| promoted 集合同时出现在根 README、bucket README、`.claude-plugin/plugin.json`，并有 `docs/<bucket>/<skill>.md` | 以机器目录为事实源，生成目录、文档和发布清单，避免手工同步漂移 |
| `AGENTS.md` 是指向 `CLAUDE.md` 的软链 | 导入不能只保存软链字符串；快照需保存其解析内容、原始路径及链接来源 |
| `disable-model-invocation: true` 与 `agents/openai.yaml` 的 `allow_implicit_invocation: false` 协调调用方式 | 通用格式和宿主扩展分开保存；不假定单一字段跨所有客户端生效 |
| Changesets 生成版本 PR、CHANGELOG 和 Git tag；同步 package 与 plugin manifest 版本 | 整仓发布版本、单个 skill 内容版本、项目锁定版本是三个不同概念 |

证据：[维护约定](https://github.com/mattpocock/skills/blob/5beb35b040e3de97e54fa9e386d7e42d15c295c2/CLAUDE.md)、[发布工作流](https://github.com/mattpocock/skills/blob/5beb35b040e3de97e54fa9e386d7e42d15c295c2/.github/workflows/release.yml)、[插件清单](https://github.com/mattpocock/skills/blob/5beb35b040e3de97e54fa9e386d7e42d15c295c2/.claude-plugin/plugin.json)。

README 将插件自动更新与 editable files 安装明确分开，并警告同一 agent 同时安装两条路径会重复。它不是“项目、预设、内容寻址、部署事务”的完整管理器。[README](https://github.com/mattpocock/skills/blob/5beb35b040e3de97e54fa9e386d7e42d15c295c2/README.md)

**不能直接复制其安装策略。** `scripts/link-skills.sh` 声明仅供维护开发，目标已有非软链目录时会 `rm -rf`，再重建链接；这不满足本产品保留用户修改、预览、备份、冲突确认和回滚的要求。[脚本](https://github.com/mattpocock/skills/blob/5beb35b040e3de97e54fa9e386d7e42d15c295c2/scripts/link-skills.sh)

许可证 MIT，复制或实质性派生需保留 copyright 和 permission notice。不能据此推定其他来源也可重新分发。[LICENSE](https://github.com/mattpocock/skills/blob/5beb35b040e3de97e54fa9e386d7e42d15c295c2/LICENSE)

## 二、Vercel Skills CLI：来源、锁与发现边界

官方快照：`a80e4c9d12d607631249d4d7d059f835d4b2f13a`，2026-10-19。[仓库](https://github.com/vercel-labs/skills/tree/a80e4c9d12d607631249d4d7d059f835d4b2f13a)

- 来源包括 `owner/repo`、GitHub tree 子路径、GitLab、Azure Repos、通用 Git URL、本地路径以及直接 SKILL.md/压缩包 URL。直接下载默认限制 10 MiB、解包 25 MiB、1000 文件。私有仓复用 Git/gh/SSH 认证，不要求应用自行存储 GitHub token。[命令参考](https://github.com/vercel-labs/skills/blob/a80e4c9d12d607631249d4d7d059f835d4b2f13a/docs/commands.md)
- 默认 symlink 模式实际是“先复制至 canonical 目录，再让 agent 目录软链至 canonical”，不等于直接链接原始仓库；copy 模式各 agent 独立复制。源码另有 link 模式。内部软链在复制时 dereference；断链会跳过并警告。这种静默不完整复制不适合本产品，应标 blocked 并报告清单。[installer.ts](https://github.com/vercel-labs/skills/blob/a80e4c9d12d607631249d4d7d059f835d4b2f13a/src/installer.ts)
- 项目 `skills-lock.json` schema 1，含 source、可选 sourceUrl/ref/skillPath、computedHash（整个目录内容 SHA-256）；全局 `.skill-lock.json` schema 3 在 `$XDG_STATE_HOME/skills/` 或 `~/.agents/`，含来源、ref、skillFolderHash（GitHub tree SHA）、时间。branch/tag ref 不是不可变 commit pin，内容 hash 也不等于完整离线重现能力。[local-lock.ts](https://github.com/vercel-labs/skills/blob/a80e4c9d12d607631249d4d7d059f835d4b2f13a/src/local-lock.ts)、[skill-lock.ts](https://github.com/vercel-labs/skills/blob/a80e4c9d12d607631249d4d7d059f835d4b2f13a/src/skill-lock.ts)
- `check` 检查更新，`update` 重新安装，支持指定技能；应借鉴命令入口，不能据此宣称具备本地编辑三方合并和事务恢复。[命令参考](https://github.com/vercel-labs/skills/blob/a80e4c9d12d607631249d4d7d059f835d4b2f13a/docs/commands.md#skills-update)

### 发现范围直接影响本仓结构

源码优先扫描根目录直接子层；`skills` 及已知 agent 容器最多下探三层。仅“完全未发现”或显式 `fullDepth` 时才递归回退，回退默认 maxDepth 为 5。发现一个 skill 后不再向其内部递归。普通目录遍历只接受 `Dirent.isDirectory()`。默认同名以 `seenNames` 去重，先发现者保留；内部可选择保留重复名供歧义检测。[skills.ts](https://github.com/vercel-labs/skills/blob/a80e4c9d12d607631249d4d7d059f835d4b2f13a/src/skills.ts)、[constants.ts](https://github.com/vercel-labs/skills/blob/a80e4c9d12d607631249d4d7d059f835d4b2f13a/src/constants.ts)

**本项目结论（设计推断）：** 已有正常 skills 时，`vendor/local-brian/*` 不保证被从根安装的 CLI 默认发现；不要把 `npx skills add <本仓>` 描述为全库存安装。使用明确 catalog ID、source ID、revision 和路径选择，禁止按裸 name 自动覆盖。

## 三、Agent Skills 标准不是版本管理协议

官方 specification 要求 skill 目录含 `SKILL.md`，YAML frontmatter 至少有 `name`、`description`；name 最长 64、与父目录名一致，不允许首尾连字符或连续连字符；description 最长 1024。支持 scripts、references、assets，强调渐进加载。`license`、`compatibility`、`metadata` 可选，`allowed-tools` 为实验字段。[官方规范](https://agentskills.io/specification)

规范允许 `metadata.version` 这样的字符串元数据，但没有定义 registry、依赖求解、SemVer 更新政策、锁文件、来源签名或部署回滚。因此本应用需要独立的包/来源/修订模型；保留原 frontmatter，不把自定义锁字段写进第三方正文。许可证缺失的来源标记 unknown，需要用户确认可用范围，不能默认可再发布。这些是产品建议，不是标准强制要求。

## 四、宿主兼容性不能只用一个目录开关

### Codex

- 当前官方 skill 路径是从 CWD 向上至仓库根各级 `.agents/skills`、`$HOME/.agents/skills`、`/etc/codex/skills` 和内置集合；支持 skill 目录软链。相同 name 不合并，可能同时出现在选择器。官方还提供 `[[skills.config]]` 按路径禁用技能的设置。旧版 `.codex/skills` 和本机已有插件缓存应视为版本相关兼容来源，不盲目迁移或删除。[Skills](https://developers.openai.com/codex/skills/)
- 指令：全局 CODEX_HOME 下先 `AGENTS.override.md` 后 `AGENTS.md`；项目根向 CWD 每级最多选一个，先 override 再 AGENTS 再配置 fallback，根向下合并；默认合计 32 KiB。不是“替换根 AGENTS 即拥有全部最终指令”。[AGENTS.md](https://developers.openai.com/codex/guides/agents-md/)
- MCP 使用 `~/.codex/config.toml`，可信项目可用 `.codex/config.toml`，表为 `[mcp_servers.<name>]`；stdio 与 Streamable HTTP 配置形态不同。只编辑受管节点，保留其他 TOML 和凭据引用。[MCP](https://developers.openai.com/codex/mcp/)

### Claude Code

- 官方列有 enterprise、personal `~/.claude/skills`、project `.claude/skills`、nested 和 additional-directory scopes；新版本 worktree fallback、插件与 synced 目录也可能提供技能。插件技能带 namespace，不能把它们误识别为用户普通目录。[Skills](https://code.claude.com/docs/en/skills)
- **新变化：v2.1.277+ 原生支持 AGENTS.md，但有条件。** 当 CWD 或祖先存在 CLAUDE.md、`.claude/CLAUDE.md` 或 CLAUDE.local.md 时，默认只加载 CLAUDE 链而不是 AGENTS；没有这些时才加载 AGENTS；个人全局和 managed 文件不阻止项目 AGENTS。CLAUDE 可 `@` 导入 AGENTS，规则还可位于 `.claude/rules` 并按 paths 条件加载。预设应用必须展示有效链，避免重复导入和互相遮蔽。[Memory / AGENTS.md](https://code.claude.com/docs/en/memory#agents-md)
- MCP local/user 配置在 `~/.claude.json`，project 为 `.mcp.json`，与 settings JSON 不是同一文件。项目服务器需要用户 approval；不可信仓库不能通过提交 settings 自行批准。应用应生成配置与提示，不能绕过宿主信任门。[MCP](https://code.claude.com/docs/en/mcp)

**产品建议：** agent adapter 有版本化能力表；“本项目禁用”只表示管理器不部署，不代表屏蔽全局、管理员、插件或父目录技能。UI 同时显示 desired 与 observed effective inventory；不能承诺跨宿主绝对隔离。

## 五、MCP：版本与本机写权限是两件事

### 日期版不能混淆

官方索引当前将 `2026-07-28` 列为最新日期版。其 modern 协议不再有初始化协商握手，每个请求携带 `_meta` 的协议版本、客户端信息、能力；不支持版本返回错误供客户端重试。`2025-11-25` 及更早为 legacy，使用 `initialize`。兼容两者称 dual-era。[官方索引](https://modelcontextprotocol.io/llms.txt)、[2026-07-28 版本兼容](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning)

首版可以**明确以经过目标客户端实测的 legacy 2025-11-25 stdio 为支持范围**，modern 2026-07-28 单独列兼容计划；或者使用已验证 dual-era SDK 并分别集成测试。不能宣称“最新规范仍统一 initialize”，也不能只因 SDK 安装成功就宣称两版互通。

### transport 与工具安全

- stdio：客户端启动本机子进程，stdin/stdout 只用于换行分隔 JSON-RPC，日志写 stderr。首版本地管理优先 stdio，不暴露监听端口。[2026 stdio](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/stdio)、[2025 transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
- 若以后增加 HTTP，必须独立设计身份验证、Origin 验证、loopback bind、DNS rebinding 与 SSRF 防护，不能把“只在本机用”当作无认证理由。[官方安全实践](https://modelcontextprotocol.io/specification/2025-11-25/basic/security_best_practices)
- 工具 `readOnlyHint`、`destructiveHint`、`idempotentHint`、`openWorldHint` 是提示而非权限机制，来自不可信服务器时不能当作安全保证。默认值分别 false、true、false、true。[2026 Schema](https://modelcontextprotocol.io/specification/2026-07-28/schema#toolannotations)、[Tools](https://modelcontextprotocol.io/specification/2026-07-28/server/tools)

### 本项目必须自行实现（设计推断）

1. MCP 查询、扫描、生成 plan 是只读；写入工具只消费经过 UI/CLI 用户确认的单次短时 approval token 和固定 plan digest。让 AI 传 `confirmed: true` 不构成授权。
2. plan 绑定项目真实路径、目标文件 old hash、来源 revision 和内容 digest；apply 前再次校验，以拒绝计划后修改和路径置换。
3. 项目根及明确用户授权全局目标采用 allowlist；realpath 检查、禁止路径穿越和越界软链写入。导入解引用是复制来源，不是允许写任意源路径。
4. 下载先进入隔离 staging，拒绝 archive traversal、软链逃逸、超限包；不执行 skill 中的 scripts/hooks，也不执行来源声明的安装命令。
5. 部署采用受管路径 manifest、逐项冲突、备份、审计、失败恢复和并发锁；删除只删除自己部署且内容未被修改的条目。规则模板只管理显式块或明确新文件，保留现有用户内容。
6. 凭据交给操作系统/Git已有机制；锁文件、错误、审计和 MCP result 不返回 token。来源链接与正文是不可信数据，不能改变工具授权策略。

## 需要落到 SPEC 的验收点

- 同名不同来源、branch 移动、tag 重指向、本地编辑后更新、许可证缺失，均不能静默覆盖。
- 目录软链、文件软链、断链、循环、越界和同一真实目录多入口均有确定扫描结果；broken source 不生成可部署 revision。
- 记录原始来源与已复制内容的独立身份，离线可复现锁定 revision，不依赖原 `/opt/case/brian/skills` 继续存在。
- 项目与预设锁定具体 revisions，预设升级不自动推进已应用项目；规则模板也有版本与差异预览。
- Codex/Claude effective discovery 与真实客户端交叉核验；全局技能干扰有可见警告。
- MCP 非授权写入、过期/重放 approval、计划后修改、并发 apply、进程中断恢复均有行为测试，不写仅断言常量相等的同义反复测试。
