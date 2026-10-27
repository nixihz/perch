# Perch

Perch 是一个本地 macOS 应用、CLI 和 stdio MCP 服务，用来管理 Codex 与 Claude Code 的 Skills、规则片段、MCP Servers 和 Plugins。

它把“选了什么、来源是什么、将写入哪些文件、谁批准了写入”放进同一套可审阅的计划和事务模型。应用不会启动 HTTP server、WebView 或 localhost API。

> 当前状态：Alpha。本仓库适合试用、评审和贡献；marketplace 搜索、依赖求解、跨进程锁和来源自动更新仍未实现。

## 能做什么

- 发现、阅读、编辑和组织本地 Skills。
- 从 GitHub 或本地目录隔离预览来源，固定 revision 后再导入。
- 为项目生成 Codex `.agents/skills`、`AGENTS.md`，或 Claude Code `.claude/skills`、`CLAUDE.md` 的变更计划。
- 维护 MCP 配置草稿，批准后写入宿主配置。
- 盘点并管理本机已发现的 Plugins；执行前展示 manifest、revision、hooks 和风险。
- 通过同一套 Swift core 提供原生应用、`skillset` CLI 和 stdio MCP。
- 在写入前展示差异，批准后执行 staging、journal、旧 hash 校验和回读。

项目写入必须经过人工批准。MCP 可以查询、预览和生成计划，但不能替用户批准计划或确认安装风险。来源脚本、hooks、子模块和 postinstall 不会被 Perch 自动执行。

## 快速开始

要求 macOS 14+、Swift 6 和 Xcode Command Line Tools。

```bash
./script/build_and_run.sh --verify
# 或
swift build --product SkillSetDesktop
.build/debug/SkillSetDesktop
```

构建 CLI 和 MCP：

```bash
swift build --product skillset
.build/debug/skillset doctor --json
.build/debug/skillset mcp serve --transport stdio
```

打包应用：

```bash
task macos-build
# 产物：dist/栖集.app
```

首次使用建议从“项目”开始：登记一个本地项目，选择宿主和 Skills，点击“预览变更”，确认差异后再批准写入。

## 仓库结构

```text
Sources/SkillSetCore/       Swift 领域模型、事务和来源处理
Sources/SkillSetApp/        SwiftUI 原生 macOS 应用
Sources/SkillSetCLI/        skillset CLI 与 stdio MCP
skills/                     随仓库发布的自维护 Skills
presets/                    可审阅的预设
registry/                   来源与内容目录
objects/                    按内容寻址的离线对象
templates/agents/           可写入项目的规则片段
docs/                       产品范围、架构、MCP 契约和验收说明
script/                     构建、安装和发布辅助脚本
tests/                      Swift、Python、Node 和 BDD 测试
```

仓库只随附 `skills/` 下的公共自维护 Skills。外部 Skill 应通过应用的来源预览和导入流程加入本机库，不应把个人库存或未核实授权的快照提交到仓库。

## 随仓库发布的 Skills

| Skill | 用途 |
| --- | --- |
| `skills/collaboration-style` | 中文协作和工程交付约定。 |
| `skills/cso` | 基于证据的安全审计流程。 |
| `skills/humanizer-zh` | 中文文本去模板化和自然化改写。 |
| `skills/kindle-pw2-eink` | Kindle Paperwhite 2 墨水屏控制。 |
| `skills/kubeconfig-manager` | kubeconfig 批量导入、命名、更新和备份恢复。 |
| `skills/likec4-dsl` | LikeC4 架构模型、视图和 CLI 工作流。 |
| `skills/mitmproxy-cli` | mitmproxy Map Local、诊断和流量验证。 |
| `skills/organize-ios-home-screen` | iPhone 主屏幕布局盘点、规划和批量写入。 |
| `skills/project-guide` | 从实际代码提取项目架构和运行路径。 |
| `skills/stc` | 清晰、准确的中文技术文稿。 |
| `skills/talent-spark-discovery` | 基于对话探索兴趣、优势和工作条件。 |
| `skills/tokenhubctl` | Token Hub 管理 API 的查询和维护。 |

每个 Skill 目录内的许可证或来源说明优先于仓库默认许可证。新增来源时请同时保留上游许可证和归属信息。

## 开发和验证

```bash
node scripts/check-skills.mjs
python3 scripts/catalog.py verify
node --test tests/*.test.mjs
python3 -m unittest discover -s tests -p 'test_*.py' -v
swift test
swift build --product SkillSetDesktop
swift build --product skillset
```

CI 在 Ubuntu 上执行结构、目录和 Python/Node 检查，在 macOS 14 上构建应用、CLI、MCP 并运行 Swift 测试。原生 UI 场景需要交互式 macOS 会话和 Accessibility 权限；无此条件时会跳过，并不会伪造通过结果。

## 文档

- [产品范围与状态](docs/SPEC.md)
- [架构](docs/specs/architecture.md)
- [MCP 契约](docs/specs/mcp.md)
- [项目接入](docs/specs/project-integration.md)
- [验收标准](docs/specs/acceptance.md)
- [设计规范](DESIGN.md)
- [第三方依赖与归属](THIRD_PARTY.md)
- [贡献指南](CONTRIBUTING.md)
- [安全报告](SECURITY.md)

## 许可证

Perch 自有代码和未带其他许可证的仓库内容采用 [MIT License](LICENSE)。第三方依赖、Skill 和图标资源继续适用各自的许可证，详见 [THIRD_PARTY.md](THIRD_PARTY.md) 及对应目录中的许可证文件。
