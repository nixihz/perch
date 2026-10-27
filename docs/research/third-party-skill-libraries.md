# 第三方 Skill 库调研

调研日期：2026-10-22（Asia/Shanghai）。本报告回答“如何接入第三方知名 Skill 库”，不代表已安装、启用或默认信任任何外部 Skill。外部目录只负责发现；真正导入仍须回到本项目现有的 Git 隔离预览、固定提交、逐项选择、许可证留存和审批部署流程。

## 结论

建议分两层接入：

1. **第一阶段接目录查询适配器**：SkillsMP、腾讯 SkillHub、ClawHub。三者在本次采样中能直接返回公开 JSON，分别提供 GitHub 原始链接/目录链接、版本或版本相关字段、来源/信任线索，适合作为“搜索候选”而不是内容信任根。
2. **第二阶段接官方或厂商仓库目录**：Anthropic、OpenAI、Vercel、Microsoft、Expo 等仓库只作为高信任来源清单，使用 GitHub 固定 commit 预览。无需把第三方网页抓取结果复制进 `registry/catalog.json`，也不自动启用候选。
3. **暂缓直接接 skills.sh API**：官方 API 文档存在，但本次未带 Vercel OIDC token 的请求均返回 `401 authentication_required`；先把它作为网页/CLI 引用来源，等凭据策略和配额模型确定后再做 API 连接器。

推荐的首批实现是“目录搜索 → 候选详情 → 打开原始来源/固定版本 → 复用现有 SourcePreviewService → 用户逐项导入”。目录记录应保存 `provider`、`providerItemID`、`canonicalURL`、`sourceURL`、`requestedRef`、`resolvedRevision`（若目录提供）、`licenseHint`、`trustSignals`、`observedAt` 和原始响应摘要；不保存 API token，不把搜索排序或下载量当作信任判断。

## 只接 skills.sh 是否够用

**做 MVP 的发现入口，够用；做长期唯一来源，不够用。** skills.sh 已覆盖公开 GitHub Skill 的搜索、排行榜、详情文件树、CLI 安装和多种 Agent 目标，适合作为用户看到第三方 Skill 的第一入口。[官方 CLI 文档](https://www.skills.sh/docs/cli) 也明确安装最终指向仓库或直接下载来源。

但它不能替代本项目的来源管理：

- skills.sh 自己声明只是第三方目录，会索引外部仓库并运行自动安全扫描，不能保证条目的质量或安全；内容归作者所有，许可证要回到源仓库判断。[使用条款](https://www.skills.sh/terms)
- API 需要 Vercel OIDC；本次未授权请求返回 `401`。桌面端如果没有明确的团队凭据方案，不能把它的 API 当作无凭据公共接口。[API 文档](https://www.skills.sh/docs/api)
- 排名和安装量是发现信号，不是许可证、维护质量、恶意行为或版本不可变性的证明。
- skills.sh 可能覆盖公开仓库，但不能替代私有仓库、本地来源、企业内部镜像和其他生态的专门目录。

因此建议把它定义成 `skills.sh` **目录适配器**：搜索结果只保存目录元数据，点击导入时解析其 `installUrl`/GitHub 来源，再进入现有 `SourcePreviewService`。导入后以 `resolvedCommit + contentHash + license snapshot` 作为本项目事实；目录下线、排名变化或 API 不可用都不应删除或改变已导入包。这样首期可以只实现 skills.sh，但数据模型和 UI 文案应保留“目录来源”和“内容来源”两个字段，后续增加 SkillHub、ClawHub 或直连官方仓库时不需要迁移已导入数据。

## 版本控制判断

可以做，而且本项目已有大部分基础。Vercel CLI 自己的 project lock 使用 `source/ref/sourceType/skillPath/computedHash`，global lock 使用 `source/ref/skillFolderHash`；它能检查和更新，但不是完整的历史版本与回滚系统。[local-lock.ts](https://github.com/vercel-labs/skills/blob/main/src/local-lock.ts)、[skill-lock.ts](https://github.com/vercel-labs/skills/blob/main/src/skill-lock.ts)

本项目应使用更强的三层锁定：

1. **上游 revision**：`skills.sh` 条目的原始 GitHub URL、子路径、请求 ref 和实际 `resolvedCommit`。
2. **内容 revision**：完整文件 manifest、许可文件摘要和 `contentHash`，不依赖分支或排行榜状态。
3. **项目锁**：项目、宿主、技能 ID、对象路径和部署时的内容 hash；回滚时重新指向已有不可变对象。

导入后检查更新只生成新预览和差异；用户批准后才生成新的本机包和部署计划。用户编辑应生成独立的 personal revision，保留上游来源和父版本，不覆盖原包。当前对象存储、项目锁、内容寻址和部署回滚已有实现；“从 skills.sh 检查更新、展示差异、审批升级、回滚到旧 revision”的完整流程仍属于下一阶段工作。

## 目录平台对比

| 平台 | 官方接口/本次实测 | 可用事实 | 接入判断 |
| --- | --- | --- | --- |
| SkillsMP | [API 文档](https://skillsmp.com/docs/api)；`GET https://skillsmp.com/api/v1/skills/search?q=react&limit=3` 返回 HTTP 200 | 返回 `githubUrl`、`skillUrl`、作者、描述、stars、更新时间和分页字段；本次 `react` 查询返回 4 条（`totalIsExact=false`），说明索引规模和数量可能是估计值 | P0 目录适配器。必须回源 GitHub 预览；API key 放 Keychain/服务端配置，不写前端或仓库 |
| 腾讯 SkillHub | [Open API](https://github.com/Tencent/skillhub/blob/main/docs/api/README.md)；`GET https://api.skillhub.cn/api/skills?keyword=react&pageSize=3` 返回 HTTP 200 | 有分页列表、详情、批量详情、下载、文件、版本、diff、评测、分类；列表返回 `publisher.verified`、`version`、`source`、`upstream_url`、`downloads`、`stars` 等；文档提示生产接入使用 `X-API-Key`，并要求不要写入前端/公开仓库 | P0 目录适配器；优先用详情/文件/版本接口建立可审计来源，再固定到上游 URL/版本；组织权限和 key 必须单独建凭据引用 |
| ClawHub | [API v1 文档](https://github.com/openclaw/clawhub/blob/main/docs/api.md)；`GET https://clawhub.ai/api/v1/search?q=react` 返回 HTTP 200 | 公共读无需 token；支持搜索、列表、详情、版本、文件、下载、resolve；响应有 `trust`、`isSuspicious`、`installability`、版本/哈希关联线索；文档要求缓存、处理 `429/Retry-After`、链接回 canonical 页面，不绕过隐藏/私有/审核过滤内容 | P0 目录适配器，但不能把 ClawHub 扫描结论当本地安全结论；对 GitHub-backed 条目优先使用 `public-github` handoff 回源，保留 ClawHub 版本与扫描摘要 |
| skills.sh | [API 文档](https://www.skills.sh/docs/api)；本次访问 `GET /api/v1/skills/search` 和 trending 均 HTTP 401 | 文档列出搜索、trending、curated、详情/文件树、audit 等 API；认证用 Vercel OIDC Bearer；认证请求限额为 600 requests/minute per (team, project)，429 使用 `Retry-After` | P1。没有稳定的用户级凭据策略前不在桌面端内置 token；可保留 `npx skills add`/网页链接和人工粘贴 GitHub 来源 |
| Skills 规范 | [Agent Skills specification](https://agentskills.io/specification) | `SKILL.md` 必须有 `name`/`description` 等基础字段；可有 scripts/references/assets；规范没有 registry、签名、依赖求解、锁文件或许可证再分发政策 | 作为导入格式校验的最低层，不把规范当作供应链信任或版本协议 |

### 取样证据

本次使用独立临时 venv `/tmp/perch-library-research-venv` 安装 Scrapling 0.5，通过 `Fetcher.get` 抓取上述官方文档和 JSON 接口。原始响应保存在 `artifacts/research/third-party-skills/scraped_sources.json` 与 `api_probes.json`；脚本为 `artifacts/research/third-party-skills/scrape_sources.py`、`probe_apis.py`。采样没有执行来源仓库脚本、hooks、安装器或插件。

## 官方仓库作为高信任候选源

仓库源比聚合目录更适合做固定 revision 导入：仓库 URL、commit、子路径和许可文件可直接进入已有 `SourcePreviewRecord` / `LibrarySkillRecord.sourceOrigin`。但“官方组织”只提高发现优先级，不能替代许可、内容和行为审核。仓库采样、提交、许可和目录结构见现有 [上游调研](upstream.md)；本轮还用 Scrapling 抓取了三家仓库 README，原始响应见 `artifacts/research/third-party-skills/repo_probes.json`。

### 本轮仓库采样补充

- [Anthropic `skills`](https://github.com/anthropics/skills)：README 说明每个 Skill 自包含 `SKILL.md`，并明确多数内容为 Apache 2.0；`docx`、`pdf`、`pptx`、`xlsx` 文档技能标为 source-available，不能按开源包处理。
- [OpenAI `skills`](https://github.com/openai/skills)：README 已标记仓库 deprecated，并指向 [OpenAI Plugins](https://github.com/openai/plugins)；单个 Skill 的许可要到其目录 `LICENSE.txt` 核实，不能按仓库根许可推断。
- [Vercel `agent-skills`](https://github.com/vercel-labs/agent-skills)：README 列出 `vercel-optimize`、`react-best-practices`、`web-design-guidelines`、`writing-guidelines`、`react-native-guidelines` 等 Skill；本次抓取仓库根 `LICENSE` 返回 404，许可必须逐条回源核对。
- [Matt Pocock `skills`](https://github.com/mattpocock/skills)：固定提交、插件清单和 MIT 许可的细节已记录在 [上游调研](upstream.md)；其 promoted/in-progress/deprecated 分层可借鉴为目录状态，但不能复制其会删除已有目录的开发链接脚本。

本轮对上述 raw README 的请求均为 HTTP 200；对根 `LICENSE` 的简单路径请求不能作为“无许可”证明，只说明需要查目录内许可证或 GitHub license 元数据。

优先级建议：

- **P0**：Anthropic、OpenAI、Vercel 官方/维护者仓库；用于验证标准、宿主兼容性和常用工程 Skill。
- **P1**：Microsoft、Expo、Supabase 等有明确组织归属和许可证的厂商仓库；导入前逐仓库确认许可和内容是否允许再分发。
- **观察**：个人集合、社区聚合、OpenClaw/ClawHub 用户上传内容；默认只作候选，不进入推荐或自动更新队列。

## 对本项目的适配建议

### 数据模型

新增只读的 `SkillDirectoryProvider` 配置和 `DirectorySkillHit` 快照，不改变现有 `Source`/`SkillRevision` 的权威模型：

- `providerID`、`providerURL`、`observedAt`、请求参数和脱敏响应摘要；
- `providerItemID`、标题、描述、作者/组织、canonical 页面；
- `sourceURL`、`sourceKind`（GitHub、SkillHub 包、ClawHub handoff 等）、建议 ref/version；
- `licenseHint`、`trustSignals`、`riskFlags`，明确“目录声明”与“本地核验”两个状态；
- `resolvedCommit`、`contentHash` 仅在现有隔离预览成功后填写。

目录快照进入 `~/.perch`，不写公开 `registry/catalog.json` 或全局技能目录。缓存应有 TTL，目录删除/下线只影响发现结果，不删除已导入的本机包。

### 接入流程

```text
目录搜索（只读）
  → 候选详情和原始链接
  → 来源白名单/网络策略检查
  → Git 隔离预览（固定 ref/commit）
  → 扫描 SKILL.md、软链、大小、许可证和 contentHash
  → 用户逐项选择并导入本机 personal 包
  → 复用现有 plan/approval/deploy
```

目录下载接口只用于“详情/来源线索”或在有明确版本摘要时作为临时预览；不能绕过现有 `SourcePreviewService` 的路径安全、Git hook 禁用、子模块禁用、完整性核验和许可证留存。对于 ClawHub 的 `public-github` handoff，直接采用其上游来源并记录 ClawHub 版本/扫描事实。

### 安全与许可门槛

- 目录搜索结果是不可信输入；严格限制 URL scheme/host，禁止凭结果改变允许写入路径或执行命令。
- 下载、解包、Git clone 均进入隔离 staging；拒绝 archive traversal、特殊文件、越界/循环软链、超限包和断链。
- 不执行 `scripts`、hooks、postinstall、commands、MCP server 或插件安装器；导入时保留文本资源供人工审阅。
- 许可证缺失、仅有聚合平台许可提示或来源许可证与包不一致时，状态为 `required/unknown`，不能自动发布或推荐。
- API key、Bearer/OIDC token 只保存凭据引用；请求日志和错误信息脱敏。实现缓存时遵守各平台 `429/Retry-After` 与条款，不高并发抓取。
- 同名不同来源不覆盖；来源更新先新建预览和 revision，内容 hash 或许可证变化须重新审核。

## 分阶段路线

### P0：可审计发现

1. 抽象 `SkillDirectoryProvider` 协议和统一分页/错误/限流结果。
2. 实现 SkillsMP、SkillHub、ClawHub 三个只读适配器；每个适配器只负责搜索/详情/版本元数据。
3. 搜索结果页显示来源、canonical URL、作者、版本、更新时间、许可证线索、扫描/验证声明和“回源预览”按钮。
4. 回源预览复用 `SourcePreviewService`；没有固定 commit 时在预览阶段解析并保存 commit，不能以 branch/tag 作为最终锁定依据。
5. 增加行为测试：分页、429 重试边界、无许可证、来源 URL 不一致、provider 下线但本机包仍可读。

### P1：官方源和更新

- 官方仓库清单配置化，但只作推荐排序和可信标记；每仓库显式固定 commit/子路径。
- 对已导入包提供“检查更新”而非自动覆盖：抓取新 revision、比较 manifest/license/content hash，生成差异和新导入计划。
- 增加源级缓存清理、离线浏览、审计导出和 API 凭据引用状态。

### P2：更深的生态能力

- skills.sh OIDC 认证策略和团队级配额确认后再接 API。
- ClawHub/SkillHub 的评测、签名、版本 diff 与本地静态风险报告对齐；仍保留本地复核。
- marketplace/plugin 依赖解析与宿主生命周期保持独立，不把 Skill 目录条目直接当 Plugin 安装。

## 未完成项

- 本报告没有安装或启用第三方 Skill，没有修改公开 `registry/catalog.json`、全局技能或宿主配置。
- skills.sh 需要有效 Vercel OIDC token 才能验证真实返回字段和团队授权流程；本次只核验官方文档和未授权错误。
- 聚合平台的排名、下载量、验证徽章是动态观察值，不应直接作为质量或安全证明。
- 需要在实现前进一步核实各平台当前条款、配额、版本字段和 API 变化；目录结果的时间戳必须进入快照。
