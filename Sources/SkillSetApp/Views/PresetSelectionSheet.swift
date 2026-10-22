import AppKit
import SwiftUI
import SkillSetCore

struct PresetSelectionSheet: View {
    @Bindable var model: AppModel
    let request: PresetSelectionRequest
    @Environment(\.dismiss) private var dismiss
    @State private var projectID: String
    @State private var presetID: String
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
        _projectID = State(initialValue: request.projectID ?? model.selectedProjectID)
        _presetID = State(initialValue: request.presetID ?? model.selectedPreset?.id ?? model.snapshot.presets.first?.id ?? "")
    }

    private var project: ProjectRecord? { model.projects.first { $0.id == projectID } }
    private var preset: PresetRecord? { model.snapshot.presets.first { $0.id == presetID } }
    private var preview: PresetDraftPreview? {
        guard let project, let preset else { return nil }
        return PresetDraftPreview(preset: preset, project: project, snapshot: model.snapshot, availablePlugins: availablePlugins)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                presetList.frame(width: 226)
                Divider()
                review
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(20)
            }
            .frame(maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 860, height: 620)
        .background(.regularMaterial)
        .disclosureGroupStyle(FullRowDisclosureGroupStyle())
        .defaultFocus($focusedPresetID, presetID, priority: .userInitiated)
        .sheet(item: $editor, onDismiss: {
            if !existingPresetIDs.contains(model.selectedPresetID) { presetID = model.selectedPresetID }
        }) { draft in
            PresetEditorSheet(model: model, draft: draft)
        }
        .task(id: projectID) { availablePlugins = model.presetPlugins(for: projectID) }
        .onChange(of: projectID) { error = nil; availablePlugins = [] }
        .onChange(of: presetID) { error = nil }
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
                Text(L10n.tr("选择组合，核对后载入项目草稿。"))
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
                .buttonStyle(.borderless).help(L10n.tr("新建预设"))
                .accessibilityLabel(L10n.tr("新建预设"))
                .accessibilityIdentifier("presets.selection.new")
            }
            .padding(.horizontal, 10)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.snapshot.presets) { preset in
                        Button {
                            presetID = preset.id
                            focusedPresetID = preset.id
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(preset.status == "local" ? preset.name : L10n.text(preset.name))
                                        .font(AppFont.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                    if presetID == preset.id {
                                        Image(systemName: "checkmark")
                                            .font(AppFont.metadata.weight(.semibold))
                                            .foregroundStyle(AppColor.accentText)
                                            .accessibilityHidden(true)
                                    }
                                }
                                Text(L10n.tr("\(preset.componentCount) 项内容 · 版本 \(preset.revision)"))
                                    .font(AppFont.metadata).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .selectionRow(presetID == preset.id)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusable()
                        .focused($focusedPresetID, equals: preset.id)
                        .onKeyPress(.upArrow) {
                            moveSelection(from: preset.id, offset: -1)
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            moveSelection(from: preset.id, offset: 1)
                            return .handled
                        }
                        .accessibilityIdentifier("presets.option.\(preset.id)")
                    }
                }
                .padding(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppColor.surface.opacity(0.6))
    }

    private func moveSelection(from id: String, offset: Int) {
        guard let index = model.snapshot.presets.firstIndex(where: { $0.id == id }) else { return }
        let next = min(max(0, index + offset), model.snapshot.presets.count - 1)
        presetID = model.snapshot.presets[next].id
        focusedPresetID = presetID
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 16) {
            targetProject
            Divider()
            if let preset {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(preset.status == "local" ? preset.name : L10n.text(preset.name)).font(AppFont.heading)
                        Spacer()
                        Text(L10n.tr("版本 \(preset.revision)"))
                            .font(AppFont.metadata).foregroundStyle(.secondary)
                    }
                    Text(preset.status == "local" ? preset.description : L10n.text(preset.description))
                        .font(AppFont.secondary).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let preview {
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 6)
                    .textSelection(.enabled)
                }
                // 切换组合或目标后回到差异开头，避免沿用上一份长列表的滚动位置。
                .id(presetID + projectID)
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

    private var targetProject: some View {
        VStack(alignment: .leading, spacing: 6) {
            if request.projectID == nil {
                HStack(spacing: 10) {
                    Picker(L10n.tr("目标项目"), selection: $projectID) {
                        Text(L10n.tr("选择目标项目")).tag("")
                        ForEach(model.projects) { project in Text(project.name).tag(project.id) }
                    }
                    .accessibilityIdentifier("presets.selection.project")
                    Button { chooseProject() } label: {
                        Label(L10n.tr("添加本机目录…"), systemImage: "folder.badge.plus")
                            .frame(minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.tr("添加本机目录…"))
                    .accessibilityLabel(L10n.tr("添加本机目录…"))
                    .accessibilityIdentifier("presets.selection.addProject")
                }
            } else {
                Label(L10n.tr("目标项目：\(project?.name ?? L10n.tr("未选择项目"))"), systemImage: "folder")
                    .font(AppFont.secondary.weight(.medium))
            }
            if let project {
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

    private func changes(title: LocalizedText, value: PresetDraftPreview.Changes, category: PresetComponent, expanded: Binding<Bool>) -> some View {
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
                Text(L10n.tr("未包含条目")).font(AppFont.secondary).foregroundStyle(.secondary)
            }
        }
    }

    private func changeRow(id: String, kind: ChangeKind, category: PresetComponent) -> some View {
        let skill = model.snapshot.catalog.entries.first { $0.id == id }
        let rule = model.snapshot.templates.first { $0.id == id }
        let plugin = (preset?.plugins ?? []).first { $0.id == id } ?? project?.draftPlugins.first { $0.id == id }
        let server = (preset?.mcpServers ?? []).first { $0.presetID == id } ?? project?.draftMCPServers.first { $0.presetID == id }
        let name: String
        let detail: String
        switch category {
        case .skills: name = skill?.declaredName ?? id; detail = skill?.sourceId ?? id
        case .instructions:
            name = rule.map { UserFacingText.templateTitle($0) } ?? id
            detail = rule.map { L10n.text(UserFacingText.builtInDescription($0.purpose)) } ?? id
        case .plugins:
            name = plugin?.name ?? id
            detail = plugin.map { "\($0.host.displayName) · \(L10n.text($0.scope.displayName)) · \($0.manifestDigest.prefix(10))" } ?? id
        case .mcp:
            name = server?.name ?? id
            detail = server.map { "\($0.host.displayName) · \(L10n.text($0.scope.displayName)) · \($0.transport)" } ?? id
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
        .help(id)
    }

    private func validationMessage(_ preview: PresetDraftPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L10n.tr("部分技能或规则暂不可用，或存在重名，请核对下方提示后重试。"), systemImage: "exclamationmark.circle")
            ForEach(preview.componentIssues, id: \.self) { Text(L10n.text($0)) }
            ForEach(Array(Set(preview.unavailableSkillIDs + preview.unavailableInstructionIDs + preview.conflictingSkillIDs)).sorted(), id: \.self) { id in
                Text(id).font(AppFont.metadata.monospaced())
            }
        }
        .font(AppFont.secondary).foregroundStyle(.red)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text(L10n.tr("只更新项目草稿，保留 AI 工具选择。安装插件或写入配置前，还需预览并批准变更。"))
                .font(AppFont.metadata).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button(L10n.tr("取消")) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("presets.selection.cancel")
            Button(L10n.tr("载入项目草稿")) {
                guard let preset else { return }
                if model.loadPreset(preset, into: projectID) { dismiss() }
                else { error = model.actionMessage }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(preview?.canLoad != true || model.isWorking)
            .accessibilityIdentifier("presets.selection.load")
        }
        .controlSize(.large)
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
