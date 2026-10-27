import SwiftUI
import SkillSetCore

struct PresetsView: View {
    @Bindable var model: AppModel
    @State private var removal: PresetRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: AppLayout.columnSpacing) {
            PageActionHeader(eyebrow: "PRESETS", title: L10n.tr("预设"),
                detail: L10n.tr("保存常用组合，用于项目草稿；写入项目前再预览并保存。")) {
                Button { model.beginNewPreset() } label: {
                    Label(L10n.tr("新建预设"), systemImage: "plus")
                }
                .buttonStyle(AppButtonStyle(kind: .primary)).keyboardShortcut("n", modifiers: .command)
                .accessibilityIdentifier("presets.new")
            }
            if model.selectedPreset == nil, let error = model.presetError {
                Text(L10n.tr(error)).font(AppFont.secondary).foregroundStyle(.red)
            }
            if !model.snapshot.presets.isEmpty {
                presetSelector
            }
            if let preset = model.selectedPreset {
                SurfaceCard {
                    PresetConfigurationEditor(model: model, draft: Binding(
                        get: { model.presetDrafts[preset.id] ?? PresetEditorDraft(preset: preset) },
                        set: { model.presetDrafts[preset.id] = $0 }), initial: PresetEditorDraft(preset: preset))
                }.id(preset.id)
            } else {
                ScrollView {
                    EmptyState(icon: "rectangle.3.group", title: L10n.tr("还没有预设"),
                        detail: L10n.tr("点击「新建预设」，保存常用的技能、片段、MCP 和插件组合。"))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            model.refreshPlugins()
            model.mcpLibrary.refresh()
        }
        .confirmationDialog(L10n.tr("删除这个预设？"), isPresented: Binding(
            get: { removal != nil }, set: { if !$0 { removal = nil } }
        ), titleVisibility: .visible) {
            Button(L10n.tr("删除"), role: .destructive) {
                if let removal {
                    model.removePreset(removal)
                }
                removal = nil
            }
            Button(L10n.tr("先不删"), role: .cancel) { removal = nil }
        } message: {
            Text(L10n.tr("预设将从本机库删除。已载入的项目草稿和已写入的文件保持不变。"))
        }
    }

    private var presetSelector: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(L10n.tr("预设")).font(AppFont.heading)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(model.snapshot.presets) { preset in
                                Button { model.presetError = nil; model.selectedPresetID = preset.id } label: {
                                    Text(preset.status == "local" ? preset.name : L10n.text(preset.name))
                                        .lineLimit(1).frame(maxWidth: 180)
                                }
                                .buttonStyle(AppButtonStyle(selected: preset.id == model.selectedPresetID))
                                .accessibilityIdentifier("presets.saved.\(preset.id)")
                                .accessibilityAddTraits(preset.id == model.selectedPresetID ? [.isSelected] : [])
                            }
                        }
                        .frame(height: AppControl.selectorHeight)
                    }
                    .frame(maxWidth: .infinity, minHeight: AppControl.selectorHeight, maxHeight: AppControl.selectorHeight)
                    if let preset = model.selectedPreset {
                        Button(L10n.tr("用于项目…")) {
                            model.presetSelection = PresetSelectionRequest(presetID: preset.id)
                        }
                        .disabled(model.presetDrafts[preset.id].map { $0 != PresetEditorDraft(preset: preset) } == true)
                        .help(L10n.tr("先预览并保存修改，再用于项目。"))
                        .accessibilityIdentifier("presets.chooseProject")
                        Button {
                            let current = model.presetDrafts[preset.id] ?? PresetEditorDraft(preset: preset)
                            model.beginEditingPreset(current.record, copy: true)
                        } label: {
                            Image(systemName: "square.on.square")
                        }
                        .accessibilityLabel(L10n.tr("复制为新预设")).help(L10n.tr("复制为新预设"))
                        .accessibilityIdentifier("presets.duplicate")
                        Button(role: .destructive) { removal = preset } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel(L10n.tr("删除预设")).help(L10n.tr("删除预设"))
                        .accessibilityIdentifier("presets.delete")
                    }
                }
                if let preset = model.selectedPreset {
                    Text(L10n.tr("\(preset.componentCount) 项内容 · 版本 \(preset.revision)"))
                        .font(AppFont.metadata).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("presets.selector")
    }
}
