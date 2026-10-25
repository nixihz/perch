import SwiftUI
import SkillSetCore

struct PresetEditorSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PresetEditorDraft
    @State private var category: PresetComponent = .skills
    @State private var search = ""
    @State private var confirmDiscard = false
    @State private var mcpEditor: MCPEditRequest?
    @FocusState private var nameFocused: Bool
    private let initial: PresetEditorDraft

    init(model: AppModel, draft: PresetEditorDraft) {
        self.model = model
        self.initial = draft
        _draft = State(initialValue: draft)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.tr(initial.name.isEmpty ? "新建预设" : "编辑预设")).font(AppFont.title)
                    Text(L10n.tr("把常用组件整理成组合，随时载入项目草稿。"))
                        .font(AppFont.secondary).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 6) {
                    ForEach(PresetComponent.allCases) { item in
                        Button { category = item } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.icon).frame(width: 20)
                                Text(L10n.text(item.title)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                Spacer()
                                Text("\(count(item))").monospacedDigit().foregroundStyle(.secondary)
                            }
                            .font(AppFont.secondary.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(12).selectionRow(item == category)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("presets.editor.category.\(item.rawValue)")
                    }
                    Spacer()
                    Text(L10n.tr("保存预设只保存组合，不会安装插件或修改项目文件。"))
                        .font(AppFont.metadata).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).padding(10)
                }
                .padding(12).frame(width: 210)
                .background(AppColor.surface.opacity(0.6))
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField(L10n.tr("预设名称"), text: $draft.name)
                            .textFieldStyle(AppTextFieldStyle())
                            .focused($nameFocused).accessibilityIdentifier("presets.editor.name")
                        TextField(L10n.tr("说明（可选）"), text: $draft.description, axis: .vertical)
                            .textFieldStyle(AppTextFieldStyle()).lineLimit(2...3)
                            .accessibilityIdentifier("presets.editor.description")
                    }
                    Divider()
                    HStack {
                        Label(L10n.text(category.title), systemImage: category.icon).font(AppFont.heading)
                        Spacer()
                        Text(L10n.tr("已选 \(count(category)) 项")).font(AppFont.secondary).foregroundStyle(.secondary)
                        if category == .mcp {
                            Button { mcpEditor = MCPEditRequest() } label: {
                                Label(L10n.tr("添加 MCP 服务"), systemImage: "plus")
                                    .frame(minHeight: 32)
                                    .contentShape(Rectangle())
                            }
                                .help(L10n.tr("添加 MCP 服务"))
                                .accessibilityLabel(L10n.tr("添加 MCP 服务"))
                                .accessibilityIdentifier("presets.editor.addMCP")
                        }
                    }
                    if category == .skills {
                        AppSearchField(query: $search, prompt: L10n.tr("搜索技能、来源或路径"),
                                       label: L10n.tr("搜索技能"), identifier: "presets.editor.search")
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            switch category {
                            case .skills: skills
                            case .plugins: plugins
                            case .mcp: servers
                            case .instructions: instructions
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 8)
                    }
                    .id(category)
                }
                .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                let reasons = draftBlockingReasons
                if !reasons.isEmpty {
                    ForEach(Array(reasons.enumerated()), id: \.offset) { _, reason in
                        Label(L10n.tr(reason), systemImage: "exclamationmark.circle")
                            .font(AppFont.secondary).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let error = model.presetError {
                    Label(L10n.tr(error), systemImage: "exclamationmark.circle")
                        .font(AppFont.secondary).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Text(L10n.tr("共 \(draft.record.componentCount) 项内容"))
                        .font(AppFont.secondary).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.tr("取消")) { cancel() }.keyboardShortcut(.cancelAction)
                    Button(L10n.tr("保存预设")) {
                        if model.savePreset(draft) { dismiss() }
                    }
                    .buttonStyle(AppButtonStyle(kind: .primary)).keyboardShortcut("s", modifiers: .command)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.record.componentCount == 0)
                    .accessibilityIdentifier("presets.editor.save")
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .appControls()
        .frame(width: 900, height: 670).background(.regularMaterial)
        .disclosureGroupStyle(FullRowDisclosureGroupStyle())
        .defaultFocus($nameFocused, true)
        .interactiveDismissDisabled(draft != initial)
        .onChange(of: draft) { _, _ in model.presetError = nil }
        .confirmationDialog(L10n.tr("放弃未保存的修改？"), isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(L10n.tr("放弃修改"), role: .destructive) { dismiss() }
            Button(L10n.tr("继续编辑"), role: .cancel) {}
        }
        .sheet(item: $mcpEditor) { request in
            PresetMCPForm(initial: request.draft) { value in
                if draft.mcpServers.enumerated().contains(where: { $0.offset != request.index && $0.element.presetID == value.presetID }) {
                    return "这个连接已添加，请核对 AI 工具、使用范围和名称。"
                }
                if let index = request.index { draft.mcpServers[index] = value }
                else { draft.mcpServers.append(value) }
                return nil
            }
        }
    }

    private var skills: some View {
        let entries = matchingSkills(model.snapshot.catalog.entries, query: search, sourceOrigins: model.sourceOrigins)
        let unresolved = unresolvedSkillIDs
        return Group {
            // 当前目录没有这些标识，搜索也筛不出勾选框；不单独列出就无法从预设里拿掉。
            ForEach(unresolved, id: \.self) { id in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(unresolvedSkillTitle(id)).font(AppFont.secondary.weight(.medium))
                        Text(L10n.tr("不在技能库"))
                            .font(AppFont.metadata).foregroundStyle(.red)
                    }
                    Spacer(minLength: 12)
                    Button(L10n.tr("移除引用")) { draft.skills.remove(id) }
                        .accessibilityIdentifier("presets.editor.skill.remove.\(id)")
                }
                .help(unresolvedSkillTitle(id))
            }
            if entries.isEmpty { Text(L10n.tr("没有匹配的技能")).foregroundStyle(.secondary) }
            ForEach(entries) { skill in
                Toggle(isOn: membership(skill.id, in: $draft.skills)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(skill.declaredName).font(AppFont.secondary.weight(.medium))
                        Text(model.skillSourceTitle(skill)).font(AppFont.metadata).foregroundStyle(.secondary)
                        if skill.isBlocked { Text(L10n.tr("暂不可用")).font(AppFont.metadata).foregroundStyle(.red) }
                    }
                }
                .toggleStyle(.checkbox).disabled(skill.isBlocked && !draft.skills.contains(skill.id))
                .help(skill.declaredName).accessibilityIdentifier("presets.editor.skill.\(skill.id)")
            }
        }
    }

    private var plugins: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.tr("选择要保存的插件版本。用于项目时，再预览并批准安装或启用。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            if model.plugins.isEmpty {
                Text(L10n.tr("还没有发现插件，请先到「插件」查看本机插件。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }
            ForEach(model.plugins) { plugin in
                let selected = draft.plugins.contains { $0.host == plugin.host && $0.pluginID == plugin.pluginID && $0.manifestDigest == plugin.manifestDigest }
                Toggle(isOn: Binding(get: { selected }, set: { checked in
                    draft.plugins.removeAll { $0.host == plugin.host && $0.pluginID == plugin.pluginID }
                    if checked {
                        let scope = plugin.host == .codex ? PluginLifecycleScope.user : PluginLifecycleScope(rawValue: plugin.scope ?? "project") ?? .project
                        draft.plugins.append(PresetPluginReference(plugin: plugin, scope: scope))
                    }
                })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plugin.name).font(AppFont.secondary.weight(.medium))
                        Text("\(plugin.host.displayName) · \(plugin.version ?? String(plugin.manifestDigest.prefix(10)))")
                            .font(AppFont.metadata).foregroundStyle(.secondary)
                        Text(plugin.components.joined(separator: " · ")).font(AppFont.metadata).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox).help(plugin.name)
                if selected {
                    AppPicker(title: L10n.tr("使用范围"), selection: Binding(
                        get: { draft.plugins.first { $0.host == plugin.host && $0.pluginID == plugin.pluginID }?.scope ?? .user },
                        set: { scope in
                            if let index = draft.plugins.firstIndex(where: { $0.host == plugin.host && $0.pluginID == plugin.pluginID }) {
                                draft.plugins[index] = PresetPluginReference(plugin: plugin, scope: scope)
                            }
                        }
                    ), valueLabel: L10n.text((draft.plugins.first { $0.host == plugin.host && $0.pluginID == plugin.pluginID }?.scope ?? .user).displayName)) {
                        ForEach(PluginLifecycleScope.allCases.filter { plugin.host != .codex || $0 == .user }) { scope in
                            Text(L10n.text(scope.displayName)).tag(scope)
                        }
                    }
                    .font(AppFont.secondary).padding(.leading, 20)
                }
            }
            ForEach(draft.plugins.filter { ref in !model.plugins.contains { $0.host == ref.host && $0.pluginID == ref.pluginID && $0.manifestDigest == ref.manifestDigest } }) { ref in
                HStack {
                    Label(ref.name, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                    Spacer()
                    Button(L10n.tr("移除")) { draft.plugins.removeAll { $0.id == ref.id } }
                }
            }
        }
    }

    private var servers: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.tr("保存连接配置，用于项目时再批准写入。选择「用户」范围会影响这个 AI 工具的所有项目。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            if draft.mcpServers.isEmpty {
                EmptyState(icon: PresetComponent.mcp.icon, title: L10n.tr("还没有 MCP 服务"), detail: L10n.tr("点「添加 MCP 服务」保存连接配置。"))
            }
            ForEach(Array(draft.mcpServers.enumerated()), id: \.element.presetID) { index, server in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(server.name).font(AppFont.secondary.weight(.semibold))
                        Text("\(server.host.displayName) · \(L10n.text(server.scope.displayName)) · \(server.transport)")
                            .font(AppFont.metadata).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.tr("编辑")) { mcpEditor = MCPEditRequest(index: index, draft: server) }
                    Button(L10n.tr("移除")) { draft.mcpServers.remove(at: index) }
                }
                .padding(12).background(AppColor.surface, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.tr("选择项目要使用的规则。栖集只更新标记之间的内容，保留文件中的其他内容；Claude Code 使用 CLAUDE.md。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            ForEach(draft.instructions.filter { id in !model.snapshot.templates.contains { $0.id == id } }.sorted(), id: \.self) { id in
                HStack {
                    Text(L10n.tr("片段已删除，请移除引用后重新选择。"))
                        .font(AppFont.secondary).foregroundStyle(.red)
                    Spacer()
                    Button(L10n.tr("移除引用")) { draft.instructions.remove(id) }
                }
            }
            ForEach(model.snapshot.templates) { template in
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: membership(template.id, in: $draft.instructions)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(UserFacingText.templateTitle(template)).font(AppFont.secondary.weight(.medium))
                            Text(UserFacingText.templatePurpose(template))
                                .font(AppFont.secondary).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox).accessibilityIdentifier("presets.editor.rule.\(template.id)")
                    DisclosureGroup(L10n.tr("查看正文")) {
                        Text(template.body).font(AppFont.metadata.monospaced()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }
                    .font(AppFont.secondary).foregroundStyle(.secondary).padding(.leading, 20)
                    .accessibilityIdentifier("presets.editor.rule.details.\(template.id)")
                }
                Divider()
            }
        }
    }

    private var draftBlockingReasons: [LocalizedText] {
        let project = model.selectedProject ?? ProjectRecord.demo[0]
        return PresetDraftPreview(preset: draft.record, project: project, snapshot: model.snapshot)
            .blockingReasons(origins: model.sourceOrigins)
    }

    private func count(_ item: PresetComponent) -> Int {
        switch item {
        case .skills: draft.skills.count
        case .plugins: draft.plugins.count
        case .mcp: draft.mcpServers.count
        case .instructions: draft.instructions.count
        }
    }

    private var unresolvedSkillIDs: [String] {
        let known = Set(model.snapshot.catalog.entries.map(\.id))
        return draft.skills.subtracting(known).sorted()
    }

    private func unresolvedSkillTitle(_ id: String) -> String {
        PresetDraftPreview.referenceName(id)
    }

    private func membership(_ id: String, in values: Binding<Set<String>>) -> Binding<Bool> {
        Binding(get: { values.wrappedValue.contains(id) }, set: { value in
            if value { values.wrappedValue.insert(id) } else { values.wrappedValue.remove(id) }
        })
    }

    private func cancel() {
        if draft != initial { confirmDiscard = true } else { dismiss() }
    }
}

enum PresetComponent: String, CaseIterable, Identifiable {
    case skills, plugins, mcp, instructions
    var id: String { rawValue }
    var title: String {
        switch self { case .skills: "技能"; case .plugins: "插件"; case .mcp: "MCP 服务"; case .instructions: "AGENTS 片段" }
    }
    var icon: String {
        switch self { case .skills: "wand.and.stars"; case .plugins: "puzzlepiece.extension"; case .mcp: "point.3.connected.trianglepath.dotted"; case .instructions: "text.badge.checkmark" }
    }
}

private struct MCPEditRequest: Identifiable {
    let id = UUID()
    var index: Int? = nil
    var draft = MCPConfigurationDraft(scope: .user)
}

private struct PresetMCPForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MCPConfigurationDraft
    @State private var arguments: String
    @State private var environment: String
    @State private var error: String?
    let save: (MCPConfigurationDraft) -> String?

    init(initial: MCPConfigurationDraft, save: @escaping (MCPConfigurationDraft) -> String?) {
        _draft = State(initialValue: initial)
        _arguments = State(initialValue: initial.args.joined(separator: "\n"))
        _environment = State(initialValue: initial.envKeys.joined(separator: ", "))
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("MCP 连接配置")).font(AppFont.title)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    AppFormField(L10n.tr("名称")) {
                        TextField("my-server", text: $draft.name).accessibilityLabel(L10n.tr("名称"))
                            .accessibilityIdentifier("presets.mcp.name")
                    }
                    AppPicker(title: L10n.tr("AI 工具"), selection: $draft.host, valueLabel: draft.host.displayName) {
                        ForEach(MCPHost.allCases) { Text($0.displayName).tag($0) }
                    }
                    AppPicker(title: L10n.tr("使用范围"), selection: $draft.scope, valueLabel: L10n.text(draft.scope.displayName)) {
                        Text(L10n.tr("项目")).tag(MCPConfigurationScope.project)
                        Text(L10n.tr("用户")).tag(MCPConfigurationScope.user)
                    }
                    AppPicker(title: L10n.tr("连接方式"), selection: $draft.transport, valueLabel: draft.transport) {
                        Text("stdio").tag("stdio")
                        Text("streamable-http").tag("streamable-http")
                    }
                    AppFormField(draft.transport == "stdio" ? L10n.tr("启动命令") : "URL") {
                        TextField(draft.transport == "stdio" ? "/path/to/server" : "https://example.com/mcp", text: $draft.commandOrURL)
                            .accessibilityLabel(draft.transport == "stdio" ? L10n.tr("启动命令") : "URL")
                            .accessibilityIdentifier("presets.mcp.command")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr("启动参数（每行一项）"))
                        TextEditor(text: $arguments).font(AppFont.metadata.monospaced()).frame(height: 70).appEditorSurface()
                    }
                    AppFormField(L10n.tr("环境变量名称（逗号分隔）")) {
                        TextField("API_TOKEN", text: $environment).accessibilityLabel(L10n.tr("环境变量名称（逗号分隔）"))
                    }
                }
            }
            if draft.host == .codex && draft.scope == .project {
                Text(L10n.text(MCPConfigurationTarget.codexProjectTrustNotice))
                    .font(AppFont.secondary).foregroundStyle(.orange)
            }
            Text(L10n.tr("只填环境变量名称，不填密钥。选择「用户」范围会影响这个 AI 工具的所有项目。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            if let error { Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(L10n.tr("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("保存连接")) {
                    draft.args = arguments.components(separatedBy: "\n").filter { !$0.isEmpty }
                    draft.envKeys = environment.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    if let issue = draft.validationIssues().first { error = issue; return }
                    error = save(draft.normalized())
                    if error == nil { dismiss() }
                }
                .buttonStyle(AppButtonStyle(kind: .primary)).keyboardShortcut("s", modifiers: .command)
                .accessibilityIdentifier("presets.mcp.save")
            }
        }
        .appControls()
        .padding(24).frame(width: 560, height: 640)
    }
}
