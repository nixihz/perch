# skill-set

Codex / Claude Code skill 包集合。每个 skill 是一个独立的 `SKILL.md` 包。

## 安装

使用 [`skill`](https://www.npmjs.com/package/skill) CLI 安装到项目的 `.codebuddy/skills/`（如需装到 `~/.claude/skills/`，把 `.codebuddy/skills` 软链过去即可）：

```bash
# 三个 skill 分别安装
npx skill skills/likec4-dsl
npx skill skills/mitmproxy-cli
npx skill skills/organize-ios-home-screen
```

> `skill` 默认从 `vercel-labs/agent-skills` 拉取，本仓库镜像在 `https://github.com/iamx/skill-set`，需通过 `SKILL_BASE_URL` 把远端指过去：

```bash
SKILL_BASE_URL=https://github.com/iamx/skill-set/tree/main \
  npx skill skills/likec4-dsl
```

## 三个 skill 一览

| Skill | 一句话用途 |
| --- | --- |
| `skills/likec4-dsl` | 把软件架构建模为 LikeC4 DSL：`.c4`/`.likec4` 模型、视图、部署、CLI 与 MCP。 |
| `skills/mitmproxy-cli` | 用 mitmproxy/mitmdump 做 Map Local、按 URL 规则返回本地文件、抓包与诊断。 |
| `skills/organize-ios-home-screen` | 通过 Appium / XCUITest / WebDriverAgent 盘点、规划、整理真实 iOS 主屏并验证。 |

每个 skill 的细节、触发条件、安全边界、依赖脚本见各自目录下的 `SKILL.md`。
