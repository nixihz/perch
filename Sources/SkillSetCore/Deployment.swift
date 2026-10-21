import CryptoKit
import Foundation

public enum DeploymentError: Error, LocalizedError, Equatable, Sendable {
    case skillNotFound(String)
    case skillBlocked(String)
    case pathOutsideRoot(String)
    case skillSourceMissing(String)
    case skillSourceChanged(String)
    case invalidMarkerID(String)
    case noChanges
    case planNotFound(String)
    case planDigestMismatch
    case planAlreadyApplied
    case invalidPlan
    case symlinkDetected(String)
    case projectNotFound(String)
    case unsupportedAgent(String)
    case instructionNotFound(String)

    public var code: String {
        switch self {
        case .skillNotFound: "SKILL_NOT_FOUND"
        case .skillBlocked: "SKILL_BLOCKED"
        case .pathOutsideRoot: "PATH_OUTSIDE_ROOT"
        case .skillSourceMissing: "SKILL_SOURCE_MISSING"
        case .skillSourceChanged: "SKILL_SOURCE_CHANGED"
        case .invalidMarkerID: "RULE_MARKER_INVALID"
        case .noChanges: "PLAN_NO_CHANGES"
        case .planNotFound: "PLAN_NOT_FOUND"
        case .planDigestMismatch: "PLAN_DIGEST_MISMATCH"
        case .planAlreadyApplied: "PLAN_ALREADY_APPLIED"
        case .invalidPlan: "PLAN_INVALID"
        case .symlinkDetected: "PATH_SYMLINK"
        case .projectNotFound: "PROJECT_NOT_FOUND"
        case .unsupportedAgent: "AGENT_UNSUPPORTED"
        case .instructionNotFound: "INSTRUCTION_NOT_FOUND"
        }
    }

    public var errorDescription: String? {
        switch self {
        case let .skillNotFound(id):
            return "找不到 Skill：\(id)"
        case let .skillBlocked(id):
            return "Skill 含阻塞问题，不能部署：\(id)"
        case let .pathOutsideRoot(path):
            return "目标路径超出项目根目录：\(path)"
        case let .skillSourceMissing(path):
            return "Skill 快照不存在或不是目录：\(path)"
        case let .skillSourceChanged(path):
            return "Skill 快照在生成计划后发生变化：\(path)"
        case let .invalidMarkerID(id):
            return "受管块 ID 无效：\(id)"
        case .noChanges:
            return "计划没有可执行的变更。"
        case let .planNotFound(id):
            return "找不到计划：\(id)"
        case .planDigestMismatch:
            return "计划内容与 digest 不一致。"
        case .planAlreadyApplied:
            return "计划已经执行，不能重复应用。"
        case .invalidPlan:
            return "计划不完整或已过期。"
        case let .symlinkDetected(path):
            return "目标路径包含符号链接，管理器拒绝写入：\(path)"
        case let .projectNotFound(path):
            return "项目根目录不存在：\(path)"
        case let .unsupportedAgent(agent):
            return "不支持的目标 agent：\(agent)"
        case let .instructionNotFound(id):
            return "找不到指令片段：\(id)"
        }
    }
}

public struct SkillAssetCopyError: Error, LocalizedError, Equatable, Sendable {
    public let path: String
    public let reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }

    public var errorDescription: String? {
        "\(path)：\(reason)"
    }
}

public struct SkillAssetFile: Codable, Hashable, Sendable {
    public let path: String
    public let sha256: String
    public let executable: Bool
    public let bytes: Int

    public init(path: String, sha256: String, executable: Bool, bytes: Int) {
        self.path = path
        self.sha256 = sha256
        self.executable = executable
        self.bytes = bytes
    }
}

public struct SkillAssetCopyResult: Hashable, Sendable {
    public let fileManifest: [SkillAssetFile]
    public let contentHash: String
    public let bytes: Int

    public var files: [String] {
        fileManifest.map(\.path)
    }

    public init(fileManifest: [SkillAssetFile], contentHash: String, bytes: Int) {
        self.fileManifest = fileManifest.sorted { $0.path < $1.path }
        self.contentHash = contentHash
        self.bytes = bytes
    }
}

public enum SkillAssetCopier {
    public static func copy(from source: URL, to destination: URL, fileManager: FileManager = .default) throws -> SkillAssetCopyResult {
        let canonicalSource = source.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: canonicalSource.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw DeploymentError.skillSourceMissing(canonicalSource.path)
        }

        let destinationRoot = destination.standardizedFileURL
        let canonicalDestination = destinationRoot.resolvingSymlinksInPath().standardizedFileURL
        guard !isInside(canonicalDestination, root: canonicalSource),
              !isInside(canonicalSource, root: canonicalDestination) else {
            throw SkillAssetCopyError(path: destination.path, reason: "目标不能位于来源目录内")
        }
        if fileManager.fileExists(atPath: destinationRoot.path) {
            try fileManager.removeItem(at: destinationRoot)
        }
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        var files: [(String, UInt16, String)] = []
        var totalBytes = 0

        try walkDirectory(
            at: canonicalSource,
            relativePath: "",
            sourceRoot: canonicalSource,
            ancestors: [],
            fileManager: fileManager,
            onDirectory: { relative in
                try fileManager.createDirectory(
                    at: destinationRoot.appendingPathComponent(relative, isDirectory: true),
                    withIntermediateDirectories: true
                )
            },
            onFile: { relative, data, permissions in
                let target = destinationRoot.appendingPathComponent(relative)
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: target, options: .atomic)
                try fileManager.setAttributes([.posixPermissions: NSNumber(value: permissions)], ofItemAtPath: target.path)
                files.append((relative, permissions, sha256(data)))
                totalBytes += data.count
            }
        )
        files.sort { $0.0 < $1.0 }
        let fileManifest = files.map {
            let path = destinationRoot.appendingPathComponent($0.0).path
            let size = ((try? fileManager.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.intValue ?? 0
            return SkillAssetFile(
                path: $0.0,
                sha256: $0.2,
                executable: $0.1 & 0o111 != 0,
                bytes: size
            )
        }
        return SkillAssetCopyResult(
            fileManifest: fileManifest,
            contentHash: hashManifest(files),
            bytes: totalBytes
        )
    }

    /// 只计算与部署相同的实体化指纹，不写目标目录，供项目观察和版本核对使用。
    public static func analyze(from source: URL, fileManager: FileManager = .default) throws -> SkillAssetCopyResult {
        let sourceRoot = source.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw DeploymentError.skillSourceMissing(sourceRoot.path)
        }
        var files: [(String, UInt16, String)] = []
        var totalBytes = 0
        try walkDirectory(
            at: sourceRoot,
            relativePath: "",
            sourceRoot: sourceRoot,
            ancestors: [],
            fileManager: fileManager,
            onDirectory: { _ in },
            onFile: { relative, data, permissions in
                files.append((relative, permissions, sha256(data)))
                totalBytes += data.count
            }
        )
        files.sort { $0.0 < $1.0 }
        let fileManifest = files.map {
            let path = sourceRoot.appendingPathComponent($0.0).path
            let size = ((try? fileManager.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.intValue ?? 0
            return SkillAssetFile(
                path: $0.0,
                sha256: $0.2,
                executable: $0.1 & 0o111 != 0,
                bytes: size
            )
        }
        return SkillAssetCopyResult(
            fileManifest: fileManifest,
            contentHash: hashManifest(files),
            bytes: totalBytes
        )
    }

    static func collectFiles(from source: URL, fileManager: FileManager = .default) throws -> [(String, Data, UInt16)] {
        let sourceRoot = source.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw DeploymentError.skillSourceMissing(sourceRoot.path)
        }
        var files: [(String, Data, UInt16)] = []
        try walkDirectory(
            at: sourceRoot,
            relativePath: "",
            sourceRoot: sourceRoot,
            ancestors: [],
            fileManager: fileManager,
            onDirectory: { _ in },
            onFile: { relative, data, permissions in
                files.append((relative, data, permissions))
            }
        )
        return files.sorted { $0.0 < $1.0 }
    }

    private static func walkDirectory(
        at directory: URL,
        relativePath: String,
        sourceRoot: URL,
        ancestors: Set<String>,
        fileManager: FileManager,
        onDirectory: (String) throws -> Void,
        onFile: (String, Data, UInt16) throws -> Void
    ) throws {
        let resolvedDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        guard !ancestors.contains(resolvedDirectory.path) else {
            throw SkillAssetCopyError(path: relativePath.isEmpty ? "." : relativePath, reason: "软链形成循环")
        }
        let nextAncestors = ancestors.union([resolvedDirectory.path])
        let children = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }

        for item in children {
            let childPath = relativePath.isEmpty
                ? item.lastPathComponent
                : "\(relativePath)/\(item.lastPathComponent)"
            let resolved = item.resolvingSymlinksInPath().standardizedFileURL
            guard isInside(resolved, root: sourceRoot) else {
                throw SkillAssetCopyError(path: childPath, reason: "软链越出 Skill 根目录")
            }

            var targetIsDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: resolved.path, isDirectory: &targetIsDirectory) else {
                throw SkillAssetCopyError(path: childPath, reason: "软链目标不存在")
            }
            if targetIsDirectory.boolValue {
                try onDirectory(childPath)
                try walkDirectory(
                    at: resolved,
                    relativePath: childPath,
                    sourceRoot: sourceRoot,
                    ancestors: nextAncestors,
                    fileManager: fileManager,
                    onDirectory: onDirectory,
                    onFile: onFile
                )
                continue
            }

            // 资源软链在部署时必须实体化；相对路径使用软链自身的名字，而不是目标文件名。
            let attributes = try fileManager.attributesOfItem(atPath: resolved.path)
            let type = attributes[.type] as? FileAttributeType
            guard type == .typeRegular else {
                throw SkillAssetCopyError(path: childPath, reason: "仅允许普通文件")
            }
            let permissions = ((attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o644) & 0o777
            let data = try Data(contentsOf: resolved, options: .mappedIfSafe)
            try onFile(childPath, data, permissions)
        }
    }

    private static func isInside(_ url: URL, root: URL) -> Bool {
        url.path == root.path || url.path.hasPrefix(root.path + "/")
    }

    static func hashManifest(_ files: [(String, UInt16, String)]) -> String {
        let manifest = files.sorted { $0.0 < $1.0 }.map { file in
            ["path": file.0, "sha256": file.2, "executable": file.1 & 0o111 != 0] as [String: Any]
        }
        let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .withoutEscapingSlashes])
        return sha256(data ?? Data())
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256(fileAt url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return sha256(data)
    }
}

public struct PlannedChange: Codable, Hashable, Sendable {
    public let action: String
    public let relativePath: String
    public let beforeHash: String?
    public let afterHash: String?
    public let unifiedDiff: String

    public init(action: String, relativePath: String, beforeHash: String?, afterHash: String?, unifiedDiff: String) {
        self.action = action
        self.relativePath = relativePath
        self.beforeHash = beforeHash
        self.afterHash = afterHash
        self.unifiedDiff = unifiedDiff
    }
}

public struct DeploymentPlan: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let projectPath: String
    public let createdAt: Date
    public let digest: String
    public let changes: [PlannedChange]
    public let warnings: [String]
    public let isApplied: Bool
    public let metadata: [String: String]?

    public init(
        id: UUID = UUID(),
        projectPath: String,
        createdAt: Date,
        digest: String,
        changes: [PlannedChange],
        warnings: [String],
        isApplied: Bool = false,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.projectPath = projectPath
        self.createdAt = createdAt
        self.digest = digest
        self.changes = changes
        self.warnings = warnings
        self.isApplied = isApplied
        self.metadata = metadata
    }
}

public struct DeploymentRequest: Hashable, Sendable {
    public var skillIDs: [String]
    public var instructionIDs: [String]
    public var agents: [String]
    public var ruleBlockID: String

    public init(
        skillIDs: [String] = [],
        instructionIDs: [String] = [],
        agents: [String] = ["codex"],
        ruleBlockID: String = "project-rules"
    ) {
        self.skillIDs = skillIDs
        self.instructionIDs = instructionIDs
        self.agents = agents
        self.ruleBlockID = ruleBlockID
    }
}

/// 在独立 staging 目录构造计划和完整目标内容，apply 只执行已复核的字节。
public struct DeploymentPlanner {
    public let catalog: CatalogDocument
    public let repositoryRoot: URL
    public let stagingRoot: URL

    private let fileManager: FileManager
    private let clock: () -> Date
    private let idGenerator: () -> UUID

    public init(
        catalog: CatalogDocument,
        repositoryRoot: URL,
        stagingRoot: URL,
        fileManager: FileManager = .default,
        clock: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> UUID = UUID.init
    ) {
        self.catalog = catalog
        self.repositoryRoot = repositoryRoot
        self.stagingRoot = stagingRoot
        self.fileManager = fileManager
        self.clock = clock
        self.idGenerator = idGenerator
    }

    public func makePlan(
        projectPath: URL,
        request: DeploymentRequest,
        skillBodies: [String: String] = [:],
        fragments: [String: String]
    ) throws -> DeploymentPlan {
        let projectRoot = try validatedProjectRoot(projectPath)
        guard request.ruleBlockID.range(of: #"^[a-z0-9][a-z0-9._-]{0,63}$"#, options: .regularExpression) != nil else {
            throw DeploymentError.invalidMarkerID(request.ruleBlockID)
        }
        let manifest = ProjectManifest(
            agents: request.agents,
            skills: request.skillIDs,
            instructions: request.instructionIDs,
            ruleBlockID: request.ruleBlockID
        )
        try manifest.validated()
        let targets = try AgentDeploymentAdapter.targets(for: manifest)

        let planID = idGenerator()
        let stage = stagingRoot.appendingPathComponent(planID.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: stage.path) {
            try fileManager.removeItem(at: stage)
        }
        try fileManager.createDirectory(at: stage, withIntermediateDirectories: true)

        let selected = try manifest.skills.map { id -> SkillEntry in
            guard let entry = catalog.entries.first(where: { $0.id == id }) else {
                throw DeploymentError.skillNotFound(id)
            }
            guard !entry.isBlocked else {
                throw DeploymentError.skillBlocked(id)
            }
            return entry
        }
        let duplicateSlugs = Dictionary(grouping: selected, by: \.slug).filter { $0.value.count > 1 }
        guard duplicateSlugs.isEmpty else {
            throw DeploymentError.invalidPlan
        }

        var instructionBodies: [(id: String, body: String)] = []
        for id in manifest.instructions {
            guard let body = fragments[id] else {
                throw DeploymentError.instructionNotFound(id)
            }
            instructionBodies.append((id, body))
        }

        let objectStore = SkillObjectStore(repositoryRoot: repositoryRoot)
        let currentLock = try? ProjectLockStore(projectRoot: projectRoot).loadLock()
        var lockedSkills: [LockedSkillRevision] = []
        var objectCount = 0
        var objectBytes = 0
        var changes: [PlannedChange] = []
        for entry in selected {
            let catalogSource = repositoryRoot.appendingPathComponent(entry.path)
            var source = catalogSource
            let sourceHash = try? SkillAssetCopier.analyze(from: catalogSource, fileManager: fileManager).contentHash
            var restoredSource: URL?
            if sourceHash != entry.contentHash {
                let temporarySource = stage
                    .appendingPathComponent(".skillset-object-sources", isDirectory: true)
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                if let locked = currentLock?.skills.first(where: {
                    $0.id == entry.id && $0.contentHash == entry.contentHash
                }) {
                    try objectStore.restore(files: locked.files, to: temporarySource)
                    source = temporarySource
                    restoredSource = temporarySource
                } else if (try? objectStore.loadManifest(contentHash: entry.contentHash)) != nil {
                    try objectStore.restore(contentHash: entry.contentHash, to: temporarySource)
                    source = temporarySource
                    restoredSource = temporarySource
                } else if fileManager.fileExists(atPath: catalogSource.path) {
                    throw DeploymentError.skillSourceChanged(catalogSource.path)
                } else {
                    throw DeploymentError.skillSourceMissing(catalogSource.path)
                }
            }
            let materialized = try objectStore.materializeSkill(source: source)
            guard materialized.contentHash == entry.contentHash else {
                throw SkillAssetCopyError(
                    path: entry.path,
                    reason: "内容指纹不一致：预期 \(entry.contentHash)，实际 \(materialized.contentHash)"
                )
            }
            objectCount += materialized.objectsWritten
            objectBytes += materialized.bytes
            lockedSkills.append(LockedSkillRevision(
                id: entry.id,
                sourceId: entry.sourceId,
                sourcePath: entry.path,
                declaredVersion: entry.declaredVersion,
                contentHash: materialized.contentHash,
                licenseReview: entry.licenseReview,
                files: materialized.fileManifest
            ))

            for target in targets {
                let relativePath = "\(target.skillsRoot)/\(entry.slug)"
                let destination = stage.appendingPathComponent(relativePath, isDirectory: true)
                let copy = try SkillAssetCopier.copy(from: source, to: destination, fileManager: fileManager)
                guard copy.contentHash == materialized.contentHash else {
                    throw SkillAssetCopyError(path: entry.path, reason: "对象存储与 staging 指纹不一致")
                }
                let observedTarget = projectRoot.appendingPathComponent(relativePath, isDirectory: true)
                let beforeHash = try directoryDigest(observedTarget)
                let action = beforeHash == nil ? "add" : (beforeHash == copy.contentHash ? "noop" : "update")
                changes.append(PlannedChange(
                    action: action,
                    relativePath: relativePath,
                    beforeHash: beforeHash,
                    afterHash: copy.contentHash,
                    unifiedDiff: "复制 \(copy.files.count) 个文件到 \(relativePath)"
                ))
            }
            if let restoredSource {
                try? fileManager.removeItem(at: restoredSource)
            }
        }

        let selectedIDs = Set(selected.map(\.id))
        guard selectedIDs == Set(manifest.skills) else {
            throw DeploymentError.invalidPlan
        }

        let instructionBody = instructionBodies
            .map(\.body)
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var lockedInstructions: [LockedInstructionRevision] = []
        for instruction in instructionBodies {
            let data = Data(instruction.body.utf8)
            let digest = try objectStore.materializeData(data)
            objectCount += 1
            objectBytes += data.count
            lockedInstructions.append(LockedInstructionRevision(
                id: instruction.id,
                sourcePath: "templates/agents/\(instruction.id).md",
                sha256: digest,
                bytes: data.count
            ))
        }

        for target in targets {
            let targetURL = projectRoot.appendingPathComponent(target.instructionsFile)
            try ensureSafeTarget(targetURL, root: projectRoot)
            let original = fileManager.fileExists(atPath: targetURL.path)
                ? try String(contentsOf: targetURL, encoding: .utf8)
                : ""
            let block = instructionBody.isEmpty
                ? try ManagedBlocks.remove(original: original, id: target.ruleBlockID)
                : try ManagedBlocks.upsert(original: original, id: target.ruleBlockID, body: instructionBody)
            if block.changed {
                let staged = stage.appendingPathComponent(target.instructionsFile)
                try Data(block.content.utf8).write(to: staged, options: .atomic)
                changes.append(PlannedChange(
                    action: original.isEmpty ? "add" : "update",
                    relativePath: target.instructionsFile,
                    beforeHash: original.isEmpty ? nil : SkillAssetCopier.sha256(Data(original.utf8)),
                    afterHash: SkillAssetCopier.sha256(Data(block.content.utf8)),
                    unifiedDiff: instructionBody.isEmpty
                        ? "移除受管块 \(target.ruleBlockID)"
                        : (block.wasInserted
                            ? "追加受管块 \(target.ruleBlockID)"
                            : "替换受管块 \(target.ruleBlockID)")
                ))
            }
        }

        let lock = ProjectLockDocument(
            manifestDigest: manifest.digest,
            targets: targets,
            skills: lockedSkills,
            instructions: lockedInstructions
        )
        try lock.validate(against: manifest)

        for (relativePath, data, description) in [
            (ProjectLockStore.manifestFileName, manifest.encodedData, "写入固定 desired 状态"),
            (ProjectLockStore.lockFileName, lock.encodedData, "写入内容修订与文件清单")
        ] {
            let target = projectRoot.appendingPathComponent(relativePath)
            try ensureSafeTarget(target, root: projectRoot)
            let original = fileManager.fileExists(atPath: target.path)
                ? try Data(contentsOf: target, options: .mappedIfSafe)
                : nil
            let beforeHash = original.map(SkillAssetCopier.sha256)
            let afterHash = SkillAssetCopier.sha256(data)
            if beforeHash != afterHash {
                let staged = stage.appendingPathComponent(relativePath)
                try fileManager.createDirectory(at: staged.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: staged, options: .atomic)
                changes.append(PlannedChange(
                    action: original == nil ? "add" : "update",
                    relativePath: relativePath,
                    beforeHash: beforeHash,
                    afterHash: afterHash,
                    unifiedDiff: description
                ))
            }
        }

        let executableChanges = changes.filter { $0.action != "noop" }
        guard !executableChanges.isEmpty else {
            try fileManager.removeItem(at: stage)
            throw DeploymentError.noChanges
        }

        let createdAt = clock()
        let digest = Self.calculateDigest(
            projectPath: projectRoot.path,
            manifestDigest: manifest.digest,
            changes: executableChanges,
            selectedSkills: selected.map { "\($0.id)@\($0.contentHash)" },
            metadata: ["planType": "skill-deployment"]
        )
        return DeploymentPlan(
            id: planID,
            projectPath: projectRoot.path,
            createdAt: createdAt,
            digest: digest,
            changes: executableChanges,
            warnings: selected.map { "\($0.id) 仍处于 \($0.integrity)；许可审查为 \($0.licenseReview)。" }
                + ["对象存储新增 \(objectCount) 个对象，共 \(objectBytes) 字节；项目锁绑定 manifest \(manifest.digest)。"],
            metadata: ["planType": "skill-deployment"]
        )
    }

    public static func calculateDigest(
        projectPath: String,
        manifestDigest: String = "",
        changes: [PlannedChange],
        selectedSkills: [String],
        metadata: [String: String]? = nil
    ) -> String {
        var canonical = "project=\(projectPath)\n"
        canonical += "manifest=\(manifestDigest)\n"
        canonical += "skills=\(selectedSkills.sorted().joined(separator: ","))\n"
        for change in changes {
            canonical += "\(change.action)|\(change.relativePath)|\(change.beforeHash ?? "nil")|\(change.afterHash ?? "nil")\n"
        }
        for (key, value) in (metadata ?? [:]).sorted(by: { $0.key < $1.key }) {
            canonical += "meta|\(key)|\(value)\n"
        }
        return SkillAssetCopier.sha256(Data(canonical.utf8))
    }

    private func validatedProjectRoot(_ url: URL) throws -> URL {
        let root = url.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw DeploymentError.projectNotFound(root.path)
        }
        return root
    }

    private func ensureSafeTarget(_ target: URL, root: URL) throws {
        let relative = target.path.replacingOccurrences(of: root.path, with: "")
        guard !relative.isEmpty, !relative.contains("..") else {
            throw DeploymentError.pathOutsideRoot(target.path)
        }
        if fileManager.fileExists(atPath: target.path),
           (try? fileManager.destinationOfSymbolicLink(atPath: target.path)) != nil {
            throw DeploymentError.symlinkDetected(target.path)
        }
        var cursor = target.deletingLastPathComponent()
        while cursor.path != root.path && cursor.path.hasPrefix(root.path + "/") {
            if fileManager.fileExists(atPath: cursor.path) {
                let values = try cursor.resourceValues(forKeys: [.isSymbolicLinkKey])
                if values.isSymbolicLink == true {
                    throw DeploymentError.symlinkDetected(cursor.path)
                }
            }
            cursor.deleteLastPathComponent()
        }
    }

    private func directoryDigest(_ url: URL) throws -> String? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }
        if (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw DeploymentError.symlinkDetected(url.path)
        }
        guard isDirectory.boolValue else {
            throw DeploymentError.invalidPlan
        }
        let prefix = url.path + "/"
        let files = try fileManager.subpathsOfDirectory(atPath: url.path)
            .sorted()
            .compactMap { relative -> (String, UInt16, String)? in
                let file = url.appendingPathComponent(relative)
                if (try? fileManager.destinationOfSymbolicLink(atPath: file.path)) != nil {
                    throw DeploymentError.symlinkDetected(file.path)
                }
                var childIsDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: file.path, isDirectory: &childIsDirectory) else {
                    return nil
                }
                guard !childIsDirectory.boolValue else { return nil }
                let attributes = try fileManager.attributesOfItem(atPath: file.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular else {
                    throw DeploymentError.invalidPlan
                }
                let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o644
                return (
                    file.path.replacingOccurrences(of: prefix, with: ""),
                    permissions,
                    SkillAssetCopier.sha256(try Data(contentsOf: file))
                )
            }
        return SkillAssetCopier.hashManifest(files)
    }
}
