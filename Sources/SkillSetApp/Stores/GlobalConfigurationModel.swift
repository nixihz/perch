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
    private(set) var skillEditingErrors: [MCPHost: String] = [:]
    private var skillDrafts: [MCPHost: GlobalConfigurationDraft] = [:]
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
        inspection = nil
        operations = []
        draft = GlobalConfigurationDraft()
        for target in MCPHost.allCases {
            do {
                let observed = try manager.inspect(host: target)
                inheritedResources[target] = observed.resources
                inheritanceErrors[target] = nil
                if target == host { inspection = observed }
                let loaded = try manager.draft(host: target)
                skillDrafts[target] = loaded
                skillEditingErrors[target] = nil
                if target == host { draft = loaded }
            } catch {
                let message = UserFacingText.error(error)
                skillDrafts[target] = nil
                skillEditingErrors[target] = message
                if target == host { self.error = message }
            }
        }
        do {
            operations = try manager.history(host: host)
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
        setSkill(id, enabled: enabled, host: host)
    }

    func isSkillSelected(_ id: String, host: MCPHost) -> Bool {
        skillDrafts[host]?.skillIDs.contains(id) == true
    }

    func canEditSkills(host: MCPHost) -> Bool {
        skillDrafts[host] != nil && skillEditingErrors[host] == nil
    }

    func setSkill(_ skill: SkillEntry, enabled: Bool, host: MCPHost, catalog: [SkillEntry]) {
        guard !enabled || !skill.isBlocked else {
            error = L10n.tr("\(skill.slug) 含阻塞问题，未加入草稿")
            return
        }
        if enabled, let selected = skillDrafts[host]?.skillIDs,
           catalog.contains(where: { $0.id != skill.id && $0.slug == skill.slug && selected.contains($0.id) }) {
            error = L10n.tr("\(skill.slug) 已有另一个来源，先移除同名条目")
            return
        }
        setSkill(skill.id, enabled: enabled, host: host)
    }

    func setSkill(_ id: String, enabled: Bool, host: MCPHost) {
        guard canEditSkills(host: host), var next = skillDrafts[host] else {
            error = skillEditingErrors[host]
            return
        }
        guard next.skillIDs.contains(id) != enabled else { return }
        next.skillIDs.removeAll { $0 == id }
        if enabled { next.skillIDs.append(id) }
        next.skillIDs.sort()
        save(next, host: host)
    }

    func setInstruction(_ id: String, enabled: Bool) {
        var next = draft
        next.instructionIDs.removeAll { $0 == id }
        if enabled { next.instructionIDs.append(id) }
        save(next)
    }

    private func save(_ next: GlobalConfigurationDraft) {
        save(next, host: host)
    }

    private func save(_ next: GlobalConfigurationDraft, host: MCPHost) {
        guard canEditSkills(host: host) else {
            error = skillEditingErrors[host]
            return
        }
        do {
            try manager.saveDraft(next, host: host)
            skillDrafts[host] = next
            if host == self.host { draft = next }
            error = nil
        } catch { self.error = UserFacingText.error(error) }
    }

    func prepareDeployment() -> StoredDeploymentPlan? {
        guard canEditSkills(host: host) else {
            error = skillEditingErrors[host]
            return nil
        }
        return prepare {
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
