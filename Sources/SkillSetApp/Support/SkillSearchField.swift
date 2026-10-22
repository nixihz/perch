import SwiftUI

/// 搜索紧邻受影响的列表，避免将技能筛选误认为全应用搜索。
struct SkillSearchField: View {
    @Binding var query: String
    @FocusState private var isFocused: Bool

    init(model: AppModel) {
        _query = Binding(get: { model.query }, set: { model.updateQuery($0) })
    }

    init(query: Binding<String>) { _query = query }

    var body: some View {
        HStack(spacing: 4) {
            Button { isFocused = true } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: [.command])
            .accessibilityLabel(L10n.tr("搜索技能"))
            .help(L10n.tr("搜索技能（⌘F）"))
            .accessibilityIdentifier("skills.search.focus")
            TextField(L10n.tr("搜索技能、来源或路径"), text: $query)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .accessibilityIdentifier("skills.search")
            if !query.isEmpty {
                Button { query = ""; isFocused = true } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("清空搜索"))
                .help(L10n.tr("清空搜索"))
                .accessibilityIdentifier("skills.search.clear")
            }
        }
        .font(AppFont.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isFocused ? AppColor.accent : AppColor.border, lineWidth: isFocused ? 2 : 1)
        }
    }
}
