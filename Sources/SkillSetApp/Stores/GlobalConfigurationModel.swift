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
    private(set) var isRefreshing = false
    private var refreshID = UUID()
    private var inheritanceID = UUID()
    private var skillDrafts: [MCPHost: GlobalConfigurationDraft] = [:]
    private var availableSkillIDs: Set<String>?
    private var availableInstructionIDs: Set<String>?
    let locations: GlobalConfigurationLocations
    private let paths: SkillSetRuntimePaths

    init(paths: SkillSetRuntimePaths, locations: GlobalConfigurationLocations? = nil) {
        self.paths = paths
        self.locations = locations ?? .detect(stateRoot: paths.applicationSupportRoot)
    }

    private var manager: GlobalConfigurationManager { GlobalConfigurationManager(paths: paths, locations: locations) }

    func selectHost(_ host: MCPHost, inBackground: Bool = false) {
        self.host = host
        takeOverExisting = false
        inspection = nil
        operations = []
        draft = GlobalConfigurationDraft()
        if inBackground {
            // 先封住空草稿的编辑窗口；排队中的切换也不能抢回后续同步刷新的代次。
            let request = UUID()
            refreshID = request
            isRefreshing = true
            Task {
                guard refreshID == request else { return }
                await refreshInBackground()
            }
        } else { refresh() }
    }

    private struct HostSnapshot: Sendable {
        let host: MCPHost
        let inspection: Result<GlobalConfigurationInspection, Error>
        let draft: Result<GlobalConfigurationDraft, Error>
        let history: Result<[GlobalOperationRecord], Error>
    }

    nonisolated private static func read(paths: SkillSetRuntimePaths, locations: GlobalConfigurationLocations) -> [HostSnapshot] {
        let manager = GlobalConfigurationManager(paths: paths, locations: locations)
        return MCPHost.allCases.map { host in
            HostSnapshot(host: host, inspection: Result { try manager.inspect(host: host) },
                         draft: Result { try manager.draft(host: host) },
                         history: Result { try manager.history(host: host) })
        }
    }

    func refresh() {
        refreshID = UUID()
        inheritanceID = UUID()
        isRefreshing = false
        apply(Self.read(paths: paths, locations: locations), inheritanceRequest: inheritanceID)
    }

    /// 页面进入只发起后台读取；保留上次结果，避免切页时闪空和阻塞导航。
    func refreshInBackground() async {
        guard !Task.isCancelled else { return }
        let id = UUID()
        refreshID = id
        let inheritanceRequest = UUID()
        inheritanceID = inheritanceRequest
        isRefreshing = true
        let paths = paths, locations = locations
        let result = await Task.detached(priority: .userInitiated) {
            Self.read(paths: paths, locations: locations)
        }.value
        guard refreshID == id else { return }
        isRefreshing = false
        guard !Task.isCancelled else { return }
        apply(result, inheritanceRequest: inheritanceRequest)
    }

    private func apply(_ snapshots: [HostSnapshot], inheritanceRequest: UUID) {
        error = nil
        for snapshot in snapshots {
            let target = snapshot.host
            do {
                let observed = try snapshot.inspection.get()
                if inheritanceID == inheritanceRequest {
                    inheritedResources[target] = observed.resources
                    inheritanceErrors[target] = nil
                }
                if target == host { inspection = observed }
            } catch {
                if inheritanceID == inheritanceRequest {
                    inheritedResources[target] = nil
                    inheritanceErrors[target] = UserFacingText.error(error)
                }
                if target == host { inspection = nil; self.error = UserFacingText.error(error) }
            }
            do {
                // 盘点失败时继续阻止草稿编辑，不能把无法核对的宿主显示为可配置。
                _ = try snapshot.inspection.get()
                let loaded = try snapshot.draft.get()
                skillDrafts[target] = loaded
                reconcileDraftIfNeeded(host: target)
                skillEditingErrors[target] = nil
                if target == host { draft = skillDrafts[target] ?? loaded }
            } catch {
                skillDrafts[target] = nil
                skillEditingErrors[target] = UserFacingText.error(error)
                if target == host { draft = GlobalConfigurationDraft(); self.error = UserFacingText.error(error) }
            }
            if target == host {
                do { operations = try snapshot.history.get() }
                catch { operations = []; self.error = UserFacingText.error(error) }
            }
        }
    }

    /// 外部来源或技能库条目被删除后，自动清理草稿中的悬空引用，保留页面可编辑状态。
    func setAvailableReferences(skillIDs: Set<String>, instructionIDs: Set<String>) {
        availableSkillIDs = skillIDs
        availableInstructionIDs = instructionIDs
        for host in MCPHost.allCases { reconcileDraftIfNeeded(host: host) }
    }

    private func reconcileDraftIfNeeded(host: MCPHost) {
        guard var next = skillDrafts[host] else { return }
        guard let availableSkillIDs, let availableInstructionIDs else { return }
        let skills = next.skillIDs.filter(availableSkillIDs.contains)
        let instructions = next.instructionIDs.filter(availableInstructionIDs.contains)
        guard skills != next.skillIDs || instructions != next.instructionIDs else { return }
        next.skillIDs = skills
        next.instructionIDs = instructions
        do {
            try manager.saveDraft(next, host: host)
            skillDrafts[host] = next
            if host == self.host { draft = next }
        } catch {
            // 草稿落盘失败仍保留内存中的可用选择，避免删除外部文件后锁死页面。
            skillDrafts[host] = next
            if host == self.host { draft = next }
        }
    }

    func refreshInheritance() {
        inheritanceID = UUID()
        applyInheritance(Self.readInheritance(paths: paths, locations: locations))
    }

    nonisolated private static func readInheritance(paths: SkillSetRuntimePaths, locations: GlobalConfigurationLocations)
        -> [MCPHost: Result<[GlobalResourceObservation], Error>] {
        let manager = GlobalConfigurationManager(paths: paths, locations: locations)
        return Dictionary(uniqueKeysWithValues: MCPHost.allCases.map { host in
            (host, Result { try manager.inspect(host: host).resources })
        })
    }

    func refreshInheritanceInBackground() async {
        guard !Task.isCancelled else { return }
        let id = UUID()
        inheritanceID = id
        let paths = paths, locations = locations
        let result = await Task.detached(priority: .userInitiated) {
            Self.readInheritance(paths: paths, locations: locations)
        }.value
        guard inheritanceID == id, !Task.isCancelled else { return }
        applyInheritance(result)
    }

    private func applyInheritance(_ results: [MCPHost: Result<[GlobalResourceObservation], Error>]) {
        for (host, result) in results {
            do {
                inheritedResources[host] = try result.get()
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
        !isRefreshing && skillDrafts[host] != nil && skillEditingErrors[host] == nil
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
