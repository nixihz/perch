import SwiftUI
import SkillSetCore

struct AIAccessView: View {
    @Bindable var model: AppModel
    @State private var host: MCPHost = .codex
    @State private var showLaunchDetails = false
    @State private var showTechnicalDetails = false

    private var installation: MCPAccessInstallation? { model.mcpAccessInstallation }
    private var inspection: MCPConfigurationInspection? { model.mcpAccessInspection(host: host) }
    private var connection: MCPAccessConnectionState {
        .inspect(inspection, installation: installation)
    }
    private var canPrepare: Bool {
        installation != nil && connection != .external && connection != .unreadable && !model.isWorking
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    eyebrow: "AI ACCESS",
                    title: L10n.tr("把栖集接入 AI 工具"),
                    detail: L10n.tr("让 Codex 或 Claude Code 查询技能、查看项目并准备变更计划。无需另外安装技能。")
                )
                programCard
                connectionCard
                usageCard
                if !model.pendingPlans.isEmpty { pendingPlansCard }
                technicalDetails
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { model.refreshAIAccess() }
        .onChange(of: host) { model.aiAccessError = nil }
        .onChange(of: model.planPresented) {
            if !model.planPresented { model.refreshAIAccess() }
        }
    }

    private var programCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(L10n.tr("MCP 程序"), systemImage: "terminal")
                        .font(AppFont.heading)
                    Spacer()
                    StatusBadge(
                        text: installation == nil ? L10n.tr("未找到完整程序") : L10n.tr("已找到程序"),
                        tone: installation == nil ? .warning : .neutral
                    )
                    Button(L10n.tr("重新检测")) { model.refreshAIAccess() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("aiAccess.refresh")
                }
                if let installation {
                    Text(installation.origin == .bundled ? L10n.tr("随 App 提供") : L10n.tr("使用本机开发构建"))
                        .font(AppFont.secondary)
                        .foregroundStyle(.secondary)
                    Text(installation.executableURL.path)
                        .font(AppFont.code)
                        .textSelection(.enabled)
                } else {
                    Text(L10n.tr("未找到完整的 MCP 程序。请重新构建或安装栖集，再重新检测。"))
                        .font(AppFont.body)
                        .foregroundStyle(.orange)
                }
                Text(L10n.tr("程序随构建提供；不会自动加入全局命令，也不会自动修改 AI 工具的配置。"))
                    .font(AppFont.secondary)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var connectionCard: some View {
        SurfaceCard(emphasis: true) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.tr("选择要接入的 AI 工具"))
                    .font(AppFont.heading)
                Picker(L10n.tr("AI 工具"), selection: $host) {
                    ForEach(MCPHost.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 340)
                .accessibilityIdentifier("aiAccess.host")
                StatusBadge(text: connectionTitle, tone: .warning)
                Text(connectionDetail)
                    .font(AppFont.body)
                    .foregroundStyle(.secondary)
                if let inspection {
                    KeyValueLine(key: L10n.tr("用户级配置"), value: inspection.configPath, monospaced: true)
                }
                if let draft = installation?.draft(host: host, paths: model.runtimePaths) {
                    DisclosureGroup(L10n.tr("查看启动命令与参数"), isExpanded: $showLaunchDetails) {
                        VStack(alignment: .leading, spacing: 8) {
                            KeyValueLine(key: L10n.tr("命令"), value: draft.commandOrURL, monospaced: true)
                            ForEach(Array(draft.args.enumerated()), id: \.offset) { index, argument in
                                KeyValueLine(key: L10n.tr("参数 \(index + 1)"), value: argument, monospaced: true)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .font(AppFont.secondary)
                }
                if let error = model.aiAccessError {
                    Label(L10n.tr(error), systemImage: "exclamationmark.triangle")
                        .font(AppFont.secondary)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("aiAccess.error")
                }
                HStack {
                    Button(connection == .updateNeeded ? L10n.tr("生成更新计划") : L10n.tr("生成接入计划")) {
                        _ = model.prepareAIAccess(host: host)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canPrepare)
                    .accessibilityIdentifier("aiAccess.prepare")
                    Button(L10n.tr("查看 MCP 服务")) { model.section = .mcp }
                        .buttonStyle(.bordered)
                }
                Text(L10n.tr("先审阅变更，再在本机批准并写入。配置完成后仍需让 AI 工具重新加载并验证。"))
                    .font(AppFont.secondary)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var connectionTitle: String {
        switch connection {
        case .unconfigured: L10n.tr("尚未配置")
        case .configured: L10n.tr("已找到配置 · 需要确认加载")
        case .updateNeeded: L10n.tr("接入路径需要更新")
        case .external: L10n.tr("已有配置 · 保留不改")
        case .unreadable: L10n.tr("配置状态待核对")
        }
    }

    private var connectionDetail: String {
        switch connection {
        case .unconfigured:
            L10n.tr("将新增名为 perch 的用户级 stdio 配置，使用上方程序的绝对路径。")
        case .configured:
            L10n.tr("已找到本应用管理的配置。请重新加载 AI 工具，确认它能列出栖集的 MCP 工具；如无法使用，可重新生成计划核对参数。")
        case .updateNeeded:
            L10n.tr("栖集的现有配置使用了旧程序路径。请生成更新计划并核对变更。")
        case .external:
            L10n.tr("已存在同名或同程序的外部配置。请到 MCP 服务查看；接入向导不会覆盖或重复添加。")
        case .unreadable:
            L10n.tr("暂时无法确认目标配置。请到 MCP 服务核对配置问题后重新检测。")
        }
    }

    private var usageCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.tr("接入后怎么用"))
                    .font(AppFont.heading)
                Text(L10n.tr("1. 批准接入计划后，让 AI 工具重新加载 MCP；必要时重新打开会话。"))
                Text(L10n.tr("2. 在 AI 工具中确认已出现 perch 的工具，再试着询问："))
                Text(L10n.tr("“列出栖集的预设，搜索代码审查技能，再把我选定的技能或预设安装到当前项目。”"))
                    .textSelection(.enabled)
                    .foregroundStyle(AppColor.accentText)
                Text(L10n.tr("3. 涉及项目写入时，先让 AI 生成计划，再回到本机审阅并批准。"))
                Text(L10n.tr("配置写入后，仍需在 AI 工具中确认加载。服务会按需启动，无需一直开着终端。"))
                    .font(AppFont.secondary)
                    .foregroundStyle(.secondary)
            }
            .font(AppFont.body)
        }
    }

    private var pendingPlansCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.tr("待本机审阅的计划"))
                        .font(AppFont.heading)
                    Spacer()
                    Text(L10n.tr("\(model.pendingPlans.count) 个"))
                        .font(AppFont.secondary)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.pendingPlans) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.plan.projectPath)
                                .font(AppFont.code)
                                .textSelection(.enabled)
                            Text(L10n.tr("有效至 \(L10n.date(record.expiresAt))"))
                                .font(AppFont.secondary)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L10n.tr("审阅计划")) { model.reviewPlan(record) }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var technicalDetails: some View {
        DisclosureGroup(L10n.tr("工具与兼容性详情"), isExpanded: $showTechnicalDetails) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("目前仅验证了 stdio 连接与 2025-11-25 版本协议；其他连接方式和 AI 工具兼容性仍待验证。"))
                Text(L10n.tr("提供预设列表、技能搜索、项目技能与预设安装、来源预览、计划和操作记录等 17 个工具；实际列表以 AI 工具发现的结果为准。"))
                Text(L10n.tr("AI 可以生成计划和执行已批准的计划；MCP 不提供批准工具。"))
            }
            .font(AppFont.secondary)
            .foregroundStyle(.secondary)
            .padding(.top, 10)
        }
        .font(AppFont.secondary)
    }
}
