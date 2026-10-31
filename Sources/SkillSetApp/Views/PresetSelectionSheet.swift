import AppKit
import SwiftUI
import SkillSetCore

struct PresetSelectionSheet: View {
    @Bindable var model: AppModel
    let request: PresetSelectionRequest
    @Environment(\.dismiss) private var dismiss
    @State private var projectID: String
    @State private var selectedPresetIDs: Set<String>
    @State private var error: LocalizedText?
    @State private var showRetainedSkills = false
    @State private var showRetainedRules = false
    @State private var showRetainedPlugins = false
    @State private var showRetainedMCP = false
    @State private var editor: PresetEditorDraft?
    @State private var existingPresetIDs: Set<String> = []
    @State private var availablePlugins: [PluginInventoryRecord] = []
    @FocusState private var focusedPresetID: String?

    init(model: AppModel, request: PresetSelectionRequest) {
        self.model = model
        self.request = request
        let targetID = request.projectID ?? model.selectedProjectID
        _projectID = State(initialValue: targetID)
        // 打开时勾选项目里已经生效的预设，取消勾选即按差集回收。
        let project = model.projects.first { $0.id == targetID }
        var selection = Set(project?.appliedPresets(host: project?.editingAgent ?? "codex").map(\.presetID) ?? [])
        if let presetID = request.presetID { selection.insert(presetID) }
        _selectedPresetIDs = State(initialValue: selection)
        _focusedPresetID = FocusState<String?>()
    }

    private var project: ProjectRecord? { model.projects.first { $0.id == projectID } }
    private var host: String { project?.editingAgent ?? "codex" }
    private var selectedPresets: [PresetRecord] { model.snapshot.presets.filter { selectedPresetIDs.contains($0.id) } }
    private var appliedPresetIDs: Set<String> { Set(project?.appliedPresets(host: host).map(\.presetID) ?? []) }
    private var preview: PresetDraftPreview? {
        guard let project else { return nil }
        return PresetDraftPreview(presets: selectedPresets, project: project, snapshot: model.snapshot,
                                  availablePlugins: availablePlugins)
    }
    private var hasChanges: Bool {
        guard let preview else { return false }
        return !preview.addedPresets.isEmpty || !preview.removedPresets.isEmpty
            || !preview.skills.isEmpty && (preview.skills.added.count + preview.skills.removed.count > 0)
            || preview.plugins.added.count + preview.plugins.updated.count + preview.plugins.removed.count > 0
            || preview.mcpServers.added.count + preview.mcpServers.updated.count + preview.mcpServers.removed.count > 0
            || preview.instructions.added.count + preview.instructions.removed.count > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                presetList.frame(width: 240)
                Divider()
                review
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(20)
            }
            .frame(maxHeight: .infinity)
            Divider()
            footer
        }
        .appControls()
        .frame(width: 880, height: 640)
        .background(.regularMaterial)
        .disclosureGroupStyle(FullRowDisclosureGroupStyle())
        .sheet(item: $editor, onDismiss: {
            if !existingPresetIDs.contains(model.selectedPresetID) { focusedPresetID = model.selectedPresetID }
        }) { draft in
            PresetEditorSheet(model: model, draft: draft)
        }
        .task(id: projectID) { availablePlugins = model.presetPlugins(for: projectID) }
        .onAppear {
            if focusedPresetID == nil {
                focusedPresetID = request.presetID ?? model.snapshot.presets.first?.id
            }
        }
        .onChange(of: projectID) { error = nil; availablePlugins = [] }
        .onChange(of: host) { error = nil }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AppColor.accentText)
                .frame(width: 42, height: 42)
                .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("使用预设")).font(AppFont.title)
                Text(L10n.tr("可同时选择多个预设；重叠内容只保留一份，取消时只移除该预设独有的内容。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var presetList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.tr("预设"))
                    .font(AppFont.metadata.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    existingPresetIDs = Set(model.snapshot.presets.map(\.id))
                    model.presetError = nil
                    model.refreshPlugins()
                    editor = PresetEditorDraft()
                } label: {
                    Label(L10n.tr("新建预设"), systemImage: "plus")
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AppButtonStyle(kind: .quiet)).help(L10n.tr("新建预设"))
                .accessibilityLabel(L10n.tr("新建预设"))
                .accessibilityIdentifier("presets.selection.new")
            }
            .padding(.horizontal, 10)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.snapshot.presets) { preset in
                        presetRow(preset)
                    }
                }
                .padding(2)
            }
            Text(L10n.tr("已勾选 \(selectedPresetIDs.count) 个预设"))
                .font(AppFont.metadata).foregroundStyle(.secondary)
                .padding(.horizontal, 10)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppColor.surface.opacity(0.6))
    }

    private func presetRow(_ preset: PresetRecord) -> some View {
        let isSelected = selectedPresetIDs.contains(preset.id)
        let isApplied = appliedPresetIDs.contains(preset.id)
        return Button {
            toggleSelection(preset.id)
            focusedPresetID = preset.id
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(AppFont.body)
                    .foregroundStyle(isSelected ? AppColor.accentText : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(preset.status == "local" ? preset.name : L10n.text(preset.name))
                            .font(AppFont.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if isApplied {
                            Text(L10n.tr("已用"))
                                .font(AppFont.metadata)
                                .foregroundStyle(AppColor.accentText)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Text(L10n.tr("\(preset.componentCount) 项内容 · 版本 \(preset.revision)"))
                        .font(AppFont.metadata).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .selectionRow(isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(AppPressButtonStyle())
        .focusable()
        .focused($focusedPresetID, equals: preset.id)
        .onKeyPress(.upArrow) {
            moveFocus(from: preset.id, offset: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveFocus(from: preset.id, offset: 1)
            return .handled
        }
        .onKeyPress(.space) {
            toggleSelection(preset.id)
            return .handled
        }
        .accessibilityIdentifier("presets.option.\(preset.id)")
        .accessibilityLabel(preset.status == "local" ? preset.name : L10n.text(preset.name))
        .accessibilityValue(isSelected ? L10n.tr("已选择") : L10n.tr("未选择"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .help(isApplied ? L10n.tr("这个预设已用于项目，取消勾选只移除它独有的内容。") : L10n.tr("勾选后写入项目草稿。"))
    }

    private func toggleSelection(_ id: String) {
        if selectedPresetIDs.contains(id) { selectedPresetIDs.remove(id) } else { selectedPresetIDs.insert(id) }
    }

    private func moveFocus(from id: String, offset: Int) {
        guard let index = model.snapshot.presets.firstIndex(where: { $0.id == id }) else { return }
        let next = min(max(0, index + offset), model.snapshot.presets.count - 1)
        focusedPresetID = model.snapshot.presets[next].id
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 16) {
            targetProject()
            Divider()
            if let preview {
                presetSummary(preview)
                changeSummary(preview)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !preview.canLoad { validationMessage(preview) }
                        changes(title: "技能", value: preview.skills, category: .skills, expanded: $showRetainedSkills)
                        Divider()
                        changes(title: "插件", value: preview.plugins, category: .plugins, expanded: $showRetainedPlugins)
                        Divider()
                        changes(title: "MCP 服务", value: preview.mcpServers, category: .mcp, expanded: $showRetainedMCP)
                        Divider()
                        changes(title: "AGENTS 片段", value: preview.instructions, category: .instructions, expanded: $showRetainedRules)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.trailing, 6)
                    .textSelection(.enabled)
                }
                // 切换组合或目标后回到差异开头，避免沿用上一份长列表的滚动位置。
                .id(selectionSignature)
            } else {
                EmptyState(
                    icon: "folder",
                    title: L10n.tr("选择目标项目"),
                    detail: L10n.tr("选择已有项目或添加本机目录，即可查看草稿变化。")
                )
            }
            if let error {
                Label(L10n.tr(error), systemImage: "exclamationmark.circle")
                    .font(AppFont.secondary).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var selectionSignature: String {
        selectedPresetIDs.sorted().joined(separator: ",") + "|" + projectID + "|" + host
    }

    private func presetSummary(_ preview: PresetDraftPreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L10n.tr("已选 \(selectedPresets.count) 个预设"))
                    .font(AppFont.heading)
                Text(L10n.tr("共 \(selectedPresets.reduce(0) { $0 + $1.componentCount }) 项内容"))
                    .font(AppFont.metadata).foregroundStyle(.secondary)
                Spacer()
            }
            if !preview.addedPresets.isEmpty {
                presetChangeLine(title: "新增", presets: preview.addedPresets, icon: "plus.circle", color: AppColor.positive)
            }
            if !preview.removedPresets.isEmpty {
                presetChangeLine(title: "取消", presets: preview.removedPresets, icon: "minus.circle", color: AppColor.accentText)
            }
            if preview.addedPresets.isEmpty && preview.removedPresets.isEmpty {
                Text(L10n.tr("与项目当前使用的预设一致。"))
                    .font(AppFont.metadata).foregroundStyle(.secondary)
            }
            // 列出已选预设的说明，用户在写入前要能逐个核对内容。
            if !selectedPresets.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(selectedPresets) { preset in
                        selectedPresetRow(preset)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectedPresetRow(_ preset: PresetRecord) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(preset.status == "local" ? preset.name : L10n.text(preset.name))
                    .font(AppFont.secondary.weight(.medium))
                if appliedPresetIDs.contains(preset.id) {
                    Text(L10n.tr("已用"))
                        .font(AppFont.metadata)
                        .foregroundStyle(AppColor.accentText)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: 4))
                }
                Spacer(minLength: 0)
            }
            Text(preset.status == "local" ? preset.description : L10n.text(preset.description))
                .font(AppFont.metadata).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func presetChangeLine(title: LocalizedText, presets: [PresetRecord], icon: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(L10n.tr(title), systemImage: icon).font(AppFont.secondary.weight(.medium)).foregroundStyle(color)
            Text(presets.map { $0.status == "local" ? $0.name : L10n.text($0.name) }.joined(separator: "、"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func targetProject() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if request.projectID == nil {
                HStack(spacing: 10) {
                    AppPicker(title: L10n.tr("目标项目"), selection: $projectID,
                              valueLabel: project?.name ?? L10n.tr("选择目标项目"), showsLabel: false) {
                        Text(L10n.tr("选择目标项目")).tag("")
                        ForEach(model.projects) { project in Text(project.name).tag(project.id) }
                    }
                    .accessibilityIdentifier("presets.selection.project")
                    Button { chooseProject() } label: {
                        Label(L10n.tr("添加本机目录…"), systemImage: "folder.badge.plus")
                            .frame(minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(AppButtonStyle(kind: .quiet))
                    .help(L10n.tr("添加本机目录…"))
                    .accessibilityLabel(L10n.tr("添加本机目录…"))
                    .accessibilityIdentifier("presets.selection.addProject")
                }
            } else {
                Label(L10n.tr("目标项目：\(project?.name ?? L10n.tr("未选择项目"))"), systemImage: "folder")
                    .font(AppFont.secondary.weight(.medium))
            }
            if let project {
                AppPicker(title: L10n.tr("目标 AI 工具"), selection: Binding(
                    get: { project.editingAgent },
                    set: { model.selectProjectHost($0 == "codex" ? .codex : .claude, projectID: project.id) }
                ), valueLabel: project.editingAgentName, showsLabel: true) {
                    Text("Codex").tag("codex")
                    Text("Claude Code").tag("claude-code")
                }
                Text(L10n.tr("每个 AI 工具各自保存预设组合。技能和规则只写入所选 AI 工具的草稿；插件和 MCP 服务使用各自标明的工具与范围。"))
                    .font(AppFont.metadata).foregroundStyle(.secondary)
                Text(project.path)
                    .font(AppFont.metadata.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1).truncationMode(.middle)
                    .help(project.path)
            }
        }
    }

    private func changeSummary(_ preview: PresetDraftPreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("与当前草稿比较"))
                .font(AppFont.metadata).foregroundStyle(.secondary)
            HStack(spacing: 18) {
                summaryCount(.added, count: preview.skills.added.count + preview.instructions.added.count + preview.plugins.added.count + preview.mcpServers.added.count)
                summaryCount(.updated, count: preview.plugins.updated.count + preview.mcpServers.updated.count)
                summaryCount(.retained, count: preview.skills.retained.count + preview.instructions.retained.count + preview.plugins.retained.count + preview.mcpServers.retained.count)
                summaryCount(.removed, count: preview.skills.removed.count + preview.instructions.removed.count + preview.plugins.removed.count + preview.mcpServers.removed.count)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AppColor.border, lineWidth: 1))
    }

    private func summaryCount(_ kind: ChangeKind, count: Int) -> some View {
        Label(L10n.tr("\(kind.title) \(count)"), systemImage: kind.icon)
            .font(AppFont.secondary.weight(.medium)).monospacedDigit()
            .foregroundStyle(count == 0 ? Color.secondary : kind.color)
            .fixedSize()
    }

    private func changes(title: LocalizedText, value: PresetComponentChanges, category: PresetComponent, expanded: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr(title)).font(AppFont.body.weight(.semibold))
            ForEach(value.added, id: \.self) { id in changeRow(id: id, kind: .added, category: category) }
            ForEach(value.updated, id: \.self) { id in changeRow(id: id, kind: .updated, category: category) }
            ForEach(value.removed, id: \.self) { id in changeRow(id: id, kind: .removed, category: category) }
            if !value.retained.isEmpty {
                DisclosureGroup(isExpanded: expanded) {
                    VStack(spacing: 10) {
                        ForEach(value.retained, id: \.self) { id in changeRow(id: id, kind: .retained, category: category) }
                    }
                    .padding(.top, 8)
                } label: {
                    Text(L10n.tr("保留 \(value.retained.count) 项"))
                        .font(AppFont.secondary).foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("presets.retained.\(category == .instructions ? "rules" : category.rawValue)")
            }
            if value.added.isEmpty && value.updated.isEmpty && value.removed.isEmpty && value.retained.isEmpty {
                Text(L10n.tr("没有选择这类内容")).font(AppFont.secondary).foregroundStyle(.secondary)
            }
        }
    }

    private func changeRow(id: String, kind: ChangeKind, category: PresetComponent) -> some View {
        let skill = model.snapshot.catalog.entries.first { $0.id == id }
        let rule = model.snapshot.templates.first { $0.id == id }
        let plugin = selectedPresets.flatMap(\.plugins).first { $0.id == id } ?? project?.draftPlugins.first { $0.id == id }
        let server = selectedPresets.flatMap(\.mcpServers).first { $0.presetID == id } ?? project?.draftMCPServers.first { $0.presetID == id }
        let name: String
        let detail: String
        switch category {
        case .skills:
            name = model.skillDisplayTitle(id)
            detail = skill.map(model.skillSourceTitle) ?? L10n.tr("不在技能库")
        case .instructions:
            name = rule.map { UserFacingText.templateTitle($0) } ?? L10n.tr("已删除的规则片段")
            detail = rule.map { L10n.text(UserFacingText.builtInDescription($0.purpose)) }
                ?? L10n.tr("片段已删除，请移除引用后重新选择。")
        case .plugins:
            let fallbackName = id.split(separator: ":").last.flatMap { $0.split(separator: "@").first }.map(String.init) ?? id
            name = plugin?.name ?? fallbackName
            detail = plugin.map { "\($0.host.displayName) · \(L10n.text($0.scope.displayName)) · \($0.manifestDigest.prefix(10))" } ?? fallbackName
        case .mcp:
            let fallbackName = id.split(separator: ":").last.map(String.init) ?? id
            name = server?.name ?? fallbackName
            detail = server.map { "\($0.host.displayName) · \(L10n.text($0.scope.displayName)) · \($0.transport)" } ?? fallbackName
        }
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.icon)
                .font(AppFont.secondary).foregroundStyle(kind.color)
                .frame(width: 16, height: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(AppFont.secondary.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(AppFont.metadata).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(L10n.tr(kind.title)).font(AppFont.metadata).foregroundStyle(kind.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .help(name)
    }

    private func validationMessage(_ preview: PresetDraftPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(preview.blockingReasons(origins: model.sourceOrigins).enumerated()), id: \.offset) { _, reason in
                Label(L10n.tr(reason), systemImage: "exclamationmark.circle")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(AppFont.secondary).foregroundStyle(.red)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text(hasChanges
                 ? L10n.tr("只更新项目草稿，保留 AI 工具选择。安装插件或写入配置前，还需预览并批准变更。")
                 : L10n.tr("与当前草稿一致，没有需要写入的变更。"))
                .font(AppFont.metadata).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button(L10n.tr("取消")) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("presets.selection.cancel")
            Button(L10n.tr("应用到项目草稿")) {
                guard let project else { return }
                if model.selectPresets(selectedPresets, into: project.id) { dismiss() }
                else { error = model.actionMessage }
            }
            .buttonStyle(AppButtonStyle(kind: .primary))
            .keyboardShortcut(.defaultAction)
            .disabled(preview?.canLoad != true || model.isWorking || !hasChanges)
            .accessibilityIdentifier("presets.selection.load")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private enum ChangeKind {
        case added, updated, retained, removed

        var title: LocalizedText {
            switch self {
            case .added: "新增"
            case .updated: "更新"
            case .retained: "保留"
            case .removed: "移除"
            }
        }

        var icon: String {
            switch self {
            case .added: "plus.circle"
            case .updated: "arrow.triangle.2.circlepath"
            case .retained: "checkmark.circle"
            case .removed: "minus.circle"
            }
        }

        var color: Color {
            switch self {
            case .added: AppColor.positive
            case .updated: AppColor.accentText
            case .retained: .secondary
            case .removed: AppColor.accentText
            }
        }
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("添加本机项目")
        panel.prompt = L10n.tr("添加")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if model.registerProject(url) {
            projectID = model.selectedProjectID
            error = nil
        } else {
            error = model.actionMessage
        }
    }
}
