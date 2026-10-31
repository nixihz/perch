import SwiftUI
import SkillSetCore

struct SkillEditorSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SkillEditorDraft
    @State private var confirmDiscard = false
    @State private var showsPreview = false
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
                    .font(AppFont.title)
                Spacer()
                StatusBadge(text: L10n.tr("本机技能库"), tone: .accent)
            }
            HStack {
                Text(L10n.tr("技能标识"))
                TextField("my-skill", text: $draft.slug)
                    .textFieldStyle(AppTextFieldStyle())
                    .disabled(isEditing)
                    .accessibilityIdentifier("skills.editor.slug")
            }
            if draft.original != nil && !isEditing {
                Text(L10n.tr("将复制到 custom 来源，附带文件一并保留。相同标识的不同来源可共存。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }
            HStack {
                Text("SKILL.md").font(AppFont.heading)
                Spacer()
                AppSegmentedPicker(title: L10n.tr("编辑视图"), selection: $showsPreview,
                    options: [(false, L10n.tr("编辑")), (true, L10n.tr("预览"))])
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("skills.editor.mode")
            }
            Group {
                if showsPreview {
                    ScrollView {
                        SkillMarkdownView(source: draft.document)
                            .padding(16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColor.controlSurface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.border, lineWidth: 1))
                    .accessibilityIdentifier("skills.editor.preview")
                } else {
                    TextEditor(text: $draft.document)
                        .font(AppFont.body.monospaced())
                        .appEditorSurface()
                        .accessibilityLabel("SKILL.md")
                        .accessibilityIdentifier("skills.editor.document")
                }
            }
            .frame(minHeight: 160, maxHeight: .infinity)
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.tr("保存位置"))
                Text(model.runtimePaths.sourcesRoot.appendingPathComponent(SkillLibraryStore.sourceID, isDirectory: true).path)
                    .font(AppFont.metadata.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if let error = model.libraryError {
                Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red).textSelection(.enabled)
            } else if draft.slug.isEmpty || draft.document.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(L10n.tr("请填写技能标识和 SKILL.md 正文，再保存。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }
            HStack {
                Button(L10n.tr("取消")) { cancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.tr("保存技能")) {
                    if model.saveSkill(draft) { dismiss() }
                }
                .buttonStyle(AppButtonStyle(kind: .primary))
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(draft.slug.isEmpty || draft.document.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("skills.editor.save")
            }
        }
        .appControls()
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
