# language: zh-CN

@bdd
功能: MCP 配置审批与兼容
  作为本机能力维护者
  我希望危险的 MCP 草稿在生成计划前被拒绝
  以便批准后的配置写入只改变受管部分并保留外部字段

  背景:
    假设 使用当前仓库作为能力库存
    而且 本机状态写入隔离的临时目录

  场景: 带凭据的 MCP URL 不生成配置计划
    假设 已登记项目 "demo"
    当 尝试以 URL "https://user:token@example.test/mcp" 生成 MCP 配置计划
    那么 操作失败，错误码为 "MCP_CONFIG_DRAFT_INVALID"
    而且 已保存的 MCP 配置计划为 0 个
    而且 项目路径 ".mcp.json" 不存在

  场景: 凭据值不能伪装成环境变量名称
    假设 已登记项目 "demo"
    当 尝试以环境变量名称 "TOKEN=super-secret" 生成 MCP 配置计划
    那么 操作失败，错误码为 "MCP_CONFIG_DRAFT_INVALID"
    而且 错误信息不包含 "super-secret"
    而且 已保存的 MCP 配置计划为 0 个
    而且 项目路径 ".mcp.json" 不存在

  场景: 非法环境变量名称不生成配置计划
    假设 已登记项目 "demo"
    当 尝试以环境变量名称 "TOKEN SECRET" 生成 MCP 配置计划
    那么 操作失败，错误码为 "MCP_CONFIG_DRAFT_INVALID"
    而且 已保存的 MCP 配置计划为 0 个
    而且 项目路径 ".mcp.json" 不存在

  场景: 批准后写入 MCP 配置并保留未知字段
    假设 已登记项目 "demo"
    而且 Claude 项目 MCP 配置包含未知字段
    当 生成项目 MCP 配置计划，名称为 "skillset"，使用环境变量 "SKILLSET_TOKEN"
    那么 计划状态为 "待批准"
    当 批准当前计划
    而且 执行部署计划
    那么 计划状态为 "已应用"
    而且 已保存的 MCP 配置计划为 1 个
    而且 MCP Server "skillset" 存在
    而且 MCP 配置保留外部未知字段
    而且 MCP Server "skillset" 的环境变量 "SKILLSET_TOKEN" 使用引用
