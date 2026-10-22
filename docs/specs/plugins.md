# Plugin 管理规格

状态：来源管理、本机插件扫描入库、只读 inventory 和审批门控生命周期已实现（2026-10-22）；marketplace 浏览、来源包直接安装、依赖图求解和跨宿主统一 enable/update 仍未实现。

## 1. 为什么单独管理 Plugin

Plugin 不是一个更大的 Skill 文件夹。它可能同时贡献 skills、MCP servers、commands、agents、hooks、LSP 或用户配置，且由宿主 marketplace、Git、目录、archive、npm 或 command source 装载。安装一个 plugin 的副作用范围比安装单个 skill 大，必须在 UI 中展开清楚。

Alpha 的「插件来源」页面管理仓库、本地目录和扫描收录包；全局配置与项目页按需打开插件配置面板。扫描读取项目 `.claude-plugin` / `.codex-plugin`、Claude 与 Codex 插件缓存、Claude `installed_plugins.json`、Codex `config.toml` 和 manifest。盘点本身不执行 hooks、commands、市场脚本或安装器。生命周期由本应用生成不可变计划，经本机 UI 或 CLI 人工批准后，只调用宿主公开 CLI；AI 通过 MCP 可以生成计划，但不能批准，也不能为高风险安装/更新作风险确认。

### 来源库与本机扫描

`PluginSourceLibrary` 将来源保存在 `~/.perch/plugins/sources/<UUID>/`。仓库来源复用隔离 Git 预览，记录固定提交；本地来源复制完整目录并计算完整包指纹，包含 hooks 等附属资源，不依赖是否存在 SKILL.md。来源编辑先准备新快照，成功后移除旧记录；删除仅按 UUID 推导栖集内路径，不信任记录中的 `workspacePath`。来源盘点不叠加宿主安装状态。

本机扫描以完整包指纹合并同内容位置。入库将完整包独立复制到 `checkout`，`import.json` 保存扫描时间、指纹与安装证据，`preview.json` 发布来源记录。复制前校验各原始位置与 manifest，复制后再次核对完整包指纹；失败清理未发布目录。既有相同内容不重复收录，附属文件改变可单独收录。来源更新、删除和入库均不改原始安装、宿主配置或待审计划；批量操作允许部分完成，界面保留未完成选择。

配置入口绑定明确 host、scope 与已登记项目 ID，不从插件来源或当前其他页面选择推断目标。生命周期仍只支持本机可发现插件；来源库不自动注册市场、安装远程包或切换既有安装。Codex 仅开放用户范围，Claude Code 支持用户和项目范围。

## 2. 统一身份和版本

内部主键：

```text
(host, marketplaceID, pluginName, sourceRevision)
```

字段：

| 字段 | 规则 |
| --- | --- |
| `host` | `claude-code`、`codex` 或待适配宿主；不跨宿主复用 manifest |
| `marketplaceID` | marketplace 来源身份；同名 marketplace 不覆盖 |
| `pluginName` | 宿主显示名，不作为全局唯一键 |
| `sourceRevision` | 完整 Git commit、archive digest 或本地 snapshot digest |
| `declaredVersion` | manifest 显示版本；不强制当作 SemVer |
| `manifestDigest` | canonical manifest bytes 的 SHA-256 |
| `components` | skills / commands / agents / hooks / mcp / lsp / userConfig |
| `dependencies` | 名称、marketplace、版本范围和解析结果 |
| `trust` | unknown / reviewed / blocked / approved |

宿主 `version` 是兼容提示；项目锁必须同时写完整 revision、manifestDigest、组件清单和适配器版本。Marketplace 自动更新只能产生新候选，不得直接改变项目锁。

## 3. Manifest 与能力矩阵

Claude 官方 manifest 位于 `.claude-plugin/plugin.json`，根目录外还可放 skills、hooks、MCP 和其他组件。依赖支持裸名、`name@marketplace` 和带 SemVer 范围的对象；范围不受约束时会跟随 marketplace 最新版本，可能导致工具重命名或插件断裂。

Codex 当前公开 CLI/help 和文档不足以确认完整 manifest schema、依赖、hooks/MCP 组合与版本更新语义。因此：

- 不把 Claude 字段复制成 Codex schema；未知字段保留为 `unknown`，不自动转义。
- Codex marketplace 只能先登记来源、版本和宿主能力，生成“待核验”计划。
- 只有真实目标版本的 fixture validate / install / remove 回归通过，才可把能力标为支持。

## 4. 解析和安全

1. 用户选择 marketplace 或本地来源；管理器下载/读取到隔离目录。
2. 校验 manifest schema、路径越界、大小/文件数、Unicode/大小写碰撞和重复组件。
3. 展开完整 inventory：贡献的 skill、MCP、hook、command、agent、依赖和启动命令。
4. 构建依赖图，报告 cycle、版本范围无解、同名遮蔽和加载顺序。
5. 对 hooks、command source、archive helper、npm postinstall、`.mcpb`/`.dxt` 二进制包默认阻塞；用户必须在可信 UI 逐项批准。
6. 只产生 install/enable/update/uninstall plan，写入前显示目标 scope、备份、会话重启要求和不可逆副作用。

管理器不执行 plugin 内脚本，不自动登录私有 marketplace，不复制凭据，不把命令参数当作安全证明。卸载或禁用只撤销管理器自己声明且未漂移的配置；不能承诺撤销已经运行的 hook 副作用。

当前只读 inventory 的额外边界：

- 扫描深度最多 7 层、最多 2,000 个目录，不进入 `node_modules`、`.git`、`artifacts`、`dist`、`build`。
- 缓存目录软链不跟随；manifest 最大 2 MiB，解析失败作为 issue 返回。
- Claude 安装索引提供 scope、安装路径和 `gitCommitSha`；Codex 配置只用于插件 id 与 enabled 状态，不把 Claude 安装事实推断给 Codex。
- “缓存存在”不等于“已安装”；未在宿主安装索引/配置中出现时明确显示“仅缓存 · 未确认安装”。
- 声明版本、manifest digest 和宿主安装 revision 分开显示，不能用目录名或 SemVer 替代不可变 revision。

生命周期执行器的额外边界：

- 首版只管理本机已发现于缓存、安装索引或宿主配置中的插件；不提供 marketplace 搜索或凭据登录。
- 计划保存宿主、plugin id、scope、目标 `manifestDigest`、工作目录、CLI realpath、固定参数、before observation digest 和 staging 内的命令描述。
- 同一 id、同一 scope 存在多个缓存版本时，调用方必须从 `plugins_list` 选择具体 `manifestDigest`；缺失摘要返回 `PLUGIN_VERSION_AMBIGUOUS`，摘要不匹配返回 `PLUGIN_VERSION_NOT_FOUND`。界面、CLI 和 MCP 共用这一绑定。
- 所有命令直接通过 `Process` 启动，不经过 shell，不接受任意附加参数；不使用 `-y`，也不自动接受 marketplace command source。
- 执行前重新读取安装事实和目标 manifest digest。计划后出现 revision、enabled、scope 或 manifest 变化时返回 `PLUGIN_STATE_STALE`，不会执行旧命令。
- 安装和更新必须先在本机 UI/CLI 显式确认“宿主将解析并安装完整包”；MCP 计划工具固定不提供该确认。`enable`、`disable`、`uninstall` 不改写安装包，但仍需同一计划批准。
- 命令完成后回读插件事实，写入 `plugin-operation.json`。stdout/stderr 截断、脱敏并保存 hash；不记录凭据。
- 命令超时或进程中断只标记 `uncertain-interrupted`，不自动重放。文件事务的通用 rollback 不适用于外部宿主副作用；需要时生成相反动作计划。

## 5. 生命周期

```text
observed → fetched → parsed → reviewed → locked → planned → installed
                                  ↘ blocked
installed → update-planned → approved → updated
installed → disable-planned / uninstall-planned → approved
```

`disable`、`uninstall`、`update` 都要保留旧 revision、备份和组件差异。宿主提示需要重启或 reload 时，UI 显示“文件已变更，宿主验证待完成”，不伪称当前会话已经切换。

当前命令矩阵：

| 宿主 | install | update | enable | disable | uninstall |
| --- | --- | --- | --- | --- | --- |
| Claude Code | `plugin install` | `plugin update` | `plugin enable` | `plugin disable` | `plugin uninstall` |
| Codex | `plugin add` | 不支持 | 不支持 | 不支持 | `plugin remove` |

Claude scope 使用 `user`、`project`、`local`；`project` / `local` 必须绑定已登记项目的 realpath。Codex 当前公开 CLI 按用户配置管理，不推断 project scope。宿主 CLI 可通过 `SKILLSET_CLAUDE_BIN` / `SKILLSET_CODEX_BIN` 指定绝对路径。

operation 状态：

```text
applying
  ├─ applied
  ├─ applied-verification-pending
  ├─ applied-after-nonzero-exit
  ├─ failed
  ├─ failed-before-launch
  └─ uncertain-interrupted
```

只有已观察到目标状态，或命令成功退出但宿主刷新滞后时，计划才标记为已消费。命令非零退出且未观察到目标状态时保留待审状态，允许排查后重新生成计划；不会自动重复执行。

## 6. UI 验收

- 列表显示 host、marketplace/source、revision、declared version、state、risk。
- 详情页能看到 skills/MCP/commands/agents/hooks 的完整 inventory 和依赖图摘要。
- `含 hook`、`命令来源需人工审核`、`宿主能力未知`、`未锁定` 等风险常驻可见。
- 未审查或有无解依赖的 plugin 不能进入项目部署选择。
- 同名 plugin 来自不同 marketplace 时显示 namespace 和 precedence，禁止先到先得。
- Alpha 展示真实缓存与安装索引，并在隔离 fixture 中验证固定参数、审批、状态漂移和 operation 回读。真实宿主生命周期仍需单次明确授权和版本记录，测试不得修改 Brian 的真实插件配置。
- 多版本缓存 fixture 必须验证：无摘要时拒绝；指定摘要时只选择该 manifest；执行前后 observation 保持同一目标摘要。
