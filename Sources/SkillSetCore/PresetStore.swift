import Foundation

/// 不保存缓存路径；以宿主、插件标识和内容指纹重新解析本机清单。
public struct PresetPluginReference: Codable, Identifiable, Hashable, Sendable {
    public let host: MCPHost
    public let pluginID: String
    public let name: String
    public let manifestDigest: String
    public let sourceRevision: String?
    public let scope: PluginLifecycleScope
    public var id: String { "\(host.rawValue):\(scope.rawValue):\(pluginID)" }

    public init(plugin: PluginInventoryRecord, scope: PluginLifecycleScope) {
        host = plugin.host
        pluginID = plugin.pluginID
        name = plugin.name
        manifestDigest = plugin.manifestDigest
        sourceRevision = plugin.sourceRevision
        self.scope = scope
    }
}

public extension MCPConfigurationDraft {
    var presetID: String { "\(host.rawValue):\(scope.rawValue):\(name)" }
}

public enum PresetStoreError: Error, LocalizedError, SkillSetCodedError {
    case invalid(String)
    case corrupt
    public var code: String { "PRESET_INVALID" }
    public var errorDescription: String? {
        switch self {
        case .invalid(let reason): reason
        case .corrupt: "本机预设文件无法读取，请检查文件后重试。"
        }
    }
}

/// 用户预设保存在本机库，不改动项目文件；显式传入的初始组合仅用于开发夹具。
public struct PresetStore {
    public let rootURL: URL
    public var documentURL: URL { rootURL.appendingPathComponent("presets.json") }
    public init(rootURL: URL) { self.rootURL = rootURL }

    public func list() throws -> [PresetRecord] {
        guard FileManager.default.fileExists(atPath: documentURL.path) else { return [] }
        do { return try JSONDecoder().decode([PresetRecord].self, from: Data(contentsOf: documentURL)) }
        catch { throw PresetStoreError.corrupt }
    }

    public func list(merging initial: [PresetRecord]) throws -> [PresetRecord] {
        Self.merging(try list(), with: initial)
    }

    private static func merging(_ local: [PresetRecord], with initial: [PresetRecord]) -> [PresetRecord] {
        let localByID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let initialIDs = Set(initial.map(\.id))
        return initial.map { localByID[$0.id] ?? $0 } + local.filter { !initialIDs.contains($0.id) }
    }

    public static func validationIssue(_ preset: PresetRecord) -> String? {
        let name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "请填写预设名称。" }
        if name.count > 80 { return "预设名称最多 80 个字符。" }
        if preset.componentCount == 0 { return "至少添加一个技能、插件、MCP 服务或 AGENTS.md 片段。" }
        if Set(preset.skills).count != preset.skills.count || Set(preset.instructionFragments).count != preset.instructionFragments.count
            || Set(preset.plugins.map(\.id)).count != preset.plugins.count
            || Set(preset.mcpServers.map { $0.normalized().presetID }).count != preset.mcpServers.count {
            return "同一组件不能重复添加，请核对宿主、作用域与名称。"
        }
        if preset.plugins.contains(where: { $0.manifestDigest.count != 64 || $0.manifestDigest.contains(where: { !$0.isHexDigit }) }) {
            return "插件缺少有效的内容指纹，请重新选择本机插件。"
        }
        if preset.plugins.contains(where: { $0.host == .codex && $0.scope != .user }) {
            return "Codex 插件仅支持用户作用域。"
        }
        for server in preset.mcpServers {
            if let issue = server.validationIssues().first { return issue }
            if server.host == .codex && server.scope == .project { return "Codex MCP 仅支持用户作用域。" }
        }
        return nil
    }

    @discardableResult
    public func save(_ preset: PresetRecord, initial: [PresetRecord]) throws -> [PresetRecord] {
        if let issue = Self.validationIssue(preset) { throw PresetStoreError.invalid(issue) }
        var records = try list()
        let available = Self.merging(records, with: initial)
        let name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if available.contains(where: { $0.id != preset.id && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            throw PresetStoreError.invalid("已有同名预设，请换一个名称。")
        }
        let old = available.first { $0.id == preset.id }
        let saved = PresetRecord(id: preset.id, name: name, description: preset.description.trimmingCharacters(in: .whitespacesAndNewlines),
                                 revision: (old?.revision ?? 0) + 1, skills: preset.skills.sorted(),
                                 instructionFragments: preset.instructionFragments.sorted(), plugins: preset.plugins,
                                 mcpServers: preset.mcpServers.map { $0.normalized() })
        records.removeAll { $0.id == saved.id }
        records.append(saved)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try encoder.encode(records).write(to: documentURL, options: .atomic)
        return Self.merging(records, with: initial)
    }

    @discardableResult
    public func remove(id: String) throws -> [PresetRecord] {
        var records = try list()
        guard records.contains(where: { $0.id == id }) else {
            throw PresetStoreError.invalid("这个预设已删除，请重新选择。")
        }
        records.removeAll { $0.id == id }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(records).write(to: documentURL, options: .atomic)
        return records
    }
}
