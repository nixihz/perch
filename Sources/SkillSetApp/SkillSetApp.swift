import SwiftUI

@main
struct SkillSetApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup(L10n.text("栖集"), id: "main") {
            ContentView(model: model)
                .appPreferences()
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.tr("设置")) {
                    model.section = .settings
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            CommandGroup(after: .appInfo) {
                Button(L10n.tr("显示项目")) {
                    model.section = .projects
                }
                .keyboardShortcut("1", modifiers: [.command])
                Button(L10n.tr("显示 Skills")) {
                    model.section = .skills
                }
                .keyboardShortcut("2", modifiers: [.command])
                Button(L10n.tr("显示 MCP Servers")) {
                    model.section = .mcp
                }
                .keyboardShortcut("3", modifiers: [.command])
            }
        }
    }
}
