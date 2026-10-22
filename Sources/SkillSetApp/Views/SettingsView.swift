import SwiftUI

struct SettingsView: View {
    @Bindable var preferences = AppPreferences.shared
    @ObservedObject var updates = AppUpdates.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppLayout.columnSpacing) {
                PageHeader(
                    eyebrow: "SETTINGS",
                    title: L10n.text("设置"),
                    detail: L10n.text("外观、语言与软件更新")
                )
                SurfaceCard {
                    HStack {
                        Label(L10n.text("外观"), systemImage: "circle.lefthalf.filled")
                            .font(AppFont.heading)
                        Spacer()
                        AppPicker(title: L10n.text("外观"), selection: $preferences.appearance,
                                  valueLabel: L10n.text(preferences.appearance == .system ? "跟随系统" : preferences.appearance == .light ? "日间模式" : "夜间模式"), showsLabel: false) {
                            Text(L10n.text("跟随系统")).tag(AppAppearance.system)
                            Text(L10n.text("日间模式")).tag(AppAppearance.light)
                            Text(L10n.text("夜间模式")).tag(AppAppearance.dark)
                        }
                        .frame(width: 180)
                        .accessibilityIdentifier("settings.appearance")
                    }
                    Divider()
                    HStack {
                        Label(L10n.text("语言"), systemImage: "globe")
                            .font(AppFont.heading)
                        Spacer()
                        AppPicker(title: L10n.text("语言"), selection: $preferences.language,
                                  valueLabel: preferences.language == .system ? L10n.text("跟随系统") : preferences.language == .chinese ? "中文" : "English", showsLabel: false) {
                            Text(L10n.text("跟随系统")).tag(AppLanguage.system)
                            Text("中文").tag(AppLanguage.chinese)
                            Text("English").tag(AppLanguage.english)
                        }
                        .frame(width: 180)
                        .accessibilityIdentifier("settings.language")
                    }
                }
                Text(L10n.text("更改立即生效，并在下次打开时保留。"))
                    .font(AppFont.secondary)
                    .foregroundStyle(.secondary)
                SurfaceCard {
                    Label(L10n.text("软件更新"), systemImage: "arrow.down.circle")
                        .font(AppFont.heading)
                    LabeledContent(L10n.text("当前版本"), value: updates.version)
                    Toggle(L10n.text("自动检查更新"), isOn: Binding(
                        get: { updates.automaticallyChecksForUpdates },
                        set: { updates.setAutomaticallyChecksForUpdates($0) }
                    ))
                    .disabled(!updates.isReady)
                    .accessibilityIdentifier("settings.automaticUpdates")
                    Text(L10n.text("发现新版本时通知你，由你决定何时安装。更新后应用会重新打开。"))
                        .font(AppFont.secondary)
                        .foregroundStyle(.secondary)
                    Button(L10n.text("检查更新…")) { updates.checkForUpdates() }
                        .disabled(!updates.canCheckForUpdates)
                        .accessibilityIdentifier("settings.checkForUpdates")
                    if let reason = updates.unavailableReason {
                        Text(L10n.text(reason))
                            .font(AppFont.secondary)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.updateStatus")
                    }
                }
                Label(L10n.text("写入项目或 AI 工具配置前，都需要你在本机批准。"), systemImage: "lock.shield")
                    .font(AppFont.metadata)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
