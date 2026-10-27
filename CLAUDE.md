@AGENTS.md
<!-- skillset:begin id=project-rules schema=1 -->
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