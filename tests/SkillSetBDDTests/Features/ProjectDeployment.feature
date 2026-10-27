# language: zh-CN

@bdd
功能: 项目能力部署审批
  作为项目负责人
  我希望先审阅不可变的部署计划
  以便只有本机人工批准后才能写入，并且计划生成后的新改动不会被静默覆盖

  背景:
    假设 使用当前仓库作为能力库存
    而且 本机状态写入隔离的临时目录

  场景: 未批准的部署计划不会写入项目
    假设 已登记项目 "demo"
    而且 草稿选择 Skill "workspace/stc"
    而且 目标 agent 为 "codex"
    当 生成部署计划
    那么 计划状态为 "待批准"
    当 在未批准时执行计划
    那么 操作失败，错误码为 "APPROVAL_REQUIRED"
    而且 项目路径 ".agents/skills/stc" 不存在
    而且 项目路径 "AGENTS.md" 不存在

  场景: 用户批准精确计划后写入项目
    假设 已登记项目 "demo"
    而且 草稿选择 Skill "workspace/stc"
    而且 目标 agent 为 "codex"
    当 生成部署计划
    而且 批准当前计划
    而且 执行部署计划
    那么 计划状态为 "已应用"
    而且 项目路径 ".agents/skills/stc/SKILL.md" 存在
    而且 项目文件 "AGENTS.md" 包含受管块
    而且 项目锁状态为 "valid"

  场景: 计划生成后项目被修改时拒绝覆盖
    假设 已登记项目 "demo"
    而且 项目文件 "AGENTS.md" 内容为 "用户原始规则"
    而且 草稿选择 Skill "workspace/stc"
    而且 目标 agent 为 "codex"
    当 生成部署计划
    而且 批准当前计划
    而且 修改项目文件 "AGENTS.md" 为 "计划后新编辑"
    当 在已批准时执行计划
    那么 操作失败，错误码为 "PLAN_STALE"
    而且 项目文件 "AGENTS.md" 内容为 "计划后新编辑"
    而且 项目路径 ".agents/skills/stc" 不存在
