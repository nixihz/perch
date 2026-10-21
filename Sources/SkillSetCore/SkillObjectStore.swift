import Foundation

public enum SkillObjectStoreError: Error, LocalizedError, Equatable, Sendable {
    case unsafeRoot(String)
    case invalidDigest(String)
    case objectMissing(String)
    case objectCorrupt(String)
    case unsafePath(String)

    public var code: String {
        switch self {
        case .unsafeRoot: "OBJECT_STORE_UNSAFE"
        case .invalidDigest: "OBJECT_DIGEST_INVALID"
        case .objectMissing: "OFFLINE_OBJECT_MISSING"
        case .objectCorrupt: "OFFLINE_OBJECT_CORRUPT"
        case .unsafePath: "PATH_OUTSIDE_ROOT"
        }
    }

    public var errorDescription: String? {
        switch self {
        case let .unsafeRoot(path):
            return "对象存储根目录不安全：\(path)"
        case let .invalidDigest(digest):
            return "对象 hash 无效：\(digest)"
        case let .objectMissing(digest):
            return "离线对象缺失：\(digest)"
        case let .objectCorrupt(digest):
            return "离线对象内容与 hash 不一致：\(digest)"
        case let .unsafePath(path):
            return "对象恢复路径不安全：\(path)"
        }
    }
}

public struct ObjectMaterializationResult: Hashable, Sendable {
    public let fileManifest: [SkillAssetFile]
    public let contentHash: String
    public let objectsWritten: Int
    public let bytes: Int

    public init(fileManifest: [SkillAssetFile], contentHash: String, objectsWritten: Int, bytes: Int) {
        self.fileManifest = fileManifest
        self.contentHash = contentHash
        self.objectsWritten = objectsWritten
        self.bytes = bytes
    }
}

public struct ObjectStoreVerification: Codable, Hashable, Sendable {
    public let checkedObjects: Int
    public let checkedBytes: Int

    public init(checkedObjects: Int, checkedBytes: Int) {
        self.checkedObjects = checkedObjects
        self.checkedBytes = checkedBytes
    }
}

public struct SkillObjectManifest: Codable, Hashable, Sendable {
    public let contentHash: String
    public let files: [SkillAssetFile]

    public init(contentHash: String, files: [SkillAssetFile]) {
        self.contentHash = contentHash
        self.files = files.sorted { $0.path < $1.path }
    }
}

/// 内容寻址对象只保存文件字节；可执行位和相对路径由项目锁记录。
public struct SkillObjectStore {
    public let repositoryRoot: URL
    public let rootURL: URL
    public let manifestsRootURL: URL

    private let fileManager: FileManager

    public init(repositoryRoot: URL, fileManager: FileManager = .default) {
        self.repositoryRoot = repositoryRoot.resolvingSymlinksInPath().standardizedFileURL
        self.rootURL = self.repositoryRoot.appendingPathComponent("objects/sha256", isDirectory: true)
        self.manifestsRootURL = self.repositoryRoot.appendingPathComponent("objects/manifests", isDirectory: true)
        self.fileManager = fileManager
    }

    public func materializeSkill(source: URL) throws -> ObjectMaterializationResult {
        try ensureSafeRoot()
        let files = try SkillAssetCopier.collectFiles(from: source, fileManager: fileManager)
        var manifest: [SkillAssetFile] = []
        var written = 0
        var totalBytes = 0
        for (path, data, permissions) in files {
            let digest = SkillAssetCopier.sha256(data)
            written += try writeObject(data, digest: digest)
            totalBytes += data.count
            manifest.append(SkillAssetFile(
                path: path,
                sha256: digest,
                executable: permissions & 0o111 != 0,
                bytes: data.count
            ))
        }
        manifest.sort { $0.path < $1.path }
        let contentHash = SkillAssetCopier.hashManifest(
            manifest.map { ($0.path, $0.executable ? UInt16(0o755) : UInt16(0o644), $0.sha256) }
        )
        written += try writeManifest(SkillObjectManifest(contentHash: contentHash, files: manifest))
        return ObjectMaterializationResult(
            fileManifest: manifest,
            contentHash: contentHash,
            objectsWritten: written,
            bytes: totalBytes
        )
    }

    public func materializeData(_ data: Data) throws -> String {
        try ensureSafeRoot()
        let digest = SkillAssetCopier.sha256(data)
        _ = try writeObject(data, digest: digest)
        return digest
    }

    public func verify(lock: ProjectLockDocument) throws -> ObjectStoreVerification {
        var digests: Set<String> = []
        for skill in lock.skills {
            digests.formUnion(skill.files.map(\.sha256))
        }
        digests.formUnion(lock.instructions.map(\.sha256))
        var bytes = 0
        for digest in digests.sorted() {
            let url = try objectURL(for: digest)
            guard fileManager.fileExists(atPath: url.path) else {
                throw SkillObjectStoreError.objectMissing(digest)
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard SkillAssetCopier.sha256(data) == digest else {
                throw SkillObjectStoreError.objectCorrupt(digest)
            }
            bytes += data.count
        }
        return ObjectStoreVerification(checkedObjects: digests.count, checkedBytes: bytes)
    }

    public func restore(files: [SkillAssetFile], to destination: URL) throws {
        try ensureSafeRoot()
        let destinationRoot = destination.standardizedFileURL
        if fileManager.fileExists(atPath: destinationRoot.path) {
            try fileManager.removeItem(at: destinationRoot)
        }
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        for file in files {
            try validateRelativePath(file.path)
            let target = destinationRoot.appendingPathComponent(file.path)
            let rootPrefix = destinationRoot.path.hasSuffix("/") ? destinationRoot.path : destinationRoot.path + "/"
            guard target.standardizedFileURL.path.hasPrefix(rootPrefix) else {
                throw SkillObjectStoreError.unsafePath(file.path)
            }
            let data = try Data(contentsOf: try objectURL(for: file.sha256), options: .mappedIfSafe)
            guard SkillAssetCopier.sha256(data) == file.sha256 else {
                throw SkillObjectStoreError.objectCorrupt(file.sha256)
            }
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: file.executable ? 0o755 : 0o644)],
                ofItemAtPath: target.path
            )
        }
    }

    public func restore(contentHash: String, to destination: URL) throws {
        let manifest = try loadManifest(contentHash: contentHash)
        guard manifest.contentHash == contentHash,
              contentHash == SkillAssetCopier.hashManifest(
                manifest.files.map { ($0.path, $0.executable ? UInt16(0o755) : UInt16(0o644), $0.sha256) }
              ) else {
            throw SkillObjectStoreError.objectCorrupt(contentHash)
        }
        try restore(files: manifest.files, to: destination)
    }

    public func loadManifest(contentHash: String) throws -> SkillObjectManifest {
        let url = try manifestURL(for: contentHash)
        guard fileManager.fileExists(atPath: url.path) else {
            throw SkillObjectStoreError.objectMissing(contentHash)
        }
        do {
            let manifest = try JSONDecoder().decode(SkillObjectManifest.self, from: Data(contentsOf: url))
            guard manifest.contentHash == contentHash else {
                throw SkillObjectStoreError.objectCorrupt(contentHash)
            }
            return manifest
        } catch let error as SkillObjectStoreError {
            throw error
        } catch {
            throw SkillObjectStoreError.objectCorrupt(contentHash)
        }
    }

    public func objectURL(for digest: String) throws -> URL {
        guard digest.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
            throw SkillObjectStoreError.invalidDigest(digest)
        }
        return rootURL
            .appendingPathComponent(String(digest.prefix(2)), isDirectory: true)
            .appendingPathComponent(String(digest.dropFirst(2)), isDirectory: false)
    }

    public func manifestURL(for contentHash: String) throws -> URL {
        guard contentHash.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
            throw SkillObjectStoreError.invalidDigest(contentHash)
        }
        return manifestsRootURL
            .appendingPathComponent(String(contentHash.prefix(2)), isDirectory: true)
            .appendingPathComponent("\(String(contentHash.dropFirst(2))).json", isDirectory: false)
    }

    private func writeObject(_ data: Data, digest: String) throws -> Int {
        let target = try objectURL(for: digest)
        if fileManager.fileExists(atPath: target.path) {
            let existing = try Data(contentsOf: target, options: .mappedIfSafe)
            guard SkillAssetCopier.sha256(existing) == digest else {
                throw SkillObjectStoreError.objectCorrupt(digest)
            }
            return 0
        }
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .atomic)
        guard SkillAssetCopier.sha256(try Data(contentsOf: temporary)) == digest else {
            try? fileManager.removeItem(at: temporary)
            throw SkillObjectStoreError.objectCorrupt(digest)
        }
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: temporary.path)
        try fileManager.moveItem(at: temporary, to: target)
        return 1
    }

    private func writeManifest(_ manifest: SkillObjectManifest) throws -> Int {
        let target = try manifestURL(for: manifest.contentHash)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard var data = try? encoder.encode(manifest) else {
            throw SkillObjectStoreError.objectCorrupt(manifest.contentHash)
        }
        data.append(0x0A)
        if fileManager.fileExists(atPath: target.path) {
            let existing = try? Data(contentsOf: target)
            if existing == data {
                return 0
            }
            throw SkillObjectStoreError.objectCorrupt(manifest.contentHash)
        }
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .atomic)
        try fileManager.moveItem(at: temporary, to: target)
        return 1
    }

    private func ensureSafeRoot() throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: repositoryRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SkillObjectStoreError.unsafeRoot(repositoryRoot.path)
        }
        for candidate in [
            repositoryRoot.appendingPathComponent("objects", isDirectory: true),
            rootURL,
            manifestsRootURL
        ] {
            if fileManager.fileExists(atPath: candidate.path) {
                let values = try candidate.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard values.isSymbolicLink != true else {
                    throw SkillObjectStoreError.unsafeRoot(candidate.path)
                }
            }
        }
        let canonicalRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        guard canonicalRoot.path == rootURL.standardizedFileURL.path
            || canonicalRoot.path.hasPrefix(repositoryRoot.path + "/") else {
            throw SkillObjectStoreError.unsafeRoot(rootURL.path)
        }
    }

    private func validateRelativePath(_ path: String) throws {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.split(separator: "/").contains(".."),
              !path.contains("\0") else {
            throw SkillObjectStoreError.unsafePath(path)
        }
    }
}
