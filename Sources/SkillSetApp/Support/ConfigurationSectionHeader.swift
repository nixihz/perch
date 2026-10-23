import SwiftUI

/// 配置区的主操作始终靠右；窄栏放不下时换行，避免标题和按钮被截断。
struct ConfigurationSectionHeader<Title: View, Actions: View>: View {
    @ViewBuilder let title: () -> Title
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                title().fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                actions().fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 10) {
                title()
                HStack {
                    Spacer(minLength: 0)
                    actions()
                }
            }
        }
        .buttonStyle(AppButtonStyle(kind: .primary))
    }
}
