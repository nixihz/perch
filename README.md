# skill-set

Codex / Claude Code skill 包集合。每个 skill 是一个独立的 `SKILL.md` 包，存放在 `skills/<name>/` 下。

## 安装（私有 Gitea）

本仓库托管在私有 Gitea `https://git.xiezhi.xin/iamx/skill-set`。`skill` CLI（`npx skill`）本身不带认证头，只能把 Gitea **Access Token 嵌进 `SKILL_BASE_URL`**，靠 HTTP Basic Auth 鉴权：

```bash
# 三个 skill 单独安装
SKILL_BASE_URL=https://<ACCESS_TOKEN>@git.xiezhi.xin/iamx/skill-set/raw/branch/main \
  npx skill skills/likec4-dsl

SKILL_BASE_URL=https://<ACCESS_TOKEN>@git.xiezhi.xin/iamx/skill-set/raw/branch/main \
  npx skill skills/mitmproxy-cli

SKILL_BASE_URL=https://<ACCESS_TOKEN>@git.xiezhi.xin/iamx/skill-set/raw/branch/main \
  npx skill skills/organize-ios-home-screen
```

把 `<ACCESS_TOKEN>` 换成在 Gitea 用户设置里生成的访问令牌（**不要用账号密码**）。安装目录默认为 `.codebuddy/skills/<name>/`；要装到 `~/.claude/skills/`，把 `.codebuddy/skills` 软链过去即可：

```bash
mkdir -p ~/.claude/skills
ln -s "$(pwd)/.codebuddy/skills"/* ~/.claude/skills/
```

> 因为是私有仓库且非 GitHub，CLI 无法自动列目录；每个 skill 目录下的 `index.json` 清单明确列出要拉取的文件。修改 skill 后**记得同步更新对应的 `index.json`**。

## 三个 skill 一览

| Skill | 一句话用途 |
| --- | --- |
| `skills/likec4-dsl` | 把软件架构建模为 LikeC4 DSL：`.c4`/`.likec4` 模型、视图、部署、CLI 与 MCP。 |
| `skills/mitmproxy-cli` | 用 mitmproxy/mitmdump 做 Map Local、按 URL 规则返回本地文件、抓包与诊断。 |
| `skills/organize-ios-home-screen` | 通过 Appium / XCUITest / WebDriverAgent 盘点、规划、整理真实 iOS 主屏并验证。 |

每个 skill 的细节、触发条件、安全边界、依赖脚本见各自目录下的 `SKILL.md`。
