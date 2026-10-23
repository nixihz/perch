import Foundation
import Observation
import SkillSetCore

struct MCPLibraryUsageTarget: Identifiable, Sendable {
    let id: String
    let host: MCPHost
    let projectID: UUID?
    let projectName: String?
    let configPath: String
    let selectedIDs: [UUID]
    let appliedEntries: [MCPLibraryEntry]
    let observedNames: [String]
    let issue: String?

    func references(_ entry: MCPLibraryEntry) -> Bool {
        selectedIDs.contains(entry.id) || appliedEntries.contains { $0.id == entry.id }
    }
}

@MainActor
@Observable
final class MCPLibraryModel {
    private(set) var entries: [MCPLibraryEntry] = []
    private(set) var selections: [String: [UUID]] = [:]
    private(set) var candidates: [MCPLibraryScanCandidate] = []
    private(set) var usageTargets: [MCPLibraryUsageTarget] = []
    private(set) var usageError: String?
    private var usageRefreshID = UUID()
    private var preferredUsageTargetID: String?
    private(set) var lastSavedID: UUID?
    private(set) var lastImportedIDs: [UUID] = []
    var error: String?
    let store: MCPLibraryStore
    private let paths: SkillSetRuntimePaths
    private let locations: GlobalConfigurationLocations?

    init(paths: SkillSetRuntimePaths, locations: GlobalConfigurationLocations? = nil) {
        self.paths = paths
        self.locations = locations
        self.store = MCPLibraryStore(rootURL: paths.applicationSupportRoot)
        refresh()
    }

    func refresh() {
        do { entries = try store.entries(); error = nil }
        catch { self.error = UserFacingText.error(error) }
    }

    func save(_ entry: MCPLibraryEntry) -> Bool {
        do {
            let saved = try store.save(entry)
            entries = try store.entries()
            lastSavedID = saved.id
            error = nil
            return true
        } catch { self.error = UserFacingText.error(error); return false }
    }

    func remove(_ entry: MCPLibraryEntry) {
        do { try store.remove(entry.id); refresh(); refreshUsage() }
        catch { self.error = UserFacingText.error(error) }
    }

    func selectedIDs(host: MCPHost, projectID: UUID?) -> [UUID] {
        selections[store.selectionKey(host: host, projectID: projectID)] ?? []
    }

    func preferUsageTarget(host: MCPHost, projectID: UUID?) {
        preferredUsageTargetID = store.selectionKey(host: host, projectID: projectID)
    }

    func initialUsageTargetID(fallbackHost: MCPHost) -> String {
        let preferred = preferredUsageTargetID ?? store.selectionKey(host: fallbackHost, projectID: nil)
        return usageTargets.contains { $0.id == preferred } ? preferred : ""
    }

    func loadSelection(host: MCPHost, projectID: UUID?) {
        usageRefreshID = UUID()
        do {
            selections[store.selectionKey(host: host, projectID: projectID)] = try store.selectedIDs(host: host, projectID: projectID)
            error = nil
        } catch { self.error = UserFacingText.error(error) }
    }

    @discardableResult
    func select(_ id: UUID, enabled: Bool, host: MCPHost, projectID: UUID?) -> Bool {
        usageRefreshID = UUID()
        do {
            if enabled, !entries.contains(where: { $0.id == id }) { throw MCPLibraryError.missingSelection }
            var ids = try store.selectedIDs(host: host, projectID: projectID)
            ids.removeAll { $0 == id }
            if enabled { ids.append(id) }
            try store.saveSelection(ids, host: host, projectID: projectID)
            selections[store.selectionKey(host: host, projectID: projectID)] = ids
            error = nil
            return true
        } catch { self.error = UserFacingText.error(error); return false }
    }

    nonisolated private static func readUsage(paths: SkillSetRuntimePaths, locations: GlobalConfigurationLocations?) throws -> [MCPLibraryUsageTarget] {
        let store = MCPLibraryStore(rootURL: paths.applicationSupportRoot)
        let resolved = locations ?? .detect(stateRoot: paths.applicationSupportRoot)
        let projects = try ProjectStore(rootURL: paths.applicationSupportRoot).list()
        var targets: [MCPLibraryUsageTarget] = []
        let contexts: [(UUID?, String?, URL?)] = [(nil, nil, nil)] + projects.map {
            ($0.id, $0.name, URL(fileURLWithPath: $0.canonicalPath))
        }
        for (projectID, projectName, root) in contexts {
            let manager = MCPConfigurationManager(projectRoot: root, applicationSupportRoot: paths.applicationSupportRoot,
                environment: ["CODEX_HOME": resolved.codexRoot.path], homeDirectory: resolved.home)
            for target in manager.targets() where target.scope == (projectID == nil ? .user : .project) {
                let inspection = manager.inspect(target)
                let selected = try store.selectedIDs(host: target.host, projectID: projectID)
                let applied = try store.applied(configPath: target.configPath)
                targets.append(MCPLibraryUsageTarget(id: store.selectionKey(host: target.host, projectID: projectID),
                    host: target.host, projectID: projectID, projectName: projectName, configPath: target.configPath,
                    selectedIDs: selected, appliedEntries: applied?.entries ?? [], observedNames: inspection.servers.map(\.name),
                    issue: UserFacingText.mcpStatus(inspection)))
            }
        }
        return targets
    }

    private func applyUsage(_ result: Result<[MCPLibraryUsageTarget], Error>) {
        do {
            usageTargets = try result.get()
            for target in usageTargets { selections[target.id] = target.selectedIDs }
            usageError = nil
        } catch { usageError = UserFacingText.error(error) }
    }

    func refreshUsage() {
        usageRefreshID = UUID()
        applyUsage(Result { try Self.readUsage(paths: paths, locations: locations) })
    }

    func refreshUsageInBackground() async {
        guard !Task.isCancelled else { return }
        let request = UUID()
        usageRefreshID = request
        let paths = paths, locations = locations
        let result = await Task.detached(priority: .userInitiated) {
            Result { try Self.readUsage(paths: paths, locations: locations) }
        }.value
        guard usageRefreshID == request, !Task.isCancelled else { return }
        applyUsage(result)
    }

    func prepareUse(_ entry: MCPLibraryEntry, host: MCPHost, projectID: UUID?) -> StoredDeploymentPlan? {
        guard select(entry.id, enabled: true, host: host, projectID: projectID) else { return nil }
        do {
            let plan = try SkillSetService(paths: paths, globalLocations: locations).makeMCPLibraryPlan(host: host, projectID: projectID)
            refreshUsage()
            return plan
        } catch { self.error = UserFacingText.error(error); refreshUsage(); return nil }
    }

    func scan() {
        do {
            candidates = try SkillSetService(paths: paths, globalLocations: locations).scanMCPLibrary()
            lastImportedIDs = []
            error = nil
        } catch { candidates = []; self.error = UserFacingText.error(error) }
    }

    func duplicate(_ candidate: MCPLibraryScanCandidate) -> Bool {
        entries.contains { $0.name == candidate.name }
    }

    var availableCandidates: [MCPLibraryScanCandidate] {
        candidates.filter { $0.entry != nil && !duplicate($0) }
    }

    /// 同名候选必须由用户明确选来源；批量选择跳过有歧义的名称。
    var unambiguousCandidateIDs: Set<String> {
        let groups = Dictionary(grouping: availableCandidates, by: \.name)
        return Set(groups.values.filter { $0.count == 1 }.compactMap { $0.first?.id })
    }

    func updatingScanSelection(_ selected: Set<String>, candidateID: String, enabled: Bool) -> Set<String> {
        guard let candidate = availableCandidates.first(where: { $0.id == candidateID }) else { return selected }
        var result = selected
        result.remove(candidateID)
        if enabled {
            let sameNameIDs = Set(candidates.filter { $0.name == candidate.name }.map(\.id))
            result.subtract(sameNameIDs)
            result.insert(candidateID)
        }
        return result
    }

    func importCandidates(_ ids: Set<String>) -> Bool {
        do {
            guard !ids.isEmpty, ids.isSubset(of: Set(candidates.map(\.id))) else { throw MCPLibraryError.scanChanged }
            let fresh = try SkillSetService(paths: paths, globalLocations: locations).scanMCPLibrary()
            let selected = try candidates.filter { ids.contains($0.id) }.map { candidate in
                guard let entry = candidate.entry,
                      fresh.contains(where: { $0.id == candidate.id && $0.entry?.draft(host: .codex, scope: .user) == entry.draft(host: .codex, scope: .user) }) else {
                    throw MCPLibraryError.scanChanged
                }
                return entry
            }
            try store.importEntries(selected)
            entries = try store.entries()
            lastImportedIDs = selected.map(\.id)
            lastSavedID = selected.first?.id
            error = nil
            return true
        } catch { self.error = UserFacingText.error(error); return false }
    }
}
