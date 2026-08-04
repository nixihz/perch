# skill-set

Codex / Claude Code skill 包集合。每个 skill 是一个独立的 `SKILL.md` 包，存放在 `skills/<name>/` 下。

## 私有仓库

CLI 不做 HTTP 认证头，私有仓库走**系统 git 的认证**。两条路任选：

- **SSH**（最干净）：把本机公钥加到 GitHub / Gitea 账户，源写成 SSH 形式即可。Gitea 示例：

  ```bash
  npx skills add ssh://git@git.xiezhi.xin:2222/iamx/skill-set.git
  # 或短形式
  npx skills add git@git.xiezhi.xin:iamx/skill-set.git
  ```

  可先用 `ssh -T git@git.xiezhi.xin` 验证连通性。

- **HTTPS + git credential helper**：把仓库 URL 当作普通 git 远端，配好 `git credential-osxkeychain` / `gh auth login` / 仓库级 `user/pass` 等任意一种方式。`npx skills add https://...` 会复用同一份凭证。

## Skill 一览

| Skill | 一句话用途 |
| --- | --- |
| `skills/kindle-pw2-eink` | 将越狱 Kindle Paperwhite 2 作为可恢复的全屏墨水屏：渲染灰度画面、通过 USB SSH 推送内容，并用 KUAL / FBInk 控制显示。 |
| `skills/likec4-dsl` | 把软件架构建模为 LikeC4 DSL：`.c4`/`.likec4` 模型、视图、部署、CLI 与 MCP。 |
| `skills/mitmproxy-cli` | 用 mitmproxy/mitmdump 做 Map Local、按 URL 规则返回本地文件、抓包与诊断。 |
| `skills/organize-ios-home-screen` | 用 go-ios 全量导出、离线规划并一次批量写入 iPhone 主屏幕布局，Appium 仅辅助 Focus 状态。 |

每个 skill 的细节、触发条件、安全边界、依赖脚本见各自目录下的 `SKILL.md`。
