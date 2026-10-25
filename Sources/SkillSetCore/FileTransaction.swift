import Foundation

public enum FileTransactionError: Error, LocalizedError, Equatable, Sendable {
    case staleFile(String)
    case unsafeDestination(String)
    case journalCorrupt(String)
    case rollbackConflict(String)
    case operationNotFound(String)
    case invalidStaging(String)

    public var code: String {
        switch self {
        case .staleFile: "PLAN_STALE"
        case .unsafeDestination: "PATH_OUTSIDE_ROOT"
        case .journalCorrupt: "RECOVERY_REQUIRED"
        case .rollbackConflict: "ROLLBACK_CONFLICT"
        case .operationNotFound: "OPERATION_NOT_FOUND"
        case .invalidStaging: "STAGING_INVALID"
        }
    }

    public var errorDescription: String? {
        switch self {
        case let .staleFile(path):
            return "目标文件在生成计划后发生变化：\(path)"
        case let .unsafeDestination(path):
            return "目标路径不安全：\(path)"
        case let .journalCorrupt(path):
            return "操作 journal 无法读取：\(path)"
        case let .rollbackConflict(path):
            return "目标文件已漂移，不能自动回滚：\(path)"
        case let .operationNotFound(id):
            return "找不到操作：\(id)"
        case let .invalidStaging(path):
            return "staging 目录不完整：\(path)"
        }
    }
}

public struct FileTransactionStep: Codable, Hashable, Sendable {
    public let scope: String?
    public let relativePath: String
    public let action: String
    public let beforeHash: String?
    public let afterHash: String?
    public var state: String
    public var temporaryPath: String?
    public var displacedPath: String?
    public var restorePath: String?
    public var discardedPath: String?

    public init(
        relativePath: String,
        action: String,
        beforeHash: String?,
        afterHash: String?,
        state: String,
        temporaryPath: String? = nil,
        displacedPath: String? = nil,
        scope: String? = nil
    ) {
        self.scope = scope
        self.relativePath = relativePath
        self.action = action
        self.beforeHash = beforeHash
        self.afterHash = afterHash
        self.state = state
        self.temporaryPath = temporaryPath
        self.displacedPath = displacedPath
        self.restorePath = nil
        self.discardedPath = nil
    }
}

public struct FileTransactionJournal: Codable, Hashable, Sendable {
    public let operationID: UUID
    public let projectPath: String
    public let planID: UUID
    public let planDigest: String
    public let createdAt: Date
    public var state: String
    public var steps: [FileTransactionStep]
    public let ownershipReceipt: ProjectOwnershipReceipt?
    public let metadata: [String: String]?

    public init(
        operationID: UUID,
        projectPath: String,
        planID: UUID,
        planDigest: String,
        createdAt: Date,
        state: String,
        steps: [FileTransactionStep],
        ownershipReceipt: ProjectOwnershipReceipt? = nil,
        metadata: [String: String]? = nil
    ) {
        self.operationID = operationID
        self.projectPath = projectPath
        self.planID = planID
        self.planDigest = planDigest
        self.createdAt = createdAt
        self.state = state
        self.steps = steps
        self.ownershipReceipt = ownershipReceipt
        self.metadata = metadata
    }
}

public struct TransactionResult: Hashable, Sendable {
    public let operationID: UUID
    public let journalURL: URL
    public let changedPaths: [String]

    public init(operationID: UUID, journalURL: URL, changedPaths: [String]) {
        self.operationID = operationID
        self.journalURL = journalURL
        self.changedPaths = changedPaths
    }
}

/// 只执行已经复核过的 staging 内容；每个目标在写入前重新检查旧 hash。
public struct FileTransactionExecutor {
    public let operationsRoot: URL
    private let versionsRoot: URL?
    private let libraryRoot: URL?
    private let sourcesRoot: URL?
    private let fileManager: FileManager
    private let clock: () -> Date
    private let idGenerator: () -> UUID

    public init(
        operationsRoot: URL,
        versionsRoot: URL? = nil,
        libraryRoot: URL? = nil,
        sourcesRoot: URL? = nil,
        fileManager: FileManager = .default,
        clock: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> UUID = UUID.init
    ) {
        self.operationsRoot = operationsRoot
        self.versionsRoot = versionsRoot
        self.libraryRoot = libraryRoot
        self.sourcesRoot = sourcesRoot
        self.fileManager = fileManager
        self.clock = clock
        self.idGenerator = idGenerator
    }

    public func apply(plan: DeploymentPlan, from stagingRoot: URL) throws -> TransactionResult {
        let projectRoot = URL(fileURLWithPath: plan.projectPath, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        try validate(plan: plan, stagingRoot: stagingRoot, projectRoot: projectRoot)
        let operationID = idGenerator()
        let operationRoot = operationsRoot.appendingPathComponent(operationID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: operationRoot, withIntermediateDirectories: true)

        var steps = plan.changes.map {
            FileTransactionStep(
                relativePath: $0.relativePath,
                action: $0.action,
                beforeHash: $0.beforeHash,
                afterHash: $0.afterHash,
                state: "pending", scope: $0.scope
            )
        }
        var journal = FileTransactionJournal(
            operationID: operationID,
            projectPath: projectRoot.path,
            planID: plan.id,
            planDigest: plan.digest,
            createdAt: clock(),
            state: "applying",
            steps: steps,
            ownershipReceipt: plan.ownershipReceipt,
            metadata: plan.metadata
        )
        try writeJournal(journal)

        do {
            for index in steps.indices {
                let change = plan.changes[index]
                let targetRoot = try destinationRoot(scope: change.scope, relativePath: change.relativePath, projectRoot: projectRoot)
                let destination = targetRoot.appendingPathComponent(change.relativePath)
                try ensureInsideProject(destination, root: targetRoot)
                try ensureNoSymlinkInParents(destination, root: targetRoot)
                try ensureTargetIsNotSymlink(destination)

                let actualHash = try currentContentHash(destination)
                let expected = change.beforeHash
                guard actualHash == expected else {
                    throw FileTransactionError.staleFile(change.relativePath)
                }

                if change.action == "remove" {
                    let backup = operationRoot.appendingPathComponent("backup/\(change.relativePath)")
                    try fileManager.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fileManager.copyItem(at: destination, to: backup)
                    guard try currentContentHash(backup) == change.beforeHash else {
                        throw FileTransactionError.staleFile(change.relativePath)
                    }
                    let displaced = siblingTemporaryURL(for: destination, suffix: "removed")
                    steps[index].displacedPath = displaced.path
                    steps[index].state = "staged"
                    journal.steps = steps
                    try writeJournal(journal)
                    guard try currentContentHash(destination) == change.beforeHash else {
                        throw FileTransactionError.staleFile(change.relativePath)
                    }
                    try fileManager.moveItem(at: destination, to: displaced)
                    steps[index].state = "old-moved"
                    journal.steps = steps
                    try writeJournal(journal)
                    guard try currentContentHash(displaced) == change.beforeHash,
                          try currentContentHash(destination) == nil else {
                        throw FileTransactionError.staleFile(change.relativePath)
                    }
                    steps[index].state = "applied"
                    journal.steps = steps
                    try writeJournal(journal)
                    try removeIfPresent(displaced)
                    continue
                }

                let staged = stagingRoot.appendingPathComponent(change.relativePath)
                guard fileManager.fileExists(atPath: staged.path) else {
                    throw FileTransactionError.invalidStaging(staged.path)
                }
                guard try currentContentHash(staged) == change.afterHash else {
                    throw FileTransactionError.invalidStaging(staged.path)
                }
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                if let beforeHash = change.beforeHash {
                    let backup = operationRoot.appendingPathComponent("backup/\(change.relativePath)")
                    try fileManager.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fileManager.copyItem(at: destination, to: backup)
                    guard try currentContentHash(backup) == beforeHash else {
                        throw FileTransactionError.staleFile(change.relativePath)
                    }
                }

                let temporary = siblingTemporaryURL(for: destination, suffix: "staged")
                let displaced = siblingTemporaryURL(for: destination, suffix: "previous")
                try removeIfPresent(temporary)
                try removeIfPresent(displaced)
                steps[index].temporaryPath = temporary.path
                steps[index].displacedPath = displaced.path
                try fileManager.copyItem(at: staged, to: temporary)
                guard try currentContentHash(temporary) == change.afterHash else {
                    try? fileManager.removeItem(at: temporary)
                    throw FileTransactionError.invalidStaging(staged.path)
                }
                steps[index].state = "staged"
                journal.steps = steps
                try writeJournal(journal)

                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.moveItem(at: destination, to: displaced)
                    steps[index].state = "old-moved"
                    journal.steps = steps
                    try writeJournal(journal)
                }
                try fileManager.moveItem(at: temporary, to: destination)
                let writtenHash = try currentContentHash(destination) ?? ""
                guard writtenHash == change.afterHash else {
                    throw FileTransactionError.staleFile(change.relativePath)
                }
                steps[index].state = "applied"
                journal.steps = steps
                try writeJournal(journal)
                try removeIfPresent(displaced)
            }
            journal.state = "applied"
            try writeJournal(journal)
            return TransactionResult(
                operationID: operationID,
                journalURL: journalURL(operationID),
                changedPaths: try plan.changes.map { change in
                    guard change.scope != nil else { return change.relativePath }
                    return try destinationRoot(scope: change.scope, relativePath: change.relativePath, projectRoot: projectRoot)
                        .appendingPathComponent(change.relativePath).path
                }
            )
        } catch {
            // 失败时尽量恢复本次已写步骤，避免留下半完成的受管目录
            let rollbackJournal = FileTransactionJournal(
                operationID: operationID,
                projectPath: projectRoot.path,
                planID: plan.id,
                planDigest: plan.digest,
                createdAt: journal.createdAt,
                state: "applying",
                steps: steps,
                ownershipReceipt: plan.ownershipReceipt,
                metadata: plan.metadata
            )
            var recovered = false
            do {
                _ = try rollback(journal: rollbackJournal)
                recovered = true
            } catch {
                // 恢复失败保留 failed journal，交给下一次启动处理
            }
            // 保留回滚逐步持久化的结果，不能用旧 steps 覆盖已恢复记录。
            journal = (try? loadJournal(operationID)) ?? rollbackJournal
            journal.state = recovered ? "failed-rolled-back" : "failed"
            try? writeJournal(journal)
            throw error
        }
    }

    public func recoverPendingOperations() throws -> [UUID] {
        guard fileManager.fileExists(atPath: operationsRoot.path) else { return [] }
        let directories = try fileManager.contentsOfDirectory(
            at: operationsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var recovered: [UUID] = []
        for directory in directories {
            guard let id = UUID(uuidString: directory.lastPathComponent),
                  let journal = try? loadJournal(id),
                  ["applying", "failed", "rolling-back"].contains(journal.state) else {
                continue
            }
            _ = try rollback(journal: journal)
            recovered.append(id)
        }
        return recovered
    }

    public func rollback(operationID: UUID) throws -> [String] {
        let journal = try loadJournal(operationID)
        return try rollback(journal: journal)
    }

    private func rollback(journal: FileTransactionJournal) throws -> [String] {
        guard journal.state != "rolled-back", journal.state != "failed-rolled-back", journal.state != "recovered" else { return [] }
        let projectRoot = URL(fileURLWithPath: journal.projectPath, isDirectory: true).resolvingSymlinksInPath()
        let operationRoot = operationsRoot.appendingPathComponent(journal.operationID.uuidString, isDirectory: true)
        var restored: [String] = []
        var updated = journal
        // rename 可能先于 journal 落盘；把已开始的步骤统一交给同一恢复路径判断。
        for index in updated.steps.indices where ["staged", "old-moved"].contains(updated.steps[index].state) {
            updated.steps[index].state = "restoring"
        }

        // 先检查整次撤销，避免后面的冲突使前面的文件已经被恢复。
        for step in updated.steps where step.state == "applied" || step.state == "restoring" {
            let targetRoot = try destinationRoot(scope: step.scope, relativePath: step.relativePath, projectRoot: projectRoot)
            let destination = targetRoot.appendingPathComponent(step.relativePath)
            try ensureInsideProject(destination, root: targetRoot)
            try ensureNoSymlinkInParents(destination, root: targetRoot)
            try ensureTargetIsNotSymlink(destination)
            let current = try currentContentHash(destination)
            let expectedAfter: String? = step.action == "remove" ? nil : step.afterHash
            guard current == expectedAfter || (step.state == "restoring" && (current == step.beforeHash || current == nil)) else {
                throw FileTransactionError.rollbackConflict(step.relativePath)
            }
            try validateRollbackTemporaries(step, destination: destination)
            if let beforeHash = step.beforeHash {
                let backup = operationRoot.appendingPathComponent("backup/\(step.relativePath)")
                guard try currentContentHash(backup) == beforeHash else {
                    throw FileTransactionError.rollbackConflict(step.relativePath)
                }
            }
        }
        updated.state = "rolling-back"
        try writeJournal(updated)

        for step in updated.steps.reversed() where step.state == "applied" || step.state == "restoring" {
            let targetRoot = try destinationRoot(scope: step.scope, relativePath: step.relativePath, projectRoot: projectRoot)
            let destination = targetRoot.appendingPathComponent(step.relativePath)
            try ensureInsideProject(destination, root: targetRoot)
            try ensureNoSymlinkInParents(destination, root: targetRoot)
            try ensureTargetIsNotSymlink(destination)
            let current = try currentContentHash(destination)
            if step.state == "restoring", current == step.beforeHash {
                try cleanupRollbackTemporaries(step, destination: destination)
                if let index = updated.steps.firstIndex(where: { $0.relativePath == step.relativePath }) {
                    updated.steps[index].state = "rolled-back"
                }
                try writeJournal(updated)
                restored.append(step.relativePath)
                continue
            }
            let expectedAfter: String? = step.action == "remove" ? nil : step.afterHash
            guard current == expectedAfter || (step.state == "restoring" && current == nil) else {
                throw FileTransactionError.rollbackConflict(step.relativePath)
            }
            if let index = updated.steps.firstIndex(where: { $0.relativePath == step.relativePath }) {
                updated.steps[index].state = "restoring"
            }
            try writeJournal(updated)
            if let beforeHash = step.beforeHash {
                let backup = operationRoot.appendingPathComponent("backup/\(step.relativePath)")
                guard try currentContentHash(backup) == beforeHash else {
                    throw FileTransactionError.rollbackConflict(step.relativePath)
                }
                try cleanupRollbackTemporaries(step, destination: destination)
                let restore = siblingTemporaryURL(for: destination, suffix: "restore")
                let discarded = siblingTemporaryURL(for: destination, suffix: "discarded")
                if let index = updated.steps.firstIndex(where: { $0.relativePath == step.relativePath }) {
                    updated.steps[index].restorePath = restore.path
                    updated.steps[index].discardedPath = discarded.path
                }
                try writeJournal(updated)
                try removeIfPresent(restore)
                try fileManager.copyItem(at: backup, to: restore)
                guard try currentContentHash(restore) == beforeHash else {
                    try? fileManager.removeItem(at: restore)
                    throw FileTransactionError.rollbackConflict(step.relativePath)
                }
                try removeIfPresent(discarded)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.moveItem(at: destination, to: discarded)
                }
                try fileManager.moveItem(at: restore, to: destination)
                guard try currentContentHash(destination) == beforeHash else {
                    throw FileTransactionError.rollbackConflict(step.relativePath)
                }
                try removeIfPresent(discarded)
                if let displacedPath = step.displacedPath {
                    let displaced = URL(fileURLWithPath: displacedPath)
                    try ensureSameParent(displaced, as: destination)
                    try removeIfPresent(displaced)
                }
            } else if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try cleanupRollbackTemporaries(step, destination: destination)
            restored.append(step.relativePath)
            if let index = updated.steps.firstIndex(where: { $0.relativePath == step.relativePath }) {
                updated.steps[index].state = "rolled-back"
            }
            try writeJournal(updated)
        }

        updated.state = "rolled-back"
        try writeJournal(updated)
        return restored
    }

    public func loadJournal(_ operationID: UUID) throws -> FileTransactionJournal {
        let url = journalURL(operationID)
        guard fileManager.fileExists(atPath: url.path) else {
            throw FileTransactionError.operationNotFound(operationID.uuidString)
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(FileTransactionJournal.self, from: data)
        } catch {
            throw FileTransactionError.journalCorrupt(url.path)
        }
    }

    private func writeJournal(_ journal: FileTransactionJournal) throws {
        let url = journalURL(journal.operationID)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(journal).write(to: url, options: .atomic)
    }

    private func journalURL(_ id: UUID) -> URL {
        operationsRoot.appendingPathComponent(id.uuidString, isDirectory: true).appendingPathComponent("journal.json")
    }

    private func validate(plan: DeploymentPlan, stagingRoot: URL, projectRoot: URL) throws {
        if plan.metadata?["planType"] == "skill-deployment",
           plan.metadata?["projectStateStorage"] != "application-v1" {
            throw DeploymentError.invalidPlan
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: projectRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FileTransactionError.unsafeDestination(projectRoot.path)
        }
        guard !plan.changes.isEmpty else {
            throw FileTransactionError.invalidStaging(stagingRoot.path)
        }
        for change in plan.changes {
            let targetRoot = try destinationRoot(scope: change.scope, relativePath: change.relativePath, projectRoot: projectRoot)
            let destination = targetRoot.appendingPathComponent(change.relativePath)
            try ensureInsideProject(destination, root: targetRoot)
            try ensureNoSymlinkInParents(destination, root: targetRoot)
            try ensureTargetIsNotSymlink(destination)
            guard try currentContentHash(destination) == change.beforeHash else {
                throw FileTransactionError.staleFile(change.relativePath)
            }
            if change.action == "remove" {
                guard change.beforeHash != nil, change.afterHash == nil else {
                    throw FileTransactionError.invalidStaging(change.relativePath)
                }
                continue
            }
            guard ["add", "update"].contains(change.action), change.afterHash != nil else {
                throw FileTransactionError.invalidStaging(change.relativePath)
            }
            let staged = stagingRoot.appendingPathComponent(change.relativePath)
            guard fileManager.fileExists(atPath: staged.path),
                  try currentContentHash(staged) == change.afterHash else {
                throw FileTransactionError.invalidStaging(staged.path)
            }
        }
        for observation in plan.observations ?? [] {
            let targetRoot = try destinationRoot(scope: observation.scope, relativePath: observation.relativePath, projectRoot: projectRoot)
            let destination = targetRoot.appendingPathComponent(observation.relativePath)
            try ensureInsideProject(destination, root: targetRoot)
            try ensureNoSymlinkInParents(destination, root: targetRoot)
            try ensureTargetIsNotSymlink(destination)
            guard try currentContentHash(destination) == observation.contentHash else {
                throw FileTransactionError.staleFile(observation.relativePath)
            }
        }
    }

    private func destinationRoot(scope: String?, relativePath: String, projectRoot: URL) throws -> URL {
        guard let scope else { return projectRoot }
        guard scope == "project-state",
              [ProjectLockStore.manifestFileName, ProjectLockStore.lockFileName].contains(relativePath) else {
            throw FileTransactionError.unsafeDestination(relativePath)
        }
        let stateRoot = operationsRoot.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let directory = ProjectLockStore(projectRoot: projectRoot, stateRoot: stateRoot).directoryURL
        try ensureNoSymlinkInParents(directory.appendingPathComponent(relativePath), root: stateRoot)
        return directory
    }

    private func ensureInsideProject(_ url: URL, root: URL) throws {
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard url.standardizedFileURL.path.hasPrefix(rootPrefix) else {
            throw FileTransactionError.unsafeDestination(url.path)
        }
    }

    private func ensureNoSymlinkInParents(_ target: URL, root: URL) throws {
        var cursor = target.deletingLastPathComponent()
        // 跨卷配置计划的共同根可能为 /，不能拼出 // 后跳过全部父目录检查。
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        while cursor.path != root.path && cursor.path.hasPrefix(rootPrefix) {
            if (try? fileManager.destinationOfSymbolicLink(atPath: cursor.path)) != nil {
                throw FileTransactionError.unsafeDestination(cursor.path)
            }
            if fileManager.fileExists(atPath: cursor.path) {
                let values = try cursor.resourceValues(forKeys: [.isSymbolicLinkKey])
                if values.isSymbolicLink == true {
                    throw FileTransactionError.unsafeDestination(cursor.path)
                }
            }
            cursor.deleteLastPathComponent()
        }
    }

    private func ensureTargetIsNotSymlink(_ target: URL) throws {
        if (try? fileManager.destinationOfSymbolicLink(atPath: target.path)) != nil {
            guard try ManagedSkillLink.hash(target, versionsRoot: versionsRoot, libraryRoot: libraryRoot, sourcesRoot: sourcesRoot) != nil else {
                throw FileTransactionError.unsafeDestination(target.path)
            }
        }
    }

    private func siblingTemporaryURL(for destination: URL, suffix: String) -> URL {
        destination.deletingLastPathComponent().appendingPathComponent(
            ".skillset-\(UUID().uuidString.lowercased())-\(suffix)-\(destination.lastPathComponent)"
        )
    }

    private func ensureSameParent(_ candidate: URL, as destination: URL) throws {
        guard candidate.deletingLastPathComponent().standardizedFileURL.path
            == destination.deletingLastPathComponent().standardizedFileURL.path else {
            throw FileTransactionError.unsafeDestination(candidate.path)
        }
    }

    private func validateRollbackTemporaries(_ step: FileTransactionStep, destination: URL) throws {
        for (path, expected) in [
            (step.restorePath, step.beforeHash),
            (step.discardedPath, step.action == "remove" ? nil : step.afterHash),
            (step.temporaryPath, step.afterHash),
            (step.displacedPath, step.beforeHash)
        ] {
            guard let path else { continue }
            let candidate = URL(fileURLWithPath: path)
            try ensureSameParent(candidate, as: destination)
            try ensureTargetIsNotSymlink(candidate)
            if let hash = try currentContentHash(candidate), hash != expected {
                throw FileTransactionError.rollbackConflict(step.relativePath)
            }
        }
    }

    private func cleanupRollbackTemporaries(_ step: FileTransactionStep, destination: URL) throws {
        try validateRollbackTemporaries(step, destination: destination)
        for path in [step.restorePath, step.discardedPath, step.temporaryPath, step.displacedPath].compactMap({ $0 }) {
            try removeIfPresent(URL(fileURLWithPath: path))
        }
    }

    private func removeIfPresent(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func currentContentHash(_ url: URL) throws -> String? {
        if let hash = try ManagedSkillLink.hash(url, versionsRoot: versionsRoot, libraryRoot: libraryRoot, sourcesRoot: sourcesRoot) { return hash }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }
        if (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw FileTransactionError.unsafeDestination(url.path)
        }
        if !isDirectory.boolValue {
            return try SkillAssetCopier.sha256(fileAt: url)
        }
        let prefix = url.path + "/"
        let files = try fileManager.subpathsOfDirectory(atPath: url.path)
            .sorted()
            .compactMap { relative -> (String, UInt16, String)? in
                let file = url.appendingPathComponent(relative)
                if (try? fileManager.destinationOfSymbolicLink(atPath: file.path)) != nil {
                    throw FileTransactionError.unsafeDestination(file.path)
                }
                var childIsDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: file.path, isDirectory: &childIsDirectory) else {
                    return nil
                }
                guard !childIsDirectory.boolValue else { return nil }
                let attributes = try fileManager.attributesOfItem(atPath: file.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular else {
                    throw FileTransactionError.unsafeDestination(file.path)
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
