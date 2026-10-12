# skill-set

Codex / Claude Code skill 包集合。每个 skill 是一个独立的 `SKILL.md` 包，存放在 `skills/<name>/` 下。

## 私有仓库

CLI 不做 HTTP 认证头，私有仓库走**系统 git 的认证**。两条路任选：

- **SSH**（最干净）：把本机公钥加到 GitHub / Gitea 账户，源写成 SSH 形式即可。Gitea 示例：

  ```bash
  npx skills add ssh://git@git.xiezhi.xin:2222/iamx/skill-set.git
  ```

  可先用 `ssh -T git@git.xiezhi.xin` 验证连通性。

- **HTTPS + git credential helper**：把仓库 URL 当作普通 git 远端，配好 `git credential-osxkeychain` / `gh auth login` / 仓库级 `user/pass` 等任意一种方式。`npx skills add https://...` 会复用同一份凭证。

## Skill 一览

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

- **STC**：技术文档、工具说明、操作规程。优先保留原意、条件、事实强度和技术字面值，再减少歧义。详见 [使用与验证说明](skills/stc/README.md)。
- **humanizer-zh**：文章或一般说明的文风润色，减少 AI 写作痕迹。
- 同时使用时，先用 STC 核对语义，再润色文风，最后对照原文复核。文风调整不能覆盖语义约束。

## 维护与验证

`skills/<name>/` 是内容源；`.agents/skills/` 是本地发现入口，`.claude/skills` 复用该入口。新增 skill 时同步目录表和发现链接，链接使用相对路径，不复制整份内容。

从仓库根目录执行：

```bash
node scripts/check-skills.mjs
node --test tests/check-skills.test.mjs
python3 skills/stc/scripts/stc-lint.py --selftest
python3 -m unittest discover -s skills/kubeconfig-manager/tests -v
```

结构检查核对目录表、元数据、本地发现链接，以及 STC 的本地引用和行为用例结构；缺失发现入口会单独警告。CI 执行结构检查与上述回归测试，不调用真实设备、集群或在线服务。

静态检查器测试不证明模型改写保持语义。修改 STC 规则后，另按 [行为评估流程](skills/stc/references/evaluation.md) 复测，并记录被测文件与实际输出。历史评估不能当作当前版本的验证结果。
