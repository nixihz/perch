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
    let skills: Changes
    let instructions: Changes
    let unavailableSkillIDs: [String]
    let unavailableInstructionIDs: [String]
    let conflictingSkillIDs: [String]

    var canLoad: Bool {
        unavailableSkillIDs.isEmpty && unavailableInstructionIDs.isEmpty && conflictingSkillIDs.isEmpty && componentIssues.isEmpty
    }

    init(preset: PresetRecord, project: ProjectRecord, snapshot: AppSnapshot, availablePlugins: [PluginInventoryRecord]? = nil) {
        plugins = Changes(current: Set(project.draftPlugins.map(\.id)), proposed: Set(preset.plugins.map(\.id)), updated: Set(preset.plugins.filter { next in project.draftPlugins.contains { $0.id == next.id && $0 != next } }.map(\.id)))
        mcpServers = Changes(current: Set(project.draftMCPServers.map(\.presetID)), proposed: Set(preset.mcpServers.map(\.presetID)), updated: Set(preset.mcpServers.filter { next in project.draftMCPServers.contains { $0.presetID == next.presetID && $0 != next } }.map(\.presetID)))
        var issues: [String] = []
        // 内置旧预设允许空组合；新增预设的完整性由本机保存边界校验。
        if preset.componentCount > 0, let issue = PresetStore.validationIssue(preset) { issues.append(issue) }
        if let availablePlugins, preset.plugins.contains(where: { reference in
            !availablePlugins.contains { $0.host == reference.host && $0.pluginID == reference.pluginID && $0.manifestDigest == reference.manifestDigest }
        }) { issues.append("插件版本不可用，请重新扫描并更新预设。") }
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
    }
}
