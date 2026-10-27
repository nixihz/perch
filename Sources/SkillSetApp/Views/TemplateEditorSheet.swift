import SwiftUI
import SkillSetCore

struct TemplateEditorSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TemplateEditorDraft
    @State private var confirmDiscard = false
    private let initial: TemplateEditorDraft

    init(model: AppModel, initialDraft: TemplateEditorDraft) {
        self.model = model
        initial = initialDraft
        _draft = State(initialValue: initialDraft)
    }

    private var hasChanges: Bool { draft != initial }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text(draft.isEditing ? "编辑片段" : "新增片段"))
                .font(AppFont.title)
            Text(L10n.tr("保存到本机片段库，随后可在项目或预设中选择。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            AppFormField(L10n.tr("片段名称")) {
                TextField(L10n.tr("例如：代码审查约定"), text: $draft.title)
                    .textFieldStyle(AppTextFieldStyle()).accessibilityIdentifier("templates.editor.title")
            }
            AppFormField(L10n.tr("说明（可选）")) {
                TextField(L10n.tr("什么时候使用这个片段"), text: $draft.purpose)
                    .textFieldStyle(AppTextFieldStyle()).accessibilityIdentifier("templates.editor.purpose")
            }
            Text(L10n.tr("规则正文")).font(AppFont.heading)
            TextEditor(text: $draft.body)
                .font(AppFont.body.monospaced()).appEditorSurface()
                .accessibilityLabel(L10n.tr("规则正文"))
                .accessibilityIdentifier("templates.editor.body")
            Text(L10n.tr("只填写规则，起止标记由栖集自动添加。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            if let error = model.templateError {
                Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red).textSelection(.enabled)
            } else if let issue = TemplateStore.validationIssue(draft.record) {
                Text(L10n.text(issue)).font(AppFont.secondary).foregroundStyle(.secondary)
            }
            HStack {
                Button(L10n.tr("取消")) { cancel() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.tr("保存片段")) {
                    if model.saveTemplate(draft) { dismiss() }
                }
                .buttonStyle(AppButtonStyle(kind: .primary)).keyboardShortcut("s", modifiers: [.command])
                .disabled(TemplateStore.validationIssue(draft.record) != nil)
                .accessibilityIdentifier("templates.editor.save")
            }
        }
        .appControls()
        .padding(24)
        .frame(minWidth: 640, idealWidth: 720, minHeight: 520, idealHeight: 620)
        .interactiveDismissDisabled(hasChanges)
        .onChange(of: draft) { _, _ in model.templateError = nil }
        .confirmationDialog(L10n.tr("放弃未保存的修改？"), isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(L10n.tr("放弃修改"), role: .destructive) { model.templateError = nil; dismiss() }
            Button(L10n.tr("继续编辑"), role: .cancel) {}
        }
    }

    private func cancel() {
        if hasChanges { confirmDiscard = true }
        else { model.templateError = nil; dismiss() }
    }
}
