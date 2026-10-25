# 技能库

状态：提案（2026-10-24）。

本文件只规定技能的存放、导入和应用。它取代下面三条现行规则：

- `docs/SPEC.md` 第 3 节第 3 条：用 namespace 区分同名技能，裸名称可以共存。
- `docs/specs/architecture.md`：裸 skill name 不能作为唯一键；技能包放在 `~/.perch/skills/packages/<uuid>`。
- 同文：应用到目标时，软链只能指向 `~/.perch/versions/<contentHash>`。

## 库

技能库是用户主目录下的一个目录。每个技能是该目录的一个直接子项，要么是文件夹，要么是单个文件。子项名字就是技能名。

扫描技能库就是读这个目录。默认目录是 `~/.agents/skills`。库只有这一处。`~/.codex/skills`、`~/.claude/skills` 以及项目中的技能目录都是应用目标，不是第二套库。

技能来源区保存来源。GitHub 仓库和本地目录各占一个来源目录。自己新建的技能也是来源，固定放在 `~/.perch/sources/custom/`。文件只存在这里。

新建技能时，在 `custom` 目录写下该技能，并在技能库放一条同名软链。库里不另存一份实体。分类若要设置，仍写在 `~/.perch/skill-categories.json`，两个目录都不因此增加分类层。

```text
~/.perch/sources/custom/
  stc/
    SKILL.md

~/.agents/skills/
  stc -> /Users/brian/.perch/sources/custom/stc
```

## 技能源

技能源是库外的一份目录，都在 `~/.perch/sources/` 下。`custom` 是其中固定的一个目录。配置 GitHub 来源时，仓库按来源地址另占一个目录，保留仓库自己的目录结构。配置来源这一步不改技能库。

来源里可以有多个技能，也可以有未选中的其他文件。GitHub 来源中，只有被加入技能库的技能才会在库中出现。`custom` 目录里的技能在新建时就进入技能库。

## 导入

加入技能库时，从一个技能源中选出若干技能，指定分类，并选定一种存放方式。同一次导入只用一种方式。库中新增的每一项都是技能库的直接子项，名字是技能名。不用来源名或分类名再套一层目录。

- 软链：库中的子项指向技能源检出里的该技能目录。技能源更新后，库中看到的内容跟着变。选择软链表示要同步。来源里的该技能消失，或技能源被删除后，这条软链断开。
- 复制：把该技能目录里的文件复制到 `~/.perch/sources/custom/<技能名>/`，并在技能库放一条同名软链。技能源之后的变化不改变这份内容。选择复制表示不要同步。删除技能源不影响已复制的技能。本地导入同样只把文件放进 `custom`，不另建 `local-imports`，也不在技能库里留实体目录。

重名的项不进入库。同一次导入里名字不冲突的其他技能仍按所选方式进入。导入不写入项目或其他宿主目录。

分类是归组标签，不出现在技能库目录里。一个技能至多一个分类，可以在导入时指定，也可以之后修改。一次导入可以把选出的技能归入同一个分类。分类记在 `~/.perch/skill-categories.json`，以技能名为键，不另发技能 ID。

下面在已有自己新建的技能 `stc` 的基础上，配置 `github.com/example/skills`，再把其中 10 个技能以软链加入库，并归入同一分类。库里只多出 10 条软链，`stc` 仍指向 `custom` 目录：

```text
~/.perch/sources/custom/
  stc/
    SKILL.md

~/.perch/sources/github.com/example/skills/
  skill-01/
    SKILL.md
  skill-02/
    SKILL.md
  skill-03/
    SKILL.md
  skill-04/
    SKILL.md
  skill-05/
    SKILL.md
  skill-06/
    SKILL.md
  skill-07/
    SKILL.md
  skill-08/
    SKILL.md
  skill-09/
    SKILL.md
  skill-10/
    SKILL.md
  README.md

~/.agents/skills/
  stc -> /Users/brian/.perch/sources/custom/stc
  skill-01 -> /Users/brian/.perch/sources/github.com/example/skills/skill-01
  skill-02 -> /Users/brian/.perch/sources/github.com/example/skills/skill-02
  skill-03 -> /Users/brian/.perch/sources/github.com/example/skills/skill-03
  skill-04 -> /Users/brian/.perch/sources/github.com/example/skills/skill-04
  skill-05 -> /Users/brian/.perch/sources/github.com/example/skills/skill-05
  skill-06 -> /Users/brian/.perch/sources/github.com/example/skills/skill-06
  skill-07 -> /Users/brian/.perch/sources/github.com/example/skills/skill-07
  skill-08 -> /Users/brian/.perch/sources/github.com/example/skills/skill-08
  skill-09 -> /Users/brian/.perch/sources/github.com/example/skills/skill-09
  skill-10 -> /Users/brian/.perch/sources/github.com/example/skills/skill-10

~/.perch/skill-categories.json
  skill-01 … skill-10 均记为所选分类
  stc 无分类则不出现
```

若这次导入选择复制，技能源目录同上。复制出来的文件放进 `custom`，库中那 10 项仍是软链，只是不再指向技能源：

```text
~/.perch/sources/custom/
  stc/
    SKILL.md
  skill-01/
    SKILL.md
  skill-02/
    SKILL.md
  skill-03/
    SKILL.md
  skill-04/
    SKILL.md
  skill-05/
    SKILL.md
  skill-06/
    SKILL.md
  skill-07/
    SKILL.md
  skill-08/
    SKILL.md
  skill-09/
    SKILL.md
  skill-10/
    SKILL.md

~/.agents/skills/
  stc -> /Users/brian/.perch/sources/custom/stc
  skill-01 -> /Users/brian/.perch/sources/custom/skill-01
  skill-02 -> /Users/brian/.perch/sources/custom/skill-02
  skill-03 -> /Users/brian/.perch/sources/custom/skill-03
  skill-04 -> /Users/brian/.perch/sources/custom/skill-04
  skill-05 -> /Users/brian/.perch/sources/custom/skill-05
  skill-06 -> /Users/brian/.perch/sources/custom/skill-06
  skill-07 -> /Users/brian/.perch/sources/custom/skill-07
  skill-08 -> /Users/brian/.perch/sources/custom/skill-08
  skill-09 -> /Users/brian/.perch/sources/custom/skill-09
  skill-10 -> /Users/brian/.perch/sources/custom/skill-10
```

技能源里的技能若不在仓库根目录，检出仍保持仓库原样。库里的软链指向该技能自己的目录，库的这一层仍然只有技能名。

## 应用

应用是单独动作。用户指定位置后，为选中的技能建立软链，指向库中的同名技能。

技能在库中，还不等于已经应用。取消应用只去掉目标位置的软链，不删除库中的技能。写入应用位置必须由用户明确执行。

## 名字

库内技能名唯一。新建或导入时名字已存在，则拒绝该项：不覆盖，也不换一套 ID 收下。

文件夹的技能名是文件夹名。单个文件的技能名是去掉扩展名后的文件名。同一个技能名不能同时存在文件夹和文件。

## 不做

- 不用 `personal/<slug>`、`source-…/<slug>`、`packages/<uuid>` 或内容哈希作为技能身份。
- 不因为来源不同而保留两个同名技能。
- 导入时不先复制进哈希版本包，再软链到版本包。
- 不在本文件中改变 MCP、插件、预设和规则片段。
