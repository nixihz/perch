# 验收与实施拆分

当前完成 Alpha 工作流切片：M0 研究和原型已完成，M1 的项目写入/项目锁/离线对象/plan/apply/rollback 与 M2 来源预览、M3 的 MCP 配置、Plugin 盘点与审批门控生命周期、legacy stdio MCP 已实现。跨进程锁、marketplace 浏览和真实宿主加载验证仍按后续里程碑验收。

## 1. 里程碑

| 阶段 | 交付 | 完成门槛 |
| --- | --- | --- |
| M0 · 研究与原生原型 | 库存快照、来源研究、SPEC、DESIGN、SwiftUI macOS 原型 | 已完成：内容可核验、没有自动启用外部快照、风险可见 |
| M1 · 核心与 CLI | project inspect、plan/apply/rollback、CLI | 部分完成：文件事务、项目锁、离线对象和 CLI 可用；正式 Source Store、跨进程锁未完成 |
| M2 · 正式本地应用 | 注册项目、来源预览、库、预设、规则、差异审批、审计 | 部分完成：项目、GitHub 预览、MCP 配置、Plugin 盘点与生命周期计划/执行可用；目录/UI 全量打磨未完成 |
| M3 · MCP 与双宿主 | stdio 服务、Codex/Claude 配置向导、有效状态验证 | 部分完成：legacy stdio MCP、双宿主项目写入和 MCP 配置计划可用；真实宿主加载矩阵未完成 |
| M4 · 更新与发布 | fork/三方冲突、预设升级、批量计划、release | 不丢本地修改、部分成功可解释、公开导出脱敏/许可核查 |

不承诺开发天数；先以 M1 的真实文件事务验证技术风险，再估 M2/M3 工作量。

## 2. P0 行为场景

| ID | 给定 / 操作 | 必须观察到的结果 |
| --- | --- | --- |
| INV-01 | 来源是目录软链和文件软链，复制后删除原始目标 | 快照仍能读；无残余链接；可执行位保持 |
| INV-02 | 遇断链、循环或越界链接 | 报具体路径，条目 blocked，不生成可部署修订 |
| INV-03 | 二次导入已有本地修改的目标 | 拒绝覆盖，原修改保留 |
| INV-04 | 盘点后来源改变 | 复制拒绝或建立全新快照，不能用旧 manifest 宣称成功 |
| INV-05 | 仅 mtime 改变 / 正文改变 / 可执行位改变 | mtime 不改修订；后两者改变修订 |
| INV-06 | 源码旁有 Git 忽略的下载运行时 | 不进入可移植指纹；干净 clone 核验不依赖它 |
| SRC-01 | 贴 Matt 根链接 | 展示固定 commit、分类、promoted 与排除项、许可，不安装 |
| SRC-02 | branch 含 `/`、子路径编码、SSH 私仓 | 正确解析或明确要求消歧；凭据不进锁/日志 |
| SRC-03 | archive traversal、zip bomb、SSRF 重定向 | 拒绝；没有目标文件、没有关闭保护 |
| VER-01 | 同名两个来源且树相同/不同 | 两条来源身份共存；部署名称冲突显式处理 |
| VER-02 | tag 移动、branch 更新 | 原锁复现旧内容；检查更新只生成新候选 |
| VER-03 | 旧库删除且断网 | 已有完整对象的锁可恢复；缺对象明确失败 |
| PRJ-01 | 两个路径指向同一项目 / 独立 worktree | 前者去重；后者有独立部署状态 |
| PRJ-02 | 取消项目选择但全局仍有 skill | desired 更新；界面明确 inherited，不能显示彻底禁用 |
| PRE-01 | 应用预设后预设升级 | 原项目锁不漂移，升级必须另行预览 |
| PRE-02 | 合并与替换受管集合 | 新增/移除数量准确；非受管文件不删除 |
| RULE-01 | 文件已有手写内容 | 只更新单一匹配受管块，块外字节不变 |
| RULE-02 | 受管标记缺尾/重复/被手改 | 冲突阻塞；没有默认全量重写 |
| RULE-03 | Codex override / Claude 有 CLAUDE 链 | 显示有效链和遮蔽，不虚构模板生效 |
| TX-01 | 新路径已存在未受管文件/目录软链 | 拒绝覆盖；原路径及源库不变 |
| TX-02 | plan 后改文件或换链接 | `PLAN_STALE`/路径错误，零隐含覆盖 |
| TX-03 | CLI 与 MCP 同时 apply | 一个持锁，另一个明确冲突/等待，不交错写 |
| TX-04 | 在第 N 次 rename 后杀进程 | journal 可重建状态；恢复或人工干预明确列出 |
| TX-05 | apply 后用户编辑再 rollback | 不覆盖用户新编辑，显示冲突 |
| PRJ-03 | 项目已有同内容技能或只有共享锁、没有本机收据 | 显示已有归属，取消选择不删除；同路径不同内容阻塞 |
| PRJ-04 | 取消技能或某个宿主选择 | 只移除本机受管且未漂移的技能与规则块；其他宿主及相邻外部内容保留；删除可撤销 |
| RULE-04 | 块外新增正文 / 块内手改 / 无归属同标记块 | 分别保留块外编辑、阻塞漂移、保留或报冲突；空文件恢复后仍存在 |
| TX-06 | 撤销遇到目标漂移或备份损坏 | 预检阶段拒绝，不先恢复项目锁；已恢复步骤逐步持久化 |
| TX-07 | 移除或 rollback 的临时 rename 期间中断 | 从 journal 与临时路径恢复；重复恢复没有额外变更 |
| MCP-01 | AI 自传 confirmed 或重放/过期审批 | 核心拒绝，无文件变更 |
| MCP-02 | 非法参数、未知字段、越权项目 | 稳定错误、脱敏结果，无任意文件读取 |
| MCP-03 | 用户批准精确计划后调用 | 仅执行同一 digest/路径/修订，重复 key 返回原 operation |
| MCP-04 | legacy/modern 客户端分别连接 | 只宣称实际覆盖的协议与版本；stderr 日志不污染 stdout |
| UI-01 | macOS 原生窗口、键盘与 reduced-motion | source-list、表单、sheet 操作可达，焦点正确，高频操作无装饰动画；不以浏览器响应式页面代替桌面验证 |
| UI-02 | 空库、无搜索结果、远端失败、权限失败 | 解释状态和下一步，不显示假成功 |
| MCP-05 | 打开 MCP 配置草稿并填写 command、args、scope、env 名称 | 结构化校验即时显示；凭据值、带认证 URL 和带空格环境变量名被拒绝；取消不改变观察状态；批准后 round-trip 保留外部内容 |
| PLG-01 | 对已发现 Plugin 生成 enable/disable/install/update/uninstall 计划 | 计划绑定 host、plugin id、scope、CLI realpath、固定 argv 和 before digest；未审批时没有任何宿主进程调用 |
| PLG-02 | 计划后插件 enabled、manifest 或 scope 变化 | apply 返回 `PLUGIN_STATE_STALE`，零宿主命令；旧计划不能继续使用 |
| PLG-03 | 含 hooks/commands/MCP 的安装或更新 | 本机 UI/CLI 未显式确认风险时拒绝生成计划；MCP 不能代确认；批准后仍不自动加 `-y` |
| PLG-04 | 宿主命令成功、失败、超时或启动前失败 | 分别记录 applied / verification-pending / failed / uncertain-interrupted；不把外部命令伪装成可通用回滚的文件事务 |
| PLG-05 | 查看含 hooks、command source、archive 或未知 Codex schema 的 Plugin | 风险常驻可见，默认阻塞；不能从 Claude manifest 推断 Codex 支持，也不能执行插件代码 |
| PLG-06 | 同一 plugin id 与 scope 有两个缓存版本，分别不传和传入 `manifestDigest` | 不传时返回 `PLUGIN_VERSION_AMBIGUOUS`；传入后计划与 operation 前后 observation 都绑定所选 manifest，不按目录顺序选择 |

## 3. 测试策略

单元测试用真实临时目录、小包 fixture 和错误注入，断言输出文件/内容/权限/状态。禁止“常量等于常量”、复制实现计算期望值、仅检查函数被调用等同义反复测试。

集成测试至少含：

- 本地 bare Git 源、移动 branch/tag、路径含空格/中文、含 `/` 的 ref、嵌套分类与相同 name。
- Codex/Claude fixture 配置，保留未知字段、注释、外部规则和插件来源。
- 两进程竞争、journal 每步中断、磁盘/权限错误、过期/重放审批。
- UI 通过真实核心操作临时项目；原型测试不能代替正式文件行为测试。
- 独立人工真实宿主会话验证，不用 mock 客户端宣称宿主兼容。

不在 CI 连接 Brian 的真实项目、设备、集群或全局配置。真实宿主测试单独授权，记录版本与截图/日志。

## 4. 当前 Alpha 边界与演示路径

| 可演示 | 不代表 |
| --- | --- |
| 原生 `.app` 读取本仓 150 条真实目录记录、搜索/筛选/查看 hash | 150 个 skill 均通过安全和许可审核 |
| 登记临时项目、保存草稿、审阅 plan、批准后写 `.agents/skills` 与 `AGENTS.md` | 已修改 `.claude`、宿主 MCP 配置或确认宿主会话加载 |
| 粘贴 GitHub 仓库根、可选 ref、隔离 clone、固定 commit 并按实际文件夹展示技能 | 预览即自动加入技能库、vendor 或项目，或已自动启用 |
| 原生来源页逐项审阅并导入本机技能库，保留完整文件、许可和来源证据；删除预览后仍可生成项目部署计划 | 自动更新来源、覆盖已有同名技能、导入即启用，或 CLI/MCP 已提供导入工具 |
| 规则片段组合与受管块回读 | 已实现 Claude `CLAUDE.md` 加载链 |
| CLI 和 MCP 查询、预览、生成计划、审批后 apply | MCP 能自行批准、modern 协议兼容或跨进程锁已具备 |
| MCP 配置真实扫描与受管写入计划；Plugin 缓存、安装索引、组件与风险盘点；在本机已发现问题插件上生成生命周期计划 | MCP 进程已健康运行；marketplace 已浏览/收录，或当前宿主会话已加载 Plugin |

推荐演示：启动 `./script/build_and_run.sh --verify` → 在一个临时目录登记项目 → 载入“个人基线” → 打开 plan sheet → 核对 digest 与路径 → 二次确认写入 → 检查 `.agents/skills`、`.claude/skills`、`AGENTS.md`、`CLAUDE.md`，确认项目没有管理器专用文件，再核对应用数据目录中的项目锁。随后到来源页粘贴 Matt 链接并固定 ref，确认候选未进入项目；在 Skills 检查 `ponytail-review` 阻塞；在 MCP 页面用临时 scope 生成配置计划；在 Plugins 页面核对真实缓存、安装索引与 hooks 风险，并为本机已发现插件生成生命周期计划，核对命令与风险后取消。真实宿主命令只在明确授权的单独验收中执行。

CLI 演示应使用 `--state <临时目录>`，完成后执行 `skillset operations get` 和 `skillset rollback` 验证 journal 与恢复。应用本身不启动 HTTP server。

## 5. DoD

每个正式功能交付须同时满足：

- 对应 SPEC/错误码/界面状态同步；未完成项有明确标记。
- 行为测试覆盖正常与关键失败路径；没有秘密/本机数据进入测试快照。
- 涉及 UI 有 DESIGN 对照、macOS accessibility tree / 截图与键盘验证；移动端不作为本地桌面产品验收目标。
- 涉及宿主/MCP 有实际版本兼容证据；不能仅通过构建判定可用。
- 读取/写入边界、备份、回滚、日志脱敏符合架构约束。
- README/任务入口可用，CI 从干净 clone 运行。

已知未完成项必须继续在 SPEC 和 README 中可见，不能因页面存在就标为完成。
