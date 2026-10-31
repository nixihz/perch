# 贡献与开发约定

- 先阅读 `README.md`、`docs/agents/domain.md` 和与改动相关的 `docs/adr/`；领域术语沿用项目文档。
- 涉及界面的改动必须同时检查 `DESIGN.md`，并补充可验证的交互证据。
- 单元测试禁止同义反复；测试应验证用户可观察的行为或重要边界。
- 注释使用中文，只解释为什么这样做，不复述代码。
- 变量名使用描述性名称。
- 改动完成后运行与范围匹配的检查，并在 Pull Request 中记录结果。
- 提交信息不添加 AI 署名或 `Co-Authored-By`。
<!-- skillset:begin id=project-rules schema=1 -->
## Agent skills

### Issue tracker

事项使用本地 Markdown，保存在 `.scratch/<feature>/`。创建、读取或更新事项前，先读 `docs/agents/issue-tracker.md`。

### Domain docs

采用 single-context：根目录 `GLOSSARY.md` 和 `docs/adr/`。探索代码、讨论领域术语或架构决策前，先读 `docs/agents/domain.md`。


- PR/MR 创建后，修改当前会话标题，前面加上 ✅；PR/MR 合并完成，修改当前会话标题，前面改成 🚀
- 单元测试规则：No tautological tests（严禁同义反复测试）
- 注释全部使用中文（除非项目已声明其他语言），只解释为什么这么做，不复述代码在做什么
- 变量名使用描述性命名
- git commit message 不添加 Co-Authored-By 等 AI 署名
- 分析需求、项目和技术文档时加载 `stc` skill。


- 涉及 UI 界面相关的应用，必须要有 DESIGN.md，否则提示用户去生成
- 设计 UI 界面时，调用 emil 相关 skill
- 开发 iOS 应用时，完成开发后远程安装到我的 iPhone 17 Pro Max
<!-- skillset:end id=project-rules -->