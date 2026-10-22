import Foundation
import Observation
import SkillSetCore

@MainActor
@Observable
final class GlobalConfigurationModel {
    var host: MCPHost = .codex
    private(set) var draft = GlobalConfigurationDraft()
    private(set) var inspection: GlobalConfigurationInspection?
    private(set) var operations: [GlobalOperationRecord] = []
    private(set) var error: String?
    var query = ""
    var takeOverExisting = false
    private(set) var inheritedResources: [MCPHost: [GlobalResourceObservation]] = [:]
    private(set) var inheritanceErrors: [MCPHost: String] = [:]
    let locations: GlobalConfigurationLocations
    private let paths: SkillSetRuntimePaths

    init(paths: SkillSetRuntimePaths, locations: GlobalConfigurationLocations? = nil) {
        self.paths = paths
        self.locations = locations ?? .detect(stateRoot: paths.applicationSupportRoot)
    }

    private var manager: GlobalConfigurationManager { GlobalConfigurationManager(paths: paths, locations: locations) }

    func selectHost(_ host: MCPHost) {
        self.host = host
        takeOverExisting = false
        inspection = nil
        operations = []
        draft = GlobalConfigurationDraft()
        refresh()
    }

    func refresh() {
        error = nil
        do {
            operations = try manager.history(host: host)
            inspection = try manager.inspect(host: host)
            draft = try manager.draft(host: host)
        } catch {
            self.error = UserFacingText.error(error)
        }
        refreshInheritance()
    }

    func refreshInheritance() {
        for host in MCPHost.allCases {
            do {
                inheritedResources[host] = try manager.inspect(host: host).resources
                inheritanceErrors[host] = nil
            } catch {
                inheritedResources[host] = nil
                inheritanceErrors[host] = UserFacingText.error(error)
            }
        }
    }

    func setInstallMethod(_ method: SkillInstallMethod) {
        var next = draft
        next.installMethod = method
        save(next)
    }

    func setSkill(_ id: String, enabled: Bool) {
        var next = draft
        next.skillIDs.removeAll { $0 == id }
        if enabled { next.skillIDs.append(id) }
        save(next)
    }

    func setInstruction(_ id: String, enabled: Bool) {
        var next = draft
        next.instructionIDs.removeAll { $0 == id }
        if enabled { next.instructionIDs.append(id) }
        save(next)
    }

    private func save(_ next: GlobalConfigurationDraft) {
        do {
            try manager.saveDraft(next, host: host)
            draft = next
            error = nil
        } catch { self.error = UserFacingText.error(error) }
    }

    func prepareDeployment() -> StoredDeploymentPlan? {
        prepare {
            try SkillSetService(paths: paths, globalLocations: locations).makeGlobalPlan(
                host: host, selection: draft, takeOverExisting: takeOverExisting)
        }
    }

    func prepareRestore(_ mode: GlobalRestoreMode) -> StoredDeploymentPlan? {
        prepare { try manager.makeRestorePlan(host: host, mode: mode) }
    }

    func prepareUndo(_ operationID: UUID) -> StoredDeploymentPlan? {
        prepare { try manager.makeUndoPlan(host: host, operationID: operationID) }
    }

    private func prepare(_ work: () throws -> StoredDeploymentPlan) -> StoredDeploymentPlan? {
        error = nil
        do { return try work() }
        catch { self.error = UserFacingText.error(error); return nil }
    }

    func didApply() {
        // 还原后用实际期望刷新草稿，避免旧选择被误认为仍在管理。
        do {
            let selection = try manager.inspect(host: host).selection
            try manager.saveDraft(selection, host: host)
            takeOverExisting = false
        } catch { self.error = UserFacingText.error(error) }
        refresh()
    }
}
