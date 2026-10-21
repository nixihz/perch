# skill-set

面向多项目的本机 skill 管理仓库和 macOS 原生桌面应用：保存技能正文、来源、不可变 revision、预设、`AGENTS.md` / `CLAUDE.md` 片段，并按项目管理 Skills、MCP Servers 与 Plugins。

当前完成 **Alpha 本地工作流切片**：真实库存、原生 macOS 应用、项目草稿、项目锁与离线对象、带审批的文件事务、GitHub 来源隔离预览、Codex / Claude Code 双宿主部署、MCP 配置计划、Plugin 盘点与审批门控生命周期、共享 CLI 和 stdio MCP。产品入口是 `.app` 与同仓 `skillset` 命令，不是 Web 页面。Plugin 生命周期只操作本机已发现插件，并通过固定宿主 CLI 执行；marketplace 搜索和依赖图求解仍未实现。

## 启动本机应用

要求 macOS 14+、Swift 6 / Xcode Command Line Tools。应用不会启动 HTTP server、WebView 或 localhost API。

```bash
./script/build_and_run.sh --verify
# 或
task app
```

构建结果为 `dist/栖集.app`，Dock 显示“栖集”，英文名为 Perch；Bundle ID、`skillset` CLI 和原数据目录不变。启动后在原生窗口中使用：

- **项目**：登记本机目录，选择 Skills、agent 和规则片段，生成计划；审阅 digest 后写入 Codex `.agents/skills` / `AGENTS.md` 或 Claude Code `.claude/skills` / `CLAUDE.md`，并生成 `skillset.json` 与 `skillset.lock.json`。
- **Skills**：按 namespace、来源、内容 hash 和完整性查看 150 条来源化记录。
- **MCP Servers**：读取 Codex TOML、Claude 项目与用户 JSON 中的真实连接；生成新增或受管配置计划，人工批准后写入并不启动 MCP 进程。
- **Plugins**：读取本机 Claude Code / Codex 缓存、Claude 安装索引、Codex 配置和 manifest，展示安装状态、marketplace、revision、组件与 hooks 风险；为本机已发现插件生成 install / update / enable / disable / uninstall 计划。计划批准后才调用固定宿主 CLI，执行前复核状态、执行后回读并记录 operation。
- **来源 / 预设 / 指令模板**：GitHub 仓库根可联网隔离预览并保存固定 commit；预设只生成项目草稿；规则片段分别写入目标宿主的 `AGENTS.md` / `CLAUDE.md` 受管块。
- **AI 接入**：真实 `skillset mcp serve --transport stdio` 提供查询、预览和计划；AI 不能自我批准写入。

项目写入只发生在用户于计划 sheet 中二次确认后，并经过旧 hash 校验、staging、journal、离线对象核验和回读；CLI 的 `approve` 是显式本机人工动作。MCP 配置写入复用同一审批与事务层；Plugin 生命周期复用计划/审批/operation 模型，但外部宿主命令不伪装成可通用回滚的文件事务。Keychain 不读取，来源脚本、hooks、子模块和 postinstall 不执行。

- 库存来自本仓真实 JSON：11 个自维护 + 139 个外部条目，共 150 条来源化记录。
- `local-brian/ponytail-review` 的 5 条断链保留为 `blocked`，不猜测修复。
- Matt 链接实测固定到 `5beb35b040e3de97e54fa9e386d7e42d15c295c2`，识别 27 个 promoted、7 个 in-progress、4 个 misc；远端可主动触发只读预览，但不会自动收录或增加库存。
- 收录不等于启用；预览结果保存在本机 Application Support，不改变旧发现目录或项目。

## 本机 CLI 与 MCP

```bash
swift build --product skillset
.build/debug/skillset doctor --json
.build/debug/skillset sources preview https://github.com/mattpocock/skills --json
.build/debug/skillset projects add /path/to/project --name demo --json
.build/debug/skillset plan <project-id> --skills workspace/stc --instructions base-zh --json
.build/debug/skillset approve <plan-id> --digest <digest>
.build/debug/skillset apply <plan-id> --digest <digest> --json
.build/debug/skillset objects verify --project <project-id> --json
.build/debug/skillset plugins list --project <project-id> --json
.build/debug/skillset plugins plan --host claude-code --plugin mattpocock-skills@mattpocock --action enable --scope user --manifest-digest <sha256> --json
.build/debug/skillset mcp servers --project <project-id> --json
```

stdio MCP 使用同一服务边界：

```bash
.build/debug/skillset mcp serve --transport stdio
```

首版协议为 legacy `2025-11-25`，提供 14 个工具：项目、Skills、来源预览、计划、审批状态、apply、operation、离线对象、MCP 配置、Plugin 盘点和 Plugin 生命周期计划。`deployment_apply` 只执行已由 UI/CLI 批准且 digest 完全一致的计划。MCP 不能批准计划，也不能替用户确认安装/更新包风险。

## 设计与规范

| 文档 | 内容 |
| --- | --- |
| [SPEC](docs/SPEC.md) | 产品范围、优先级、用户故事、成功标准、待定事项 |
| [上游调研](docs/research/upstream.md) | Matt / Vercel、Agent Skills、Codex / Claude 和 MCP 的官方证据 |
| [本地盘点](docs/research/local-inventory.md) | 139 包迁移、24 条顶层软链实体化、5 条断链和核验边界 |
| [架构](docs/specs/architecture.md) | 三种版本、来源解析、锁、宿主适配、部署事务与恢复 |
| [MCP 与 CLI](docs/specs/mcp.md) | 工具、输入输出、人工审批、错误码和兼容门槛 |
| [验收](docs/specs/acceptance.md) | M0–M4、失败路径和真实宿主验证 |
| [BDD](docs/specs/bdd.md) | 中文 Gherkin 场景、执行边界，以及项目部署、来源预览、MCP 配置、Plugin 生命周期与原生 UI 切片；原生 UI 覆盖搜索空态、权限失败、表单和二次确认 |
| [DESIGN.md](DESIGN.md) | 信息架构、字号、色彩、键盘、移动和动效约束 |

## 目录与版本

```text
skills/                     11 个自维护包
vendor/local-brian/         139 个来源化实体快照，不自动启用
registry/                  来源、内容目录、逐文件指纹与迁移凭证
objects/                   按内容寻址的 Skill 文件与 manifest 离线对象
presets/                   3 个草稿预设
templates/agents/          中文协作、工程质量、界面交付片段
docs/                      调研、SPEC、架构与验收
Sources/SkillSetCore/      Swift 领域模型与只读资源快照
Sources/SkillSetApp/       SwiftUI 原生 macOS 应用
Sources/SkillSetCLI/       skillset CLI 与 stdio MCP
script/build_and_run.sh    构建并启动 dist/栖集.app
```

整仓发布版本、skill 不可变内容修订、项目锁定版本分开管理。当前目录使用完整 SHA-256 标识内容，包含相对路径、文件内容和可执行位；项目锁记录 manifest digest、目标宿主、逐文件 hash 和离线对象，源目录删除后仍可核验与恢复。Git 忽略的按需运行时不计入可移植载荷。`workspace/stc` 与 `local-brian/stc` 是独立来源身份，即使内容相同也不覆盖。

迁移保留原路径、链接解析和旧库 dirty 状态；旧目录消失后仍可仅凭本仓核验实体快照。`local-brian/ponytail-review` 内有 5 条断链，正常文件已保留，但条目 blocked，不能部署。有限秘密扫描、指纹通过不代表许可、安全或模型行为已审核；本仓先私用，公开导出前必须脱敏并核查授权。

## 自维护 Skill 一览

| Skill | 一句话用途 |
| --- | --- |
| `skills/brian-working-style` | Brian 的长期协作约定：中文输出、基于真实信息推进任务，并补齐验证和交付文档。 |
| `skills/humanizer-zh` | 去除文本中的 AI 生成痕迹（夸大的象征意义、宣传性语言、三段式法则、AI 词汇、公式化收尾等），使其更自然、更像人类书写。 |
| `skills/kindle-pw2-eink` | 将越狱 Kindle Paperwhite 2 作为可恢复的全屏墨水屏：渲染灰度画面、通过 USB SSH 推送内容，并用 KUAL / FBInk 控制显示。 |
| `skills/kubeconfig-manager` | 批量导入独立 kubeconfig，统一命名并预览冲突，支持凭据更新、备份恢复和 kubectx 切换。 |
| `skills/likec4-dsl` | 把软件架构建模为 LikeC4 DSL：`.c4`/`.likec4` 模型、视图、部署、CLI 与 MCP。 |
| `skills/mitmproxy-cli` | 用 mitmproxy/mitmdump 做 Map Local、按 URL 规则返回本地文件、抓包与诊断。 |
| `skills/organize-ios-home-screen` | 用 go-ios 全量导出、离线规划并一次批量写入 iPhone 主屏幕布局，Appium 仅辅助 Focus 状态。 |
| `skills/project-guide` | 从仓库实际文件梳理用途、架构、入口、运行流程和验证方式。 |
| `skills/stc` | 清晰明了 · 中文技术文稿：保留原意，减少中文技术文档、工具描述、错误提示和操作指令中的歧义。 |
| `skills/talent-spark-discovery` | 从轻松的日常聊天开始，逐步探索兴趣、优势与工作条件，结合经历和反馈形成有依据、可修正的建议。 |
| `skills/tokenhubctl` | 通过管理 API 查询和管理 Token Hub 的 context、workspace、用户、用量和上游状态。 |

每个 skill 的细节、触发条件、安全边界、依赖脚本见各自目录下的 `SKILL.md`。

## 中文文稿如何选择 skill

- **STC**：技术文档、工具说明、操作规程。优先保留原意、条件、事实强度和技术字面值，再减少歧义。详见 [STC 约定](skills/stc/SKILL.md)。
- **humanizer-zh**：文章或一般说明的文风润色，减少 AI 写作痕迹。
- 同时使用时，先用 STC 核对语义，再润色文风，最后对照原文复核。文风调整不能覆盖语义约束。

## 维护与验证

`skills/<name>/` 是自维护内容源；`.agents/skills/` 和 `.claude/skills` 是本仓已有的 11 个发现入口。**不要把库存目录自动全量链接到发现目录。** 新建自维护包先进入目录和评审，是否启用另外决定；人工维护的发现链接使用相对路径。

从仓库根目录执行：

```bash
./script/build_and_run.sh --verify
swift build --product SkillSetDesktop
swift build --product skillset
swift test
task bdd
node scripts/check-skills.mjs
python3 scripts/catalog.py verify
node --test tests/*.test.mjs
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

也可执行 `task app`、`task check`、`task test` 或 `task swift-test`。目录核验无需原 `/opt/case/brian/skills` 或 Magpie 路径。仅重新盘点时使用 `task inventory`；重新复制前先读[迁移说明](docs/research/local-inventory.md)，导入脚本会拒绝覆盖已有不同内容。

BDD 使用 `CucumberSwift` 执行 `tests/SkillSetBDDTests/Features/` 下的中文 Gherkin。不要使用 `swift test --parallel`，也不要依赖 `swift test --filter <场景名>`：前者不会运行场景，后者会以零测试通过。按标签运行时使用 `task bdd` 或 `CUCUMBER_TAGS=bdd swift test`。原生 UI 场景需要交互式 macOS 桌面会话和 Accessibility 权限；`CI=true` 或未授权环境会明确跳过。Plugin 表单场景使用隔离 HOME 和临时宿主 CLI，按钮批准只生成计划，不调用真实 Claude Code 或 Codex。

既有 kubeconfig 回归需要 `kubectl` 和 PyYAML；建议在临时 venv 安装，不修改全局环境：

```bash
python3 -m venv /tmp/skill-set-test-venv
/tmp/skill-set-test-venv/bin/python -m pip install PyYAML==6.0.3
/tmp/skill-set-test-venv/bin/python -m unittest discover -s skills/kubeconfig-manager/tests -v
```

结构检查只检查自维护包的目录表、显示元数据、已有发现入口与 STC 本地引用；保留历史行为用例的版本才检查其用例结构。它不是完整 YAML/Agent Skills 合规检查器。CI 在 Ubuntu 核验库存、迁移行为和既有 kubeconfig 回归，在 macOS 核验 Swift core 和原生应用构建；不连接真实设备、集群、宿主配置或业务服务。

静态测试不能证明 skill 的模型输出正确。变更规则正文后仍应以实际请求和上下文评估，记录被测版本与输出，不复用旧结果。

## 私有来源

正式来源接入规划复用系统 Git/SSH credential helper，不把 token 写进 URL、锁或日志。现有 Vercel Skills CLI 也可用系统 Git 认证访问本仓，例如：

```bash
npx skills add ssh://git@git.xiezhi.xin:2222/iamx/skill-set.git
```

这会按该 CLI 自己的发现和安装策略操作，**不等于安装本仓 150 条完整库存**，也不经过本管理器的计划/审批。需要可审计写入时使用 `skillset`；完整版本锁、来源收录和宿主适配边界见 SPEC。
