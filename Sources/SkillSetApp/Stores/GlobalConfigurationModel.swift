import Foundation
import Observation
import SkillSetCore

@MainActor
@Observable
final class GlobalConfigurationModel {
    var host: SkillConfigurationTarget = .codex
    private(set) var draft = GlobalConfigurationDraft()
    private(set) var inspection: GlobalConfigurationInspection?
    private(set) var operations: [GlobalOperationRecord] = []
    private(set) var error: String?
    var query = ""
    var takeOverExisting = false
    private(set) var inheritedResources: [SkillConfigurationTarget: [GlobalResourceObservation]] = [:]
    private(set) var inheritanceErrors: [SkillConfigurationTarget: String] = [:]
    private(set) var skillEditingErrors: [SkillConfigurationTarget: String] = [:]
    private(set) var isRefreshing = false
    private(set) var isSavingSkill = false
    private(set) var skillSaveMessage: String?
    private var refreshID = UUID()
    private var inheritanceID = UUID()
    private var skillDrafts: [SkillConfigurationTarget: GlobalConfigurationDraft] = [:]
    private var availableSkillIDs: Set<String>?
    private var availableInstructionIDs: Set<String>?
    let locations: GlobalConfigurationLocations
    private let paths: SkillSetRuntimePaths

    init(paths: SkillSetRuntimePaths, locations: GlobalConfigurationLocations? = nil) {
        self.paths = paths
        self.locations = locations ?? .detect(stateRoot: paths.applicationSupportRoot)
    }

    private var manager: GlobalConfigurationManager { GlobalConfigurationManager(paths: paths, locations: locations) }

    func selectHost(_ host: SkillConfigurationTarget, inBackground: Bool = false) {
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
        let host: SkillConfigurationTarget
        let inspection: Result<GlobalConfigurationInspection, Error>
        let draft: Result<GlobalConfigurationDraft, Error>
        let history: Result<[GlobalOperationRecord], Error>
    }

    nonisolated private static func read(paths: SkillSetRuntimePaths, locations: GlobalConfigurationLocations) -> [HostSnapshot] {
        let manager = GlobalConfigurationManager(paths: paths, locations: locations)
        return SkillConfigurationTarget.allCases.map { host in
            HostSnapshot(host: host, inspection: Result { try manager.inspect(host: host) },
                         draft: Result { try manager.draft(host: host) },
                         history: Result { try manager.history(host: host) })
        }
    }

    func refresh() {
        guard !isSavingSkill else { return }
        refreshID = UUID()
        inheritanceID = UUID()
        isRefreshing = false
        apply(Self.read(paths: paths, locations: locations), inheritanceRequest: inheritanceID)
    }

    /// 页面进入只发起后台读取；保留上次结果，避免切页时闪空和阻塞导航。
    func refreshInBackground() async {
        guard !Task.isCancelled, !isSavingSkill else { return }
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
        for host in SkillConfigurationTarget.allCases { reconcileDraftIfNeeded(host: host) }
    }

    private func reconcileDraftIfNeeded(host: SkillConfigurationTarget) {
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
        -> [SkillConfigurationTarget: Result<[GlobalResourceObservation], Error>] {
        let manager = GlobalConfigurationManager(paths: paths, locations: locations)
        return Dictionary(uniqueKeysWithValues: SkillConfigurationTarget.allCases.map { host in
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

    private func applyInheritance(_ results: [SkillConfigurationTarget: Result<[GlobalResourceObservation], Error>]) {
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
        setInstallMethod(method, host: host)
    }

    func selection(host: SkillConfigurationTarget) -> GlobalConfigurationDraft? { skillDrafts[host] }

    func setInstallMethod(_ method: SkillInstallMethod, host: SkillConfigurationTarget) {
        guard var next = skillDrafts[host] else { return }
        next.installMethod = method
        save(next, host: host)
    }

    func setSkill(_ id: String, enabled: Bool) {
        setSkill(id, enabled: enabled, host: host)
    }

    func isSkillSelected(_ id: String, host: SkillConfigurationTarget) -> Bool {
        skillDrafts[host]?.skillIDs.contains(id) == true
    }

    func canEditSkills(host: SkillConfigurationTarget) -> Bool {
        !isRefreshing && !isSavingSkill && skillDrafts[host] != nil && skillEditingErrors[host] == nil
    }

    func duplicateSkillNotice(_ skill: SkillEntry, catalog: [SkillEntry]) -> String? {
        func names(_ entry: SkillEntry) -> Set<String> {
            Set([entry.slug, entry.declaredName.isEmpty ? entry.slug : entry.declaredName].map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            })
        }
        let matchingNames = names(skill)
        let targets = [SkillConfigurationTarget.agents, .codex].filter { target in
            let selected = Set(skillDrafts[target]?.skillIDs ?? [])
            return catalog.contains { selected.contains($0.id) && !names($0).isDisjoint(with: matchingNames) }
                || (inheritedResources[target] ?? []).contains {
                    matchingNames.contains(URL(fileURLWithPath: $0.path).lastPathComponent.lowercased())
                        && URL(fileURLWithPath: $0.path).deletingLastPathComponent() == locations.skillsRoot(target)
                }
        }
        guard targets.count == 2 else { return nil }
        return L10n.tr("Agents 与 Codex 中有同名技能，请核对来源；加载优先级由 Codex 决定。")
    }

    func setSkill(_ skill: SkillEntry, enabled: Bool, host: SkillConfigurationTarget, catalog: [SkillEntry]) {
        guard validateSkill(skill, enabled: enabled, host: host, catalog: catalog) else { return }
        setSkill(skill.id, enabled: enabled, host: host)
    }

    private func validateSkill(_ skill: SkillEntry, enabled: Bool, host: SkillConfigurationTarget, catalog: [SkillEntry]) -> Bool {
        guard !enabled || !skill.isBlocked else {
            error = L10n.tr("\(skill.slug) 未通过文件检查，请到技能库查看原因。")
            return false
        }
        if enabled, let selected = skillDrafts[host]?.skillIDs,
           catalog.contains(where: { $0.id != skill.id && $0.slug == skill.slug && selected.contains($0.id) }) {
            error = L10n.tr("\(skill.slug) 已选了另一个来源，请先取消同名技能。")
            return false
        }
        return true
    }

    @discardableResult
    func saveSkill(_ skill: SkillEntry, enabled: Bool, host: SkillConfigurationTarget, catalog: [SkillEntry]) async -> Bool {
        skillSaveMessage = nil
        guard validateSkill(skill, enabled: enabled, host: host, catalog: catalog) else { return false }
        return await saveSkill(skill.id, name: skill.slug, enabled: enabled, host: host)
    }

    @discardableResult
    func saveSkill(_ id: String, name: String, enabled: Bool, host: SkillConfigurationTarget) async -> Bool {
        guard canEditSkills(host: host), let previous = skillDrafts[host] else { return false }
        var next = previous
        next.skillIDs.removeAll { $0 == id }
        if enabled { next.skillIDs.append(id) }
        next.skillIDs.sort()
        isSavingSkill = true
        refreshID = UUID()
        inheritanceID = UUID()
        let inheritanceRequest = inheritanceID
        error = nil
        skillSaveMessage = nil
        let paths = paths, locations = locations, takeOver = takeOverExisting
        let updatedDraft = next
        let result = await Task.detached(priority: .userInitiated) {
            let manager = GlobalConfigurationManager(paths: paths, locations: locations)
            var failure: String?
            do {
                // 单次点击只改变该技能，不能顺带部署其他技能或规则的待保存草稿。
                let observed = try manager.inspect(host: host)
                let skillPath = locations.skillsRoot(host).appendingPathComponent(name).path
                if observed.resources.contains(where: { $0.path == skillPath && $0.managed && $0.modified }) {
                    // 无预览的取消操作不能静默保留修改后的文件并解除管理。
                    throw DeploymentError.managedSkillDrift(skillPath)
                }
                var selection = observed.selection
                selection.installMethod = previous.installMethod
                selection.skillIDs.removeAll { $0 == id }
                if enabled { selection.skillIDs.append(id) }
                selection.skillIDs.sort()
                let service = try SkillSetService(paths: paths, globalLocations: locations)
                let plan: StoredDeploymentPlan?
                do { plan = try service.makeGlobalPlan(host: host, selection: selection, takeOverExisting: takeOver) }
                catch DeploymentError.noChanges { plan = nil }
                try manager.saveDraft(updatedDraft, host: host)
                do {
                    if let plan {
                        try service.approve(planID: plan.id, digest: plan.plan.digest)
                        _ = try service.apply(planID: plan.id, digest: plan.plan.digest)
                    }
                } catch {
                    let applyFailure = UserFacingText.error(error)
                    do { try manager.saveDraft(previous, host: host) }
                    catch { throw NSError(domain: "GlobalSkillSaving", code: 1, userInfo: [NSLocalizedDescriptionKey:
                        applyFailure + "\n" + UserFacingText.error(error)]) }
                    throw error
                }
            } catch { failure = UserFacingText.error(error) }
            return (Self.read(paths: paths, locations: locations), failure)
        }.value
        isSavingSkill = false
        apply(result.0, inheritanceRequest: inheritanceRequest)
        if let failure = result.1 { error = failure; return false }
        skillSaveMessage = L10n.tr("已保存：\(host.displayName) · \(name)")
        return true
    }

    func setSkill(_ id: String, enabled: Bool, host: SkillConfigurationTarget) {
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
        setInstruction(id, enabled: enabled, host: host)
    }

    func isInstructionSelected(_ id: String, host: SkillConfigurationTarget) -> Bool {
        skillDrafts[host]?.instructionIDs.contains(id) == true
    }

    func setInstruction(_ id: String, enabled: Bool, host: SkillConfigurationTarget) {
        guard host != .agents, canEditSkills(host: host), var next = skillDrafts[host] else { return }
        next.instructionIDs.removeAll { $0 == id }
        if enabled { next.instructionIDs.append(id) }
        save(next, host: host)
    }

    @discardableResult
    func saveInstruction(_ template: TemplateRecord, enabled: Bool, host: SkillConfigurationTarget) async -> Bool {
        await saveInstruction(template.id, title: UserFacingText.templateTitle(template), enabled: enabled, host: host)
    }

    @discardableResult
    func saveInstruction(_ id: String, title: String, enabled: Bool, host: SkillConfigurationTarget) async -> Bool {
        guard host != .agents, canEditSkills(host: host), let previous = skillDrafts[host] else { return false }
        var next = previous
        next.instructionIDs.removeAll { $0 == id }
        if enabled { next.instructionIDs.append(id) }
        isSavingSkill = true
        refreshID = UUID()
        inheritanceID = UUID()
        let inheritanceRequest = inheritanceID
        error = nil
        skillSaveMessage = nil
        let paths = paths, locations = locations, takeOver = takeOverExisting
        let updatedDraft = next
        let result = await Task.detached(priority: .userInitiated) {
            let manager = GlobalConfigurationManager(paths: paths, locations: locations)
            var failure: String?
            do {
                let observed = try manager.inspect(host: host)
                if let rulesPath = locations.rulesURL(for: host)?.path,
                   observed.resources.contains(where: { $0.path == rulesPath && $0.managed && $0.modified }) {
                    throw DeploymentError.managedRuleDrift(rulesPath)
                }
                var selection = observed.selection
                selection.instructionIDs.removeAll { $0 == id }
                if enabled { selection.instructionIDs.append(id) }
                let service = try SkillSetService(paths: paths, globalLocations: locations)
                let plan: StoredDeploymentPlan?
                do { plan = try service.makeGlobalPlan(host: host, selection: selection, takeOverExisting: takeOver) }
                catch DeploymentError.noChanges { plan = nil }
                try manager.saveDraft(updatedDraft, host: host)
                do {
                    if let plan {
                        try service.approve(planID: plan.id, digest: plan.plan.digest)
                        _ = try service.apply(planID: plan.id, digest: plan.plan.digest)
                    }
                } catch {
                    let applyFailure = UserFacingText.error(error)
                    do { try manager.saveDraft(previous, host: host) }
                    catch { throw NSError(domain: "GlobalInstructionSaving", code: 1, userInfo: [NSLocalizedDescriptionKey:
                        applyFailure + "\n" + UserFacingText.error(error)]) }
                    throw error
                }
            } catch { failure = UserFacingText.error(error) }
            return (Self.read(paths: paths, locations: locations), failure)
        }.value
        isSavingSkill = false
        apply(result.0, inheritanceRequest: inheritanceRequest)
        if let failure = result.1 { error = failure; return false }
        skillSaveMessage = L10n.tr("已保存：\(host.displayName) · \(title)")
        return true
    }

    private func save(_ next: GlobalConfigurationDraft, host: SkillConfigurationTarget) {
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
        prepareDeployment(host: host)
    }

    func prepareDeployment(host: SkillConfigurationTarget) -> StoredDeploymentPlan? {
        guard canEditSkills(host: host), let selection = skillDrafts[host] else {
            error = skillEditingErrors[host]
            return nil
        }
        return prepare {
            try SkillSetService(paths: paths, globalLocations: locations).makeGlobalPlan(
                host: host, selection: selection, takeOverExisting: takeOverExisting)
        }
    }

    func prepareSnapshotRepair(host: SkillConfigurationTarget? = nil) -> StoredDeploymentPlan? {
        prepare { try manager.makeSnapshotRepairPlan(host: host ?? self.host) }
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
