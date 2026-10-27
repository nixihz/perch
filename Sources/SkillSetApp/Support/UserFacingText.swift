import Foundation
import Darwin
import OSLog
import SkillSetCore

enum UserFacingText {
    private static let errorLogger = Logger(subsystem: "com.example.perch", category: "ApplicationError")

    @MainActor
    static func templateTitle(_ template: TemplateRecord, language: AppLanguage? = nil) -> String {
        template.isLocal ? template.title : L10n.text(template.title, language: language)
    }

    @MainActor
    static func templatePurpose(_ template: TemplateRecord, language: AppLanguage? = nil) -> String {
        template.isLocal ? template.purpose : L10n.text(builtInDescription(template.purpose), language: language)
    }

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
        return L10n.tr("无法读取项目配置：\(reason)")
    }

    @MainActor
    static func planSummary(_ change: PlannedChange) -> String {
        change.unifiedDiff.components(separatedBy: "\n").map { localizedPlanSummary($0) }.joined(separator: "\n")
    }

    @MainActor
    private static func localizedPlanSummary(_ summary: String) -> String {
        // 仅翻译管理器生成的说明，真实 diff、命令参数和技能内容不能被替换。
        if let match = summary.wholeMatch(of: /^复制 ([0-9]+) 个文件到 (.+)$/) {
            return L10n.tr("复制 \(match.1) 个文件到 \(match.2)")
        }
        if let match = summary.wholeMatch(of: /^移除未漂移的受管技能 (.+)；操作备份可用于撤销$/) {
            return L10n.tr("移除栖集写入的技能 \(match.1)；可从操作备份恢复")
        }
        let ruleActions = [
            ("追加受管块 ", "添加栖集维护的规则"),
            ("替换受管块 ", "更新栖集维护的规则"),
            ("移除受管块 ", "移除栖集维护的规则")
        ]
        for (prefix, title) in ruleActions where summary.hasPrefix(prefix) {
            return L10n.text(title) + " " + summary.dropFirst(prefix.count)
        }
        for action in PluginLifecycleAction.allCases {
            let prefix = action.displayName + "："
            if summary.hasPrefix(prefix) {
                return L10n.text(action.displayName) + ": " + summary.dropFirst(prefix.count)
            }
        }
        if let match = summary.wholeMatch(of: /^(Codex|Claude Code) · (用户|项目)：保留或写入 \[(.*)\]；移除 \[(.*)\]$/) {
            return L10n.tr("\(match.1) · \(LocalizedText(stringLiteral: String(match.2)))：保留或写入 [\(match.3)]；移除 [\(match.4)]")
        }
        if let match = summary.wholeMatch(of: /^(新增|更新|删除) (Codex|Claude Code) (项目|用户) MCP Server (.+)$/) {
            return "\(L10n.text(String(match.1))) \(match.2) \(L10n.text(String(match.3))) \(L10n.text("MCP 服务")) \(match.4)"
        }
        return L10n.text(summary)
    }

    // 异常的附带文本可能来自系统或外部进程，不能作为界面文案直接展示。
    static func error(_ error: Error) -> String {
        let message = errorMessage(error)
        let code = (error as? any SkillSetCodedError)?.code ?? "UNCLASSIFIED"
        let systemError = error as NSError
        errorLogger.error("code=\(code, privacy: .public) type=\(String(reflecting: type(of: error)), privacy: .public) domain=\(systemError.domain, privacy: .public) systemCode=\(systemError.code) message=\(message, privacy: .private)")
        return message
    }

    /// 批量结果里的失败原因只有稳定错误码，这里补成用户可读的原因。
    static func message(forCode code: String) -> String {
        errorMessage(SkillSetCodedFailure(code: code))
    }

    private static func errorMessage(_ error: Error) -> String {
        if case let DeploymentError.symlinkDetected(path) = error {
            if path.hasSuffix("/.claude/skills") {
                return "Claude Code 的技能文件夹链接到了其他位置，暂时无法保存。请改用独立文件夹。"
            }
            if path.hasSuffix("/.agents/skills") {
                return "Codex 的技能文件夹链接到了其他位置，暂时无法保存。请改用独立文件夹。"
            }
            if URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent == "skills" {
                return "已有同名技能链接，无法替换。请先移走这个链接，再保存。"
            }
            return "要保存的位置链接到了其他位置，栖集没有修改它。请打开所在文件夹处理后再试。"
        }
        // 只展示由 Core 定义的原因与文件路径，不回显解码器或外部进程的原始异常。
        if let globalError = error as? GlobalConfigurationError,
           case .verificationFailed = globalError {
            return globalError.localizedDescription
        }
        let code = (error as? any SkillSetCodedError)?.code
            ?? (error as? MCPConfigurationError)?.code
            ?? (error as? PluginInventoryError)?.code
            ?? (error as? ProjectLockError)?.code
        if let code {
            switch code {
            case "HARNESS_SCOPE_CONFLICT":
                return "这些变更也会影响另一个 AI 工具，请返回配置页核对共用技能、规则和安装方式后重新预览。"
            case "PLUGIN_SOURCE_CHANGED":
                return "插件内容在扫描后已改变，请重新扫描并选择后再收录。"
            case "PLUGIN_SOURCE_COLLECTED":
                return "相同插件内容已经收录，请重新扫描查看来源记录。"
            case "GLOBAL_STATE_CORRUPT":
                return "全局管理记录无法核验，请检查操作历史和本机数据；已有文件保持不变。"
            case "GLOBAL_BASELINE_MISSING":
                return "原始备份缺失或已改变，无法安全还原；请检查备份后重试。"
            case "GLOBAL_OPERATION_STALE":
                return "已有后续全局变更，请先撤销后续操作，再撤销这次操作。"
            case "TEMPLATE_STORE_CORRUPT":
                return "本机片段库无法读取，请检查数据文件后重试。"
            case "SOURCE_IMPORT_CHANGED":
                return "来源内容或许可文件已改变，请重新预览仓库后再加入技能库。"
            case "SOURCE_IMPORT_UNAVAILABLE":
                return "这个技能暂时无法导入，请检查来源文件并重新预览仓库。"
            case "SKILLS_SH_QUERY_TOO_SHORT":
                return "请至少输入 2 个字符，再搜索 skills.sh。"
            case "SKILLS_SH_SEARCH_FAILED":
                return "skills.sh 搜索失败，请检查网络后重试。"
            case "SKILLS_SH_RESPONSE_INVALID":
                return "skills.sh 返回了无法识别的响应，请稍后重试。"
            case "SKILLS_SH_SKILL_ID_INVALID":
                return "这项结果缺少技能标识，请到 skills.sh 核对。"
            case "SKILLS_SH_INVALID_SOURCE":
                return "这个目录条目没有可用的 GitHub 仓库，请到 skills.sh 查看安装说明。"
            case "SKILLS_SH_SKILL_NOT_FOUND":
                return "来源仓库的当前版本里没有这个技能，请到 skills.sh 核对。"
            case "SKILLS_SH_AMBIGUOUS_SKILL":
                return "来源仓库中有多个同名技能，无法确定要安装哪一个，请换一个目录条目。"
            case "SKILL_FILE_LIMIT_EXCEEDED":
                return "技能目录条目过多，无法展示附属文件；请检查来源目录。"
            case "LIBRARY_DOCUMENT_INVALID":
                return "请保留完整的 YAML 头部，填写 name、description 和非空正文；文件不能超过 2 MiB。"
            case "LIBRARY_SLUG_INVALID":
                return "技能标识须为小写字母、数字和连字符，长度不超过 80 个字符。"
            case "LIBRARY_DUPLICATE":
                return "本地技能已有这个标识，请换一个标识后保存。"
            case "LIBRARY_STALE":
                return "技能内容已改变。请先复制保留未保存的改动，再关闭并重新打开编辑器。"
            case "LIBRARY_CORRUPT":
                return "技能库记录无法读取，请检查栖集的数据目录；已有技能版本仍保留。"
            case "PLAN_NOT_FOUND":
                return "找不到这份计划，请返回配置页重新预览变更。"
            case "PLAN_INVALID", "PLAN_INVALID_STATE", "PLUGIN_STAGED_COMMAND_INVALID":
                return "这份计划无法使用，请重新预览并核对变更后再写入。"
            case "OPERATION_NOT_FOUND", "PLUGIN_OPERATION_CORRUPT":
                return "操作记录缺失或无法读取，请检查备份和目标文件后再试。"
            case "OFFLINE_OBJECT_MISSING", "OFFLINE_OBJECT_CORRUPT", "OBJECT_STORE_UNSAFE", "OBJECT_DIGEST_INVALID":
                return "本机保存的技能版本缺失或无法读取，请检查技能库并从来源重新加入。"
            case "TEMPLATE_INVALID":
                return "片段无法保存，请检查名称和规则正文后再试。"
            case "PRESET_INVALID":
                return "预设无法保存，请检查名称和所选内容后再试。"
            case "PLAN_EXPIRED", "PLAN_STALE", "PLAN_DIGEST_MISMATCH", "PLUGIN_STATE_STALE", "PROJECT_LOCK_STALE":
                return "计划已过期或目标已改变，请重新生成计划并审阅。"
            case "APPROVAL_REQUIRED":
                return "请先在本机审阅并批准这份计划。"
            case "PLAN_ALREADY_APPLIED":
                return "这份计划已完成，请重新读取配置查看结果。"
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
            case "SKILL_TARGET_CONFLICT":
                return "目标目录已有同名技能且内容不同，请先核对差异，或取消选择这个技能。"
            case "RULE_TARGET_CONFLICT":
                return "已有同标记规则不属于本应用，请核对规则来源和内容后再配置。"
            case "SKILL_MANAGED_DRIFT":
                return "栖集写入的技能已被修改，请先核对并保留改动，再重新生成计划。"
            case "RULE_MANAGED_DRIFT":
                return "栖集写入的规则已被修改，请先核对并保留改动，再重新生成计划。"
            case "INSTRUCTION_NOT_FOUND":
                return "找不到 AGENTS 片段，请在草稿中重新选择。"
            case "SELECTION_LIMIT_EXCEEDED":
                return "一次最多选择 200 个技能，请减少选择后重试。"
            case "SOURCE_INVALID_URL", "SOURCE_HOST_NOT_ALLOWED":
                return "请填写 HTTPS 或 SSH Git 仓库链接，或 GitHub 的 owner/repo 简写。"
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
            case "MCP_LIBRARY_DUPLICATE":
                return "配置库或所选结果中有同名服务，请修改名称或只保留一个。"
            case "MCP_LIBRARY_SELECTION_MISSING":
                return "所选 MCP 服务已从配置库删除，请移除引用后重新预览。"
            case "MCP_LIBRARY_SCAN_CHANGED":
                return "MCP 配置在扫描后已改变，请重新扫描后再加入配置库。"
            case "MCP_LIBRARY_CONNECTION_MODIFIED":
                return "栖集写入的 MCP 服务已被修改或移除，请到「MCP 服务 → AI 工具中的配置」核对改动。"
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
            case "PLUGIN_ID_INVALID", "PLUGIN_MANIFEST_DIGEST_INVALID":
                return "插件信息不完整，请重新扫描后选择插件。"
            case "PLUGIN_SCOPE_AMBIGUOUS", "PLUGIN_VERSION_AMBIGUOUS", "PLUGIN_SCOPE_UNSUPPORTED", "PLUGIN_PROJECT_REQUIRED":
                return "无法确定插件的目标项目、安装范围或版本，请重新选择项目和插件。"
            case "PLUGIN_ACTION_UNSUPPORTED", "PLUGIN_ROLLBACK_UNSUPPORTED":
                return "所属工具不支持这项插件操作，请到原工具中处理。"
            case "PLUGIN_NOT_INSTALLED", "PLUGIN_ALREADY_INSTALLED", "PLUGIN_ALREADY_ENABLED", "PLUGIN_ALREADY_DISABLED":
                return "插件当前状态不适用这项操作，请重新扫描后选择。"
            case "PATH_OUTSIDE_ROOT", "PATH_SYMLINK":
                return "要保存的位置无法使用，请检查文件夹是否已被移动或替换。"
            case "STAGING_INVALID":
                return "保存准备失败，请重新预览后再试。"
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
        case sourceKind, trust, metadataReview, integrity, presetStatus, mergePolicy, component, scope
    }

    static func builtInDescription(_ value: String) -> String {
        switch value {
        case "把协作约定放进每个项目的受管块。": "把协作规则用于项目，只更新栖集维护的部分。"
        default: value
        }
    }

    static func mcpState(_ value: String) -> String {
        switch value {
        case "管理器受管": "由栖集管理"
        case "仅观察": "已有配置"
        default: "配置状态待检查"
        }
    }

    static func metadata(_ value: String, field: MetadataField) -> String {
        let labels: [String: String]
        switch field {
        case .sourceKind:
            labels = ["workspace": "本仓库", "local-snapshot": "本地快照", "git": "代码仓库"]
        case .trust:
            labels = ["local-owned": "本地自维护", "review-required": "待审查"]
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

    static func isInformationalProjectNote(_ text: String) -> Bool {
        let roots = [".agents/skills", ".claude/skills"]
        let rules = ["AGENTS.md", "CLAUDE.md"]
        return roots.contains { text == "\($0)：父目录是软链，未扫描。" }
            || rules.contains { text == "\($0)：文件是软链，不读取受管块。" }
    }

    // 只转换已知诊断；未知或夹带英文的外部文本不回显，也不据此推断成功状态。
    static func isInformationalPlanNote(_ text: String) -> Bool {
        // 旧计划仍能打开，但已移除的逐技能许可提醒不再展示。
        if text.range(of: #"^[^\r\n]+ 仍处于 [a-z-]+；许可审查为 [a-z-]+。$"#, options: .regularExpression) != nil {
            return true
        }
        // 仅识别核心生成的完整格式，未知或附带外部内容的提示仍保留给用户。
        return text.range(of: #"^对象存储新增 [0-9]+ 个对象，共 [0-9]+ 字节；项目锁绑定 manifest sha256:[0-9a-f]{64}。$"#, options: .regularExpression) != nil
    }

    static func diagnostic(_ text: String, context: DiagnosticContext) -> String {
        switch context {
        case .project:
            if text == ".claude/skills：父目录是软链，未扫描。" {
                return "Claude Code 的技能文件夹链接到了其他位置，未读取其中的技能。"
            }
            if text == ".agents/skills：父目录是软链，未扫描。" {
                return "Codex 的技能文件夹链接到了其他位置，未读取其中的技能。"
            }
            if text.contains("软链") || text.contains("符号链接") {
                return "项目中的文件链接保持原样，栖集没有修改它们。"
            }
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
            case "预览只 clone 固定提交并读取文本，不执行仓库脚本、hooks、postinstall 或子模块。":
                return "来源预览只读取固定版本的文本，不运行仓库脚本或读取子模块。"
            default:
                return "来源包含无法识别的提示，请先核对仓库内容。"
            }
        case .plan:
            if isInformationalPlanNote(text) {
                return "部署内容已保存到本机版本库，项目版本记录将随计划更新。"
            }
            if text == "此操作影响当前用户在该 AI 工具中的全部项目。" { return "影响所选 AI 工具的全部项目。" }
            if text.contains("保留原归属") { return "项目原有内容会保留，取消选择不会删除。" }
            if text.contains("缺少本机管理记录") { return "无法确认这些内容是否由栖集写入，会保留已有文件。请先核对来源和内容。" }
            if text.hasPrefix("宿主：") { return "请核对上方的目标工具、安装范围和工作目录。" }
            if text.hasPrefix("目标配置：") { return "请核对上方列出的配置文件路径。" }
            if text.contains("白名单") { return "仅运行计划中列出的命令，不接受额外参数。" }
            if text.contains("状态变化") { return "执行前会重新核对插件清单和安装状态，发生变化时计划失效。" }
            if text.contains("人工核对的组件") { return "插件含有可运行组件，请核对其命令、自动运行脚本、服务和配置风险。" }
            if text.contains("保留宿主") { return "卸载后仍会保留插件数据。" }
            if text.contains("重启会话") { return "可能需要重启 AI 工具的会话；配置更新不代表当前会话已加载。" }
            if text.contains("副作用") { return "停用或卸载不能撤销脚本已经造成的改动。" }
            if text == "只更新当前项目的 MCP 配置；全局连接仍可能生效。" { return "只更新当前项目的 MCP 配置；全局连接仍可能生效。" }
            if text == "取消勾选只移除本配置库写入且未被修改的服务。" { return "取消勾选只移除本配置库写入且未被修改的服务。" }
            if text.contains("环境变量") { return "只写入环境变量引用，不读取或复制密钥值。" }
            if text.hasPrefix("Claude JSON") { return "保留其他配置项，但配置项的排列顺序可能改变。" }
            if text.hasPrefix("Codex TOML") { return "只修改本应用管理的配置部分，保留其他文本和注释。" }
            return "计划包含无法识别的提示，请先核对目标、范围和风险，暂不批准。"
        }
    }

    static func mcpStatus(_ inspection: MCPConfigurationInspection) -> String? {
        guard !inspection.issues.isEmpty else { return nil }
        // 仅识别观察器生成的完整提示；外部名称和系统异常都不能作为界面文案回显。
        let existingConnectionNotes = Set(inspection.servers
            .filter { !$0.managed && inspection.scope == .user }
            .map { "\($0.name)：现有用户级配置；编辑或删除须预览并批准。" })
        if inspection.issues.allSatisfy(existingConnectionNotes.contains) {
            return "已有配置；可编辑或删除，批准计划后生效。"
        }
        return "MCP 配置无法读取，请检查配置文件和目录权限后重新扫描。"
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
        case "MIT", "MIT · 仍需逐 skill 审查": "MIT"
        case "Apache-2.0", "Apache-2.0 迹象 · 仍需逐 skill 审查": "Apache-2.0"
        case "GPL", "GPL 迹象 · 需合规审查": "GPL"
        case "已找到许可文件", "检测到许可文件 · 未自动判定": "已找到许可文件"
        case "未找到仓库许可文件", "未检测到根许可文件 · 禁止默认再分发": "未找到仓库许可文件"
        default: "未记录许可信息"
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
