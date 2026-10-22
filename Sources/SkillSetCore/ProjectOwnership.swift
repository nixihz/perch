import Foundation

/// 归属证据只保存在本机 journal；项目锁和相同内容本身不授予删除权限。
public struct ProjectOwnershipReceipt: Codable, Hashable, Sendable {
    public let lockHash: String
    public let skillHashes: [String: String]
    public let ruleHashes: [String: String]?

    public init(lockHash: String, skillHashes: [String: String], ruleHashes: [String: String]? = nil) {
        self.lockHash = lockHash
        self.skillHashes = skillHashes
        self.ruleHashes = ruleHashes
    }
}

public struct PlannedObservation: Codable, Hashable, Sendable {
    public let relativePath: String
    public let contentHash: String?

    public init(relativePath: String, contentHash: String?) {
        self.relativePath = relativePath
        self.contentHash = contentHash
    }
}

enum ProjectOwnershipReader {
    static func skills(projectRoot: URL, operationsRoot: URL?, fileManager: FileManager = .default) throws -> [String: String] {
        try receipt(projectRoot: projectRoot, operationsRoot: operationsRoot, fileManager: fileManager)?.skillHashes ?? [:]
    }

    static func receipt(projectRoot: URL, operationsRoot: URL?, fileManager: FileManager = .default) throws -> ProjectOwnershipReceipt? {
        guard let operationsRoot, fileManager.fileExists(atPath: operationsRoot.path) else { return nil }
        let lockURL = projectRoot.appendingPathComponent(ProjectLockStore.lockFileName)
        guard fileManager.fileExists(atPath: lockURL.path) else { return nil }
        let lockHash = try SkillAssetCopier.sha256(fileAt: lockURL)
        let executor = FileTransactionExecutor(operationsRoot: operationsRoot, fileManager: fileManager)
        let directories = try fileManager.contentsOfDirectory(at: operationsRoot, includingPropertiesForKeys: nil)
        var matches: [FileTransactionJournal] = []
        for directory in directories {
            guard let id = UUID(uuidString: directory.lastPathComponent),
                  let journal = try? executor.loadJournal(id),
                  journal.projectPath == projectRoot.path else { continue }
            // 未收尾的事务不能作为新计划的起点，否则可能丢失恢复依据。
            if journal.state == "applying" || journal.state == "failed" || journal.state == "rolling-back" {
                throw FileTransactionError.journalCorrupt(directory.path)
            }
            if journal.state == "applied", journal.ownershipReceipt?.lockHash == lockHash {
                matches.append(journal)
            }
        }
        // 相同锁若对应不同归属，无法仅凭时间证明先后关系，采取保守交集。
        guard let first = matches.first?.ownershipReceipt else { return nil }
        var hashes = first.skillHashes
        var rules = first.ruleHashes ?? [:]
        for match in matches.dropFirst() {
            hashes = hashes.filter { match.ownershipReceipt?.skillHashes[$0.key] == $0.value }
            rules = rules.filter { match.ownershipReceipt?.ruleHashes?[$0.key] == $0.value }
        }
        return ProjectOwnershipReceipt(lockHash: lockHash, skillHashes: hashes, ruleHashes: rules)
    }
}
