import Foundation

public enum ProjectLockError: Error, LocalizedError, Equatable, Sendable {
    case corruptManifest(String)
    case corruptLock(String)
    case lockStale
    case invalidManifest(String)
    case unsupportedAgent(String)
    case unsafeRelativePath(String)

    public var code: String {
        switch self {
        case .corruptManifest: "PROJECT_MANIFEST_CORRUPT"
        case .corruptLock: "PROJECT_LOCK_CORRUPT"
        case .lockStale: "PROJECT_LOCK_STALE"
        case .invalidManifest: "PROJECT_MANIFEST_INVALID"
        case .unsupportedAgent: "AGENT_UNSUPPORTED"
        case .unsafeRelativePath: "PATH_OUTSIDE_ROOT"
        }
    }

    public var errorDescription: String? {
        switch self {
        case let .corruptManifest(path):
            return "项目清单无法读取：\(path)"
        case let .corruptLock(path):
            return "项目锁无法读取：\(path)"
        case .lockStale:
            return "本机项目版本记录与安装选择不一致，需要重新生成计划。"
        case let .invalidManifest(reason):
            return "项目清单无效：\(reason)"
        case let .unsupportedAgent(agent):
            return "项目清单包含不支持的 agent：\(agent)"
        case let .unsafeRelativePath(path):
            return "项目清单包含不安全的相对路径：\(path)"
        }
    }
}

/// 单一宿主的期望内容；共享旧格式只在读取时展开，不再让界面编辑互相覆盖。
public struct ProjectHarnessSelection: Codable, Hashable, Sendable {
    public var skillIDs: [String]
    public var instructionIDs: [String]

    public init(skillIDs: [String] = [], instructionIDs: [String] = []) {
        self.skillIDs = Array(Set(skillIDs)).sorted()
        self.instructionIDs = Array(Set(instructionIDs)).sorted()
    }
}

public struct ProjectManifest: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let agents: [String]
    public let skills: [String]
    public let instructions: [String]
    public let ruleBlockID: String
    public let harnessSelections: [String: ProjectHarnessSelection]?

    public init(
        schemaVersion: Int = 1,
        agents: [String],
        skills: [String],
        instructions: [String],
        ruleBlockID: String = "project-rules",
        harnessSelections: [String: ProjectHarnessSelection]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.agents = Self.normalized(agents)
        self.skills = Self.normalized(harnessSelections.map { $0.values.flatMap(\.skillIDs) } ?? skills)
        self.instructions = Self.normalized(harnessSelections.map { $0.values.flatMap(\.instructionIDs) } ?? instructions)
        self.ruleBlockID = ruleBlockID
        self.harnessSelections = harnessSelections
    }

    public var resolvedHarnessSelections: [String: ProjectHarnessSelection] {
        harnessSelections ?? Dictionary(uniqueKeysWithValues: agents.map {
            ($0, ProjectHarnessSelection(skillIDs: skills, instructionIDs: instructions))
        })
    }

    public func selection(for agent: String) -> ProjectHarnessSelection {
        resolvedHarnessSelections[agent] ?? ProjectHarnessSelection()
    }

    public var digest: String {
        "sha256:\(SkillAssetCopier.sha256(canonicalData))"
    }

    public var canonicalData: Data {
        encodedData(pretty: false)
    }

    public var encodedData: Data {
        encodedData(pretty: true)
    }

    public func validated() throws {
        guard schemaVersion == 1 else {
            throw ProjectLockError.invalidManifest("不支持的 schemaVersion \(schemaVersion)")
        }
        guard projectRuleBlockIsValid(ruleBlockID) else {
            throw ProjectLockError.invalidManifest("ruleBlockID 无效")
        }
        if let harnessSelections {
            guard Set(harnessSelections.keys) == Set(agents),
                  Set(harnessSelections.values.flatMap(\.skillIDs)) == Set(skills),
                  Set(harnessSelections.values.flatMap(\.instructionIDs)) == Set(instructions) else {
                throw ProjectLockError.invalidManifest("宿主选择与项目汇总不一致")
            }
        }
        for agent in agents {
            guard AgentDeploymentAdapter.target(for: agent) != nil else {
                throw ProjectLockError.unsupportedAgent(agent)
            }
        }
        for path in skills + instructions {
            guard !path.isEmpty,
                  !path.hasPrefix("/"),
                  !path.split(separator: "/").contains("..") else {
                throw ProjectLockError.unsafeRelativePath(path)
            }
        }
    }

    private static func normalized(_ values: [String]) -> [String] {
        Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }

    private func encodedData(pretty: Bool) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        guard var data = try? encoder.encode(self) else {
            return Data()
        }
        if pretty {
            data.append(0x0A)
        }
        return data
    }
}

public struct ProjectDeploymentTarget: Codable, Hashable, Sendable {
    public let agent: String
    public let skillsRoot: String
    public let instructionsFile: String
    public let ruleBlockID: String

    public init(agent: String, skillsRoot: String, instructionsFile: String, ruleBlockID: String) {
        self.agent = agent
        self.skillsRoot = skillsRoot
        self.instructionsFile = instructionsFile
        self.ruleBlockID = ruleBlockID
    }
}

public enum AgentDeploymentAdapter {
    public static let supportedAgents = ["claude-code", "codex"]

    public static func targets(for manifest: ProjectManifest) throws -> [ProjectDeploymentTarget] {
        try manifest.validated()
        var targets: [ProjectDeploymentTarget] = []
        for agent in manifest.agents {
            guard let target = target(for: agent, ruleBlockID: manifest.ruleBlockID) else {
                throw ProjectLockError.unsupportedAgent(agent)
            }
            targets.append(target)
        }
        guard !targets.isEmpty || manifest.harnessSelections?.isEmpty == true else {
            throw ProjectLockError.invalidManifest("至少选择一个目标 agent")
        }
        return targets
    }

    public static func target(for agent: String, ruleBlockID: String = "project-rules") -> ProjectDeploymentTarget? {
        switch agent {
        case "codex":
            return ProjectDeploymentTarget(
                agent: agent,
                skillsRoot: ".agents/skills",
                instructionsFile: "AGENTS.md",
                ruleBlockID: ruleBlockID
            )
        case "claude-code":
            return ProjectDeploymentTarget(
                agent: agent,
                skillsRoot: ".claude/skills",
                instructionsFile: "CLAUDE.md",
                ruleBlockID: ruleBlockID
            )
        default:
            return nil
        }
    }
}

public struct LockedSkillRevision: Codable, Hashable, Sendable {
    public let id: String
    public let sourceId: String
    public let sourcePath: String
    public let declaredVersion: String?
    public let contentHash: String
    public let licenseReview: String
    public let files: [SkillAssetFile]

    public init(
        id: String,
        sourceId: String,
        sourcePath: String,
        declaredVersion: String?,
        contentHash: String,
        licenseReview: String,
        files: [SkillAssetFile]
    ) {
        self.id = id
        self.sourceId = sourceId
        self.sourcePath = sourcePath
        self.declaredVersion = declaredVersion
        self.contentHash = contentHash
        self.licenseReview = licenseReview
        self.files = files.sorted { $0.path < $1.path }
    }
}

public struct LockedInstructionRevision: Codable, Hashable, Sendable {
    public let id: String
    public let sourcePath: String
    public let sha256: String
    public let bytes: Int

    public init(id: String, sourcePath: String, sha256: String, bytes: Int) {
        self.id = id
        self.sourcePath = sourcePath
        self.sha256 = sha256
        self.bytes = bytes
    }
}

public struct ProjectLockDocument: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let manifestDigest: String
    public let hashAlgorithm: String
    public let objectStore: String
    public let adapterVersion: String
    public let targets: [ProjectDeploymentTarget]
    public let skills: [LockedSkillRevision]
    public let instructions: [LockedInstructionRevision]
    public let managementRevision: UUID?

    public init(
        schemaVersion: Int = 1,
        manifestDigest: String,
        hashAlgorithm: String = "sha256:path-content-executable:v1",
        objectStore: String = "objects/sha256",
        adapterVersion: String = "native-macos-1",
        targets: [ProjectDeploymentTarget],
        skills: [LockedSkillRevision],
        instructions: [LockedInstructionRevision],
        managementRevision: UUID? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.manifestDigest = manifestDigest
        self.hashAlgorithm = hashAlgorithm
        self.objectStore = objectStore
        self.adapterVersion = adapterVersion
        self.targets = targets
        self.skills = skills.sorted { $0.id < $1.id }
        self.instructions = instructions.sorted { $0.id < $1.id }
        self.managementRevision = managementRevision
    }

    public var encodedData: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard var data = try? encoder.encode(self) else { return Data() }
        data.append(0x0A)
        return data
    }

    public func validate(against manifest: ProjectManifest) throws {
        try manifest.validated()
        guard schemaVersion == 1 else {
            throw ProjectLockError.lockStale
        }
        guard manifestDigest == manifest.digest else {
            throw ProjectLockError.lockStale
        }
        guard hashAlgorithm == "sha256:path-content-executable:v1" else {
            throw ProjectLockError.lockStale
        }
        guard targets == (try AgentDeploymentAdapter.targets(for: manifest)) else {
            throw ProjectLockError.lockStale
        }
        let skillIDs = skills.map(\.id)
        let instructionIDs = instructions.map(\.id)
        guard skillIDs.count == Set(skillIDs).count,
              instructionIDs.count == Set(instructionIDs).count,
              Set(skillIDs) == Set(manifest.skills),
              Set(instructionIDs) == Set(manifest.instructions) else {
            throw ProjectLockError.lockStale
        }
        for skill in skills {
            guard !skill.sourcePath.hasPrefix("/"),
                  !skill.sourcePath.split(separator: "/").contains("..") else {
                throw ProjectLockError.unsafeRelativePath(skill.sourcePath)
            }
            for file in skill.files {
                guard !file.path.isEmpty,
                      !file.path.hasPrefix("/"),
                      !file.path.split(separator: "/").contains(".."),
                      file.sha256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
                    throw ProjectLockError.lockStale
                }
            }
            guard skill.contentHash == SkillAssetCopier.hashManifest(
                skill.files.map { ($0.path, $0.executable ? UInt16(0o755) : UInt16(0o644), $0.sha256) }
            ) else {
                throw ProjectLockError.lockStale
            }
        }
        for instruction in instructions {
            guard !instruction.sourcePath.hasPrefix("/"),
                  !instruction.sourcePath.split(separator: "/").contains(".."),
                  instruction.sha256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
                throw ProjectLockError.lockStale
            }
        }
    }
}

public struct ProjectStateSnapshot: Hashable, Sendable {
    public let manifest: ProjectManifest?
    public let lock: ProjectLockDocument?
    public let status: String
    public let issues: [String]

    public init(manifest: ProjectManifest?, lock: ProjectLockDocument?, status: String, issues: [String]) {
        self.manifest = manifest
        self.lock = lock
        self.status = status
        self.issues = issues
    }
}

public struct ProjectLockStore {
    public static let manifestFileName = "skillset.json"
    public static let lockFileName = "skillset.lock.json"

    public let projectRoot: URL
    public let stateRoot: URL
    private let fileManager: FileManager

    public init(projectRoot: URL, stateRoot: URL = ProjectStore.defaultRootURL, fileManager: FileManager = .default) {
        self.projectRoot = projectRoot.resolvingSymlinksInPath().standardizedFileURL
        self.stateRoot = stateRoot.resolvingSymlinksInPath().standardizedFileURL
        self.fileManager = fileManager
    }

    public var directoryURL: URL {
        let key = SkillAssetCopier.sha256(Data(projectRoot.path.utf8))
        return stateRoot.appendingPathComponent("project-state/\(key)", isDirectory: true)
    }

    public var manifestURL: URL {
        directoryURL.appendingPathComponent(Self.manifestFileName)
    }

    public var lockURL: URL {
        directoryURL.appendingPathComponent(Self.lockFileName)
    }

    /// 只读取能由本机已完成事务证明归属的旧记录；同名用户文件不会被当成管理记录。
    public var legacyRecordURLs: [URL] {
        guard !fileManager.fileExists(atPath: manifestURL.path),
              !fileManager.fileExists(atPath: lockURL.path) else { return [] }
        let oldManifest = projectRoot.appendingPathComponent(Self.manifestFileName)
        let oldLock = projectRoot.appendingPathComponent(Self.lockFileName)
        guard (try? fileManager.destinationOfSymbolicLink(atPath: oldManifest.path)) == nil,
              (try? fileManager.destinationOfSymbolicLink(atPath: oldLock.path)) == nil,
              let manifestData = try? Data(contentsOf: oldManifest),
              let lockData = try? Data(contentsOf: oldLock),
              let manifest = try? JSONDecoder().decode(ProjectManifest.self, from: manifestData),
              let lock = try? JSONDecoder().decode(ProjectLockDocument.self, from: lockData),
              (try? lock.validate(against: manifest)) != nil else { return [] }
        let operations = stateRoot.appendingPathComponent("operations")
        let executor = FileTransactionExecutor(operationsRoot: operations, fileManager: fileManager)
        let directories = (try? fileManager.contentsOfDirectory(at: operations, includingPropertiesForKeys: nil)) ?? []
        let lockHash = SkillAssetCopier.sha256(lockData)
        let hasReceipt = directories.contains { directory in
            guard let id = UUID(uuidString: directory.lastPathComponent),
                  let journal = try? executor.loadJournal(id) else { return false }
            return journal.state == "applied" && journal.projectPath == projectRoot.path
                && journal.ownershipReceipt?.lockHash == lockHash
        }
        return hasReceipt ? [oldManifest, oldLock] : []
    }

    public var observedLockURL: URL {
        legacyRecordURLs.last ?? lockURL
    }

    public func loadManifest() throws -> ProjectManifest? {
        let manifestURL = legacyRecordURLs.first ?? self.manifestURL
        guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }
        if (try? fileManager.destinationOfSymbolicLink(atPath: manifestURL.path)) != nil {
            throw ProjectLockError.corruptManifest(manifestURL.path)
        }
        do {
            let manifest = try JSONDecoder().decode(
                ProjectManifest.self,
                from: try Data(contentsOf: manifestURL)
            )
            try manifest.validated()
            return manifest
        } catch let error as ProjectLockError {
            throw error
        } catch {
            throw ProjectLockError.corruptManifest(manifestURL.path)
        }
    }

    public func loadLock() throws -> ProjectLockDocument? {
        let lockURL = observedLockURL
        guard fileManager.fileExists(atPath: lockURL.path) else { return nil }
        if (try? fileManager.destinationOfSymbolicLink(atPath: lockURL.path)) != nil {
            throw ProjectLockError.corruptLock(lockURL.path)
        }
        do {
            return try JSONDecoder().decode(ProjectLockDocument.self, from: try Data(contentsOf: lockURL))
        } catch {
            throw ProjectLockError.corruptLock(lockURL.path)
        }
    }

    public func inspect() -> ProjectStateSnapshot {
        var issues: [String] = []
        let manifest: ProjectManifest?
        do {
            manifest = try loadManifest()
        } catch {
            return ProjectStateSnapshot(
                manifest: nil,
                lock: nil,
                status: "corrupt",
                issues: [error.localizedDescription]
            )
        }
        guard let manifest else {
            return ProjectStateSnapshot(
                manifest: nil,
                lock: nil,
                status: "absent",
                issues: ["项目尚无本机安装记录。"]
            )
        }

        let lock: ProjectLockDocument?
        do {
            lock = try loadLock()
        } catch {
            return ProjectStateSnapshot(
                manifest: manifest,
                lock: nil,
                status: "corrupt",
                issues: [error.localizedDescription]
            )
        }
        guard let lock else {
            return ProjectStateSnapshot(
                manifest: manifest,
                lock: nil,
                status: "unlocked",
                issues: ["本机安装选择已存在，但缺少版本记录。"]
            )
        }
        do {
            try lock.validate(against: manifest)
            return ProjectStateSnapshot(manifest: manifest, lock: lock, status: "valid", issues: issues)
        } catch {
            issues.append(error.localizedDescription)
            return ProjectStateSnapshot(manifest: manifest, lock: lock, status: "stale", issues: issues)
        }
    }
}

private func projectRuleBlockIsValid(_ value: String) -> Bool {
    value.range(of: #"^[a-z0-9][a-z0-9._-]{0,63}$"#, options: .regularExpression) != nil
}
