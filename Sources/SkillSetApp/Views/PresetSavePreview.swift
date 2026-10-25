import SwiftUI
import SkillSetCore

struct PresetSavePreview: View {
    @Bindable var model: AppModel
    let draft: PresetEditorDraft
    let initial: PresetEditorDraft
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var changes: PresetDraftPreview {
        let baseline = ProjectRecord(id: "preset-preview", name: initial.name, path: "", adapter: "", inherited: "",
            draftSkillIDs: initial.skills, appliedSkillIDs: [], agents: [], fragments: initial.instructions.sorted(),
            pendingChanges: 0, draftPlugins: initial.plugins, draftMCPServers: initial.mcpServers)
        return PresetDraftPreview(preset: draft.record, project: baseline, snapshot: model.snapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("预览预设")).font(AppFont.title.weight(.bold))
            Text(draft.name).font(AppFont.heading)
            if !draft.description.isEmpty { Text(draft.description).font(AppFont.secondary).foregroundStyle(.secondary) }
            Text(L10n.tr("只保存预设，项目和 AI 工具配置保持不变。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section(.skills, change: changes.skills, names: draft.skills.sorted().map(model.skillDisplayTitle),
                        removed: changes.skills.removed.map(model.skillDisplayTitle))
                    section(.instructions, change: changes.instructions,
                        names: draft.instructions.sorted().map(instructionName), removed: changes.instructions.removed.map(instructionName))
                    section(.mcp, change: changes.mcpServers, names: draft.mcpServers.map { "\($0.host.displayName) · \(L10n.text($0.scope.displayName)) · \($0.name)" },
                        removed: initial.mcpServers.filter { changes.mcpServers.removed.contains($0.presetID) }.map(\.name))
                    ForEach(draft.mcpServers, id: \.presetID) { server in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(server.commandOrURL).font(AppFont.code).textSelection(.enabled)
                            if !server.args.isEmpty { Text(server.args.joined(separator: "\n")).font(AppFont.code).textSelection(.enabled) }
                            if !server.envKeys.isEmpty {
                                Text(L10n.tr("环境变量引用：\(server.envKeys.joined(separator: "、"))（只保存名称）"))
                                    .font(AppFont.secondary).foregroundStyle(.secondary)
                            }
                        }
                    }
                    section(.plugins, change: changes.plugins,
                        names: draft.plugins.map { "\($0.host.displayName) · \(L10n.text($0.scope.displayName)) · \($0.name)" },
                        removed: initial.plugins.filter { changes.plugins.removed.contains($0.id) }.map(\.name))
                    ForEach(draft.plugins) { plugin in
                        DisclosureGroup(plugin.name) {
                            Text(plugin.manifestDigest).font(AppFont.code).textSelection(.enabled)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = model.presetError { Text(L10n.tr(error)).font(AppFont.secondary).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(L10n.tr("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("保存")) {
                    if model.savePreset(draft) { onSaved() }
                }
                .buttonStyle(AppButtonStyle(kind: .primary))
                .accessibilityIdentifier("presets.review.save")
            }
        }
        .padding(24).frame(width: 760, height: 620).appControls()
    }

    private func section(_ kind: PresetComponent, change: PresetDraftPreview.Changes, names: [String], removed: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text(kind.title)).font(AppFont.heading)
            Text(L10n.tr("新增 \(change.added.count) · 更新 \(change.updated.count) · 移除 \(change.removed.count) · 保留 \(change.retained.count)"))
                .font(AppFont.metadata).foregroundStyle(.secondary)
            ForEach(Array(names.enumerated()), id: \.offset) { _, name in Text(name).font(AppFont.secondary) }
            ForEach(Array(removed.enumerated()), id: \.offset) { _, name in
                Text(L10n.tr("移除：\(name)")).font(AppFont.secondary).foregroundStyle(.orange)
            }
            Divider()
        }
    }

    private func instructionName(_ id: String) -> String {
        model.snapshot.templates.first { $0.id == id }.map { UserFacingText.templateTitle($0) } ?? L10n.tr("片段已删除")
    }
}
