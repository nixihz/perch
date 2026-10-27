import SwiftUI
import SkillSetCore

struct PresetEditorSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PresetEditorDraft
    private let initial: PresetEditorDraft

    init(model: AppModel, draft: PresetEditorDraft) {
        self.model = model
        self.initial = draft
        _draft = State(initialValue: draft)
    }

    var body: some View {
        PresetConfigurationEditor(model: model, draft: $draft, initial: initial, onClose: { dismiss() })
            .padding(24).frame(width: 900, height: 670).background(.regularMaterial)
            .interactiveDismissDisabled(draft != initial)
    }
}

/// 页面和新建面板共用同一编辑器；预设内容不直接写入项目或宿主。
struct PresetConfigurationEditor: View {
    @Bindable var model: AppModel
    @Binding var draft: PresetEditorDraft
    let initial: PresetEditorDraft
    var onClose: (() -> Void)? = nil
    @State private var category: PresetComponent = .skills
    @State private var search = ""
    @State private var availableHeight: CGFloat = 0
    @State private var confirmDiscard = false
    @State private var mcpEditor: MCPEditRequest?
    @State private var preview: PresetEditorDraft?
    @State private var closeAfterSave = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: availableHeight < 500 ? 4 : 14) {
            ConfigurationSectionHeader {
                Text(L10n.tr(onClose == nil ? "配置草稿" : initial.name.isEmpty ? "新建预设" : "编辑预设"))
                    .font(AppFont.heading)
            } actions: {
                Button(L10n.tr("预览")) { preview = draft }
                    .buttonStyle(AppButtonStyle(kind: .primary))
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || draft.record.componentCount == 0 || !draftBlockingReasons.isEmpty)
                    .accessibilityIdentifier("presets.editor.preview")
            }
            HStack(spacing: 10) {
                TextField(L10n.tr("预设名称"), text: $draft.name)
                    .textFieldStyle(AppTextFieldStyle()).focused($nameFocused).accessibilityIdentifier("presets.editor.name")
                TextField(L10n.tr("说明（可选）"), text: $draft.description)
                    .textFieldStyle(AppTextFieldStyle()).accessibilityIdentifier("presets.editor.description")
            }
            AppSegmentedPicker(title: L10n.tr("资源类型"), selection: $category,
                options: [PresetComponent.skills, .instructions, .mcp, .plugins].map { ($0, L10n.text($0.title)) }).accessibilityIdentifier("presets.editor.categories")
            if category == .skills {
                selectedSkillPills
            }
            HStack(spacing: 10) {
                AppSearchField(query: $search, prompt: L10n.tr("搜索名称、来源或说明"),
                    label: L10n.tr("搜索配置资源"), identifier: "presets.editor.search")
                if category == .mcp {
                    Button { mcpEditor = MCPEditRequest() } label: {
                        Label(L10n.tr("添加 MCP 服务"), systemImage: "plus")
                    }.accessibilityIdentifier("presets.editor.addMCP")
                }
            }
            HStack {
                Text(L10n.tr("勾选只改预设草稿，预览后保存；用于项目时再选择 AI 工具。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
                Spacer()
                Text(L10n.tr("已选 \(count(category)) 项")).font(AppFont.metadata).foregroundStyle(.secondary)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch category {
                    case .skills: skills
                    case .plugins: plugins
                    case .mcp: servers
                    case .instructions: instructions
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.id(category)
            if !draftBlockingReasons.isEmpty {
                ForEach(Array(draftBlockingReasons.enumerated()), id: \.offset) { _, reason in
                    Text(L10n.tr(reason)).font(AppFont.secondary).foregroundStyle(.red)
                }
            } else if let error = model.presetError {
                Text(L10n.tr(error)).font(AppFont.secondary).foregroundStyle(.red)
            } else if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(L10n.tr("请填写预设名称，并至少选择一项内容。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            } else if draft.record.componentCount == 0 {
                Text(L10n.tr("请至少选择一项内容，再预览保存。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }
            HStack {
                Text(L10n.tr("共 \(draft.record.componentCount) 项内容")).font(AppFont.secondary).foregroundStyle(.secondary)
                Spacer()
                if onClose != nil {
                    Button(L10n.tr("取消")) { cancel() }.keyboardShortcut(.cancelAction)
                } else if draft != initial {
                    Button(L10n.tr("放弃修改")) { confirmDiscard = true }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { availableHeight = $0 }
        .appControls()
        .disclosureGroupStyle(FullRowDisclosureGroupStyle())
        .onChange(of: draft) { _, _ in model.presetError = nil }
        .onAppear { if onClose != nil && initial.name.isEmpty { nameFocused = true } }
        .confirmationDialog(L10n.tr("放弃未保存的修改？"), isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(L10n.tr("放弃修改"), role: .destructive) {
                if let onClose { onClose() } else { draft = initial }
            }
            Button(L10n.tr("继续编辑"), role: .cancel) {}
        }
        .sheet(item: $preview, onDismiss: {
            if closeAfterSave { closeAfterSave = false; onClose?() }
        }) { reviewed in
            PresetSavePreview(model: model, draft: reviewed, initial: initial) {
                closeAfterSave = true
                preview = nil
            }
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("presets.configuration")
    }

    private var selectedSkillPills: some View {
        let entries = Dictionary(uniqueKeysWithValues: model.snapshot.catalog.entries.map { ($0.id, $0) })
        let items = draft.skills.map { id in
            SelectedSkillPills.Item(id: id, name: model.skillDisplayTitle(id),
                detail: entries[id].map { model.skillDisplayTitle(id) + " · " + model.skillSourceTitle($0) }
                    ?? L10n.tr("不在技能库"))
        }.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
        return SelectedSkillPills(items: items, identifierPrefix: "presets.editor", compact: availableHeight < 500, remove: { draft.skills.remove($0) })
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
            if entries.isEmpty {
                Text(L10n.tr("没有匹配的技能，请调整搜索或先到技能库添加。")).foregroundStyle(.secondary)
            }
            ForEach(entries) { skill in
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(skill.declaredName).font(AppFont.body.weight(.semibold))
                        Text(model.skillSourceTitle(skill)).font(AppFont.metadata).foregroundStyle(.secondary)
                        Text(skill.description).font(AppFont.secondary).foregroundStyle(.secondary).lineLimit(2)
                        if skill.isBlocked {
                            Text(L10n.tr("未通过文件检查，请到技能库查看原因。"))
                                .font(AppFont.secondary).foregroundStyle(.red)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    selectionButton(skill.declaredName, selected: draft.skills.contains(skill.id),
                        identifier: "presets.editor.skill.\(skill.id)") {
                        if draft.skills.contains(skill.id) { draft.skills.remove(skill.id) }
                        else { draft.skills.insert(skill.id) }
                    }.disabled(skill.isBlocked && !draft.skills.contains(skill.id))
                }.padding(.vertical, 8)
                Divider()
            }
        }
    }

    private var plugins: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.tr("选择要保存的插件版本。用于项目时，再预览并批准安装或启用。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            if model.plugins.isEmpty {
                Text(L10n.tr("还没有找到插件，请到「插件来源」扫描本机插件。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }
            if !model.plugins.isEmpty && !model.plugins.contains(where: { matches([$0.name, $0.description, $0.marketplaceID ?? ""]) }) {
                Text(L10n.tr("没有匹配的配置资源，请调整搜索。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }
            ForEach(model.plugins.filter { matches([$0.name, $0.description, $0.marketplaceID ?? ""]) }) { plugin in
                let selected = draft.plugins.contains { $0.host == plugin.host && $0.pluginID == plugin.pluginID && $0.manifestDigest == plugin.manifestDigest }
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plugin.name).font(AppFont.body.weight(.semibold))
                        Text("\(plugin.host.displayName) · \(plugin.version ?? String(plugin.manifestDigest.prefix(10)))")
                            .font(AppFont.metadata).foregroundStyle(.secondary)
                        Text(plugin.description).font(AppFont.secondary).foregroundStyle(.secondary).lineLimit(2)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    SkillHostToggles(skillName: plugin.name, identifierPrefix: "presets.editor.plugin.\(plugin.id)",
                        isSelected: { $0 == plugin.host && selected }, isEnabled: { $0 == plugin.host },
                        setSelected: { _, checked in
                            draft.plugins.removeAll { $0.host == plugin.host && $0.pluginID == plugin.pluginID }
                            if checked {
                                let scope = plugin.host == .codex ? PluginLifecycleScope.user : PluginLifecycleScope(rawValue: plugin.scope ?? "project") ?? .project
                                draft.plugins.append(PresetPluginReference(plugin: plugin, scope: scope))
                            }
                        })
                }
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
            if !search.isEmpty && !model.mcpLibrary.entries.contains(where: { matches([$0.name, $0.commandOrURL]) })
                && !draft.mcpServers.contains(where: { matches([$0.name, $0.commandOrURL]) }) {
                Text(L10n.tr("没有匹配的配置资源，请调整搜索。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }
            ForEach(model.mcpLibrary.entries.filter { matches([$0.name, $0.commandOrURL]) }) { entry in
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.name).font(AppFont.body.weight(.semibold))
                        Text(MCPConnectionFields.transportTitle(entry.transport)).font(AppFont.secondary).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    SkillHostToggles(skillName: entry.name, identifierPrefix: "presets.editor.mcp.\(entry.id)",
                        isSelected: { host in draft.mcpServers.contains { $0.presetID == entry.draft(host: host, scope: .project).presetID } },
                        setSelected: { host, enabled in
                            let server = entry.draft(host: host, scope: .project)
                            draft.mcpServers.removeAll { $0.presetID == server.presetID }
                            if enabled { draft.mcpServers.append(server) }
                        })
                }.padding(.vertical, 8)
                Divider()
            }
            if draft.mcpServers.isEmpty && model.mcpLibrary.entries.isEmpty {
                EmptyState(icon: PresetComponent.mcp.icon, title: L10n.tr("还没有 MCP 服务"), detail: L10n.tr("点「添加 MCP 服务」保存连接配置。"))
            }
            ForEach(Array(draft.mcpServers.enumerated()).filter { matches([$0.element.name, $0.element.commandOrURL]) }, id: \.element.presetID) { index, server in
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
            if !model.snapshot.templates.contains(where: { matches([$0.title, $0.purpose, $0.body]) }) {
                Text(L10n.tr("没有匹配的 AGENTS 片段，请调整搜索或到「AGENTS 片段」添加。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }
            ForEach(draft.instructions.filter { id in !model.snapshot.templates.contains { $0.id == id } }.sorted(), id: \.self) { id in
                HStack {
                    Text(L10n.tr("片段已删除，请移除引用后重新选择。"))
                        .font(AppFont.secondary).foregroundStyle(.red)
                    Spacer()
                    Button(L10n.tr("移除引用")) { draft.instructions.remove(id) }
                }
            }
            ForEach(model.snapshot.templates.filter { matches([$0.title, $0.purpose, $0.body]) }) { template in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(UserFacingText.templateTitle(template)).font(AppFont.body.weight(.semibold))
                            Text(UserFacingText.templatePurpose(template)).font(AppFont.secondary).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        selectionButton(UserFacingText.templateTitle(template), selected: draft.instructions.contains(template.id),
                            identifier: "presets.editor.rule.\(template.id)") {
                            if draft.instructions.contains(template.id) { draft.instructions.remove(template.id) }
                            else { draft.instructions.insert(template.id) }
                        }
                    }
                    Text(template.body).font(AppFont.code).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
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

    private func matches(_ fields: [String]) -> Bool {
        search.isEmpty || fields.contains { $0.localizedCaseInsensitiveContains(search) }
    }

    private func selectionButton(_ name: String, selected: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: selected ? "checkmark" : "plus")
                .frame(width: 12, height: 12)
        }
        .buttonStyle(AppButtonStyle(selected: selected))
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(L10n.tr("在预设中使用「\(name)」"))
        .accessibilityValue(selected ? L10n.tr("已选择") : L10n.tr("未选择"))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func cancel() {
        if draft != initial { confirmDiscard = true } else { onClose?() }
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
                        Text(L10n.tr("启动参数（每行一项，保留项内空格）"))
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
