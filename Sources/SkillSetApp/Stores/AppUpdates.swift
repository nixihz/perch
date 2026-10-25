import Combine
import Foundation
import Sparkle

/// 所有窗口与菜单共用更新器，偏好和调度交给 Sparkle 持久化。
@MainActor
final class AppUpdates: ObservableObject {
    static let shared = AppUpdates()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var isReady = false
    @Published private(set) var unavailableReason: String?
    let version: String
    private var controller: SPUStandardUpdaterController?

    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        let release = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "—"
        version = "\(release) (\(build))"
        guard UpdateConfiguration(info: info) != nil else {
            unavailableReason = "这个版本暂不支持在线更新，请到官网下载新版。"
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
        )
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
        do {
            try controller.updater.start()
            isReady = true
        } catch {
            unavailableReason = "更新服务暂时不可用，请重新打开应用后再试。"
        }
    }

    func checkForUpdates() {
        guard isReady, canCheckForUpdates else { return }
        controller?.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard isReady else { return }
        controller?.updater.automaticallyChecksForUpdates = enabled
    }
}
