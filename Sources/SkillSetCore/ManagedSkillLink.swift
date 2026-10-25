import Foundation

public enum SkillInstallMethod: String, Codable, CaseIterable, Sendable {
    case symlink
    case copy
}

/// 链接指纹同时绑定目标路径和内容，换到同内容的外部目录也属于漂移。
enum ManagedSkillLink {
    static func hash(_ url: URL, versionsRoot: URL?, libraryRoot: URL? = nil, sourcesRoot: URL? = nil) throws -> String? {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else { return nil }
        let destination = URL(fileURLWithPath: target, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
        let library = libraryRoot?.standardizedFileURL
        let sources = sourcesRoot?.standardizedFileURL
        let versions = versionsRoot?.standardizedFileURL
        let pointsAtLibrary = library.map { destination.deletingLastPathComponent().path == $0.path } ?? false
        let pointsAtSource = sources.map { destination.path.hasPrefix($0.path + "/") } ?? false
        let legacyVersion = versions.map { destination.deletingLastPathComponent().path == $0.path } ?? false
            && destination.lastPathComponent.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
        guard pointsAtLibrary || pointsAtSource || legacyVersion else { return nil }
        let contentRoot = destination.resolvingSymlinksInPath().standardizedFileURL
        let content = try SkillAssetCopier.analyze(from: contentRoot).contentHash
        if legacyVersion, content != destination.lastPathComponent { throw FileTransactionError.staleFile(url.path) }
        return expectedHash(destination: destination, contentHash: content)
    }

    static func expectedHash(destination: URL, contentHash: String) -> String {
        SkillAssetCopier.sha256(Data("symlink|\(destination.standardizedFileURL.path)|\(contentHash)".utf8))
    }

    static func prepare(source: URL, contentHash: String, root: URL) throws -> URL {
        try prepare(contentHash: contentHash, root: root) { temporary in
            try SkillAssetCopier.copy(from: source, to: temporary)
        }
    }

    /// 版本目录还不存在时直接写入已读入的字节，避免计划阶段把源目录再复制一遍。
    static func prepare(snapshot: SkillAssetSnapshot, contentHash: String, root: URL) throws -> URL {
        try prepare(contentHash: contentHash, root: root) { temporary in
            try SkillAssetCopier.write(snapshot, to: temporary)
        }
    }

    private static func prepare(
        contentHash: String,
        root: URL,
        write: (URL) throws -> SkillAssetCopyResult
    ) throws -> URL {
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
        let copied = try write(temporary)
        guard copied.contentHash == contentHash else { throw SourceSkillImportError.changed }
        try manager.moveItem(at: temporary, to: destination)
        return destination
    }
}
