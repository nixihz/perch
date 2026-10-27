import SwiftUI

/// 搜索紧邻受影响的列表，所有页面共用焦点、清空行为和点击区域。
struct AppSearchField: View {
    @Binding var query: String
    let prompt: String
    let label: String
    let identifier: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Button { isFocused = true } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(isFocused ? AppColor.accentText : .secondary)
                    .frame(width: AppControl.iconTarget, height: AppControl.iconTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: .command)
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier + ".focus")
            TextField(prompt, text: $query)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
            if !query.isEmpty {
                Button { query = ""; isFocused = true } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: AppControl.iconTarget, height: AppControl.iconTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("清空搜索"))
                .help(L10n.tr("清空搜索"))
                .accessibilityIdentifier(identifier + ".clear")
            }
        }
        .font(AppFont.body)
        .frame(height: AppControl.height)
        .background {
            RoundedRectangle(cornerRadius: AppControl.radius)
                .fill(AppColor.controlSurface)
                .onTapGesture { isFocused = true }
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppControl.radius)
                .strokeBorder(isFocused ? AppColor.accent : AppColor.border, lineWidth: isFocused ? 2 : 1)
                .allowsHitTesting(false)
        }
    }
}

struct SkillSearchField: View {
    @Binding var query: String

    init(model: AppModel) {
        _query = Binding(get: { model.query }, set: { model.updateQuery($0) })
    }

    init(query: Binding<String>) { _query = query }

    var body: some View {
        AppSearchField(query: $query, prompt: L10n.tr("搜索技能、来源或路径"),
                       label: L10n.tr("搜索技能"), identifier: "skills.search")
    }
}
