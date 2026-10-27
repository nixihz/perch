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

构建与安装也可分开执行（安装会替换目标目录中的 `栖集.app`，不会自动启动）：

```bash
task macos-build         # 只构建并打包到 dist/栖集.app
task macos-install-only  # 只安装已有产物到 /Applications/栖集.app
task macos-install       # 先构建，再安装
task macos-install -- --release  # 构建 Release 并安装
```

`PERCH_DIST_DIR` 可指定构建产物目录；`MACOS_INSTALL_DIR` 可指定已存在的安装目录，例如 `task macos-install-only MACOS_INSTALL_DIR="$HOME/Applications"`。

构建结果为 `dist/栖集.app`，Dock 显示“栖集”，英文名为 Perch；Bundle ID、`skillset` CLI 和原数据目录不变。启动后在原生窗口中使用：

首次使用从「项目」开始：添加项目目录，选择 AI 工具，再选择技能和规则，或点「使用预设…」载入常用组合。点击「预览变更」核对目标文件，批准后才会写入。也可以先用空态中的「浏览技能库」「查看预设」了解现有内容。

侧栏按「配置」「技能与规则」「AI 工具」分组，菜单栏「前往」提供相同入口与快捷键。详细信息的箭头、标题和整行空白均可展开、收起。

- **全局配置**：选择 Codex 或 Claude Code，为当前用户的全部项目配置技能和规则；已有内容默认保留，显式接管时保存原始备份。支持撤销操作、恢复接管前状态和停止管理但保留文件，均需预览并批准。详见 [全局配置与还原](docs/specs/global-configuration.md)。

- **项目**：登记本机目录，选择 Skills、agent 和规则片段，生成计划；审阅 digest 后写入 Codex `.agents/skills` / `AGENTS.md` 或 Claude Code `.claude/skills` / `CLAUDE.md`。安装选择、版本记录和恢复信息保存在应用数据目录 `~/.perch/`，不在用户项目目录添加管理器专用文件。
- **Skills**：搜索和阅读来源化技能，新增、编辑或移除本地技能；外部快照可“复制并编辑”及隐藏后恢复。本地技能保存在 `~/.perch/skills/`，不会自动启用；选择到项目草稿后仍需生成并批准计划。
- **MCP Servers**：读取 Codex TOML、Claude 项目与用户 JSON 中的真实连接；生成新增或受管配置计划，人工批准后写入并不启动 MCP 进程。
- **Plugins**：读取本机 Claude Code / Codex 缓存、Claude 安装索引、Codex 配置和 manifest，展示安装状态、marketplace、revision、组件与 hooks 风险；为本机已发现插件生成 install / update / enable / disable / uninstall 计划。计划批准后才调用固定宿主 CLI，执行前复核状态、执行后回读并记录 operation。
- **来源 / 预设 / 规则片段**：GitHub 仓库根可联网预览并保存固定 commit，在技能旁点击“加入技能库…”可审阅正文与文件、修改本机标识并保存完整独立副本；保留附带文件和仓库许可，删除来源预览不影响已导入技能。导入后点击“前往项目”，选择技能、预览变更并批准写入。项目页可直接使用预设，预设页可选择项目或添加本机目录，载入前展示草稿中技能与规则的新增、保留、移除项；预设只生成项目草稿，真实写入仍需预览与批准；规则片段分别写入目标宿主的 `AGENTS.md` / `CLAUDE.md` 受管块。
- **技能正文预览**：详情默认解析 Markdown，支持标题、列表、引用、代码块与表格，可切换完整原文；新增与编辑支持原位预览。YAML 元信息默认收起，草稿和保存内容保持原样。预览不执行 HTML、脚本，也不自动加载远程图片。
- **AGENTS 片段**：支持新增、搜索、编辑、复制正文和创建副本。点击“用于配置…”选择项目或全局目标，核对真实路径和合成规则，再“加入草稿并预览…”。审批页提供差异、写入前和写入后正文；批准后写入并回读，宿主加载仍需验证。使用位置列出草稿、已写入配置和预设，片段更新需要再次部署；删除后引用显示不可用，清理后才能重新部署。关闭目标选择不会保存草稿；取消审批保留已加入的草稿，目标文件保持不变。
- **跨电脑复制片段库**：将 `templates.json` 放入 `~/.perch/`。缺失标识与可选字段、正文中的裸换行会兼容读取，首次改写前自动备份原文件；读取失败会显示路径与“重新读取”，修复后无需重启。
- **AI 接入**：检查随 App 提供的 MCP 程序与运行资源，分别显示程序、Codex / Claude 用户级配置和宿主加载待验证状态；选择宿主后生成接入计划，本机审阅并批准后才写配置。真实 `skillset mcp serve --transport stdio` 提供查询、预览和计划；AI 不能自我批准写入。

项目写入只发生在用户于计划 sheet 中二次确认后，并经过旧 hash 校验、staging、journal、离线对象核验和回读；CLI 的 `approve` 是显式本机人工动作。MCP 配置写入复用同一审批与事务层；Plugin 生命周期复用计划/审批/operation 模型，但外部宿主命令不伪装成可通用回滚的文件事务。Keychain 不读取，来源脚本、hooks、子模块和 postinstall 不执行。

项目接入现在区分“项目已有”和“栖集管理”：相同内容保留原归属，同路径不同内容与受管内容漂移会阻塞。取消技能或宿主选择会规划移除未漂移的受管技能与规则块，并保存可撤销的备份；块外新增规则保留。旧锁没有本机管理记录时不自动接管，旧版待执行部署计划须重新生成。接入基线、恢复接入前状态和完整退出管理仍待实现，详见[项目接入设计](docs/specs/project-integration.md)。

- 片段和预设默认空库，仅显示用户保存的条目，均可删除。技能库默认无内置来源。配置 Git 仓库或本地目录并同步后，即可搜索其中的技能；本仓 JSON 快照仅保留为仓库资料。
- `local-brian/ponytail-review` 的 5 条断链保留为 `blocked`，不猜测修复。
- Matt 链接实测固定到 `5beb35b040e3de97e54fa9e386d7e42d15c295c2`，识别 27 个 promoted、7 个 in-progress、4 个 misc；远端可主动触发只读预览，但不会自动收录或增加库存。
- 来源缓存保存在 `~/.perch/cache/sources/`，技能完整包和安装版本分别保存在 `skills/`、`versions/`。同步不等于启用；启用时可选择软链接（默认）或复制，经计划批准后写入项目或用户级 harness 目录。

## 本机 CLI 与 MCP

桌面应用已接入 Sparkle 2.10.0，菜单和设置页提供检查更新。Perch 迁移到 [app.u1.fan 官网](https://app.u1.fan/x/perch/)，从 build 4 起使用新平台的下载包和 Sparkle 清单；旧版需手动安装一次迁移版，之后可在应用内检查更新。配置、版本号、Release 打包与后续签名发布步骤见[在线更新说明](docs/sparkle-updates.md)。

```bash
swift build --product skillset
.build/debug/skillset doctor --json
.build/debug/skillset sources preview https://github.com/mattpocock/skills --json
.build/debug/skillset projects add /path/to/project --name demo --json
.build/debug/skillset plan <project-id> --skills workspace/stc --instructions <saved-snippet-id> --json
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

MCP 服务名为 `perch`，首版协议为 legacy `2025-11-25`，提供 59 个工具，覆盖技能库、规则片段、预设、来源、项目、MCP 配置库与插件来源管理，以及项目/全局应用计划、apply、operation、离线对象核验和 Plugin 生命周期计划。`mcp_batch` 支持一个请求顺序处理最多 50 项工具调用，读操作复用快照；完整技能包、分类及来源证据、片段或预设变化后刷新，并返回逐项成功或失败结果。同一进程中这些内容未变化时，后续调用复用已加载的库，检查只读文件元数据。JSON-RPC 数组请求也按单个数组响应处理。库 CRUD 即时生效：编辑技能会立即影响软链部署，删除库条目或其跟随来源会使对应软链部署失效；复制部署不变。`skills_create` 可用 `sourceSkillId` 复制完整技能包及来源证据。批量工具声明可能包含删除、部署和联网操作，各项仍遵循自身校验与审批；完整工具矩阵见 [MCP 契约](docs/specs/mcp.md)。`skills_install` / `presets_install` 接收已登记项目的绝对路径或 ID，追加技能与规则并返回待批准计划；含插件或 MCP 的混合预设转本机完整审阅。`deployment_apply` 只执行已由 UI/CLI 批准且 digest 完全一致的计划。MCP 不能批准计划，也不能替用户确认安装/更新包风险。

## 设计与规范

| 文档 | 内容 |
| --- | --- |
| [SPEC](docs/SPEC.md) | 产品范围、优先级、用户故事、成功标准、待定事项 |
| [上游调研](docs/research/upstream.md) | Matt / Vercel、Agent Skills、Codex / Claude 和 MCP 的官方证据 |
| [本地盘点](docs/research/local-inventory.md) | 139 包迁移、24 条顶层软链实体化、5 条断链和核验边界 |
| [架构](docs/specs/architecture.md) | 三种版本、来源解析、锁、宿主适配、部署事务与恢复 |
| [MCP 与 CLI](docs/specs/mcp.md) | 工具、输入输出、人工审批、错误码和兼容门槛 |
| [验收](docs/specs/acceptance.md) | M0–M4、失败路径和真实宿主验证 |
| [BDD](docs/specs/bdd.md) | 中文 Gherkin 场景、执行边界，以及项目部署、来源预览、MCP 配置、Plugin 生命周期与原生 UI 切片；原生 UI 覆盖首开任务引导、菜单导航、标题与空白展开、搜索空态、权限失败、表单和二次确认 |
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
| `skills/cso` | gstack 的安全审计 Skill：基于证据审查代码、依赖、基础设施与 AI/Skill 供应链；v3 需要专用运行程序。[来源与安装依赖](skills/cso/SOURCE.md)。 |
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

技能库是栖集私有库存 `~/.perch/skills/library/`，里面只留软链，技能实体放在 `~/.perch/sources/custom/` 或来源检出。`~/.agents/skills` 是共享安装目录，只在全局配置中点击 Agents 图标保存后写入，不再作为私有技能库。

首次初始化会读取 Agents、Codex、Claude Code 的技能目录，把尚未入库存、且不是跟随技能来源的技能复制到 `~/.perch/sources/custom/<技能名>/`，并在私有库存里留下同名软链。之后「扫描已安装技能…」只扫描手动追加的目录，不再读取这些官方目录。原安装保持原样。同名技能不覆盖。旧的 `~/.perch/sources/local-imports` 会在启动时迁入 `custom` 后删除。

全局配置采用单栏草稿：在技能标签中点击 Agents / Codex / Claude Code 开关，其他资源使用 Codex / Claude Code 图标；技能图标点击即保存，再次点击取消；成功给出反馈，失败保留原选择。其他资源按目标预览后保存，安装方式与接管已有内容在安装选项中设置，并随对应工具图标保存；插件仅支持其所属宿主。全局文件现状与还原历史入口已从此页隐藏，备份与恢复能力仍保留。

全局、项目和预设的技能标签下均展示已选技能 pill，搜索不会隐藏已选项。全局 pill 可独立切换三个技能目标，项目 pill 仍切换 Codex / Claude Code；× 从当前范围的所有目标草稿中取消；预设的 × 只移除组合中的该技能。大量选择在已选区独立滚动；全局技能胶囊点击图标或 × 即保存，项目与预设仍按草稿流程保存。

系统不要求用户审查技能许可。许可证原文随来源和技能包保留，导入与保存不增加许可审查步骤。

全局技能配置并列提供 **Agents / Codex / Claude Code**：分别保存到 `~/.agents/skills`、`${CODEX_HOME:-~/.codex}/skills` 与 `${CLAUDE_CONFIG_DIR:-~/.claude}/skills`，草稿、安装方式与管理记录独立。Agents 只配置共享技能；规则、MCP 和插件仍按工具配置。Codex 也会加载 Agents 技能，取消 Codex 勾选不会停用共享目录中的内容。同名技能会显示提示，点击工具图标保存时可核对另一个目录的路径。

项目页与全局配置共用同一资源草稿组件，顶部增加紧凑项目选择区。点击项目名切换下面的配置；技能与片段、MCP、插件按项目和工具分别保存草稿，预览后点击“保存”提交当前计划。路径、继承、文件现状与待批准计划可从“项目详情…”查看。 共用技能、规则或安装方式需要同时更新两个工具时，项目预览会展示关联变更，点击“保存”一并执行；另一个工具的未部署草稿继续保留。

预设页同样采用上下结构：顶部切换预设，下方直接编辑四类资源，预览后保存。每个预设的未保存修改在当前会话中独立保留，保存组合不会修改项目或 AI 工具配置；保存后再通过“用于项目…”载入项目草稿。
