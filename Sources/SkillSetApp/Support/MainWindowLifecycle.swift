import AppKit
import SwiftUI

@MainActor
final class MainWindowAppDelegate: NSObject, NSApplicationDelegate {
    static let sceneID = "main"
    var openMainWindow: (() -> Void)?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 交给 SwiftUI 按场景标识恢复窗口，避免持有已关闭的 NSWindow 或另建一套界面状态。
        guard let openMainWindow else { return true }
        openMainWindow()
        return false
    }
}

struct MainWindowReopenRegistration: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    let appDelegate: MainWindowAppDelegate

    func body(content: Content) -> some View {
        content.onAppear {
            // 关闭后保留场景打开动作；重建窗口时更新为当前环境的动作。
            appDelegate.openMainWindow = { openWindow(id: MainWindowAppDelegate.sceneID) }
        }
    }
}

struct MainWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button(L10n.tr("显示主窗口")) {
                openWindow(id: MainWindowAppDelegate.sceneID)
            }
            .keyboardShortcut("0", modifiers: [.command])
        }
    }
}
