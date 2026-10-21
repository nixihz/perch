# language: zh-CN

@bdd
功能: Plugin 生命周期审批与漂移防护
  作为本机能力维护者
  我希望危险动作先经过风险确认和精确计划审批
  以便状态变化后不会执行旧命令，审批前也不会启动宿主进程

  背景:
    假设 使用当前仓库作为能力库存
    而且 本机状态写入隔离的临时目录

  场景: 未确认可执行组件风险时不生成安装计划
    假设 本机只有含 hook 的 Claude Plugin 缓存 "risky@demo"
    当 尝试生成 Plugin "risky@demo" 的 "安装" 计划
    那么 操作失败，错误码为 "PLUGIN_RISK_APPROVAL_REQUIRED"
    而且 Plugin 生命周期计划为 0 个
    而且 宿主进程调用为 0 次

  场景: 已批准的计划在 Plugin 状态变化后拒绝执行
    假设 本机已安装并启用 Claude Plugin "sample@demo"
    当 生成 Plugin "sample@demo" 的 "停用" 计划
    而且 批准当前计划
    而且 在计划后停用 Plugin "sample@demo"
    当 在已批准时执行计划
    那么 操作失败，错误码为 "PLUGIN_STATE_STALE"
    而且 Plugin 生命周期计划为 1 个
    而且 计划状态为 "已批准"
    而且 Plugin 操作记录为 0 个
    而且 宿主进程调用为 0 次

  场景: 审批前不调用宿主进程
    假设 本机已安装并停用 Claude Plugin "sample@demo"
    当 生成 Plugin "sample@demo" 的 "启用" 计划
    那么 计划状态为 "待批准"
    而且 Plugin 生命周期计划为 1 个
    当 在未批准时执行计划
    那么 操作失败，错误码为 "APPROVAL_REQUIRED"
    而且 Plugin 操作记录为 0 个
    而且 宿主进程调用为 0 次
