import SwiftUI
import SkillSetCore

struct AIAccessView: View {
    @Bindable var model: AppModel
    @State private var host: MCPHost = .codex
    @State private var scope: MCPConfigurationScope = .user
    @State private var showLaunchDetails = false
    @State private var showTechnicalDetails = false
    @State private var showProgramDetails = false
    @State private var refreshRevision = 0

    private var installation: MCPAccessInstallation? { model.mcpAccessInstallation }
    private var inspection: MCPConfigurationInspection? { model.mcpAccessInspection(host: host, scope: scope) }
    private var connection: MCPAccessConnectionState {
        .inspect(inspection, installation: installation)
    }
    private var canPrepare: Bool {
        installation != nil && connection != .external && connection != .unreadable && !model.isWorking && !model.isRefreshingAIAccess
            && (scope == .user || model.selectedProject != nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    eyebrow: "AI ACCESS",
                    title: L10n.tr("把栖集接入 AI 工具"),
                    detail: L10n.tr("这是栖集对外提供的 MCP 接口。让 AI 查询你的能力库、查看项目并准备配置计划。")
                )
                connectionCard
                if !model.pendingPlans.isEmpty { pendingPlansCard }
                usageCard
                DisclosureGroup(L10n.tr("程序与路径诊断"), isExpanded: $showProgramDetails) {
                    programCard.padding(.top, 10)
                }
                technicalDetails
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: model.selectedProjectID + ":" + String(refreshRevision)) {
            await model.refreshAIAccessInBackground()
        }
        .onChange(of: host) { model.aiAccessError = nil }
        .onChange(of: model.planPresented) {
            if !model.planPresented { refreshRevision += 1 }
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
                    Button(L10n.tr("重新检测")) { refreshRevision += 1 }
                        .disabled(model.isRefreshingAIAccess)
                        .buttonStyle(AppButtonStyle())
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
                HStack {
                    Label(L10n.tr("AI 工具 → 栖集"), systemImage: "arrow.right.circle")
                        .font(AppFont.heading)
                    Spacer()
                    StatusBadge(text: "stdio", tone: .neutral)
                }
                Text(L10n.tr("选择要接入的 AI 工具")).font(AppFont.secondary)
                Picker(L10n.tr("AI 工具"), selection: $host) {
                    ForEach(MCPHost.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 340)
                .accessibilityIdentifier("aiAccess.host")
                Picker(L10n.tr("使用范围"), selection: $scope) {
                    Text(L10n.tr("用户")).tag(MCPConfigurationScope.user)
                    Text(L10n.tr("项目")).tag(MCPConfigurationScope.project)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 340)
                .accessibilityIdentifier("aiAccess.scope")
                if scope == .project {
                    AppPicker(title: L10n.tr("目标项目"), selection: $model.selectedProjectID,
                              valueLabel: model.selectedProject?.name ?? L10n.tr("请选择")) {
                        Text(L10n.tr("请选择")).tag("")
                        ForEach(model.projects) { project in Text(project.name).tag(project.id) }
                    }
                    .accessibilityIdentifier("aiAccess.project")
                    if model.selectedProject == nil {
                        Text(L10n.tr("请先到「项目」添加并选择一个项目，再配置项目连接。"))
                            .font(AppFont.secondary).foregroundStyle(.orange)
                    }
                }
                if model.isRefreshingAIAccess {
                    ProgressView(L10n.tr("正在读取接入状态…")).controlSize(.small)
                } else {
                    HStack(spacing: 8) {
                        StatusBadge(text: connectionTitle, tone: connection == .configured ? .neutral : .warning)
                        if installation == nil {
                            StatusBadge(text: L10n.tr("未找到完整程序"), tone: .danger)
                        }
                    }
                    Text(connectionDetail)
                        .font(AppFont.body)
                        .foregroundStyle(.secondary)
                }
                if let inspection {
                    KeyValueLine(key: scope == .project ? L10n.tr("项目级配置") : L10n.tr("用户级配置"), value: inspection.configPath, monospaced: true)
                }
                if host == .codex && scope == .project {
                    Text(L10n.text(MCPConfigurationTarget.codexProjectTrustNotice))
                        .font(AppFont.secondary).foregroundStyle(.orange)
                }
                Text(scope == .project
                    ? L10n.tr("影响范围：仅写入所选项目；全局 MCP 配置仍可能生效。栖集按需启动。")
                    : L10n.tr("影响范围：当前用户的全部项目。栖集按需启动，无需手动运行服务。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
                if installation == nil {
                    Text(L10n.tr("未找到完整的 MCP 程序。请重新构建或安装栖集，再重新检测。"))
                        .font(AppFont.secondary).foregroundStyle(.orange)
                    Button(L10n.tr("重新检测")) { refreshRevision += 1 }
                        .disabled(model.isRefreshingAIAccess)
                }
                if let draft = installation?.draft(host: host, scope: scope, paths: model.runtimePaths) {
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
                        _ = model.prepareAIAccess(host: host, scope: scope)
                    }
                    .buttonStyle(AppButtonStyle(kind: .primary))
                    .disabled(!canPrepare)
                    .accessibilityIdentifier("aiAccess.prepare")
                    if connection == .external || connection == .unreadable {
                        Button(L10n.tr("查看 MCP 服务")) { model.section = .mcp }
                            .buttonStyle(AppButtonStyle())
                    }
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
            scope == .project
                ? L10n.tr("将新增名为 perch 的项目级 stdio 配置，使用栖集程序的绝对路径。")
                : L10n.tr("将新增名为 perch 的用户级 stdio 配置，使用栖集程序的绝对路径。")
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
                Text(L10n.tr("从接入到可用"))
                    .font(AppFont.heading)
                Text(L10n.tr("1. 预览并批准上方接入计划，将 perch 连接写入所选工具。"))
                Text(L10n.tr("2. 重新加载 AI 工具，确认出现 perch 的工具，再试着询问："))
                Text(L10n.tr("“列出栖集的预设，搜索代码审查技能，再把我选定的技能或预设安装到当前项目。”"))
                    .textSelection(.enabled)
                    .foregroundStyle(AppColor.accentText)
                Text(L10n.tr("3. 涉及项目写入时，先让 AI 生成计划，再回到本机审阅并批准。"))
                Text(L10n.tr("配置写入后，仍需在 AI 工具中确认加载。服务会按需启动，无需一直开着终端。"))
                    .font(AppFont.secondary)
                    .foregroundStyle(.secondary)
                Divider()
                HStack(alignment: .top) {
                    Text(L10n.tr("要连接其他 MCP 服务？在 MCP 配置库保存连接，再选择使用范围。"))
                        .font(AppFont.secondary).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.tr("打开 MCP 配置库")) { model.section = .mcp }
                }
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
                            .buttonStyle(AppButtonStyle())
                    }
                }
            }
        }
    }

    private var technicalDetails: some View {
        DisclosureGroup(L10n.tr("工具与兼容性详情"), isExpanded: $showTechnicalDetails) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("目前仅验证了 stdio 连接与 2025-11-25 版本协议；其他连接方式和 AI 工具兼容性仍待验证。"))
                Text(L10n.tr("提供技能库、片段、预设、来源、项目和 MCP 配置库的管理，以及项目与全局应用计划等 59 个工具；实际列表以 AI 工具发现的结果为准。"))
                Text(L10n.tr("AI 可以生成计划和执行已批准的计划；MCP 不提供批准工具。"))
            }
            .font(AppFont.secondary)
            .foregroundStyle(.secondary)
            .padding(.top, 10)
        }
        .font(AppFont.secondary)
    }
}
