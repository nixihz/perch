# skill-set

Codex / Claude Code skill 包集合。每个 skill 是一个独立的 `SKILL.md` 包，存放在 `skills/<name>/` 下。

## 安装

使用 [`skills`](https://github.com/vercel-labs/skills) CLI（`npx skills`）。它原生支持任何 Git 服务，走真正的 `git clone`，所以 GitHub、GitLab、自建 Gitea 都能用。

```bash
# GitHub：公开仓库直接 owner/repo
npx skills add iamx/skill-set

# GitHub：私有仓库，owner/repo 形式
npx skills add iamx/skill-set

# GitHub：完整 URL
npx skills add https://github.com/iamx/skill-set

# 只装某一个 skill
npx skills add iamx/skill-set --skill likec4-dsl
```

### 私有仓库

CLI 不做 HTTP 认证头，私有仓库走**系统 git 的认证**。两条路任选：

- **SSH**（最干净）：把本机公钥加到 GitHub / Gitea 账户，源写成 SSH 形式即可。Gitea 示例：

  ```bash
  npx skills add ssh://git@git.xiezhi.xin:2222/iamx/skill-set.git
  # 或短形式
  npx skills add git@git.xiezhi.xin:iamx/skill-set.git
  ```

  可先用 `ssh -T git@git.xiezhi.xin` 验证连通性。

- **HTTPS + git credential helper**：把仓库 URL 当作普通 git 远端，配好 `git credential-osxkeychain` / `gh auth login` / 仓库级 `user/pass` 等任意一种方式。`npx skills add https://...` 会复用同一份凭证。

### 装到哪里、给谁用

默认装到当前项目的 `./<agent>/skills/`，加 `-g` 装到 `~/<agent>/skills/`。`-a` 指定 agent（`claude-code`、`codex` 等）：

```bash
# 装到全局，给 Claude Code 用
npx skills add iamx/skill-set -g -a claude-code

# 装到项目，给 Codex 用
npx skills add iamx/skill-set -a codex

# 列一下仓库里有啥 skill（不真装）
npx skills add iamx/skill-set --list
```

安装方式默认是**符号链接**（源更新、agent 立刻看到），加 `--copy` 改为拷贝。

## 三个 skill 一览

| Skill | 一句话用途 |
| --- | --- |
| `skills/likec4-dsl` | 把软件架构建模为 LikeC4 DSL：`.c4`/`.likec4` 模型、视图、部署、CLI 与 MCP。 |
| `skills/mitmproxy-cli` | 用 mitmproxy/mitmdump 做 Map Local、按 URL 规则返回本地文件、抓包与诊断。 |
| `skills/organize-ios-home-screen` | 通过 Appium / XCUITest / WebDriverAgent 盘点、规划、整理真实 iOS 主屏并验证。 |

每个 skill 的细节、触发条件、安全边界、依赖脚本见各自目录下的 `SKILL.md`。
