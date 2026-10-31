import Foundation
import SkillSetCore

struct PresetSelectionRequest: Identifiable {
    let id = UUID()
    var projectID: String?
    var presetID: String?
}

/// 一类资源相对当前草稿的差异。
struct PresetComponentChanges {
    let added: [String]
    let retained: [String]
    let updated: [String]
    let removed: [String]

    init(current: Set<String>, proposed: Set<String>, updated: Set<String> = []) {
        added = proposed.subtracting(current).sorted()
        self.updated = updated.intersection(proposed).intersection(current).sorted()
        retained = proposed.intersection(current).subtracting(updated).sorted()
        removed = current.subtracting(proposed).sorted()
    }

    var isEmpty: Bool { added.isEmpty && updated.isEmpty && removed.isEmpty && retained.isEmpty }
}

/// 多个预设写入项目草稿后的差异预览。
///
/// 合并规则与 `PresetDraftMerge` 一致：多个预设取并集，取消预设只回收它独占的内容。
struct PresetDraftPreview {
    enum Mode {
        /// 并入新预设，已生效的预设保持不变。
        case merge
        /// 以选中集合为准，未选中的预设按差集取消。
        case select
    }

    let plugins: PresetComponentChanges
    let mcpServers: PresetComponentChanges
    let componentIssues: [String]
    let unavailablePluginNames: [String]
    let skills: PresetComponentChanges
    let instructions: PresetComponentChanges
    let unavailableSkillIDs: [String]
    let unavailableInstructionIDs: [String]
    let conflictingSkillIDs: [String]
    /// 本次新增的预设。
    let addedPresets: [PresetRecord]
    /// 本次取消的预设。
    let removedPresets: [PresetRecord]
    /// 合并后的草稿状态，写入时以此为准。
    let mergedState: PresetDraftState

    private let snapshot: AppSnapshot
    private let mergedSkillIDs: Set<String>

    var canLoad: Bool {
        unavailableSkillIDs.isEmpty && unavailableInstructionIDs.isEmpty && conflictingSkillIDs.isEmpty && componentIssues.isEmpty
    }

    init(presets: [PresetRecord], project: ProjectRecord, snapshot: AppSnapshot,
         availablePlugins: [PluginInventoryRecord]? = nil, mode: Mode = .select) {
        let host = project.editingAgent
        let current = PresetDraftState(selections: project.harnessSelections, plugins: project.draftPlugins,
                                       mcpServers: project.draftMCPServers, applications: project.presetApplications)
        let merged = mode == .merge
            ? PresetDraftMerge.merging(presets, host: host, to: current)
            : PresetDraftMerge.selecting(presets, host: host, to: current)

        let currentSelection = current.selections[host] ?? ProjectHarnessSelection()
        let mergedSelection = merged.selections[host] ?? ProjectHarnessSelection()
        skills = PresetComponentChanges(current: Set(currentSelection.skillIDs), proposed: Set(mergedSelection.skillIDs))
        instructions = PresetComponentChanges(current: Set(currentSelection.instructionIDs), proposed: Set(mergedSelection.instructionIDs))
        let updatedPluginIDs = Set(merged.plugins.compactMap { reference -> String? in
            guard let existing = current.plugins.first(where: { $0.id == reference.id }) else { return nil }
            return existing == reference ? nil : reference.id
        })
        plugins = PresetComponentChanges(current: Set(current.plugins.map(\.id)), proposed: Set(merged.plugins.map(\.id)),
                                         updated: updatedPluginIDs)
        let updatedMCPIDs = Set(merged.mcpServers.compactMap { server -> String? in
            guard let existing = current.mcpServers.first(where: { $0.presetID == server.presetID }) else { return nil }
            return existing == server ? nil : server.presetID
        })
        mcpServers = PresetComponentChanges(current: Set(current.mcpServers.map(\.presetID)), proposed: Set(merged.mcpServers.map(\.presetID)),
                                             updated: updatedMCPIDs)

        var issues: [String] = []
        // 内置旧预设允许空组合；新增预设的完整性由本机保存边界校验。
        for preset in presets where preset.componentCount > 0 {
            if let issue = PresetStore.validationIssue(preset) { issues.append(issue) }
        }
        let targetPlugins = presets.flatMap(\.plugins)
        let missingPlugins = targetPlugins.filter { reference in
            guard let availablePlugins else { return false }
            return !availablePlugins.contains { $0.host == reference.host && $0.pluginID == reference.pluginID && $0.manifestDigest == reference.manifestDigest }
        }
        unavailablePluginNames = missingPlugins.map { $0.name.isEmpty ? $0.pluginID : $0.name }
        if !missingPlugins.isEmpty { issues.append("插件版本不可用，请重新扫描并更新预设。") }
        // 多个预设指向同一插件但版本不同时不能静默取其中一个。
        let conflictingPlugins = Dictionary(grouping: targetPlugins, by: \.id)
            .filter { $0.value.count > 1 && Set($0.value.map(\.manifestDigest)).count > 1 }
        for (pluginID, references) in conflictingPlugins.sorted(by: { $0.key < $1.key }) {
            let name = references.first?.name.isEmpty == false ? references[0].name : pluginID
            issues.append("预设里的插件「\(name)」版本不一致，请先统一版本。")
        }
        componentIssues = issues

        let targetSkillIDs = Set(presets.flatMap(\.skills))
        let mergedSkillIDs = Set(mergedSelection.skillIDs)
        let available = snapshot.catalog.entries.filter { !$0.isBlocked }
        unavailableSkillIDs = targetSkillIDs.subtracting(Set(available.map(\.id))).sorted()
        unavailableInstructionIDs = Set(presets.flatMap(\.instructionFragments))
            .subtracting(Set(snapshot.templates.map(\.id))).sorted()
        let selected = available.filter { mergedSkillIDs.contains($0.id) }
        conflictingSkillIDs = Dictionary(grouping: selected, by: \.slug).values
            .filter { $0.count > 1 }.flatMap { $0.map(\.id) }.sorted()

        let appliedIDs = Set(project.appliedPresets(host: host).map(\.presetID))
        let targetIDs = Set(presets.map(\.id))
        addedPresets = presets.filter { !appliedIDs.contains($0.id) }
        removedPresets = appliedIDs.subtracting(targetIDs).sorted().map { id in
            snapshot.presets.first { $0.id == id } ?? PresetRecord(id: id, name: id)
        }
        self.snapshot = snapshot
        self.mergedSkillIDs = mergedSkillIDs
        self.mergedState = merged
    }

    /// 单个预设的预览，保留给预设编辑器的可用性检查。
    ///
    /// 这里按并集计算：预设编辑器只关心这个预设能不能用，不该顺手取消项目里已生效的其他预设。
    init(preset: PresetRecord, project: ProjectRecord, snapshot: AppSnapshot,
         availablePlugins: [PluginInventoryRecord]? = nil) {
        self.init(presets: [preset], project: project, snapshot: snapshot, availablePlugins: availablePlugins, mode: .merge)
    }

    /// 同名技能只比较 slug。提示必须带上名称和来源，否则无法判断该取消哪一项。
    func blockingReasons(origins: [String: SourceSkillOrigin] = [:]) -> [LocalizedText] {
        let entries = Dictionary(uniqueKeysWithValues: snapshot.catalog.entries.map { ($0.id, $0) })
        var reasons: [LocalizedText] = []
        for id in unavailableSkillIDs {
            guard let skill = entries[id] else {
                // 预设保存的是技能标识。技能离开库后，不能把整段来源哈希当作提示。
                reasons.append("技能「\(Self.referenceName(id))」不在技能库。请从预设中移除这项引用。")
                continue
            }
            let place = skillPlace(skill, origins: origins)
            if let detail = blockedDetail(skill) {
                reasons.append("技能「\(skill.declaredName)」暂不可用：\(detail)来源：\(place)")
            } else {
                reasons.append("技能「\(skill.declaredName)」暂不可用。来源：\(place)")
            }
        }
        if !unavailableInstructionIDs.isEmpty {
            reasons.append("AGENTS 片段已不在库中，请从预设中移除这项引用。")
        }
        let selected = snapshot.catalog.entries.filter { mergedSkillIDs.contains($0.id) && !$0.isBlocked }
        let conflicts = Dictionary(grouping: selected, by: \.slug).values.filter { $0.count > 1 }
            .sorted { $0[0].slug < $1[0].slug }
        for group in conflicts {
            let copies = group.sorted { $0.id < $1.id }
            let places = copies.map { skillPlace($0, origins: origins) }
            let placesCollide = Set(places).count != places.count
            let items = zip(copies, places).map { skill, place in
                placesCollide ? "\(skill.declaredName)（\(skill.sourceId)）" : "\(skill.declaredName)（\(place)）"
            }.joined(separator: "、")
            reasons.append("同名冲突，请只保留一项：\(items)")
        }
        for name in unavailablePluginNames {
            reasons.append("插件「\(name)」的这个版本不可用，请重新扫描并更新预设。")
        }
        let pluginNotice = "插件版本不可用，请重新扫描并更新预设。"
        reasons += componentIssues.filter { $0 != pluginNotice }.map { LocalizedText(stringLiteral: $0) }
        return reasons
    }

    static func referenceName(_ id: String) -> String {
        let slug = id.split(separator: "/").last.map(String.init) ?? id
        return slug.isEmpty ? id : slug
    }

    private func skillPlace(_ skill: SkillEntry, origins: [String: SourceSkillOrigin]) -> String {
        let url = origins[skill.id]?.url.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return url.isEmpty ? skill.sourceId : url
    }

    private func blockedDetail(_ skill: SkillEntry) -> LocalizedText? {
        var seen: [String] = []
        for issue in skill.issues {
            let text = UserFacingText.catalogIssue(issue)
            if !seen.contains(text) { seen.append(text) }
        }
        guard !seen.isEmpty else { return nil }
        return LocalizedText.joining(seen.map { LocalizedText(stringLiteral: $0) }, separator: " ")
    }
}
