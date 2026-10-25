import Foundation
import Observation
import SkillSetCore

/// 插件选择只保存到栖集草稿，宿主命令仍由逐份预览的生命周期计划执行。
@MainActor
@Observable
final class PluginSelectionModel {
    private(set) var plugins: [PluginInventoryRecord] = []
    private(set) var issues: [String] = []
    private(set) var error: String?
    private(set) var isLoading = false
    private(set) var isReady = false
    private(set) var selections: [String: Bool] = [:]
    var acknowledgedRisk = false
    private var refreshID = UUID()
    private let paths: SkillSetRuntimePaths
    private let home: URL
    private let projectID: UUID?
    private let projectRoot: URL?
    private var draftURL: URL {
        paths.applicationSupportRoot.appendingPathComponent(projectID.map { "plugin-drafts/\($0.uuidString).json" } ?? "global/plugin-draft.json")
    }

    init(paths: SkillSetRuntimePaths, home: URL, projectID: UUID? = nil, projectRoot: URL? = nil) {
        self.paths = paths
        self.home = home
        self.projectID = projectID
        self.projectRoot = projectRoot
    }

    func refresh() async {
        let request = UUID()
        refreshID = request
        isLoading = true
        isReady = false
        let home = home, url = draftURL, projectRoot = projectRoot
        let result = await Task.detached(priority: .userInitiated) {
            Result {
                let snapshot = PluginInventoryManager(projectRoot: projectRoot, homeDirectory: home).inspect()
                let selections = FileManager.default.fileExists(atPath: url.path)
                    ? try JSONDecoder().decode([String: Bool].self, from: Data(contentsOf: url)) : [:]
                return (snapshot, selections)
            }
        }.value
        guard refreshID == request else { return }
        isLoading = false
        guard !Task.isCancelled else { return }
        do {
            let (snapshot, saved) = try result.get()
            plugins = snapshot.records.filter {
                if projectID != nil { return $0.host == .claudeCode && ($0.scope == nil || $0.scope == "project") }
                return $0.host == .codex || $0.scope == nil || $0.scope == "user"
            }
            issues = snapshot.issues
            selections = saved
            error = nil
            isReady = true
            acknowledgedRisk = false
        } catch { self.error = UserFacingText.error(error) }
    }

    func selected(_ plugin: PluginInventoryRecord) -> Bool {
        selections[selectionKey(plugin)] ?? selections[plugin.id] ?? (plugin.installed && plugin.enabled != false)
    }

    private func selectionKey(_ plugin: PluginInventoryRecord) -> String {
        // 安装前后的 scope 可能变化，草稿键绑定包内容，避免卸载后重新命中旧安装选择。
        "\(plugin.host.rawValue):\(plugin.pluginID):\(plugin.manifestDigest)"
    }

    func select(_ plugin: PluginInventoryRecord, enabled: Bool) {
        guard !isLoading, isReady, plugins.contains(where: { $0.id == plugin.id && $0.manifestDigest == plugin.manifestDigest }) else { return }
        var next = selections
        // 同一个插件的两个缓存版本不能同时进入安装草稿。
        let prefix = "\(plugin.host.rawValue):\(plugin.pluginID):"
        for key in next.keys.filter({ $0.hasPrefix(prefix) }) { next.removeValue(forKey: key) }
        if enabled != (plugin.installed && plugin.enabled != false) { next[selectionKey(plugin)] = enabled }
        do {
            try FileManager.default.createDirectory(at: draftURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: draftURL, options: .atomic)
            selections = next
            error = nil
            acknowledgedRisk = false
        } catch { self.error = UserFacingText.error(error) }
    }

    func action(_ plugin: PluginInventoryRecord) -> PluginLifecycleAction? {
        let enabled = selected(plugin)
        if !plugin.installed { return enabled ? .install : nil }
        if enabled == (plugin.enabled != false) { return nil }
        return enabled ? .enable : (plugin.host == .codex ? .uninstall : .disable)
    }

    func pending(host: MCPHost) -> [PluginInventoryRecord] {
        plugins.filter { $0.host == host && action($0) != nil }
    }

    func prepare(_ plugin: PluginInventoryRecord, locations: GlobalConfigurationLocations) -> StoredDeploymentPlan? {
        guard let action = action(plugin) else { return nil }
        do {
            let plan = try SkillSetService(paths: paths, globalLocations: locations).makePluginLifecyclePlan(
                projectID: projectID, request: PluginLifecycleRequest(host: plugin.host, pluginID: plugin.pluginID,
                    action: action, scope: projectID == nil ? .user : .project, expectedManifestDigest: plugin.manifestDigest,
                    acknowledgeExecutableComponents: acknowledgedRisk))
            error = nil
            return plan
        } catch { self.error = UserFacingText.error(error); return nil }
    }
}
