import Foundation

public enum MCPLibraryError: Error, LocalizedError, SkillSetCodedError {
    case duplicate
    case missingSelection
    case scanChanged
    case modifiedConnection

    public var code: String {
        switch self {
        case .duplicate: "MCP_LIBRARY_DUPLICATE"
        case .missingSelection: "MCP_LIBRARY_SELECTION_MISSING"
        case .scanChanged: "MCP_LIBRARY_SCAN_CHANGED"
        case .modifiedConnection: "MCP_LIBRARY_CONNECTION_MODIFIED"
        }
    }
    public var errorDescription: String? { code }
}

/// 连接配置不绑定宿主或范围；只有配置页的选择决定写入目标。
public struct MCPLibraryEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var transport: String
    public var commandOrURL: String
    public var args: [String]
    public var envKeys: [String]

    public init(id: UUID = UUID(), name: String = "", transport: String = "stdio",
                commandOrURL: String = "", args: [String] = [], envKeys: [String] = []) {
        self.id = id
        self.name = name
        self.transport = transport
        self.commandOrURL = commandOrURL
        self.args = args
        self.envKeys = envKeys
    }

    public func draft(host: MCPHost, scope: MCPConfigurationScope) -> MCPConfigurationDraft {
        MCPConfigurationDraft(name: name, host: host, scope: scope, transport: transport,
                              commandOrURL: commandOrURL, args: args, envKeys: envKeys)
    }
}

public struct MCPLibraryAppliedSelection: Codable, Equatable, Sendable {
    public let configPath: String
    public let entries: [MCPLibraryEntry]
    public let nodeHashes: [String: String]
}

public struct MCPLibraryStore {
    public let rootURL: URL
    public init(rootURL: URL) { self.rootURL = rootURL.appendingPathComponent("mcp") }
    public var documentURL: URL { rootURL.appendingPathComponent("library.json") }

    public func entries() throws -> [MCPLibraryEntry] {
        try read([MCPLibraryEntry].self, at: documentURL) ?? []
    }

    @discardableResult
    public func save(_ entry: MCPLibraryEntry) throws -> MCPLibraryEntry {
        let draft = entry.draft(host: .codex, scope: .user).normalized()
        guard draft.validationIssues().isEmpty else {
            throw MCPConfigurationError.invalidDraft(draft.validationIssues().joined(separator: "；"))
        }
        var entries = try entries()
        guard !entries.contains(where: { $0.id != entry.id && $0.name == draft.name }) else {
            throw MCPLibraryError.duplicate
        }
        let saved = MCPLibraryEntry(id: entry.id, name: draft.name, transport: draft.transport,
            commandOrURL: draft.commandOrURL, args: draft.args, envKeys: draft.envKeys)
        entries.removeAll { $0.id == saved.id }
        entries.append(saved)
        try write(entries.sorted { $0.name < $1.name }, to: documentURL)
        return saved
    }

    public func importEntries(_ imported: [MCPLibraryEntry]) throws {
        var all = try entries()
        for entry in imported {
            let draft = entry.draft(host: .codex, scope: .user)
            guard draft.validationIssues().isEmpty else {
                throw MCPConfigurationError.invalidDraft(draft.validationIssues().joined(separator: "；"))
            }
            guard !all.contains(where: { $0.name == entry.name }) else { throw MCPLibraryError.duplicate }
            all.append(entry)
        }
        try write(all.sorted { $0.name < $1.name }, to: documentURL)
    }

    public func remove(_ id: UUID) throws {
        try write(entries().filter { $0.id != id }, to: documentURL)
    }

    public func selectionKey(host: MCPHost, projectID: UUID?) -> String {
        "\(projectID.map { "project-" + $0.uuidString } ?? "user")-\(host.rawValue)"
    }

    public func selectedIDs(host: MCPHost, projectID: UUID?) throws -> [UUID] {
        try read([UUID].self, at: draftURL(host: host, projectID: projectID)) ?? []
    }

    public func saveSelection(_ ids: [UUID], host: MCPHost, projectID: UUID?) throws {
        try write(Array(Set(ids)).sorted { $0.uuidString < $1.uuidString }, to: draftURL(host: host, projectID: projectID))
    }

    public func appliedURL(configPath: String) -> URL {
        rootURL.appendingPathComponent("selections/" + SkillAssetCopier.sha256(Data(configPath.utf8)) + ".json")
    }

    public func applied(configPath: String) throws -> MCPLibraryAppliedSelection? {
        let selection = try read(MCPLibraryAppliedSelection.self, at: appliedURL(configPath: configPath))
        guard selection == nil || selection?.configPath == configPath else {
            throw MCPConfigurationError.configCorrupt(appliedURL(configPath: configPath).path)
        }
        return selection
    }

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value) + Data("\n".utf8)
    }

    private func draftURL(host: MCPHost, projectID: UUID?) -> URL {
        rootURL.appendingPathComponent("drafts/" + selectionKey(host: host, projectID: projectID) + ".json")
    }

    private func read<T: Decodable>(_ type: T.Type, at url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do { return try JSONDecoder().decode(type, from: Data(contentsOf: url)) }
        catch { throw MCPConfigurationError.configCorrupt(url.path) }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(value).write(to: url, options: .atomic)
    }
}
