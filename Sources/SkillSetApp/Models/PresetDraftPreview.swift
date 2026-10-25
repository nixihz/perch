import Foundation
import SkillSetCore

struct PresetSelectionRequest: Identifiable {
    let id = UUID()
    var projectID: String?
    var presetID: String?
}

struct PresetDraftPreview {
    struct Changes {
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
    }

    let plugins: Changes
    let mcpServers: Changes
    let componentIssues: [String]
    let unavailablePluginNames: [String]
    let skills: Changes
    let instructions: Changes
    let unavailableSkillIDs: [String]
    let unavailableInstructionIDs: [String]
    let conflictingSkillIDs: [String]
    private let snapshot: AppSnapshot
    private let preset: PresetRecord

    var canLoad: Bool {
        unavailableSkillIDs.isEmpty && unavailableInstructionIDs.isEmpty && conflictingSkillIDs.isEmpty && componentIssues.isEmpty
    }

    init(preset: PresetRecord, project: ProjectRecord, snapshot: AppSnapshot, availablePlugins: [PluginInventoryRecord]? = nil) {
        plugins = Changes(current: Set(project.draftPlugins.map(\.id)), proposed: Set(preset.plugins.map(\.id)), updated: Set(preset.plugins.filter { next in project.draftPlugins.contains { $0.id == next.id && $0 != next } }.map(\.id)))
        mcpServers = Changes(current: Set(project.draftMCPServers.map(\.presetID)), proposed: Set(preset.mcpServers.map(\.presetID)), updated: Set(preset.mcpServers.filter { next in project.draftMCPServers.contains { $0.presetID == next.presetID && $0 != next } }.map(\.presetID)))
        var issues: [String] = []
        // 内置旧预设允许空组合；新增预设的完整性由本机保存边界校验。
        if preset.componentCount > 0, let issue = PresetStore.validationIssue(preset) { issues.append(issue) }
        let missingPlugins = preset.plugins.filter { reference in
            guard let availablePlugins else { return false }
            return !availablePlugins.contains { $0.host == reference.host && $0.pluginID == reference.pluginID && $0.manifestDigest == reference.manifestDigest }
        }
        unavailablePluginNames = missingPlugins.map { $0.name.isEmpty ? $0.pluginID : $0.name }
        if !missingPlugins.isEmpty { issues.append("插件版本不可用，请重新扫描并更新预设。") }
        componentIssues = issues
        let skillIDs = Set(preset.skills)
        skills = Changes(current: project.draftSkillIDs, proposed: skillIDs)
        instructions = Changes(current: Set(project.fragments), proposed: Set(preset.instructionFragments))
        let available = snapshot.catalog.entries.filter { !$0.isBlocked }
        unavailableSkillIDs = skillIDs.subtracting(Set(available.map(\.id))).sorted()
        unavailableInstructionIDs = Set(preset.instructionFragments)
            .subtracting(Set(snapshot.templates.map(\.id))).sorted()
        let selected = available.filter { skillIDs.contains($0.id) }
        conflictingSkillIDs = Dictionary(grouping: selected, by: \.slug).values
            .filter { $0.count > 1 }.flatMap { $0.map(\.id) }.sorted()
        self.snapshot = snapshot
        self.preset = preset
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
        for id in unavailableInstructionIDs {
            reasons.append("规则不在片段库：\(id)")
        }
        let selected = snapshot.catalog.entries.filter { preset.skills.contains($0.id) && !$0.isBlocked }
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
