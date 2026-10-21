import Foundation
import Darwin
import SkillSetCore

enum UserFacingText {
    @MainActor
    static func localizedScope(_ value: String) -> String {
        let parts = value.components(separatedBy: " · ")
        return ([L10n.text(parts.first ?? "")] + parts.dropFirst()).joined(separator: " · ")
    }

    @MainActor
    static func localizedInheritance(_ value: String) -> String {
        let prefix = "项目观察失败："
        guard value.hasPrefix(prefix) else { return L10n.text(value) }
        let reason = LocalizedText(stringLiteral: String(value.dropFirst(prefix.count)))
        return L10n.tr("项目观察失败：\(reason)")
    }

    @MainActor
    static func planSummary(_ change: PlannedChange) -> String {
        let summary = change.unifiedDiff
        // 仅翻译管理器生成的说明，真实 diff、命令参数和技能内容不能被替换。
        if let match = summary.wholeMatch(of: /^复制 ([0-9]+) 个文件到 (.+)$/) {
            return L10n.tr("复制 \(match.1) 个文件到 \(match.2)")
        }
        for prefix in ["追加受管块 ", "替换受管块 ", "移除受管块 "] where summary.hasPrefix(prefix) {
            return L10n.text(String(prefix.dropLast())) + " " + summary.dropFirst(prefix.count)
        }
        for action in PluginLifecycleAction.allCases {
            let prefix = action.displayName + "："
            if summary.hasPrefix(prefix) {
                return L10n.text(action.displayName) + ": " + summary.dropFirst(prefix.count)
            }
        }
        if let match = summary.wholeMatch(of: /^(新增|更新) (Codex|Claude Code) (项目|用户) MCP Server (.+)$/) {
            return "\(L10n.text(String(match.1))) \(match.2) \(L10n.text(String(match.3))) MCP Server \(match.4)"
        }
        return L10n.text(summary)
    }

    // 异常的附带文本可能来自系统或外部进程，不能作为界面文案直接展示。
    static func error(_ error: Error) -> String {
        let code = (error as? any SkillSetCodedError)?.code
            ?? (error as? MCPConfigurationError)?.code
            ?? (error as? PluginInventoryError)?.code
            ?? (error as? ProjectLockError)?.code
        if let code {
            switch code {
            case "PLAN_EXPIRED", "PLAN_STALE", "PLAN_DIGEST_MISMATCH", "PLUGIN_STATE_STALE", "PROJECT_LOCK_STALE":
                return "计划已过期或目标已改变，请重新生成计划并审阅。"
            case "APPROVAL_REQUIRED":
                return "请先在本机审阅并批准这份计划。"
            case "PLAN_ALREADY_APPLIED":
                return "这份计划已经执行，无需再次执行。"
            case "PLAN_NO_CHANGES":
                return "没有需要写入的变更，请先调整项目草稿。"
            case "RECOVERY_REQUIRED", "ROLLBACK_CONFLICT", "PLUGIN_EXECUTION_UNCERTAIN":
                return "操作未能确认完成，请先检查操作记录和目标状态，不要重复执行。"
            case "PROJECT_PATH_MISSING", "PROJECT_PATH_NOT_DIRECTORY", "PROJECT_NOT_FOUND":
                return "找不到项目目录，请重新选择一个本机文件夹。"
            case "PROJECT_ALREADY_REGISTERED":
                return "这个项目已添加，请在项目列表中选择。"
            case "PROJECT_NAME_INVALID":
                return "项目名称格式不对，请修改名称后重试。"
            case "PROJECT_REGISTRY_CORRUPT", "PROJECT_DRAFT_CORRUPT", "PLAN_RECORD_CORRUPT":
                return "本机保存的记录无法读取，请检查应用数据目录或从备份恢复。"
            case "PROJECT_MANIFEST_CORRUPT", "PROJECT_LOCK_CORRUPT", "PROJECT_MANIFEST_INVALID":
                return "项目配置无法读取，请检查项目清单和锁定文件，必要时从备份恢复。"
            case "AGENT_UNSUPPORTED":
                return "暂不支持这个 AI 工具，请重新选择 Codex 或 Claude Code。"
            case "REPOSITORY_NOT_FOUND":
                return "找不到技能库目录，请检查技能库位置后重新打开应用。"
            case "SKILL_SOURCE_CHANGED", "SKILL_SOURCE_MISSING", "SKILL_NOT_FOUND":
                return "技能来源已改变或无法读取，请检查来源后重新选择技能。"
            case "SKILL_BLOCKED", "SKILL_ASSET_UNSAFE":
                return "技能未通过完整性检查，请先修复来源，再重新生成快照。"
            case "INSTRUCTION_NOT_FOUND":
                return "找不到规则片段，请在草稿中重新选择。"
            case "SELECTION_LIMIT_EXCEEDED":
                return "一次最多选择 200 个技能，请减少选择后重试。"
            case "SOURCE_INVALID_URL", "SOURCE_HOST_NOT_ALLOWED":
                return "请填写 HTTPS 格式的 GitHub 仓库链接。"
            case "SOURCE_INVALID_REF":
                return "分支或标签格式不对，请检查后重试，也可以留空使用默认分支。"
            case "SOURCE_CREDENTIALS_REJECTED":
                return "请移除链接中的用户名和密钥。私有仓库请先通过系统 Git 登录。"
            case "SOURCE_GIT_FAILED":
                return "仓库读取失败，请检查网络、访问权限和分支名称，再重新预览。"
            case "SOURCE_LIMIT_EXCEEDED":
                return "仓库超过预览大小限制，请换一个较小的仓库。"
            case "SOURCE_PREVIEW_CORRUPT":
                return "保存的来源预览无法读取，请重新预览仓库。"
            case "MCP_CONFIG_CONFLICT", "MCP_CONFIG_NOT_OWNED":
                return "已有同名 MCP 服务不属于本应用，请换一个名称，或先在原工具中处理。"
            case "MCP_CONFIG_CORRUPT", "MCP_CONFIG_ROOT_MISSING":
                return "MCP 配置无法读取，请检查配置文件和目录权限后重新扫描。"
            case "MCP_CONFIG_DRAFT_INVALID", "MCP_CONFIG_TARGET_UNSUPPORTED":
                return "MCP 配置不受支持，请检查连接方式、名称和作用范围后重试。"
            case "PLUGIN_RISK_APPROVAL_REQUIRED":
                return "请先核对插件的运行风险并勾选确认，再生成计划。"
            case "PLUGIN_HOST_CLI_MISSING", "PLUGIN_COMMAND_LAUNCH_FAILED":
                return "无法启动插件所属工具，请确认已安装并可在本机运行。"
            case "PLUGIN_COMMAND_FAILED":
                return "插件操作失败，请检查操作记录和插件状态后，再决定是否重试。"
            case "PLUGIN_NOT_FOUND", "PLUGIN_VERSION_NOT_FOUND", "PLUGIN_MANIFEST_UNREADABLE", "PLUGIN_INVENTORY_UNSAFE":
                return "插件记录无法读取，请检查插件目录和访问权限后重新扫描。"
            case "PLUGIN_SCOPE_AMBIGUOUS", "PLUGIN_VERSION_AMBIGUOUS", "PLUGIN_SCOPE_UNSUPPORTED", "PLUGIN_PROJECT_REQUIRED":
                return "无法确定插件的目标项目、安装范围或版本，请重新选择项目和插件。"
            case "PLUGIN_ACTION_UNSUPPORTED", "PLUGIN_ROLLBACK_UNSUPPORTED":
                return "所属工具不支持这项插件操作，请到原工具中处理。"
            case "PLUGIN_NOT_INSTALLED", "PLUGIN_ALREADY_INSTALLED", "PLUGIN_ALREADY_ENABLED", "PLUGIN_ALREADY_DISABLED":
                return "插件当前状态不适用这项操作，请重新扫描后选择。"
            case "PATH_OUTSIDE_ROOT", "PATH_SYMLINK", "STAGING_INVALID":
                return "目标路径未通过安全检查，请检查目录位置和符号链接，再重新生成计划。"
            default:
                if code.hasPrefix("MANAGED_BLOCK_") || code == "RULE_MARKER_INVALID" {
                    return "规则标记不完整或有冲突，请检查规则文件后重新生成计划。"
                }
                return "操作未完成，请重新读取当前状态后再试。"
            }
        }
        let systemError = error as NSError
        if systemError.domain == NSCocoaErrorDomain {
            switch systemError.code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                return "没有访问文件的权限，请检查目录权限后重试。"
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                return "找不到所需文件，请检查文件位置后重新读取。"
            case NSFileWriteOutOfSpaceError:
                return "磁盘空间不足，请清理空间后重试。"
            default: break
            }
        }
        if systemError.domain == NSURLErrorDomain {
            return "网络连接失败，请检查网络后重试。"
        }
        if systemError.domain == NSPOSIXErrorDomain {
            switch systemError.code {
            case Int(EACCES), Int(EPERM):
                return "没有访问文件或运行命令的权限，请检查权限后重试。"
            case Int(ENOSPC):
                return "磁盘空间不足，请清理空间后重试。"
            case Int(ENOENT):
                return "找不到所需文件或命令，请检查位置后重新读取。"
            default: break
            }
        }
        return "操作未完成，请重新读取当前状态后再试。"
    }

    enum MetadataField: CaseIterable {
        case sourceKind, trust, licenseReview, metadataReview, integrity, presetStatus, mergePolicy, component, scope
    }

    static func metadata(_ value: String, field: MetadataField) -> String {
        let labels: [String: String]
        switch field {
        case .sourceKind:
            labels = ["workspace": "本仓库", "local-snapshot": "本地快照", "git": "代码仓库"]
        case .trust:
            labels = ["local-owned": "本地自维护", "review-required": "待审查"]
        case .licenseReview:
            labels = ["required": "待审查", "per-skill": "需逐个技能审查"]
        case .metadataReview:
            labels = ["not-schema-validated": "格式尚未核验"]
        case .integrity:
            labels = ["blocked": "不可部署", "snapshotted": "已快照"]
        case .presetStatus:
            labels = ["draft": "草稿"]
        case .mergePolicy:
            labels = ["explicit-selection": "按预设替换草稿"]
        case .component:
            labels = ["skills": "技能", "commands": "命令", "agents": "智能体", "hooks": "自动运行脚本",
                      "MCP": "MCP 服务", "LSP": "语言服务", "userConfig": "用户配置", "manifest": "插件清单"]
        case .scope:
            labels = ["user": "当前用户", "project": "当前项目", "local": "仅本机"]
        }
        return labels[value] ?? "未识别，需核对"
    }

    static func catalogIssue(_ issue: CatalogIssue) -> String {
        switch issue.reason {
        case "broken-or-cyclic-link": "链接目标丢失或循环引用，请修复来源后重新生成快照。"
        default: "来源未通过完整性检查，请核对来源文件后重新生成快照。"
        }
    }

    enum DiagnosticContext {
        case project, plugin, source, plan, candidate
    }

    // 只转换已知诊断；未知或夹带英文的外部文本不回显，也不据此推断成功状态。
    static func diagnostic(_ text: String, context: DiagnosticContext) -> String {
        switch context {
        case .project:
            if text.contains("软链") { return "项目中有符号链接，未将其视为本应用管理的内容，请检查链接目标。" }
            if text.contains("没有来源") { return "项目中有来源不明的技能目录，请核对后重新选择技能。" }
            if text.contains("受管块") { return "项目规则无法读取，请检查规则标记是否完整。" }
            if text.contains("多个来源") { return "多个来源包含相同技能，请在草稿中明确选择来源。" }
            if text.contains("不一致") { return "本机内容与技能库记录不一致，请检查文件改动后重新生成计划。" }
            return "项目内容未能完成核对，请检查目录权限、技能来源和规则文件。"
        case .plugin:
            return "部分插件记录无法读取，请检查插件目录、安装记录和访问权限后重新扫描。"
        case .candidate:
            return "这个技能无法读取或未通过完整性检查，请修复来源后重新预览。"
        case .source:
            switch text {
            case "内容指纹与许可提示不等于安全、合规或模型行为审核。":
                return "内容指纹和许可提示不代表已完成安全、合规或行为审查。"
            case "预览只 clone 固定提交并读取文本，不执行仓库脚本、hooks、postinstall 或子模块。":
                return "来源预览只读取固定版本的文本，不运行仓库脚本或读取子模块。"
            default:
                return "来源包含无法识别的提示，请先核对仓库内容和许可，不要直接启用。"
            }
        case .plan:
            if text.contains("许可审查") { return "技能许可尚未完成审查，请核对许可后再批准。" }
            if text.hasPrefix("宿主：") { return "请核对上方的目标工具、安装范围和工作目录。" }
            if text.hasPrefix("目标配置：") { return "请核对上方列出的配置文件路径。" }
            if text.contains("白名单") { return "仅运行计划中列出的命令，不接受额外参数。" }
            if text.contains("状态变化") { return "执行前会重新核对插件清单和安装状态，发生变化时计划失效。" }
            if text.contains("人工核对的组件") { return "插件含有可运行组件，请核对其命令、自动运行脚本、服务和配置风险。" }
            if text.contains("保留宿主") { return "卸载后仍会保留插件数据。" }
            if text.contains("重启会话") { return "可能需要重启 AI 工具的会话；配置更新不代表当前会话已加载。" }
            if text.contains("副作用") { return "停用或卸载不能撤销脚本已经造成的改动。" }
            if text.contains("环境变量") { return "只写入环境变量引用，不读取或复制密钥值。" }
            if text.hasPrefix("Claude JSON") { return "保留其他配置项，但配置项的排列顺序可能改变。" }
            if text.hasPrefix("Codex TOML") { return "只修改本应用管理的配置部分，保留其他文本和注释。" }
            return "计划包含无法识别的提示，请先核对目标、范围和风险，暂不批准。"
        }
    }

    static func pluginRisk(_ text: String) -> String {
        switch text {
        case "含 hook": "包含自动运行脚本，请核对触发时机和文件改动。"
        case "含 command": "包含可运行命令，请核对命令行为。"
        case "含 MCP": "包含 MCP 服务，请核对服务权限。"
        case "启动 LSP": "可能启动语言服务进程。"
        case "包含用户配置项": "包含用户配置，请核对所需权限和敏感信息。"
        case "缓存不等于启用": "只有缓存记录，尚未确认安装或启用。"
        case "未发现可执行副作用": "扫描未发现可运行组件，但不代表已经过安全审查。"
        default: "存在未识别的插件风险，请先核对插件内容。"
        }
    }

    static func pluginState(_ plugin: PluginInventoryRecord) -> String {
        guard plugin.installed else { return "仅缓存 · 未确认安装" }
        return switch plugin.enabled {
        case true?: "已安装 · 已启用"
        case false?: "已安装 · 已停用"
        case nil: "已安装 · 启用状态待确认"
        }
    }

    static func changeAction(_ action: String) -> String {
        switch action {
        case "add": "新增"
        case "update", "replace": "更新"
        case "remove", "delete": "删除"
        case "plugin-command": "插件命令"
        case "install": "安装"
        case "enable": "启用"
        case "disable": "停用"
        case "uninstall": "卸载"
        default: "未识别操作"
        }
    }

    static func licenseEvidence(_ evidence: String) -> String {
        switch evidence {
        case "MIT · 仍需逐 skill 审查": "可能采用 MIT 许可，仍需逐个技能审查"
        case "Apache-2.0 迹象 · 仍需逐 skill 审查": "可能采用 Apache-2.0 许可，仍需逐个技能审查"
        case "GPL 迹象 · 需合规审查": "可能采用 GPL 许可，需合规审查"
        case "检测到许可文件 · 未自动判定": "已找到许可文件，尚未确认许可类型"
        case "未检测到根许可文件 · 禁止默认再分发": "未找到仓库许可文件，请勿直接再分发"
        default: "许可尚未确认，请核对来源许可文件"
        }
    }

    static func applyResult(_ message: String?) -> String {
        switch message {
        case nil: "文件已写入并核对，仍需在 AI 工具中确认加载状态。"
        case "宿主命令成功，回读已观察到目标状态。": "插件命令已完成，已确认目标状态。"
        case "宿主命令已成功退出，但回读尚未观察到目标状态；可能需要刷新宿主或重启会话。":
            "插件命令已完成，但尚未确认目标状态，请刷新 AI 工具或重启会话后检查。"
        case "宿主命令非零退出，但回读已观察到目标状态；保留原始退出码供排查。":
            "已观察到插件目标状态，但命令报告异常，请检查操作记录，不要重复执行。"
        default: "操作返回了未识别的结果，请检查操作记录和目标状态，不要重复执行。"
        }
    }
}
