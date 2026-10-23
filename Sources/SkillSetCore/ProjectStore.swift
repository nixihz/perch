import Foundation

public enum SkillSetStoreError: Error, LocalizedError, Equatable, Sendable {
    case projectPathMissing(String)
    case projectPathNotDirectory(String)
    case projectNotFound(String)
    case duplicateProject(String)
    case corruptRegistry(String)
    case invalidProjectName

    public var code: String {
        switch self {
        case .projectPathMissing: "PROJECT_PATH_MISSING"
        case .projectPathNotDirectory: "PROJECT_PATH_NOT_DIRECTORY"
        case .projectNotFound: "PROJECT_NOT_FOUND"
        case .duplicateProject: "PROJECT_ALREADY_REGISTERED"
        case .corruptRegistry: "PROJECT_REGISTRY_CORRUPT"
        case .invalidProjectName: "PROJECT_NAME_INVALID"
        }
    }

    public var errorDescription: String? {
        switch self {
        case let .projectPathMissing(path):
            return "项目路径不存在：\(path)"
        case let .projectPathNotDirectory(path):
            return "项目路径不是目录：\(path)"
        case let .projectNotFound(id):
            return "未登记项目：\(id)"
        case let .duplicateProject(path):
            return "项目已经登记：\(path)"
        case let .corruptRegistry(path):
            return "项目登记文件无法读取：\(path)"
        case .invalidProjectName:
            return "项目名称不能为空，且不能包含路径分隔符。"
        }
    }
}

public struct ProjectRegistration: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public let canonicalPath: String
    public let createdAt: Date
    public var lastObservedAt: Date
    public var agents: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        canonicalPath: String,
        createdAt: Date,
        lastObservedAt: Date,
        agents: [String]
    ) {
        self.id = id
        self.name = name
        self.canonicalPath = canonicalPath
        self.createdAt = createdAt
        self.lastObservedAt = lastObservedAt
        self.agents = agents
    }
}

public struct ProjectRegistryDocument: Codable, Sendable {
    public let schemaVersion: Int
    public var projects: [ProjectRegistration]

    public init(schemaVersion: Int = 1, projects: [ProjectRegistration] = []) {
        self.schemaVersion = schemaVersion
        self.projects = projects
    }
}

/// 只负责本机登记，不会修改项目目录或宿主配置。
public struct ProjectStore {
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

    public static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".perch", isDirectory: true)
    }

    public var registryURL: URL {
        rootURL.appendingPathComponent("projects.json")
    }

    public func list() throws -> [ProjectRegistration] {
        try load().projects.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    public func project(id: UUID) throws -> ProjectRegistration {
        guard let project = try load().projects.first(where: { $0.id == id }) else {
            throw SkillSetStoreError.projectNotFound(id.uuidString)
        }
        return project
    }

    public func register(
        path: URL,
        name requestedName: String? = nil,
        agents: [String] = []
    ) throws -> ProjectRegistration {
        let canonicalURL = try canonicalProjectURL(path)
        var document = try load()
        if let index = document.projects.firstIndex(where: { $0.canonicalPath == canonicalURL.path }) {
            document.projects[index].lastObservedAt = clock()
            document.projects[index].agents = normalizedAgents(document.projects[index].agents + agents)
            try save(document)
            return document.projects[index]
        }

        let name = (requestedName ?? canonicalURL.lastPathComponent)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\") else {
            throw SkillSetStoreError.invalidProjectName
        }

        let now = clock()
        let project = ProjectRegistration(
            name: name,
            canonicalPath: canonicalURL.path,
            createdAt: now,
            lastObservedAt: now,
            agents: normalizedAgents(agents)
        )
        document.projects.append(project)
        try save(document)
        return project
    }

    /// 修改登记元数据，不移动目录、不写宿主文件。
    public func update(id: UUID, name: String? = nil, agents: [String]? = nil) throws -> ProjectRegistration {
        var document = try load()
        guard let index = document.projects.firstIndex(where: { $0.id == id }) else {
            throw SkillSetStoreError.projectNotFound(id.uuidString)
        }
        if let name {
            let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !value.contains("/"), !value.contains("\\") else {
                throw SkillSetStoreError.invalidProjectName
            }
            document.projects[index].name = value
        }
        if let agents { document.projects[index].agents = normalizedAgents(agents) }
        try save(document)
        return document.projects[index]
    }

    public func unregister(id: UUID) throws {
        var document = try load()
        guard document.projects.contains(where: { $0.id == id }) else {
            throw SkillSetStoreError.projectNotFound(id.uuidString)
        }
        document.projects.removeAll { $0.id == id }
        try save(document)
    }

    public func refresh(id: UUID) throws -> ProjectRegistration {
        var document = try load()
        guard let index = document.projects.firstIndex(where: { $0.id == id }) else {
            throw SkillSetStoreError.projectNotFound(id.uuidString)
        }
        let currentURL = URL(fileURLWithPath: document.projects[index].canonicalPath, isDirectory: true)
        let canonicalURL = try canonicalProjectURL(currentURL)
        guard canonicalURL.path == document.projects[index].canonicalPath else {
            throw SkillSetStoreError.projectPathMissing(document.projects[index].canonicalPath)
        }
        document.projects[index].lastObservedAt = clock()
        try save(document)
        return document.projects[index]
    }

    public func canonicalProjectURL(_ url: URL) throws -> URL {
        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else {
            throw SkillSetStoreError.projectPathMissing(standardized.path)
        }
        guard isDirectory.boolValue else {
            throw SkillSetStoreError.projectPathNotDirectory(standardized.path)
        }
        return standardized.resolvingSymlinksInPath().standardizedFileURL
    }

    private func load() throws -> ProjectRegistryDocument {
        guard fileManager.fileExists(atPath: registryURL.path) else {
            return ProjectRegistryDocument()
        }
        do {
            let data = try Data(contentsOf: registryURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ProjectRegistryDocument.self, from: data)
        } catch {
            throw SkillSetStoreError.corruptRegistry(registryURL.path)
        }
    }

    private func save(_ document: ProjectRegistryDocument) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        try data.write(to: registryURL, options: .atomic)
    }

    private func normalizedAgents(_ agents: [String]) -> [String] {
        Array(Set(agents.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted()
    }
}
