import Foundation

/// 预设写入项目草稿时留下的贡献快照。
///
/// 快照记录“当时放进去的内容”，不随预设库后续编辑变化。
/// 取消预设时按快照计算差集：只回收该预设独占的部分，其他预设和手动选择的内容保持不变。
public struct PresetApplication: Codable, Identifiable, Hashable, Sendable {
    public let presetID: String
    /// 应用时的 AI 工具目标。技能和片段按宿主独立保存，因此记录宿主才能定位回收位置。
    public let host: String
    public let revision: Int
    public var skillIDs: [String]
    public var instructionIDs: [String]
    public var pluginIDs: [String]
    public var mcpServerIDs: [String]

    public var id: String { "\(presetID)@\(host)" }

    public init(presetID: String, host: String, revision: Int, skillIDs: [String] = [],
                instructionIDs: [String] = [], pluginIDs: [String] = [], mcpServerIDs: [String] = []) {
        self.presetID = presetID
        self.host = host
        self.revision = revision
        self.skillIDs = Array(Set(skillIDs)).sorted()
        self.instructionIDs = Array(Set(instructionIDs)).sorted()
        self.pluginIDs = Array(Set(pluginIDs)).sorted()
        self.mcpServerIDs = Array(Set(mcpServerIDs)).sorted()
    }

    public init(preset: PresetRecord, host: String) {
        self.init(presetID: preset.id, host: host, revision: preset.revision,
                  skillIDs: preset.skills, instructionIDs: preset.instructionFragments,
                  pluginIDs: preset.plugins.map(\.id), mcpServerIDs: preset.mcpServers.map(\.presetID))
    }
}

/// 项目草稿中与预设相关的部分。技能和片段按宿主保存，插件和 MCP 服务是草稿级内容。
public struct PresetDraftState: Hashable, Sendable {
    public var selections: [String: ProjectHarnessSelection]
    public var plugins: [PresetPluginReference]
    public var mcpServers: [MCPConfigurationDraft]
    public var applications: [PresetApplication]

    public init(selections: [String: ProjectHarnessSelection] = [:], plugins: [PresetPluginReference] = [],
                mcpServers: [MCPConfigurationDraft] = [], applications: [PresetApplication] = []) {
        self.selections = selections
        self.plugins = plugins
        self.mcpServers = mcpServers
        self.applications = applications
    }
}

/// 多预设合并规则。
///
/// - 并集：多个预设的内容同时保留，重叠内容只算一份。
/// - 差集：取消某个预设时，只移除它独占的内容，仍被其他预设提供的内容保留。
public enum PresetDraftMerge {
    /// 并集应用：把预设并入草稿，同名预设按新内容刷新，其他预设保持不变。
    public static func merging(_ presets: [PresetRecord], host: String, to state: PresetDraftState) -> PresetDraftState {
        let refreshed = presets.map { PresetApplication(preset: $0, host: host) }
        let kept = state.applications.filter { application in
            application.host != host || !refreshed.contains { $0.presetID == application.presetID }
        }
        return apply(targets: kept + refreshed, contents: presets, host: host, state: state)
    }

    /// 以选中集合为准：该宿主最终只保留这些预设，其余预设按差集回收。
    public static func selecting(_ presets: [PresetRecord], host: String, to state: PresetDraftState) -> PresetDraftState {
        let targets = presets.map { PresetApplication(preset: $0, host: host) }
        let otherHosts = state.applications.filter { $0.host != host }
        return apply(targets: otherHosts + targets, contents: presets, host: host, state: state)
    }

    /// 取消预设后的结果。只回收该预设独占的内容，其余保持不变。
    public static func removing(presetIDs: Set<String>, host: String, from state: PresetDraftState) -> PresetDraftState {
        let removed = state.applications.filter { presetIDs.contains($0.presetID) && $0.host == host }
        let remaining = state.applications.filter { !removed.contains($0) }
        guard !removed.isEmpty else { return state }

        let keptSkillIDs = Set(remaining.filter { $0.host == host }.flatMap(\.skillIDs))
        let keptInstructionIDs = Set(remaining.filter { $0.host == host }.flatMap(\.instructionIDs))
        let keptPluginIDs = Set(remaining.flatMap(\.pluginIDs))
        let keptMCPIDs = Set(remaining.flatMap(\.mcpServerIDs))

        let removedSkillIDs = Set(removed.flatMap(\.skillIDs)).subtracting(keptSkillIDs)
        let removedInstructionIDs = Set(removed.flatMap(\.instructionIDs)).subtracting(keptInstructionIDs)
        let removedPluginIDs = Set(removed.flatMap(\.pluginIDs)).subtracting(keptPluginIDs)
        let removedMCPIDs = Set(removed.flatMap(\.mcpServerIDs)).subtracting(keptMCPIDs)

        var selections = state.selections
        var selection = selections[host] ?? ProjectHarnessSelection()
        selection.skillIDs = selection.skillIDs.filter { !removedSkillIDs.contains($0) }
        selection.instructionIDs = selection.instructionIDs.filter { !removedInstructionIDs.contains($0) }
        selections[host] = selection

        return PresetDraftState(
            selections: selections,
            plugins: state.plugins.filter { !removedPluginIDs.contains($0.id) },
            mcpServers: state.mcpServers.filter { !removedMCPIDs.contains($0.presetID) },
            applications: remaining
        )
    }

    /// 目标应用集合写入草稿后的结果。targets 是全部宿主的目标记录。
    private static func apply(targets: [PresetApplication], contents: [PresetRecord], host: String,
                              state: PresetDraftState) -> PresetDraftState {
        let targetsByID = Dictionary(targets.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        // 技能和片段按宿主保存，只统计当前宿主的目标内容。
        let hostTargets = targets.filter { $0.host == host }
        let targetSkillIDs = Set(hostTargets.flatMap(\.skillIDs))
        let targetInstructionIDs = Set(hostTargets.flatMap(\.instructionIDs))
        // 插件和 MCP 服务属于草稿级内容，所有宿主的目标都算数。
        let targetPluginIDs = Set(targets.flatMap(\.pluginIDs))
        let targetMCPIDs = Set(targets.flatMap(\.mcpServerIDs))

        // 同宿主下被取消或内容变化的旧记录先回收，再判断这些内容是否仍有人提供。
        let obsoleteApplications = state.applications.filter { application in
            guard let target = targetsByID[application.id] else { return true }
            return application != target
        }
        let obsoleteHostApplications = obsoleteApplications.filter { $0.host == host }
        let obsoleteSkillIDs = Set(obsoleteHostApplications.flatMap(\.skillIDs)).subtracting(targetSkillIDs)
        let obsoleteInstructionIDs = Set(obsoleteHostApplications.flatMap(\.instructionIDs)).subtracting(targetInstructionIDs)
        let obsoletePluginIDs = Set(obsoleteApplications.flatMap(\.pluginIDs)).subtracting(targetPluginIDs)
        let obsoleteMCPIDs = Set(obsoleteApplications.flatMap(\.mcpServerIDs)).subtracting(targetMCPIDs)

        var selections = state.selections
        var selection = selections[host] ?? ProjectHarnessSelection()
        selection.skillIDs = (selection.skillIDs.filter { !obsoleteSkillIDs.contains($0) } + targetSkillIDs).sorted()
        selection.instructionIDs = (selection.instructionIDs.filter { !obsoleteInstructionIDs.contains($0) } + targetInstructionIDs).sorted()
        selections[host] = selection

        var plugins = state.plugins.filter { !obsoletePluginIDs.contains($0.id) }
        for record in contents {
            for reference in record.plugins {
                plugins.removeAll { $0.id == reference.id }
                plugins.append(reference)
            }
        }
        var mcpServers = state.mcpServers.filter { !obsoleteMCPIDs.contains($0.presetID) }
        for record in contents {
            for server in record.mcpServers {
                mcpServers.removeAll { $0.presetID == server.presetID }
                mcpServers.append(server)
            }
        }

        return PresetDraftState(selections: selections, plugins: plugins, mcpServers: mcpServers,
                                 applications: targetsByID.values.sorted { $0.id < $1.id })
    }
}
