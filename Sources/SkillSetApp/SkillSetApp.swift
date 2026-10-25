import SwiftUI

@main
struct SkillSetApp: App {
    @NSApplicationDelegateAdaptor(MainWindowAppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @StateObject private var updates = AppUpdates.shared

    var body: some Scene {
        Window(L10n.text("栖集"), id: MainWindowAppDelegate.sceneID) {
            ContentView(model: model)
                .appPreferences()
                .modifier(MainWindowReopenRegistration(appDelegate: appDelegate))
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            MainWindowCommands()
            CommandGroup(replacing: .appSettings) {
                Button(L10n.tr("设置")) {
                    model.section = .settings
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            CommandGroup(after: .appInfo) {
                Button(L10n.tr("检查更新…")) {
                    updates.checkForUpdates()
                }
                .disabled(!updates.canCheckForUpdates)
            }
            CommandMenu(L10n.tr("前往")) {
                ForEach(Array(NavigationItem.groups.enumerated()), id: \.offset) { index, group in
                    if index > 0 { Divider() }
                    ForEach(group.items) { item in
                        Button(item.title) {
                            model.section = item
                        }
                        .keyboardShortcut(KeyEquivalent(Character(item.keyboardShortcut)), modifiers: [.command])
                    }
                }
            }
        }
    }
}
