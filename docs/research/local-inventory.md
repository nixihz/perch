# 本地库存与迁移记录

日期：2026-10-21。起始 HEAD：`92b67baf4333a710b74e329c3294eac521fc0007`。开始时工作区干净。

## 原状

`skills/` 是 11 个自维护包，`.agents/skills` 逐个链接，`.claude/skills` 复用该目录。没有应用、MCP、项目清单、预设、来源清单或 DESIGN.md。

`/opt/case/brian/skills` 是另一个 Git 工作区，HEAD 为 `4536bbd230ced702613fe651bd5c390720a852c7`，盘点时 dirty。因此 Git commit 只能说明来源基线，不能替代本轮文件内容 hash。

该目录 139 个顶层 skill 包中，115 个为实体目录、24 个为指向 Magpie Library 的软链。没有顶层断链；`ponytail-review` 内 5 个链接失效。完整路径和原因见 [导入清单](../../registry/local-import.json)。

本机 `~/.agents/skills` 本身链接到旧库；另有 `.codex/skills`、`.claude/skills` 和 Magpie Library 目录。只确认这些目录存在，没有读取或输出宿主凭据，也没有修改宿主配置。

## 本轮迁移

- 复制目标：`vendor/local-brian/<原目录名>/`。原目录与原软链保留，不移动、不删除。
- 复制了 916 个文件，共 13,502,512 字节，24 个顶层软链均变为仓库内实体内容。
- 不复制 `.git`、缓存、构建输出和系统噪声；拒绝敏感文件名、已知秘密模式、特殊文件、越界和超限内容。
- 5 条断链没有可读取内容，不猜测替代目标；对应条目标为 `blocked`。已存在的普通文件保留作为可审核库存，不构成可部署修订。
- 未向 `.agents/skills` 或 `.claude/skills` 增加 139 条入口，也未调整全局软链。
- `registry/catalog.json` 同时索引 11 个自维护与 139 个外部条目；namespace 分开，不按裸 name 覆盖。

## 同名不代表同版本

| 裸名称 | 目录比较 |
| --- | --- |
| humanizer-zh | 相同 |
| likec4-dsl | 相同 |
| mitmproxy-cli | 相同 |
| project-guide | 相同 |
| stc | 相同 |
| tokenhubctl | 排除 Git 忽略的按需运行时后相同 |

初步扫描曾把 `tokenhubctl` 判断为不同；复核后确认差异来自自维护目录内 `.gitignore` 排除的 `tokenhubctl/assets/` 按需运行时。它不进入可移植目录指纹，不能把本机下载缓存当源码版本。相同树仍保留两条来源记录，未来内容 store 可去重，但来源身份不能合并。

## 核验边界

当前 `catalog.py` 是一次性迁移辅助工具，不是正式部署核心：

- 能检查实体复制、文件 hash、可执行位、断链、循环、越界、已存在不同目标和复制期间内容变化。
- 元数据只抽取显示字段，标为 `not-schema-validated`；没有宣称全量 YAML/Agent Skills 合规。
- 秘密扫描采用有限正则，不能证明所有文件均无秘密。
- `snapshotted` 只表示内容快照，不表示脚本已运行、依赖已安装、许可可再发布或 skill 行为已评估。
- `verify` 无需旧库或 Magpie 路径，可在 clone 后仅凭当前仓库验证；不调用外部 skill 代码。

## 已发现的既有维护问题

上次简化 STC 后删除了旧 README、lint 脚本与评估文件，但根 README、结构检查和 CI 仍引用它们。本轮没有恢复已删除功能，而是让历史用例检查只作用于实际保留用例的版本，并删除过期命令/链接；当前引用检查仍保留。

## 重跑

```bash
python3 scripts/catalog.py inventory \
  --allow-linked-root /Users/brian/.config/magpie/library/skills \
  --output /tmp/skillset-import-plan.json

python3 scripts/catalog.py import \
  --allow-linked-root /Users/brian/.config/magpie/library/skills

python3 scripts/catalog.py verify
```

`import` 不覆盖已有不同目录；后续来源变化应走正式版本导入，不能把本辅助工具当强制同步器。若只需要核验，应运行 `verify`，不要在 CI 访问本机绝对来源路径。
