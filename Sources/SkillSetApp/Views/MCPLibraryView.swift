import SwiftUI
import SkillSetCore

struct MCPServersView: View {
    @Bindable var model: AppModel
    @State private var tab = "library"
    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var editor: MCPLibraryEntry?
    @State private var usingEntry: MCPLibraryEntry?
    @State private var deleting: MCPLibraryEntry?
    @State private var scanPresented = false
    @State private var pendingPlan = false
    @State private var savedFeedback = false
    private var library: MCPLibraryModel { model.mcpLibrary }
    private var filtered: [MCPLibraryEntry] {
        library.entries.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.commandOrURL.localizedCaseInsensitiveContains(query) }
    }
    private var selectedEntry: MCPLibraryEntry? {
        filtered.first(where: { $0.id == selectedID }) ?? filtered.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AppSegmentedPicker(title: L10n.tr("MCP 服务"), selection: $tab,
                options: [("library", L10n.tr("配置库")), ("observed", L10n.tr("AI 工具中的配置"))])
            .frame(maxWidth: 360)
            if tab == "observed" { MCPObservedServersView(model: model) }
            else { libraryContent }
        }
        .task { library.refresh(); await library.refreshUsageInBackground() }
        .sheet(item: $editor) { entry in
            MCPLibraryEditorSheet(library: library, entry: entry) { saved in
                query = ""; selectedID = saved.id; savedFeedback = true
                library.refreshUsage()
            }
        }
        .sheet(isPresented: $scanPresented, onDismiss: {
            if let id = library.lastImportedIDs.first { query = ""; selectedID = id; savedFeedback = true }
            library.refreshUsage()
        }) { MCPLibraryScanSheet(library: library) }
        .sheet(item: $usingEntry, onDismiss: {
            if pendingPlan { pendingPlan = false; model.planPresented = true }
        }) { entry in
            MCPLibraryUseSheet(model: model, entry: entry) { plan in
                model.preparedPlan = plan
                pendingPlan = true
            }
        }
        .onChange(of: model.planPresented) { _, presented in if !presented { library.refreshUsage() } }
        .confirmationDialog(L10n.tr("从配置库删除服务？"), isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button(L10n.tr("删除"), role: .destructive) {
                if let deleting { library.remove(deleting) }
                deleting = nil
            }
            Button(L10n.tr("先不删"), role: .cancel) { deleting = nil }
        } message: {
            Text(L10n.tr("已写入的连接会保留。要移除连接，请到全局配置或项目中取消选择，再预览并保存。"))
        }
        .appControls()
    }

    private var libraryContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageActionHeader(eyebrow: "MCP LIBRARY", title: L10n.tr("MCP 配置库"),
                detail: L10n.tr("保存常用连接，在「全局配置」或「项目」中选择服务，预览后写入 AI 工具配置。")) {
                Button(L10n.tr("扫描已有配置…")) { library.scan(); scanPresented = true }
                    .accessibilityIdentifier("mcp.library.scan")
                Button { savedFeedback = false; editor = MCPLibraryEntry() } label: {
                    Label(L10n.tr("添加 MCP 服务"), systemImage: "plus")
                }
                .buttonStyle(AppButtonStyle(kind: .primary))
                .accessibilityIdentifier("mcp.library.add")
            }
            HStack {
                Text(L10n.tr("\(library.entries.count) 个服务")).font(AppFont.secondary).foregroundStyle(.secondary)
                Spacer()
            }
            if let error = library.error { Text(L10n.text(error)).foregroundStyle(.red) }
            HStack(alignment: .top, spacing: AppLayout.columnSpacing) {
                libraryList.frame(width: AppLayout.listWidth)
                if let entry = selectedEntry {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            connectionDetail(entry)
                            usageDetail(entry)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyState(icon: "point.3.connected.trianglepath.dotted", title: L10n.tr("添加可复用的 MCP 配置"),
                        detail: L10n.tr("点击「添加 MCP 服务」，或「扫描已有配置」加入服务。"))
                }
            }
        }
    }

    private var libraryList: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                AppSearchField(query: $query, prompt: L10n.tr("搜索名称或命令"),
                    label: L10n.tr("搜索 MCP 服务"), identifier: "mcp.library.search")
                if filtered.isEmpty {
                    Text(L10n.tr("没有匹配的服务，请调整搜索；也可添加服务或扫描已有配置。"))
                        .font(AppFont.secondary).foregroundStyle(.secondary)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filtered) { entry in
                            Button { selectedID = entry.id; savedFeedback = false } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(entry.name).font(AppFont.body.weight(.semibold)).foregroundStyle(.primary)
                                    Text(MCPConnectionFields.transportTitle(entry.transport))
                                        .font(AppFont.secondary).foregroundStyle(.secondary)
                                    let count = library.usageTargets.filter { $0.references(entry) }.count
                                    Text(library.usageError == nil ? L10n.tr("\(count) 个配置范围") : L10n.tr("使用范围暂不可读"))
                                        .font(AppFont.metadata).foregroundStyle(.secondary)
                                }
                                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .selectionRow(selectedEntry?.id == entry.id).contentShape(Rectangle())
                            }.buttonStyle(AppPressButtonStyle())
                            .accessibilityIdentifier("mcp.library.entry.\(entry.id)")
                        }
                    }
                }
            }
        }
    }

    private func connectionDetail(_ entry: MCPLibraryEntry) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(entry.name).font(AppFont.title)
                if savedFeedback {
                    Label(L10n.tr("已保存在配置库，下一步选择使用范围。"), systemImage: "checkmark.circle")
                        .font(AppFont.secondary).foregroundStyle(AppColor.positive)
                }
                MCPConnectionFields(entry: entry)
                Button(L10n.tr("用于配置…")) { library.refreshUsage(); usingEntry = entry }
                    .buttonStyle(AppButtonStyle(kind: .primary))
                    .accessibilityIdentifier("mcp.library.use")
                HStack {
                    Button(L10n.tr("编辑…")) { savedFeedback = false; editor = entry }
                    Button(L10n.tr("删除…"), role: .destructive) { deleting = entry }
                }
                Text(L10n.tr("保存和编辑只改变配置库。已有连接需要重新预览并批准更新。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func usageDetail(_ entry: MCPLibraryEntry) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.tr("使用范围")).font(AppFont.heading)
                let usages = library.usageTargets.filter { $0.references(entry) }
                if let error = library.usageError {
                    Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.orange)
                } else if usages.isEmpty {
                    Text(L10n.tr("还没有使用这项服务，点击「用于配置…」选择使用范围。"))
                        .font(AppFont.secondary).foregroundStyle(.secondary)
                }
                ForEach(usages) { usage in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(usage.host.displayName + " · " + (usage.projectName ?? L10n.tr("全局配置")))
                            .font(AppFont.body.weight(.semibold))
                        HStack {
                            if usage.selectedIDs.contains(entry.id) { StatusBadge(text: L10n.tr("草稿已选择"), tone: .accent) }
                            if usage.appliedEntries.contains(where: { $0.id == entry.id }) {
                                StatusBadge(text: L10n.tr("有写入记录"), tone: .neutral)
                            }
                        }
                        Text(usage.configPath).font(AppFont.code).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if let issue = usage.issue { Text(L10n.text(issue)).font(AppFont.secondary).foregroundStyle(.orange) }
                        Button(L10n.tr("查看这份配置")) {
                            if let projectID = usage.projectID {
                                model.selectedProjectID = projectID.uuidString
                                model.selectProjectHost(usage.host == .codex ? .codex : .claude)
                                model.section = .projects
                            } else {
                                model.globalConfiguration.selectHost(SkillConfigurationTarget(usage.host)); model.section = .globalConfiguration
                            }
                        }
                    }
                    Divider()
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MCPConnectionFields: View {
    let entry: MCPLibraryEntry

    static func transportTitle(_ transport: String) -> String {
        L10n.tr(transport == "stdio" ? "本机进程 · stdio" : "远程地址 · HTTP")
    }

    private var endpoint: String {
        guard entry.transport != "stdio" else {
            return MCPConnectionSafety.containsCredential([entry.commandOrURL]) ? L10n.tr("已隐藏敏感内容") : entry.commandOrURL
        }
        guard var url = URLComponents(string: entry.commandOrURL) else { return entry.commandOrURL }
        // 地址摘要不展示认证字段；完整表单只用于用户主动编辑。
        url.user = nil; url.password = nil; url.query = nil; url.fragment = nil
        return url.string ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            field(L10n.tr("连接方式"), value: Self.transportTitle(entry.transport))
            field(L10n.tr(entry.transport == "stdio" ? "启动命令" : "服务地址"), value: endpoint, code: true)
            if entry.transport == "stdio" {
                DisclosureGroup(L10n.tr("\(entry.args.count) 个启动参数")) {
                    if entry.args.isEmpty {
                        Text(L10n.tr("未设置")).font(AppFont.secondary).foregroundStyle(.secondary)
                    } else if let arguments = Self.visibleArguments(entry) {
                        Text(arguments.joined(separator: "\n")).font(AppFont.code).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(L10n.tr("参数可能含凭据，已隐藏。请编辑配置并改用环境变量引用。"))
                            .font(AppFont.secondary).foregroundStyle(.orange)
                    }
                }.font(AppFont.secondary)
            }
            field(L10n.tr("环境变量名称"), value: entry.envKeys.isEmpty ? L10n.tr("未设置") : entry.envKeys.joined(separator: "、"), code: !entry.envKeys.isEmpty)
        }
    }

    static func visibleArguments(_ entry: MCPLibraryEntry) -> [String]? {
        MCPConnectionSafety.containsCredential(entry.args) ? nil : entry.args
    }

    private func field(_ label: String, value: String, code: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(AppFont.metadata).foregroundStyle(.secondary)
            Text(value).font(code ? AppFont.code : AppFont.body).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MCPLibraryUseSheet: View {
    @Bindable var model: AppModel
    let entry: MCPLibraryEntry
    let onPlan: (StoredDeploymentPlan) -> Void
    @State private var targetID = ""
    @State private var overwriteConfirmationPresented = false
    @Environment(\.dismiss) private var dismiss
    private var library: MCPLibraryModel { model.mcpLibrary }
    private var target: MCPLibraryUsageTarget? { library.usageTargets.first { $0.id == targetID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("选择 MCP 使用范围")).font(AppFont.title)
            Text(entry.name).font(AppFont.heading)
            AppPicker(title: L10n.tr("目标配置"), selection: $targetID, valueLabel: target.map(targetTitle) ?? L10n.tr("请选择")) {
                ForEach(library.usageTargets) { target in Text(targetTitle(target)).tag(target.id) }
            }
            if let target {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(L10n.tr(target.projectID == nil
                            ? "影响所选 AI 工具的全部项目。"
                            : "仅写入所选项目；全局 MCP 配置仍可能生效。"), systemImage: target.projectID == nil ? "globe" : "folder")
                            .font(AppFont.secondary).foregroundStyle(target.projectID == nil ? .orange : .secondary)
                        if target.host == .codex && target.projectID != nil {
                            Text(L10n.text(MCPConfigurationTarget.codexProjectTrustNotice))
                                .font(AppFont.secondary).foregroundStyle(.orange)
                        }
                        Text(L10n.tr("配置文件")).font(AppFont.heading)
                        Text(target.configPath).font(AppFont.code).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Divider()
                        Text(L10n.tr("本次会预览这个范围的全部 MCP 草稿选择。"))
                            .font(AppFont.secondary).foregroundStyle(.secondary)
                        let names = library.entries.filter { target.selectedIDs.contains($0.id) || $0.id == entry.id }.map(\.name)
                        Text(names.joined(separator: "、")).font(AppFont.body).textSelection(.enabled)
                        if target.observedNames.contains(entry.name) && !target.appliedEntries.contains(where: { $0.id == entry.id }) {
                            Label(L10n.tr("目标配置已有同名连接，预览会检查归属并阻止覆盖。"), systemImage: "exclamationmark.triangle")
                                .font(AppFont.secondary).foregroundStyle(.orange)
                        }
                        if let issue = target.issue { Text(L10n.text(issue)).font(AppFont.secondary).foregroundStyle(.orange) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let error = library.error ?? library.usageError {
                Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red)
            }
            Text(L10n.tr("预览失败或取消审批时，已保存的草稿会保留；配置文件不会写入。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            HStack {
                Button(L10n.tr("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.tr("加入草稿并预览…")) {
                    guard let target else { return }
                    if target.observedNames.contains(entry.name) &&
                        !target.appliedEntries.contains(where: { $0.name == entry.name }) {
                        overwriteConfirmationPresented = true
                    } else {
                        prepareUse(target: target)
                    }
                }
                .buttonStyle(AppButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
                .disabled(target == nil || model.isWorking)
                .accessibilityIdentifier("mcp.library.use.preview")
            }
        }
        .confirmationDialog(L10n.tr("覆盖已有的同名 MCP 服务？"), isPresented: $overwriteConfirmationPresented,
                            titleVisibility: .visible) {
            Button(L10n.tr("覆盖并预览"), role: .destructive) {
                guard let target else { return }
                library.approveExternalOverwrite(host: target.host, projectID: target.projectID, names: [entry.name])
                prepareUse(target: target)
            }
            Button(L10n.tr("先不覆盖"), role: .cancel) {}
        } message: {
            let path = target?.configPath ?? L10n.tr("目标配置")
            Text(L10n.tr("将替换 \(entry.name) 在 \(path) 中的现有内容。原文件会按计划保留备份；如果文件在审批前发生变化，计划会失效。"))
        }
        .appControls().padding(26).frame(width: 660, height: 580)
        .onAppear {
            targetID = library.initialUsageTargetID(fallbackHost: model.globalConfiguration.host.mcpHost ?? .codex)
        }
    }

    private func prepareUse(target: MCPLibraryUsageTarget) {
        guard let plan = library.prepareUse(entry, host: target.host, projectID: target.projectID) else { return }
        onPlan(plan)
        dismiss()
    }

    private func targetTitle(_ target: MCPLibraryUsageTarget) -> String {
        target.host.displayName + " · " + (target.projectName ?? L10n.tr("全局配置"))
    }
}
