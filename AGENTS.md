# skill-set 协作约定

- 始终使用中文回复；代码标识符使用英文，注释用中文解释原因。
- 分析需求、项目和技术文档时加载 `stc` skill。
- 新增 UI 前先读 `DESIGN.md`；缺少时先提醒并补齐设计约定。
- `skills/` 是自维护内容；`vendor/` 是带来源的实体快照。修改外部快照前先看 `registry/local-import.json`，不要直接批量同步或覆盖。
- 收录不等于启用。只有用户选择的 skill 才能写入项目发现目录；本轮原型不写真实项目、全局 skills 或 agent 配置。
- 变更 skill 内容后核对 `registry/catalog.json` 指纹；仅从可信的本地来源重新生成目录，不运行来源中的脚本。
- 修改来源导入、部署或 MCP 时，先读 `docs/specs/architecture.md` 和 `docs/specs/mcp.md`；实现仍以 SPEC 中的里程碑为界。
- 单元测试检查可观察行为和失败路径，严禁同义反复测试。
- PR/MR 创建后将当前会话标题前缀设为 ✅；合并后改为 🚀。
- 完成时报告验证结果、未完成项和使用过的 skill；若 skill 有改进空间，说明具体建议，不擅自修改外部 skill。

## Agent skills

### Issue tracker

事项使用本地 Markdown，保存在 `.scratch/<feature>/`。创建、读取或更新事项前，先读 `docs/agents/issue-tracker.md`。

### Domain docs

采用 single-context：根目录 `GLOSSARY.md` 和 `docs/adr/`。探索代码、讨论领域术语或架构决策前，先读 `docs/agents/domain.md`。
