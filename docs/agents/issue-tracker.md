# 事项跟踪：本地 Markdown

本仓库的工作事项和功能规格保存在 `.scratch/` 中，不创建远程 Issue。
现有 `docs/SPEC.md` 等项目规范保持原用途，不自动搬迁。

## 文件约定

- 每个功能使用独立目录：`.scratch/<feature-slug>/`。
- 功能规格保存为 `.scratch/<feature-slug>/spec.md`。
- 实施事项按票据拆分：`.scratch/<feature-slug>/issues/<NN>-<slug>.md`。
  编号从 `01` 开始递增，每张票据独立成文件，不合并成一个事项清单。
- 每张票据顶部使用 `Status:` 行记录状态：
  `open`（待处理）、`claimed`（已认领）、`resolved`（已解决）。
- 评论和讨论追加到票据底部的 `## Comments` 标题下。

## 当 skill 要求“发布到事项跟踪系统”

功能规格写入对应目录的 `spec.md`；实施事项写入 `issues/` 下的独立票据。
目录不存在时按需创建。

## 当 skill 要求“读取相关票据”

读取用户提供的票据路径。若只给编号，先在相关功能目录内定位；
存在歧义时向用户确认。

## Wayfinder 工作流

供 `/wayfinder` 使用；配置本身不会安装或启用该 skill。

- 工作地图：`.scratch/<effort>/map.md`，记录笔记、已作决策和待澄清问题。
- 子票据：`.scratch/<effort>/issues/<NN>-<slug>.md`。
  正文写明待解决问题，使用 `Type:` 行记录类型：
  `research`、`prototype`、`grilling` 或 `task`。
- 阻塞关系：在票据顶部用 `Blocked by: NN, NN` 列出同一工作目录内的前置票据。
  所有前置票据均为 `resolved` 时，当前票据才解除阻塞。
- 下一张票据：按编号选择第一张状态为 `open` 且无未解决阻塞的票据。
- 认领：开始工作前，先将 `Status:` 改为 `claimed` 并保存。
- 解决：在 `## Answer` 下追加结论，将状态改为 `resolved`，
  再把结论摘要和票据链接追加到 `map.md` 的已作决策部分。
