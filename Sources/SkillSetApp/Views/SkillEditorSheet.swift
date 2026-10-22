import SwiftUI
import SkillSetCore

struct SkillEditorSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SkillEditorDraft
    @State private var confirmDiscard = false
    private let initial: SkillEditorDraft

    init(model: AppModel, initialDraft: SkillEditorDraft) {
        self.model = model
        initial = initialDraft
        _draft = State(initialValue: initialDraft)
    }

    private var isEditing: Bool { draft.original?.sourceId == SkillLibraryStore.sourceID }
    private var hasChanges: Bool { draft.slug != initial.slug || draft.document != initial.document }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.text(isEditing ? "编辑技能" : draft.original == nil ? "新增技能" : "复制并编辑"))
                    .font(AppFont.title.weight(.bold))
                Spacer()
                StatusBadge(text: L10n.tr("本机技能库"), tone: .accent)
            }
            Text(L10n.tr("编辑完整 SKILL.md，包含 name、description 和正文。保存后可在项目草稿中选择。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            HStack {
                Text(L10n.tr("技能标识"))
                TextField("my-skill", text: $draft.slug)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isEditing)
                    .accessibilityIdentifier("skills.editor.slug")
            }
            if draft.original != nil && !isEditing {
                Text(L10n.tr("将复制到 personal 来源，附带文件一并保留。相同标识的不同来源可共存。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }
            TextEditor(text: $draft.document)
                .font(AppFont.body.monospaced())
                .border(AppColor.border)
                .accessibilityLabel("SKILL.md")
                .accessibilityIdentifier("skills.editor.document")
            Text(model.runtimePaths.libraryRoot.path)
                .font(AppFont.metadata.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            if let error = model.libraryError {
                Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Button(L10n.tr("取消")) { cancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.tr("保存技能")) {
                    if model.saveSkill(draft) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(draft.slug.isEmpty || draft.document.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("skills.editor.save")
            }
        }
        .padding(24)
        .frame(minWidth: 640, idealWidth: 720, minHeight: 520, idealHeight: 620)
        .interactiveDismissDisabled(hasChanges)
        .confirmationDialog(L10n.tr("放弃未保存的修改？"), isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(L10n.tr("放弃修改"), role: .destructive) { model.libraryError = nil; dismiss() }
            Button(L10n.tr("继续编辑"), role: .cancel) {}
        }
    }

    private func cancel() {
        if hasChanges { confirmDiscard = true }
        else { model.libraryError = nil; dismiss() }
    }
}
