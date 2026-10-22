import Foundation

public struct SkillPackageFile: Identifiable, Equatable, Sendable {
    public let path: String
    public let bytes: Int
    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
    public var directory: String { (path as NSString).deletingLastPathComponent }
}

public enum SkillFilePreview: Equatable, Sendable {
    case text(String)
    case unsupported
    case tooLarge
}

public enum SkillPackageError: Error, SkillSetCodedError {
    case fileLimitExceeded
    public var code: String { "SKILL_FILE_LIMIT_EXCEEDED" }
}

extension SkillLibraryStore {
    public static let previewByteLimit = 2 * 1_024 * 1_024

    /// 列表仅取文件信息，避免切换技能时把图片、脚本和大文件全部读入内存。
    public func attachedFiles(for entry: SkillEntry, repositoryRoot: URL?) throws -> [SkillPackageFile] {
        let source = try sourceURL(for: entry, repositoryRoot: repositoryRoot).resolvingSymlinksInPath().standardizedFileURL
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: source, includingPropertiesForKeys: Array(keys), options: [],
            errorHandler: { _, error in enumerationError = error; return false }
        ) else { throw CocoaError(.fileReadNoSuchFile) }
        var files: [SkillPackageFile] = []
        var visited = 0
        while let item = enumerator.nextObject() as? URL {
            visited += 1
            guard visited <= 12_000 else { throw SkillPackageError.fileLimitExceeded }
            // macOS 的枚举结果可能保留 /private/var 别名，先统一路径再计算相对位置。
            let file = item.standardizedFileURL
            guard file.path.hasPrefix(source.path + "/") else { throw SkillLibraryError.unsafePath }
            let path = String(file.path.dropFirst(source.path.count + 1))
            if isExcluded(path, entry: entry) {
                enumerator.skipDescendants()
                continue
            }
            try checkPath(file, inside: source)
            let values = try file.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else { throw SkillLibraryError.unsafePath }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { throw SkillLibraryError.unsafePath }
            if path != "SKILL.md" {
                files.append(SkillPackageFile(path: path, bytes: values.fileSize ?? 0))
            }
        }
        if let enumerationError { throw enumerationError }
        return files.sorted { $0.path < $1.path }
    }

    /// Finder 定位与预览共用路径校验；每次操作重新检查，拒绝列表载入后的软链置换。
    public func attachedFileURL(_ path: String, for entry: SkillEntry, repositoryRoot: URL?) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !path.contains("\0"), !isExcluded(path, entry: entry) else {
            throw SkillLibraryError.unsafePath
        }
        let source = try sourceURL(for: entry, repositoryRoot: repositoryRoot).resolvingSymlinksInPath().standardizedFileURL
        let file = source.appendingPathComponent(path)
        try checkPath(file, inside: source)
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw SkillLibraryError.unsafePath }
        return file
    }

    public func previewAttachedFile(_ path: String, for entry: SkillEntry, repositoryRoot: URL?) throws -> SkillFilePreview {
        let file = try attachedFileURL(path, for: entry, repositoryRoot: repositoryRoot)
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Self.previewByteLimit else { return .tooLarge }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        // 实际读取也设上限，避免文件在大小检查后增长导致无界读取。
        let data = try handle.read(upToCount: Self.previewByteLimit + 1) ?? Data()
        guard data.count <= Self.previewByteLimit else { return .tooLarge }
        guard !data.contains(0), let text = String(data: data, encoding: .utf8),
              !text.unicodeScalars.contains(where: { $0.value < 32 && ![9, 10, 13].contains($0.value) }) else {
            return .unsupported
        }
        return .text(text)
    }

    private func isExcluded(_ path: String, entry: SkillEntry) -> Bool {
        entry.excludedPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}
