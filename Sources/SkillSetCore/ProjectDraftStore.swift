import Foundation

public enum ProjectDraftStoreError: Error, LocalizedError, Equatable, Sendable {
    case corruptDocument(String)

    public var code: String { "PROJECT_DRAFT_CORRUPT" }

    public var errorDescription: String? {
        switch self {
        case let .corruptDocument(path):
            return "项目草稿文件无法读取：\(path)"
        }
    }
}

public struct ProjectDraft: Codable, Identifiable, Hashable, Sendable {
    public let projectID: UUID
    public var skillIDs: [String]
    public var instructionIDs: [String]
    public var agents: [String]
    public var plugins: [PresetPluginReference]
    public var mcpServers: [MCPConfigurationDraft]
    public var harnessSelections: [String: ProjectHarnessSelection]?
    public var updatedAt: Date

    public var id: UUID { projectID }

    public init(
        projectID: UUID,
        skillIDs: [String],
        instructionIDs: [String] = [],
        agents: [String] = ["codex"],
        updatedAt: Date,
        plugins: [PresetPluginReference] = [],
        mcpServers: [MCPConfigurationDraft] = [],
        harnessSelections: [String: ProjectHarnessSelection]? = nil
    ) {
        self.projectID = projectID
        self.skillIDs = harnessSelections.map { Array(Set($0.values.flatMap(\.skillIDs))).sorted() } ?? skillIDs
        self.instructionIDs = harnessSelections.map { Array(Set($0.values.flatMap(\.instructionIDs))).sorted() } ?? instructionIDs
        self.agents = agents
        self.updatedAt = updatedAt
        self.plugins = plugins
        self.mcpServers = mcpServers
        self.harnessSelections = harnessSelections
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projectID = try c.decode(UUID.self, forKey: .projectID)
        skillIDs = try c.decode([String].self, forKey: .skillIDs)
        instructionIDs = try c.decode([String].self, forKey: .instructionIDs)
        agents = try c.decode([String].self, forKey: .agents)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        plugins = try c.decodeIfPresent([PresetPluginReference].self, forKey: .plugins) ?? []
        mcpServers = try c.decodeIfPresent([MCPConfigurationDraft].self, forKey: .mcpServers) ?? []
        harnessSelections = try c.decodeIfPresent([String: ProjectHarnessSelection].self, forKey: .harnessSelections)
    }

    public var resolvedHarnessSelections: [String: ProjectHarnessSelection] {
        harnessSelections ?? Dictionary(uniqueKeysWithValues: agents.map {
            ($0, ProjectHarnessSelection(skillIDs: skillIDs, instructionIDs: instructionIDs))
        })
    }
}

private struct ProjectDraftDocument: Codable {
    let schemaVersion: Int
    var drafts: [ProjectDraft]
}

/// 草稿只属于本机编辑状态，不代表项目已经写入或启用。
public struct ProjectDraftStore {
    public let rootURL: URL

    private let fileManager: FileManager
    private let clock: () -> Date

    public init(
        rootURL: URL = ProjectStore.defaultRootURL,
        fileManager: FileManager = .default,
        clock: @escaping () -> Date = Date.init
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.clock = clock
    }

    public var documentURL: URL {
        rootURL.appendingPathComponent("project-drafts.json")
    }

    public func load(projectID: UUID) throws -> ProjectDraft? {
        try loadDocument().drafts.first { $0.projectID == projectID }
    }

    @discardableResult
    public func save(
        projectID: UUID,
        skillIDs: some Sequence<String>,
        instructionIDs: some Sequence<String>,
        agents: some Sequence<String>,
        plugins: [PresetPluginReference]? = nil,
        mcpServers: [MCPConfigurationDraft]? = nil,
        harnessSelections: [String: ProjectHarnessSelection]? = nil
    ) throws -> ProjectDraft {
        var document = try loadDocument()
        let previous = document.drafts.first { $0.projectID == projectID }
        let draft = ProjectDraft(
            projectID: projectID,
            skillIDs: normalized(skillIDs),
            instructionIDs: normalized(instructionIDs),
            agents: normalized(agents),
            updatedAt: clock(),
            plugins: plugins ?? previous?.plugins ?? [],
            mcpServers: mcpServers ?? previous?.mcpServers ?? [],
            harnessSelections: harnessSelections
        )
        document.drafts.removeAll { $0.projectID == projectID }
        document.drafts.append(draft)
        document.drafts.sort { $0.projectID.uuidString < $1.projectID.uuidString }
        try write(document)
        return draft
    }

    public func remove(projectID: UUID) throws {
        var document = try loadDocument()
        let previousCount = document.drafts.count
        document.drafts.removeAll { $0.projectID == projectID }
        guard document.drafts.count != previousCount else { return }
        try write(document)
    }

    private func loadDocument() throws -> ProjectDraftDocument {
        guard fileManager.fileExists(atPath: documentURL.path) else {
            return ProjectDraftDocument(schemaVersion: 1, drafts: [])
        }
        do {
            let data = try Data(contentsOf: documentURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ProjectDraftDocument.self, from: data)
        } catch {
            throw ProjectDraftStoreError.corruptDocument(documentURL.path)
        }
    }

    private func write(_ document: ProjectDraftDocument) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(document).write(to: documentURL, options: .atomic)
    }

    private func normalized(_ values: some Sequence<String>) -> [String] {
        Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted()
    }
}
