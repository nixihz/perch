import SwiftUI

struct RuleFilePreviewView: View {
    let preview: RuleFilePreview
    @State private var mode = 0

    private var content: String? { mode == 0 ? preview.diff : mode == 1 ? preview.before : preview.after }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(preview.id)
                    .font(AppFont.code.weight(.semibold))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                AppSegmentedPicker(title: L10n.tr("规则内容"), selection: $mode,
                    options: [(0, L10n.tr("差异")), (1, L10n.tr("写入前")), (2, L10n.tr("写入后"))])
                .labelsHidden()
                .frame(width: 248)
                .accessibilityIdentifier("templates.plan.contentMode")
                .help(L10n.tr("− 表示移除的行，+ 表示写入的行；其余行为上下文。"))
            }
            ScrollView {
                Text(content ?? L10n.tr("文件不存在"))
                    .font(AppFont.code)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .accessibilityIdentifier("templates.plan.ruleContent")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
