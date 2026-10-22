import Foundation

public enum SkillLibraryError: Error, SkillSetCodedError, Equatable, Sendable {
    case invalidDocument, invalidSlug, duplicate, stale, corrupt, unsafePath

    public var code: String {
        switch self {
        case .invalidDocument: "LIBRARY_DOCUMENT_INVALID"
        case .invalidSlug: "LIBRARY_SLUG_INVALID"
        case .duplicate: "LIBRARY_DUPLICATE"
        case .stale: "LIBRARY_STALE"
        case .corrupt: "LIBRARY_CORRUPT"
        case .unsafePath: "PATH_OUTSIDE_ROOT"
        }
    }
}

public struct SkillEditorDraft: Identifiable, Sendable {
    public let id: UUID
    public var slug: String
    public var document: String
    public let original: SkillEntry?

    public init(slug: String = "", document: String = "---\nname: my-skill\ndescription: 描述技能的用途与使用条件\n---\n\n# My Skill\n\n", original: SkillEntry? = nil) {
        id = UUID()
        self.slug = slug
        self.document = document
        self.original = original
    }
}

public struct LibrarySkillRecord: Codable, Sendable {
    public let entry: SkillEntry
    public let originID: String?
    public let sourceOrigin: SourceSkillOrigin?
}

struct LibraryIndex: Codable {
    var schemaVersion = 1
    var records: [LibrarySkillRecord] = []
    var hiddenIDs: [String] = []
}

/// 每次保存创建独立版本目录，最后原子替换索引；旧版本保留，写入失败不破坏当前版本。
public struct SkillLibraryStore {
    public static let sourceID = "personal"
    public let rootURL: URL
    private let fileManager = FileManager.default

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public func catalog(merging base: CatalogDocument) throws -> CatalogDocument {
        let index = try load()
        return CatalogDocument(
            schemaVersion: base.schemaVersion, hashAlgorithm: base.hashAlgorithm,
            entries: (base.entries.filter { !index.hiddenIDs.contains($0.id) } + index.records.map(\.entry).filter { !index.hiddenIDs.contains($0.id) })
                .sorted { $0.id < $1.id }
        )
    }

    public func hiddenCount() throws -> Int { try load().hiddenIDs.count }

    public func sourceOrigins() throws -> [String: SourceSkillOrigin] {
        Dictionary(uniqueKeysWithValues: try load().records.compactMap { record in
            record.sourceOrigin.map { (record.entry.id, $0) }
        })
    }

    public func sourceURLs() throws -> [String: URL] {
        try Dictionary(uniqueKeysWithValues: load().records.map { ($0.entry.id, try packageURL($0.entry.path)) })
    }

    public func document(for entry: SkillEntry, repositoryRoot: URL?) throws -> String {
        let source = try sourceURL(for: entry, repositoryRoot: repositoryRoot)
        let file = source.appendingPathComponent("SKILL.md")
        try checkPath(file, inside: source)
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 2 * 1_024 * 1_024 else { throw SkillLibraryError.invalidDocument }
        return try String(contentsOf: file, encoding: .utf8)
    }

    public func save(_ draft: SkillEditorDraft, repositoryRoot: URL?) throws -> SkillEntry {
        guard draft.slug.range(of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) != nil,
              draft.slug.count <= 80 else { throw SkillLibraryError.invalidSlug }
        let metadata = try Self.metadata(draft.document)
        var index = try load()
        let id = "\(Self.sourceID)/\(draft.slug)"
        let editing = draft.original?.sourceId == Self.sourceID
        if let existing = index.records.first(where: { $0.entry.id == id }),
           !editing || existing.entry.id != draft.original?.id {
            throw SkillLibraryError.duplicate
        }
        if editing {
            guard let original = draft.original, original.id == id,
                  index.records.contains(where: { $0.entry.id == original.id && $0.entry.contentHash == original.contentHash }) else {
                throw SkillLibraryError.stale
            }
        }
        var source: URL?
        if let original = draft.original {
            guard !original.isBlocked else { throw DeploymentError.skillBlocked(original.id) }
            let url = try sourceURL(for: original, repositoryRoot: repositoryRoot)
            guard try SkillAssetCopier.analyze(from: url).contentHash == original.contentHash else {
                throw SkillLibraryError.stale
            }
            source = url
        }
        try prepareRoot()
        let relative = "packages/\(UUID().uuidString)"
        let destination = try packageURL(relative)
        var committed = false
        defer { if !committed { try? fileManager.removeItem(at: destination) } }
        if let source {
            _ = try SkillAssetCopier.copy(from: source, to: destination)
        } else {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        }
        try Data(draft.document.utf8).write(to: destination.appendingPathComponent("SKILL.md"), options: .atomic)
        let analysis = try SkillAssetCopier.analyze(from: destination)
        let entry = SkillEntry(
            id: id, slug: draft.slug, declaredName: metadata.name, description: metadata.description,
            declaredVersion: metadata.version, metadataReview: "not-schema-validated", sourceId: Self.sourceID,
            path: relative, contentHash: analysis.contentHash, fileCount: analysis.fileManifest.count,
            bytes: analysis.bytes, integrity: "snapshotted", issues: [],
            licenseReview: draft.original?.licenseReview ?? "required", excludedPaths: []
        )
        let origin = editing ? index.records.first(where: { $0.entry.id == id })?.originID : draft.original?.id
        let sourceOrigin = draft.original.flatMap { original in
            index.records.first { $0.entry.id == original.id }?.sourceOrigin
        }
        index.records.removeAll { $0.entry.id == id }
        index.records.append(LibrarySkillRecord(entry: entry, originID: origin, sourceOrigin: sourceOrigin))
        try write(index)
        committed = true
        return entry
    }

    /// 导入保存独立副本，核对复制后的内容再发布索引；任何失败都清理新包。
    func importSource(_ draft: SourceSkillImportDraft, source: URL, licenses: [String: Data]) throws -> SkillEntry {
        guard draft.slug.range(of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) != nil,
              draft.slug.count <= 80 else { throw SkillLibraryError.invalidSlug }
        var index = try load()
        let id = "\(Self.sourceID)/\(draft.slug)"
        guard !index.records.contains(where: { $0.entry.id == id }) else { throw SkillLibraryError.duplicate }
        try prepareRoot()
        let relative = "packages/\(UUID())"
        let destination = try packageURL(relative)
        var committed = false
        defer { if !committed { try? fileManager.removeItem(at: destination) } }
        let copied = try SkillAssetCopier.copy(from: source, to: destination)
        guard copied.contentHash == draft.origin.contentHash else { throw SourceSkillImportError.changed }
        let document = try String(contentsOf: destination.appendingPathComponent("SKILL.md"), encoding: .utf8)
        let metadata = try Self.metadata(document)
        // 根目录技能也不能把仓库的 Git 数据带到项目中。
        let git = destination.appendingPathComponent(".git")
        if fileManager.fileExists(atPath: git.path) { try fileManager.removeItem(at: git) }
        if !licenses.isEmpty {
            var name = "_source_licenses"
            while fileManager.fileExists(atPath: destination.appendingPathComponent(name).path) { name += "_" }
            let directory = destination.appendingPathComponent(name)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, data) in licenses { try data.write(to: directory.appendingPathComponent(name), options: .atomic) }
        }
        let analysis = try SkillAssetCopier.analyze(from: destination)
        let entry = SkillEntry(
            id: id, slug: draft.slug, declaredName: metadata.name, description: metadata.description,
            declaredVersion: metadata.version, metadataReview: "not-schema-validated", sourceId: Self.sourceID,
            path: relative, contentHash: analysis.contentHash, fileCount: analysis.fileManifest.count,
            bytes: analysis.bytes, integrity: "snapshotted", issues: [], licenseReview: "required", excludedPaths: []
        )
        index.records.append(LibrarySkillRecord(entry: entry, originID: draft.origin.url + "#" + draft.origin.path, sourceOrigin: draft.origin))
        try write(index)
        committed = true
        return entry
    }

    public func remove(_ entry: SkillEntry) throws {
        var index = try load()
        if entry.sourceId == Self.sourceID {
            guard index.records.contains(where: { $0.entry.id == entry.id && $0.entry.contentHash == entry.contentHash }),
                  try SkillAssetCopier.analyze(from: packageURL(entry.path)).contentHash == entry.contentHash else {
                throw SkillLibraryError.stale
            }
            index.records.removeAll { $0.entry.id == entry.id }
        } else if !index.hiddenIDs.contains(entry.id) {
            index.hiddenIDs.append(entry.id)
        }
        try prepareRoot()
        try write(index)
    }

    public func restoreHidden() throws {
        var index = try load()
        index.hiddenIDs = []
        try prepareRoot()
        try write(index)
    }

    func sourceURL(for entry: SkillEntry, repositoryRoot: URL?) throws -> URL {
        if entry.sourceId == Self.sourceID || entry.sourceId.hasPrefix("source-") { return try packageURL(entry.path) }
        guard let repositoryRoot else { throw SkillSetServiceError.repositoryNotFound }
        let source = repositoryRoot.appendingPathComponent(entry.path).standardizedFileURL
        try checkPath(source, inside: repositoryRoot)
        return source
    }

    func packageURL(_ path: String) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "packages", UUID(uuidString: String(parts[1])) != nil else {
            throw SkillLibraryError.unsafePath
        }
        let url = rootURL.appendingPathComponent(path)
        try checkPath(url, inside: rootURL)
        return url
    }

    func checkPath(_ url: URL, inside root: URL) throws {
        let root = root.standardizedFileURL
        guard root.resolvingSymlinksInPath().path == root.path,
              url.standardizedFileURL.path.hasPrefix(root.path + "/"),
              url.resolvingSymlinksInPath().path == url.standardizedFileURL.path else {
            throw SkillLibraryError.unsafePath
        }
    }

    func prepareRoot() throws {
        try checkPath(rootURL.appendingPathComponent("packages"), inside: rootURL)
        try fileManager.createDirectory(at: rootURL.appendingPathComponent("packages"), withIntermediateDirectories: true)
    }

    func load() throws -> LibraryIndex {
        let url = rootURL.appendingPathComponent("index.json")
        try checkPath(url, inside: rootURL)
        guard fileManager.fileExists(atPath: url.path) else { return LibraryIndex() }
        let index: LibraryIndex
        do { index = try JSONDecoder().decode(LibraryIndex.self, from: Data(contentsOf: url)) }
        catch { throw SkillLibraryError.corrupt }
        guard index.schemaVersion == 1, Set(index.records.map { $0.entry.id }).count == index.records.count else {
            throw SkillLibraryError.corrupt
        }
        for record in index.records {
            let entry = record.entry
            let personal = entry.sourceId == Self.sourceID && entry.id == "personal/\(entry.slug)"
            let source = entry.sourceId.range(of: #"^source-[0-9a-f]{64}$"#, options: .regularExpression) != nil
                && entry.id.hasPrefix(entry.sourceId + "/") && entry.id.hasSuffix("/" + entry.slug)
            guard personal || source,
                  !entry.slug.isEmpty, !entry.slug.contains("/"), entry.slug != ".", entry.slug != ".." else {
                throw SkillLibraryError.corrupt
            }
            _ = try packageURL(entry.path)
        }
        return index
    }

    func write(_ index: LibraryIndex) throws {
        let url = rootURL.appendingPathComponent("index.json")
        try checkPath(url, inside: rootURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(index).write(to: url, options: .atomic)
    }

    /// 仅提取展示所需字段；保留完整原文和未知字段，不宣称完成 YAML schema 校验。
    private static func metadata(_ text: String) throws -> (name: String, description: String, version: String?) {
        guard text.utf8.count <= 2 * 1_024 * 1_024 else { throw SkillLibraryError.invalidDocument }
        let lines = text.components(separatedBy: .newlines)
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---"),
              !lines.dropFirst(end + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SkillLibraryError.invalidDocument
        }
        var values: [String: String] = [:]
        for i in 1..<end {
            let line = lines[i]
            guard line.first?.isWhitespace == false, let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon])
            guard ["name", "description", "version"].contains(key) else { continue }
            guard values[key] == nil else { throw SkillLibraryError.invalidDocument }
            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if ["|", ">", "|-", ">-", "|+", ">+"].contains(value) {
                let separator = value.hasPrefix(">") ? " " : "\n"
                value = lines[(i + 1)..<end].prefix { $0.isEmpty || $0.first?.isWhitespace == true }
                    .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: separator)
            } else if value.hasPrefix("\"") {
                guard let decoded = try? JSONDecoder().decode(String.self, from: Data(value.utf8)) else {
                    throw SkillLibraryError.invalidDocument
                }
                value = decoded
            } else if value.hasPrefix("'") && value.hasSuffix("'") {
                value = String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
            }
            values[key] = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let name = values["name"], !name.isEmpty,
              let description = values["description"], !description.isEmpty else { throw SkillLibraryError.invalidDocument }
        return (name, description, values["version"])
    }
}
