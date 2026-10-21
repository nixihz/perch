# BDD 场景与执行约定

状态：五个纵向切片已实现（2026-10-21）。当前覆盖项目部署审批、计划漂移、阻塞 Skill，来源预览的远端失败、固定 commit 和隔离不收录，MCP 配置的凭据拒绝与脱敏、环境变量名称校验和未知字段保留，Plugin 生命周期的风险确认、状态漂移和审批前零宿主进程调用，以及原生 UI 的键盘导航、搜索空态、权限失败说明、项目空态、MCP/Plugin 表单、计划 sheet 和双层审批取消。

## 1. 目标与边界

BDD 用产品行为描述高风险规则。项目部署与 Plugin 生命周期调用与 App、CLI、MCP 相同的 `SkillSetService`；来源预览调用共享的 `SourcePreviewService`。场景验证真实临时项目、Git checkout、计划状态、文件、锁、宿主命令调用日志和错误码，不复制核心实现，也不为测试增加产品分支。

项目部署功能文件是 `tests/SkillSetBDDTests/Features/ProjectDeployment.feature`，对应以下验收规则：

| 场景 | 验收映射 |
| --- | --- |
| 未批准的部署计划不会写入项目 | S5 的核心审批边界；MCP/CLI 协议层另测 |
| 用户批准精确计划后写入项目 | S5 的核心审批与写入链路 |
| 计划生成后项目被修改时拒绝覆盖 | TX-02、TX-05 |
| 阻塞 Skill 不能进入部署计划 | INV-02 |

来源预览功能文件是 `tests/SkillSetBDDTests/Features/SourcePreview.feature`，对应以下验收规则：

| 场景 | 验收映射 |
| --- | --- |
| 远端失败不会留下预览 | SRC-01 的失败边界；失败后不保存记录，也不残留隔离目录 |
| 预览固定到所选 commit | SRC-01、VER-02；生成记录绑定解析后的 commit，标签移动后已保存预览仍读取原内容 |
| 预览只写入隔离区而不收录 | SRC-01；预览保存到隔离数据，不改变 catalog、库存或项目目录 |

来源预览场景通过真实本地 bare Git 仓库和 Git `insteadOf` 传输映射执行完整 clone、fetch、checkout 链路，不替换被测服务。远端失败也走真实 Git 命令，而不是注入异常。

MCP 配置功能文件是 `tests/SkillSetBDDTests/Features/MCPConfiguration.feature`，对应以下验收规则：

| 场景 | 验收映射 |
| --- | --- |
| 带凭据的 MCP URL 不生成配置计划 | MCP-02、MCP-05；草稿错误发生在计划创建前，项目配置不变 |
| 凭据值不能伪装成环境变量名称 | MCP-02、MCP-05；拒绝在 env 名称位置携带值，错误信息不回显凭据 |
| 非法环境变量名称不生成配置计划 | MCP-02、MCP-05；env 只接受变量名，不接收值或空格 |
| 批准后写入 MCP 配置并保留未知字段 | MCP-03、MCP-05；批准后写入受管 server，保留外部顶层键和已有 server 的未知字段 |

MCP 场景通过 `SkillSetService.makeMCPConfigPlan`、计划存储和文件事务执行，使用项目级 Claude `.mcp.json` 临时 fixture，不读取或写入真实用户宿主配置。

Plugin 生命周期功能文件是 `tests/SkillSetBDDTests/Features/PluginLifecycle.feature`，对应以下验收规则：

| 场景 | 验收映射 |
| --- | --- |
| 未确认可执行组件风险时不生成安装计划 | PLG-03；风险确认在计划创建前完成，失败后零计划、零宿主进程调用 |
| 已批准的计划在 Plugin 状态变化后拒绝执行 | PLG-02；重新读取安装事实发现状态漂移，计划不标记已应用，零宿主进程和零 operation |
| 审批前不调用宿主进程 | PLG-01；待批准计划不能执行，宿主命令调用与 operation 都为零 |

Plugin 场景使用隔离的临时 `HOME`、Claude Plugin 缓存、安装索引和启用设置，并把宿主 CLI 指向临时可执行脚本。脚本只在被调用时追加参数到日志；场景据此验证真实 `Process` 边界没有被触发，不通过 mock 调用次数替代产品结果。

原生 UI 功能文件是 `tests/SkillSetBDDTests/Features/NativeUI.feature`，对应以下验收规则：

| 场景 | 验收映射 |
| --- | --- |
| 侧栏和快捷键可用键盘操作 | UI-01；方向键更新 source-list 选中项，`⌘3` 切换详情，搜索字段暴露原生提示文本 |
| 没有项目时原生界面给出下一步 | UI-02；空态说明原因，并提供可用的登记入口 |
| 原生计划 sheet 展示完整审批信息 | UI-01；sheet 显示目标路径、完整 digest、状态、安全门、第一项变更和审批按钮 |
| 按 Escape 取消计划不改变项目和计划状态 | UI-01；sheet 关闭后焦点回到侧栏，计划仍待批准且 digest 不变，项目目录不变 |
| 搜索无结果时不再显示旧 Skill 详情 | UI-02；搜索筛选后清除失效选择，显示零匹配和清空搜索的下一步 |
| 项目权限失败时解释状态和恢复入口 | UI-02；真实不可读目录触发观察失败，显示具体原因和重新选择项目的恢复提示，不生成计划 |
| MCP 表单拒绝凭据值且不生成计划 | MCP-02、UI-02；原生表单拒绝 env 名称位置的值，校验文本不回显凭据，零配置计划 |
| Plugin 风险确认门解锁安装计划 | PLG-03、UI-01；风险未确认时安装按钮禁用，勾选后可生成计划，宿主进程仍为零调用 |
| 批准部署前需要第二次确认 | UI-01；首次批准只打开确认对话框，显示路径、变更数量和两个选择；取消后计划仍待批准且项目不变 |

原生 UI 场景启动隔离的 `SkillSetDesktop` 子进程，通过 macOS accessibility tree 查找窗口、source-list、表单字段、复选框、sheet、静态文本和按钮，并发送文本、方向键、`⌘3` 与 Escape。Plugin 场景在隔离 `HOME` 中创建真实缓存 manifest，并把宿主 CLI 指向只记录调用的临时脚本。场景同时回读隔离 Application Support 中的计划记录和真实项目目录。测试只使用临时 `HOME`、`CFFIXED_USER_HOME`、`CODEX_HOME` 和应用数据，不读取或改写真实宿主状态。

所有场景只使用隔离的临时 Application Support、项目目录和宿主 HOME。测试不得读取或写入真实的 Codex、Claude Code、Keychain、全局 Skill 或宿主配置。

## 2. 文件结构

```text
tests/SkillSetBDDTests/
  Features/                     中文 Gherkin，CucumberSwift 只递归读取此目录
  BDDWorld.swift                场景状态、临时工作区与可观察断言
  NativeUIHarness.swift         原生子进程、Accessibility 与键盘操作
  ProjectDeploymentSteps.swift  唯一的 StepImplementation 与步骤定义
```

SwiftPM 会把所有测试目标链接进同一测试包，因此整个 package 只能有一个 `extension Cucumber: StepImplementation`。新增功能文件时复用同一入口，并在 `setupSteps()` 中注册步骤。

## 3. 写作规则

- 使用 `# language: zh-CN`，功能、场景和步骤描述业务结果，不描述按钮坐标或内部函数名。
- `假设 / 当 / 那么` 保持因果顺序；一个场景验证一条可观察规则，失败路径单独成场景。
- 步骤只通过共享服务、真实临时文件和公开只读状态断言结果；禁止同义反复断言，禁止复制实现公式生成期望值。
- 文件名、Skill ID、错误码和受管块 ID 保持字面值；中文说明使用项目现行术语。
- Gherkin 行内 `#` 会被解析为注释，即使位于引号内。需要多行或含 `#` 的正文时使用 DocString，不要拼进普通步骤。
- 场景数据不得包含真实凭据、用户路径或个人配置快照。

## 4. 运行方式

```bash
task bdd
# 等价于
CUCUMBER_TAGS=bdd CUCUMBER_VERBOSE=1 swift test
```

执行限制：

- 不要使用 `swift test --parallel`。Cucumber 场景不在 `swift test list` 中，并行执行会漏跑且可能仍通过。
- 不要用 `swift test --filter <场景名>` 选择场景。该命令不会运行动态生成的场景，可能报告零测试通过。
- 使用标签筛选：在功能或场景前添加 `@bdd`，再设置 `CUCUMBER_TAGS=bdd`。
- 常规 `swift test` 同时执行 Swift Testing、XCTest 布局回归与 Cucumber 场景，CI 沿用该入口。
- 原生 UI 场景需要交互式 macOS 桌面会话与 Accessibility 权限。`CI=true` 或测试进程未获授权时，场景以 `XCTSkip` 明确跳过；本机运行 `task bdd` 时仍会执行这些场景。

## 5. 当前边界

原生 UI 已覆盖导航、搜索与项目空态、权限失败、MCP/Plugin 表单和双层审批取消。它不替代文件事务、Plugin 状态漂移和宿主命令边界的服务级场景，也不证明真实宿主已加载配置；这些边界继续由现有服务级 BDD 单独验证。
