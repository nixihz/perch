# 贡献指南

感谢你为 Perch 提交问题、文档或代码。

## 开始之前

请先阅读 [README](README.md)、[架构说明](docs/specs/architecture.md) 和 [验收标准](docs/specs/acceptance.md)。如果改动涉及界面，请同时阅读 [DESIGN.md](DESIGN.md)。

## 提交改动

1. 从最新分支创建功能分支。
2. 保持变更范围单一，说明用户可观察到的行为变化。
3. 新增来源或 Skill 时，保留许可证、版权和来源 revision；不要提交个人库存、凭据、缓存或构建产物。
4. 运行与改动相关的检查，并在 Pull Request 中记录命令和结果。
5. 代码注释使用中文，只解释设计原因；变量名使用描述性名称。

## 测试

```bash
node scripts/check-skills.mjs
python3 scripts/catalog.py verify
node --test tests/*.test.mjs
python3 -m unittest discover -s tests -p 'test_*.py' -v
swift test
```

涉及 macOS 应用或 Swift core 时，还应运行对应的 `swift build`。原生 UI 测试需要交互式 macOS 会话和 Accessibility 权限。

## Pull Request

请在描述中写清楚问题、行为变化、验证命令和已知限制。不要在 Pull Request 中粘贴真实凭据、私有仓库地址或用户项目内容。
