import SwiftUI
import SkillSetCore

struct MCPObservedServersView: View {
    @Bindable var model: AppModel
    @State private var configPresented = false
    @State private var editingServer: MCPObservedServer?
    @State private var deletingServer: MCPObservedServer?
    @State private var query = ""

    private var filteredServers: [MCPServerRecord] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.mcpServers.filter {
            term.isEmpty || [$0.name, $0.host, $0.scope, $0.command].contains {
                $0.localizedCaseInsensitiveContains(term)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                eyebrow: "MCP SERVERS",
                title: L10n.tr("AI 工具中的 MCP 配置"),
                detail: L10n.tr("查看 Codex 和 Claude Code 的 MCP 配置。修改前先生成计划，等你在本机批准；不会读取凭据值或启动服务。")
            )
            HStack(spacing: 8) {
                Text(L10n.tr("\(model.mcpConfigInspections.count) 个配置目标 · \(model.mcpServers.count) 个服务"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
                Spacer()
                Button {
                    editingServer = nil
                    configPresented = true
                } label: {
                    Label(L10n.tr("直接配置连接…"), systemImage: "plus")
                }
                .buttonStyle(AppButtonStyle(kind: .primary))
                .tint(AppColor.accent)
            }
            if let project = model.selectedProject {
                Text(L10n.tr("显示全局配置与项目：\(project.name)"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            } else {
                Text(L10n.tr("当前显示全局配置；选择项目后可查看对应的项目连接。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: AppLayout.columnSpacing) {
                serverList
                    .frame(width: AppLayout.listWidth)
                serverDetail
            }
        }
        .sheet(isPresented: $configPresented) {
            MCPConfigSheet(model: model, existingServer: editingServer)
        }
        .confirmationDialog(L10n.tr("删除 MCP 服务？"), isPresented: Binding(
            get: { deletingServer != nil }, set: { if !$0 { deletingServer = nil } }
        ), titleVisibility: .visible) {
            if let server = deletingServer {
                Button(L10n.tr("生成删除计划"), role: .destructive) {
                    model.removeMCPServer(server)
                    deletingServer = nil
                }
            }
            Button(L10n.tr("取消"), role: .cancel) { deletingServer = nil }
        } message: {
            Text(L10n.tr("只移除选中的服务配置，不卸载程序。预览并批准计划后才会写入；用户级配置会影响该工具的全部项目。"))
        }
        .task {
            model.refreshMCPConfigurations()
        }
        .onChange(of: model.selectedProjectID) {
            model.refreshMCPConfigurations()
        }
    }

    private var serverList: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.tr("已发现的服务"))
                    .font(AppFont.heading)
                AppSearchField(query: $query, prompt: L10n.tr("搜索名称、工具或路径"),
                               label: L10n.tr("搜索 MCP 服务"), identifier: "mcp.search")
                if filteredServers.isEmpty {
                    Text(query.isEmpty ? L10n.tr("尚未发现连接。可以直接配置连接，或到配置库添加可复用服务。") : L10n.tr("没有匹配的 MCP 服务，请调整搜索条件。"))
                        .font(AppFont.secondary)
                        .foregroundStyle(.secondary)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(filteredServers) { server in
                            Button {
                                model.selectedMCPID = server.id
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: server.id == model.selectedMCPID ? "point.3.connected.trianglepath.dotted" : "point.3.connected.trianglepath.dotted")
                                        .foregroundStyle(server.id == model.selectedMCPID ? AppColor.accentText : .secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(server.name)
                                            .font(AppFont.body.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text("\(server.host) · \(UserFacingText.localizedScope(server.scope))")
                                            .font(AppFont.secondary)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    StatusBadge(
                                        text: L10n.text(UserFacingText.mcpState(server.state)),
                                        tone: server.state == "管理器受管" ? .positive : .warning
                                    )
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 6)
                                .selectionRow(server.id == model.selectedMCPID)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Divider()
                Text(L10n.tr("「由栖集管理」表示配置由栖集写入，仍需在 AI 工具中确认服务是否加载。"))
                    .font(AppFont.secondary)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var serverDetail: some View {
        if let server = model.selectedMCP, filteredServers.contains(where: { $0.id == server.id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SurfaceCard(emphasis: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(server.name)
                                        .font(AppFont.title.weight(.bold))
                                    Text(L10n.text(server.note))
                                        .font(AppFont.body)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                StatusBadge(text: L10n.text(UserFacingText.mcpState(server.state)), tone: .warning)
                            }
                            Divider()
                            HStack(spacing: 8) {
                                StatusBadge(text: server.transport, tone: .accent)
                                StatusBadge(text: UserFacingText.localizedScope(server.scope), tone: .neutral)
                                StatusBadge(text: server.host, tone: .neutral)
                            }
                        }
                    }
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.tr("连接预览"))
                                .font(AppFont.heading)
                            if server.transport == "stdio" {
                                Text(model.mcpCommandPreview(server))
                                    .font(AppFont.code)
                                    .foregroundStyle(AppColor.ink)
                                    .textSelection(.enabled)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                            } else {
                                Text(server.command)
                                    .font(AppFont.code)
                                    .textSelection(.enabled)
                            }
                            if !server.envKeys.isEmpty {
                                Label(L10n.tr("环境变量引用：\(server.envKeys.joined(separator: "、"))（只保存名称）"), systemImage: "key")
                                    .font(AppFont.secondary)
                                    .foregroundStyle(.secondary)
                            }
                            Text(L10n.text(server.note))
                                .font(AppFont.secondary)
                                .foregroundStyle(.secondary)
                        }
                    }
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.tr("操作"))
                                .font(AppFont.heading)
                            HStack {
                                Button(L10n.tr("重新扫描")) {
                                    model.refreshMCPStatus(server)
                                }
                                .buttonStyle(AppButtonStyle(kind: .primary))
                                .tint(AppColor.accent)
                                if let observed = model.selectedMCPObservation {
                                    Button(L10n.tr("编辑…")) {
                                        editingServer = observed
                                        configPresented = true
                                    }
                                    .accessibilityIdentifier("mcp.edit")
                                    Button(L10n.tr("删除…"), role: .destructive) {
                                        deletingServer = observed
                                    }
                                    .accessibilityIdentifier("mcp.delete")
                                }
                            }
                            Text(L10n.tr("编辑和删除只影响选中的服务，保留其他配置。用户级配置会影响该工具的全部项目；修改前须预览并批准计划。"))
                                .font(AppFont.secondary)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } else {
            EmptyState(icon: "point.3.connected.trianglepath.dotted", title: L10n.tr("选择一个 MCP 服务"), detail: L10n.tr("从左侧选择服务查看配置，或点击「直接配置连接…」创建待批准计划。"))
        }
    }
}

struct MCPConfigSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    // 默认宿主是 Codex，其项目作用域不受支持，必须从可见的用户选项开始。
    @State private var draft = MCPConfigurationDraft(scope: .user)
    @State private var showValidation = false
    @State private var replaceArguments = false
    let existingServer: MCPObservedServer?

    init(model: AppModel, existingServer: MCPObservedServer? = nil) {
        self.model = model
        self.existingServer = existingServer
        if let server = existingServer {
            _draft = State(initialValue: MCPConfigurationDraft(name: server.name, host: server.host,
                scope: server.scope, transport: server.transport, commandOrURL: server.command))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("生成 MCP 配置计划"))
                        .font(AppFont.title.weight(.bold))
                    Text(L10n.tr("填写连接信息和环境变量名称。先预览计划，批准后才会修改 AI 工具配置。"))
                        .font(AppFont.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: L10n.tr("计划模式"), tone: .warning)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    AppFormField(L10n.tr("名称")) {
                        TextField("my-server", text: $draft.name)
                            .accessibilityLabel(L10n.tr("名称"))
                            .accessibilityIdentifier("mcp.config.name")
                            .disabled(existingServer != nil)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        AppPicker(title: L10n.tr("AI 工具"), selection: $draft.host, valueLabel: draft.host.displayName) {
                            ForEach(MCPHost.allCases) { host in
                                Text(host.displayName).tag(host)
                            }
                        }
                        .accessibilityIdentifier("mcp.config.host")
                        .disabled(existingServer != nil)
                        .onChange(of: draft.host) {
                            if draft.host == .codex { draft.scope = .user }
                        }
                        AppPicker(title: L10n.tr("使用范围"), selection: $draft.scope, valueLabel: L10n.text(draft.scope.displayName)) {
                            if draft.host == .claudeCode { Text(L10n.tr("项目")).tag(MCPConfigurationScope.project) }
                            Text(L10n.tr("用户")).tag(MCPConfigurationScope.user)
                        }
                        .accessibilityIdentifier("mcp.config.scope")
                        .disabled(existingServer != nil)
                    }
                    AppPicker(title: L10n.tr("连接方式"), selection: $draft.transport, valueLabel: draft.transport) {
                        Text("stdio").tag("stdio")
                        Text("streamable-http").tag("streamable-http")
                    }
                    .accessibilityIdentifier("mcp.config.transport")
                    .disabled(existingServer != nil)
                    AppFormField(draft.transport == "stdio" ? L10n.tr("启动命令") : "URL") {
                        TextField(draft.transport == "stdio" ? "/path/to/server" : "https://example.com/mcp", text: $draft.commandOrURL)
                            .accessibilityLabel(draft.transport == "stdio" ? L10n.tr("启动命令") : "URL")
                            .accessibilityIdentifier("mcp.config.command")
                    }
                    if existingServer != nil {
                        Toggle(L10n.tr("替换启动参数"), isOn: $replaceArguments)
                        Text(L10n.tr("默认保留现有参数、环境变量和其他配置；开启替换后，空参数表示清空。"))
                            .font(AppFont.secondary)
                    }
                    if existingServer == nil || replaceArguments {
                        AppFormField(L10n.tr("参数（每行一个，保留参数内空格）")) {
                            TextField("--option", text: Binding(
                                get: { draft.args.joined(separator: "\n") },
                                set: { draft.args = $0.components(separatedBy: "\n").filter { !$0.isEmpty } }
                            ), axis: .vertical)
                            .accessibilityLabel(L10n.tr("参数（每行一个，保留参数内空格）"))
                        }
                    }
                    if existingServer == nil {
                        AppFormField(L10n.tr("环境变量名称（逗号分隔）")) {
                            TextField("API_TOKEN", text: Binding(
                                get: { draft.envKeys.joined(separator: ", ") },
                                set: { draft.envKeys = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                            ))
                            .accessibilityLabel(L10n.tr("环境变量名称（逗号分隔）"))
                        }
                    }
                }
                .padding(2)
            }
            if showValidation && !draft.validationIssues().isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(draft.validationIssues(), id: \.self) {
                        Label(L10n.text($0), systemImage: "exclamationmark.triangle")
                    }
                }
                .font(AppFont.secondary)
                .foregroundStyle(.red)
            }
            if draft.scope == .project && model.selectedProjectID.isEmpty {
                Label(L10n.tr("请先到「项目」添加并选择一个项目，再配置项目连接。"), systemImage: "exclamationmark.triangle")
                    .font(AppFont.secondary)
                    .foregroundStyle(.orange)
            }
            if draft.host == .codex && draft.scope == .project {
                Label(L10n.tr("Codex 目前只支持用户级配置；项目连接请选择 Claude Code。"), systemImage: "info.circle")
                    .font(AppFont.secondary)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack {
                Spacer()
                Button(L10n.tr("取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.tr("生成配置计划")) {
                    showValidation = true
                    guard draft.validationIssues().isEmpty else { return }
                    if model.makeMCPConfigPlan(draft, existingServer: existingServer, replaceArguments: replaceArguments) {
                        dismiss()
                    }
                }
                .buttonStyle(AppButtonStyle(kind: .primary))
                .tint(AppColor.accent)
            }
        }
        .appControls()
        .padding(26)
        .frame(width: 600, height: 620)
    }
}

