import SwiftUI
import SkillSetCore

struct PresetsView: View {
    @Bindable var model: AppModel
    @State private var removal: PresetRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageActionHeader(eyebrow: "PRESETS", title: L10n.tr("用户预设"),
                       detail: L10n.tr("保存常用的技能、插件、MCP 服务和规则组合，再选择项目使用。")) {
                    Button { model.beginNewPreset() } label: {
                        Label(L10n.tr("新建预设"), systemImage: "plus")
                            .frame(minHeight: 32)
                            .contentShape(Rectangle())
                    }
                        .buttonStyle(AppButtonStyle(kind: .primary)).keyboardShortcut("n", modifiers: .command)
                        .help(L10n.tr("新建预设"))
                        .accessibilityLabel(L10n.tr("新建预设"))
                        .accessibilityIdentifier("presets.new")
            }
            if let error = model.presetError {
                Label(L10n.tr(error), systemImage: "exclamationmark.circle").font(AppFont.secondary).foregroundStyle(.red)
            }
            HStack(alignment: .top, spacing: AppLayout.columnSpacing) {
                presetList.frame(width: AppLayout.listWidth)
                presetDetail
            }
        }
        .confirmationDialog(L10n.tr("删除这个预设？"), isPresented: Binding(
            get: { removal != nil }, set: { if !$0 { removal = nil } }
        ), titleVisibility: .visible) {
            Button(L10n.tr("删除"), role: .destructive) {
                if let removal { model.removePreset(removal) }
                removal = nil
            }
            Button(L10n.tr("先不删"), role: .cancel) { removal = nil }
        } message: {
            Text(L10n.tr("预设将从本机库删除。已载入的项目草稿和已写入的文件保持不变。"))
        }
    }

    private var presetList: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.tr("已保存预设")).font(AppFont.heading)
                    Spacer()
                }
                ScrollView {
                    VStack(spacing: 6) {
                        if model.snapshot.presets.isEmpty {
                            Text(L10n.tr("还没有预设，点击“新建预设”保存自己的组合。"))
                                .font(AppFont.secondary).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12)
                        }
                        ForEach(model.snapshot.presets) { preset in
                            Button { model.selectedPresetID = preset.id } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "rectangle.3.group")
                                        .foregroundStyle(preset.id == model.selectedPresetID ? AppColor.accentText : .secondary)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(preset.status == "local" ? preset.name : L10n.text(preset.name))
                                            .font(AppFont.body.weight(.semibold)).foregroundStyle(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(L10n.tr("\(preset.componentCount) 项内容 · 版本 \(preset.revision)"))
                                            .font(AppFont.metadata).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(10).selectionRow(preset.id == model.selectedPresetID)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("presets.saved.\(preset.id)")
                        }
                    }
                    .padding(2)
                }
                Divider()
                Text(L10n.tr("使用预设后，可在项目中继续调整。预览并批准变更后，才会写入文件或安装组件。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var presetDetail: some View {
        if let preset = model.selectedPreset {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SurfaceCard(emphasis: true) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(preset.status == "local" ? preset.name : L10n.text(preset.name)).font(AppFont.title.weight(.bold))
                                Spacer()
                                StatusBadge(text: L10n.tr("版本 \(preset.revision)"), tone: .accent)
                            }
                            if !preset.description.isEmpty {
                                Text(preset.status == "local" ? preset.description : L10n.text(preset.description))
                                    .font(AppFont.body).foregroundStyle(.secondary)
                            }
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 10) {
                                    presetActions(preset)
                                }
                                VStack(alignment: .leading, spacing: 10) {
                                    presetActions(preset)
                                }
                            }
                        }
                    }
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 18) {
                            componentHeader(.skills, count: preset.skills.count)
                            ForEach(preset.skills, id: \.self) { id in
                                let skill = model.snapshot.catalog.entries.first { $0.id == id }
                                componentRow(skill?.declaredName ?? id, detail: skill?.sourceId ?? id)
                            }
                            Divider()
                            componentHeader(.plugins, count: preset.plugins.count)
                            ForEach(preset.plugins) { plugin in
                                componentRow(plugin.name, detail: "\(plugin.host.displayName) · \(L10n.text(plugin.scope.displayName)) · \(plugin.manifestDigest.prefix(10))")
                            }
                            Divider()
                            componentHeader(.mcp, count: preset.mcpServers.count)
                            ForEach(preset.mcpServers, id: \.presetID) { server in
                                componentRow(server.name, detail: "\(server.host.displayName) · \(L10n.text(server.scope.displayName)) · \(server.transport)")
                            }
                            Divider()
                            componentHeader(.instructions, count: preset.instructionFragments.count)
                            ForEach(preset.instructionFragments, id: \.self) { id in
                                if let template = model.snapshot.templates.first(where: { $0.id == id }) {
                                    DisclosureGroup(UserFacingText.templateTitle(template)) {
                                        Text(template.body).font(AppFont.metadata.monospaced()).textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                                    }
                                    .font(AppFont.secondary)
                                    .accessibilityIdentifier("presets.rule.details.\(id)")
                                    Text(UserFacingText.templatePurpose(template))
                                        .font(AppFont.secondary).foregroundStyle(.secondary)
                                } else { Text(id).foregroundStyle(.red) }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            EmptyState(icon: "rectangle.3.group", title: L10n.tr("选择一个预设"), detail: L10n.tr("从左侧选择预设，或点「新建预设」保存常用组合。"))
        }
    }

    @ViewBuilder
    private func presetActions(_ preset: PresetRecord) -> some View {
        Button(L10n.tr("用于项目…")) { model.presetSelection = PresetSelectionRequest(presetID: preset.id) }
            .buttonStyle(AppButtonStyle(kind: .primary)).tint(AppColor.accent)
            .accessibilityIdentifier("presets.chooseProject")
        Button(L10n.tr("编辑预设")) {
            model.beginEditingPreset(preset)
        }
        .accessibilityIdentifier("presets.edit")
        Button(L10n.tr("复制为新预设")) {
            model.beginEditingPreset(preset, copy: true)
        }
        .accessibilityIdentifier("presets.duplicate")
        Button(L10n.tr("删除预设"), role: .destructive) { removal = preset }
            .accessibilityIdentifier("presets.delete")
    }

    private func componentHeader(_ kind: PresetComponent, count: Int) -> some View {
        HStack {
            Label(L10n.text(kind.title), systemImage: kind.icon).font(AppFont.heading)
            Spacer()
            Text(count == 0 ? L10n.tr("未包含条目") : L10n.tr("\(count) 条"))
                .font(AppFont.metadata).foregroundStyle(.secondary)
        }
    }

    private func componentRow(_ name: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(AppFont.secondary.weight(.medium))
            Text(detail).font(AppFont.metadata).foregroundStyle(.secondary)
        }
        .textSelection(.enabled)
    }
}
