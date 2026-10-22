import Foundation
import SkillSetCore

struct PresetEditorDraft: Identifiable, Equatable {
    let id: String
    var name: String
    var description: String
    var skills: Set<String>
    var instructions: Set<String>
    var plugins: [PresetPluginReference]
    var mcpServers: [MCPConfigurationDraft]

    @MainActor
    init(preset: PresetRecord? = nil, copy: Bool = false) {
        id = copy ? UUID().uuidString : preset?.id ?? UUID().uuidString
        name = copy ? "" : preset.map { $0.status == "local" ? $0.name : L10n.text($0.name) } ?? ""
        description = preset.map { $0.status == "local" ? $0.description : L10n.text($0.description) } ?? ""
        skills = Set(preset?.skills ?? [])
        instructions = Set(preset?.instructionFragments ?? [])
        plugins = preset?.plugins ?? []
        mcpServers = preset?.mcpServers ?? []
    }

    var record: PresetRecord {
        PresetRecord(id: id, name: name, description: description, skills: skills.sorted(),
                     instructionFragments: instructions.sorted(), plugins: plugins, mcpServers: mcpServers)
    }
}
