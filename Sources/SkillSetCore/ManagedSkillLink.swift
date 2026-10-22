import Foundation

public enum SkillInstallMethod: String, Codable, CaseIterable, Sendable {
    case symlink
    case copy
}

/// 链接指纹同时绑定目标路径和内容，换到同内容的外部目录也属于漂移。
enum ManagedSkillLink {
    static func hash(_ url: URL, versionsRoot: URL?) throws -> String? {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else { return nil }
        guard let versionsRoot else { throw FileTransactionError.unsafeDestination(url.path) }
        let root = versionsRoot.standardizedFileURL
        let destination = URL(fileURLWithPath: target, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
        guard destination.deletingLastPathComponent().path == root.path,
              destination.path == destination.resolvingSymlinksInPath().path,
              root.path == root.resolvingSymlinksInPath().path,
              destination.lastPathComponent.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
            throw FileTransactionError.unsafeDestination(url.path)
        }
        let content = try SkillAssetCopier.analyze(from: destination).contentHash
        guard content == destination.lastPathComponent else { throw FileTransactionError.staleFile(url.path) }
        return SkillAssetCopier.sha256(Data("symlink|\(destination.path)|\(content)".utf8))
    }

    static func prepare(source: URL, contentHash: String, root: URL) throws -> URL {
        let manager = FileManager.default
        let root = root.standardizedFileURL
        guard root.resolvingSymlinksInPath().path == root.path else { throw FileTransactionError.unsafeDestination(root.path) }
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(contentHash, isDirectory: true)
        if manager.fileExists(atPath: destination.path) {
            guard destination.resolvingSymlinksInPath().path == destination.path,
                  try SkillAssetCopier.analyze(from: destination).contentHash == contentHash else {
                throw FileTransactionError.staleFile(destination.path)
            }
            return destination
        }
        let temporary = root.appendingPathComponent(".\(UUID())")
        defer { try? manager.removeItem(at: temporary) }
        let copied = try SkillAssetCopier.copy(from: source, to: temporary)
        guard copied.contentHash == contentHash else { throw SourceSkillImportError.changed }
        try manager.moveItem(at: temporary, to: destination)
        return destination
    }
}
