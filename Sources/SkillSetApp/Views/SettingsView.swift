import SwiftUI

struct SettingsView: View {
    @Bindable var preferences = AppPreferences.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppLayout.columnSpacing) {
                PageHeader(
                    eyebrow: "SETTINGS",
                    title: L10n.text("设置"),
                    detail: L10n.text("外观与语言")
                )
                SurfaceCard {
                    HStack {
                        Label(L10n.text("外观"), systemImage: "circle.lefthalf.filled")
                            .font(AppFont.heading)
                        Spacer()
                        Picker(L10n.text("外观"), selection: $preferences.appearance) {
                            Text(L10n.text("跟随系统")).tag(AppAppearance.system)
                            Text(L10n.text("日间模式")).tag(AppAppearance.light)
                            Text(L10n.text("夜间模式")).tag(AppAppearance.dark)
                        }
                        .labelsHidden()
                        .frame(width: 180)
                        .accessibilityIdentifier("settings.appearance")
                    }
                    Divider()
                    HStack {
                        Label(L10n.text("语言"), systemImage: "globe")
                            .font(AppFont.heading)
                        Spacer()
                        Picker(L10n.text("语言"), selection: $preferences.language) {
                            Text(L10n.text("跟随系统")).tag(AppLanguage.system)
                            Text("中文").tag(AppLanguage.chinese)
                            Text("English").tag(AppLanguage.english)
                        }
                        .labelsHidden()
                        .frame(width: 180)
                        .accessibilityIdentifier("settings.language")
                    }
                }
                Text(L10n.text("更改立即生效，并在下次打开时保留。"))
                    .font(AppFont.secondary)
                    .foregroundStyle(.secondary)
                Label(L10n.text("受管写入仍需本机人工批准。"), systemImage: "lock.shield")
                    .font(AppFont.metadata)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
