# language: zh-CN

@bdd @configurationexperience
功能: 同一项目按 AI 工具独立配置
  作为同时使用 Codex 与 Claude Code 的开发者
  我希望分别选择它们需要的能力
  以便调整其中一个工具时保留另一个工具的配置

  背景:
    假设 使用当前仓库作为能力库存
    而且 本机状态写入隔离的临时目录
    而且 已登记项目 "independent-harness"
    而且 宿主 "codex" 单独选择技能 "workspace/stc"
    而且 宿主 "claude-code" 单独选择技能 "workspace/humanizer-zh"

  场景: 两个 AI 工具只收到各自选择的技能
    当 生成独立宿主部署计划
    那么 项目路径 ".agents/skills/stc" 不存在
    而且 项目路径 ".claude/skills/humanizer-zh" 不存在
    当 批准当前计划
    而且 执行部署计划
    那么 项目路径 ".agents/skills/stc/SKILL.md" 存在
    而且 项目路径 ".claude/skills/humanizer-zh/SKILL.md" 存在
    而且 项目路径 ".agents/skills/humanizer-zh" 不存在
    而且 项目路径 ".claude/skills/stc" 不存在

  场景: 清空 Claude 的选择后 Codex 内容保持不变
    当 生成独立宿主部署计划
    而且 批准当前计划
    而且 执行部署计划
    而且 记录项目文件 ".agents/skills/stc/SKILL.md" 的内容
    而且 清空宿主 "claude-code" 的技能选择
    而且 生成独立宿主部署计划
    那么 项目路径 ".claude/skills/humanizer-zh/SKILL.md" 存在
    当 批准当前计划
    而且 执行部署计划
    那么 项目路径 ".claude/skills/humanizer-zh" 不存在
    而且 项目文件 ".agents/skills/stc/SKILL.md" 保持已记录的内容

  场景: 预览 Claude 不会连带部署 Codex 的草稿
    当 仅预览宿主 "claude-code" 的变更
    而且 批准当前计划
    而且 执行部署计划
    那么 项目路径 ".claude/skills/humanizer-zh/SKILL.md" 存在
    而且 项目路径 ".agents/skills/stc" 不存在
    当 仅预览宿主 "codex" 的变更
    而且 批准当前计划
    而且 执行部署计划
    那么 项目路径 ".agents/skills/stc/SKILL.md" 存在
    而且 项目路径 ".claude/skills/humanizer-zh/SKILL.md" 存在
