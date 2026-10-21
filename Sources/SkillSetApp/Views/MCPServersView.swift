import SwiftUI
import SkillSetCore

struct MCPServersView: View {
    @Bindable var model: AppModel
    @State private var configPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                eyebrow: "MCP SERVERS",
                title: L10n.tr("管理 AI 工具的 MCP 服务"),
                detail: L10n.tr("查看 Codex 和 Claude Code 的 MCP 配置。修改前先生成计划，等你在本机批准；不会读取凭据值或启动服务。")
            )
            HStack(spacing: 8) {
                StatusBadge(text: L10n.tr("\(model.mcpConfigInspections.count) 个配置目标"), tone: .accent)
                StatusBadge(text: L10n.tr("\(model.mcpServers.count) 个服务"), tone: .neutral)
                StatusBadge(text: L10n.tr("未知条目只观察"), tone: .warning)
                StatusBadge(text: L10n.tr("凭据只保留引用"), tone: .positive)
                Spacer()
                Button {
                    configPresented = true
                } label: {
                    Label(L10n.tr("添加 MCP 服务"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.accent)
            }
            HStack(alignment: .top, spacing: AppLayout.columnSpacing) {
                serverList
                    .frame(width: AppLayout.listWidth)
                serverDetail
            }
        }
        .sheet(isPresented: $configPresented) {
            MCPConfigSheet(model: model)
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
                Text(L10n.tr("宿主观察"))
                    .font(AppFont.heading)
                if model.mcpServers.isEmpty {
                    Text(L10n.tr("还没有 MCP 服务。点击「添加 MCP 服务」开始配置。"))
                        .font(AppFont.secondary)
                        .foregroundStyle(.secondary)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(model.mcpServers) { server in
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
                                        text: L10n.text(server.state),
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
                Text(L10n.tr("「管理器受管」表示配置由本应用管理，不代表 AI 工具已经加载服务。"))
                    .font(AppFont.secondary)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var serverDetail: some View {
        if let server = model.selectedMCP {
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
                                StatusBadge(text: L10n.text(server.state), tone: .warning)
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
                                Text(L10n.tr("streamable-http · URL 和 OAuth 由宿主维护"))
                                    .font(AppFont.code)
                                    .foregroundStyle(.secondary)
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
                                .buttonStyle(.borderedProminent)
                                .tint(AppColor.accent)
                                if server.state == "仅观察" {
                                    Text(L10n.tr("现有配置不属于管理器；同名新增会阻塞。"))
                                        .font(AppFont.secondary)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Text(L10n.tr("Codex 只替换带 skillset 标记的 TOML 块；Claude JSON 保留未知键但会按 JSON 重排对象键。两类配置不会跨宿主复制。"))
                                .font(AppFont.secondary)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } else {
            EmptyState(icon: "point.3.connected.trianglepath.dotted", title: L10n.tr("选择一个 MCP 服务"), detail: L10n.tr("左侧条目展示管理器可观察的配置边界。"))
        }
    }
}

struct MCPConfigSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    // 默认宿主是 Codex，其项目作用域不受支持，必须从可见的用户选项开始。
    @State private var draft = MCPConfigurationDraft(scope: .user)
    @State private var showValidation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("生成 MCP 配置计划"))
                        .font(AppFont.title.weight(.bold))
                    Text(L10n.tr("只填写结构化字段和环境变量名称；批准前不会修改宿主配置。"))
                        .font(AppFont.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: L10n.tr("计划模式"), tone: .warning)
            }
            Form {
                TextField(L10n.tr("名称"), text: $draft.name)
                Picker(L10n.tr("宿主"), selection: $draft.host) {
                    ForEach(MCPHost.allCases) { host in
                        Text(host.displayName).tag(host)
                    }
                }
                .onChange(of: draft.host) {
                    if draft.host == .codex {
                        draft.scope = .user
                    }
                }
                Picker(L10n.tr("作用域"), selection: $draft.scope) {
                    if draft.host == .claudeCode {
                        Text(L10n.tr("项目")).tag(MCPConfigurationScope.project)
                    }
                    Text(L10n.tr("用户")).tag(MCPConfigurationScope.user)
                }
                Picker(L10n.tr("连接方式"), selection: $draft.transport) {
                    Text("stdio").tag("stdio")
                    Text("streamable-http").tag("streamable-http")
                }
                TextField(
                    draft.transport == "stdio" ? L10n.tr("启动命令") : "URL",
                    text: $draft.commandOrURL
                )
                TextField(L10n.tr("参数（空格分隔）"), text: Binding(
                    get: { draft.args.joined(separator: " ") },
                    set: { draft.args = $0.split(separator: " ").map(String.init) }
                ))
                TextField(L10n.tr("环境变量名称（逗号分隔）"), text: Binding(
                    get: { draft.envKeys.joined(separator: ", ") },
                    set: { draft.envKeys = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                ))
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
                Label(L10n.tr("项目作用域需要先在项目页登记并选择项目。"), systemImage: "exclamationmark.triangle")
                    .font(AppFont.secondary)
                    .foregroundStyle(.orange)
            }
            if draft.host == .codex && draft.scope == .project {
                Label(L10n.tr("当前只支持 Codex 用户级 config.toml；项目级请选 Claude。"), systemImage: "info.circle")
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
                    if model.makeMCPConfigPlan(draft) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.accent)
            }
        }
        .padding(26)
        .frame(width: 560, height: 520)
    }
}

