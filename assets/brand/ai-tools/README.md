# AI 工具图标来源

项目和全局技能行用 Codex、Claude 图标分别切换对应工具的草稿选择。图标只标识工具，不表示工具已加载技能或官方合作关系。

## 上游与许可

- 仓库：[LobeHub / lobe-icons](https://github.com/lobehub/lobe-icons)。
- 固定版本：[680f1d7f95b5ae6a494fe43539da8a992f17b53d](https://github.com/lobehub/lobe-icons/tree/680f1d7f95b5ae6a494fe43539da8a992f17b53d)，取用日期为 2026-10-23。
- 许可：MIT，原文保存在 [LICENSE.lobe-icons](LICENSE.lobe-icons)。品牌名称与商标归各自所有者所有；MIT 许可针对上游提供的图标素材。
- [codex.svg](https://github.com/lobehub/lobe-icons/blob/680f1d7f95b5ae6a494fe43539da8a992f17b53d/packages/static-svg/icons/codex.svg)：对应本目录 `codex.svg`。
- [claude.svg](https://github.com/lobehub/lobe-icons/blob/680f1d7f95b5ae6a494fe43539da8a992f17b53d/packages/static-svg/icons/claude.svg)：对应本目录 `claude.svg`，用于 Claude Code 入口。

本目录中的 SVG 是上游原始文件，没有修改路径。SHA-256：

| 文件 | 内容指纹 |
| --- | --- |
| `codex.svg` | `d08b4e824cd6727e89617f59e4737273ff53e44c1da849d016dd64dfd08b33e1` |
| `claude.svg` | `365a70a7eb3956d9b9a96086058ebe04e1dbd8e291a756ad964e8a283fbd6d38` |

## 应用资源

`Sources/SkillSetApp/Resources/Theme.xcassets` 中的 `CodexLogo.imageset` 与 `ClaudeLogo.imageset` 使用由上述 SVG 导出的 PDF。转换前仅将根元素的 `width`、`height` 从 `1em` 改为 `24`，并把 `currentColor` 改为黑色；保留矢量路径和 `24 × 24` viewBox。转换使用本机 `rsvg-convert 2.62.1`，参数为 `--format pdf --dpi-x 72 --dpi-y 72`，生成 `24 × 24pt` 的矢量 PDF。采用 PDF 是为了避免 Asset Catalog 的 CoreSVG 解析警告。

两个 imageset 均启用保留矢量及 template 渲染，并已通过 macOS 14 目标的 `actool` 编译。`SkillHostToggles` 使用应用的动态文字颜色，浅色与深色窗口共用图形，不依赖网络或运行时 SVG 解析。按钮尺寸为 `36 × 36pt`，Logo 为 `20 × 20pt`；开启状态另带勾号、底色和边框。
