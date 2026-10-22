import SwiftUI

struct RuleFilePreviewView: View {
    let preview: RuleFilePreview
    @State private var mode = 0

    private var content: String? { mode == 0 ? preview.diff : mode == 1 ? preview.before : preview.after }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preview.id).font(AppFont.code.weight(.semibold)).textSelection(.enabled)
            Picker(L10n.tr("规则内容"), selection: $mode) {
                Text(L10n.tr("差异")).tag(0)
                Text(L10n.tr("写入前")).tag(1)
                Text(L10n.tr("写入后")).tag(2)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("templates.plan.contentMode")
            if mode == 0 {
                Text(L10n.tr("− 表示移除的行，+ 表示写入的行；其余行为上下文。"))
                    .font(AppFont.metadata).foregroundStyle(.secondary)
            }
            Text(content ?? L10n.tr("文件不存在"))
                .font(AppFont.code).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("templates.plan.ruleContent")
        }
    }
}
