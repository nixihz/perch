import Foundation
import Observation
import SkillSetCore

@MainActor
@Observable
final class MCPLibraryModel {
    private(set) var entries: [MCPLibraryEntry] = []
    private(set) var selections: [String: [UUID]] = [:]
    private(set) var candidates: [MCPLibraryScanCandidate] = []
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
        do { _ = try store.save(entry); refresh(); return true }
        catch { self.error = UserFacingText.error(error); return false }
    }

    func remove(_ entry: MCPLibraryEntry) {
        do { try store.remove(entry.id); refresh() }
        catch { self.error = UserFacingText.error(error) }
    }

    func selectedIDs(host: MCPHost, projectID: UUID?) -> [UUID] {
        selections[store.selectionKey(host: host, projectID: projectID)] ?? []
    }

    func loadSelection(host: MCPHost, projectID: UUID?) {
        do {
            selections[store.selectionKey(host: host, projectID: projectID)] = try store.selectedIDs(host: host, projectID: projectID)
            error = nil
        } catch { self.error = UserFacingText.error(error) }
    }

    func select(_ id: UUID, enabled: Bool, host: MCPHost, projectID: UUID?) {
        do {
            var ids = try store.selectedIDs(host: host, projectID: projectID)
            ids.removeAll { $0 == id }
            if enabled { ids.append(id) }
            try store.saveSelection(ids, host: host, projectID: projectID)
            loadSelection(host: host, projectID: projectID)
        } catch { self.error = UserFacingText.error(error) }
    }

    func scan() {
        do { candidates = try SkillSetService(paths: paths, globalLocations: locations).scanMCPLibrary(); error = nil }
        catch { self.error = UserFacingText.error(error) }
    }

    func duplicate(_ candidate: MCPLibraryScanCandidate) -> Bool {
        entries.contains { $0.name == candidate.name }
    }

    func importCandidates(_ ids: Set<String>) -> Bool {
        do {
            let fresh = try SkillSetService(paths: paths, globalLocations: locations).scanMCPLibrary()
            let selected = try candidates.filter { ids.contains($0.id) }.map { candidate in
                guard let entry = candidate.entry,
                      fresh.contains(where: { $0.id == candidate.id && $0.entry?.draft(host: .codex, scope: .user) == entry.draft(host: .codex, scope: .user) }) else {
                    throw MCPLibraryError.scanChanged
                }
                return entry
            }
            try store.importEntries(selected)
            refresh()
            return true
        } catch { self.error = UserFacingText.error(error); return false }
    }
}
