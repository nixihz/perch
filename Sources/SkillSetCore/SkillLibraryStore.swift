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

struct SkillLibraryMeta: Codable, Sendable {
    var categories: [String: String] = [:]
    var origins: [String: SourceSkillOrigin] = [:]
    /// 旧文件里的隐藏名单只为解码兼容。删除后不再写回，也不再参与目录。
    var hiddenIDs: [String] = []
}

struct LibraryIndex: Codable, Sendable {
    var schemaVersion = 1
    var records: [LibrarySkillRecord] = []
    var hiddenIDs: [String] = []
}

public struct LibrarySkillRecord: Codable, Sendable {
    public let entry: SkillEntry
    public let originID: String?
    public let sourceOrigin: SourceSkillOrigin?
}

/// 一次目录扫描的结果。技能名来自库目录里的子项，不再读取 packages 索引。
public struct LoadedSkillLibrary: Sendable {
    public let origins: [String: SourceSkillOrigin]
    public let packageURLs: [String: URL]
    let records: [LibrarySkillRecord]

    public func catalog(merging base: CatalogDocument) -> CatalogDocument {
        let ids = Set(records.map(\.entry.id))
        let kept = base.entries.filter { !ids.contains($0.id) }
        return CatalogDocument(
            schemaVersion: base.schemaVersion, hashAlgorithm: base.hashAlgorithm,
            entries: (kept + records.map(\.entry)).sorted { $0.id < $1.id }
        )
    }
}

/// 技能文件放在来源目录。自建、本地导入和复制都放在 custom，技能库里只留同名软链。跟随来源的导入则指向来源目录。
public struct SkillLibraryStore {
    public static let sourceID = "custom"
    public static let linkedSourceID = "link"
    public static let copiedSourceID = "copy"
    public let libraryURL: URL
    public let sourcesURL: URL
    public let categoriesURL: URL
    private let fileManager = FileManager.default

    public init(libraryURL: URL, sourcesURL: URL, categoriesURL: URL) {
        self.libraryURL = libraryURL.standardizedFileURL
        self.sourcesURL = sourcesURL.standardizedFileURL
        self.categoriesURL = categoriesURL.standardizedFileURL
    }

    public var customURL: URL { sourcesURL.appendingPathComponent(Self.sourceID, isDirectory: true) }

    public func catalog(merging base: CatalogDocument) throws -> CatalogDocument {
        try loadLibrary().catalog(merging: base)
    }

    public func sourceOrigins() throws -> [String: SourceSkillOrigin] {
        try loadLibrary().origins
    }

    public func sourceURLs() throws -> [String: URL] {
        try loadLibrary().packageURLs
    }

    public func loadLibrary() throws -> LoadedSkillLibrary {
        try migrateLegacyPackagesIfNeeded()
        // 库里的实体目录是以前复制进来的技能。文件改放到 custom，库内只留软链。
        try adoptOwnedDirectories()
        var meta = try loadMeta()
        if !meta.hiddenIDs.isEmpty {
            meta.hiddenIDs = []
            try writeMeta(meta)
        }
        let records = try scan(origins: meta.origins)
        let urls = Dictionary(uniqueKeysWithValues: try records.map { record in
            (record.entry.id, try sourceURL(for: record.entry, repositoryRoot: nil))
        })
        return LoadedSkillLibrary(origins: meta.origins, packageURLs: urls, records: records)
    }

    public func document(for entry: SkillEntry, repositoryRoot: URL?) throws -> String {
        let source = try sourceURL(for: entry, repositoryRoot: repositoryRoot)
        let file = source.appendingPathComponent("SKILL.md")
        let resolved = file.resolvingSymlinksInPath().standardizedFileURL
        try checkPath(resolved, inside: source.resolvingSymlinksInPath().standardizedFileURL)
        let size = try resolved.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 2 * 1_024 * 1_024 else { throw SkillLibraryError.invalidDocument }
        return try String(contentsOf: resolved, encoding: .utf8)
    }

    public func save(_ draft: SkillEditorDraft, repositoryRoot: URL?) throws -> SkillEntry {
        try validateSlug(draft.slug)
        _ = try Self.metadata(draft.document)
        let loaded = try loadLibrary()
        if loaded.records.contains(where: { $0.entry.slug == draft.slug && $0.entry.id != draft.original?.id }) {
            throw SkillLibraryError.duplicate
        }
        if let original = draft.original, original.id == draft.slug,
           original.sourceId == Self.sourceID || original.sourceId == Self.copiedSourceID {
            guard loaded.records.contains(where: { $0.entry.id == original.id && $0.entry.contentHash == original.contentHash }) else {
                throw SkillLibraryError.stale
            }
            let directory = try sourceURL(for: original, repositoryRoot: repositoryRoot)
            guard try SkillAssetCopier.analyze(from: directory).contentHash == original.contentHash else {
                throw SkillLibraryError.stale
            }
            try Data(draft.document.utf8).write(to: directory.appendingPathComponent("SKILL.md"), options: .atomic)
            return try requireSkill(draft.slug)
        }

        try prepareRoots()
        let destination = customURL.appendingPathComponent(draft.slug, isDirectory: true)
        try ensureRealDirectory(customURL)
        guard !fileManager.fileExists(atPath: destination.path) else { throw SkillLibraryError.duplicate }
        var committed = false
        defer { if !committed { try? fileManager.removeItem(at: destination) } }
        if let original = draft.original {
            guard !original.isBlocked else { throw DeploymentError.skillBlocked(original.id) }
            let source = try sourceURL(for: original, repositoryRoot: repositoryRoot)
            _ = try SkillAssetCopier.copy(from: source, to: destination)
        } else {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        }
        try Data(draft.document.utf8).write(to: destination.appendingPathComponent("SKILL.md"), options: .atomic)
        try linkLibrary(name: draft.slug, to: destination)
        committed = true
        var meta = try loadMeta()
        if let original = draft.original, let origin = loaded.origins[original.id] {
            meta.origins[draft.slug] = origin
            try writeMeta(meta)
        }
        return try requireSkill(draft.slug)
    }

    /// 软链指向来源目录。复制不跟随来源，文件和自建技能放在同一处，库里只留软链。重名拒绝，不覆盖。
    func importSource(_ draft: SourceSkillImportDraft, source: URL, licenses: [String: Data]) throws -> SkillEntry {
        try validateSlug(draft.slug)
        let document = try String(contentsOf: source.appendingPathComponent("SKILL.md"), encoding: .utf8)
        _ = try Self.metadata(document)
        let loaded = try loadLibrary()
        guard !loaded.records.contains(where: { $0.entry.slug == draft.slug }) else { throw SkillLibraryError.duplicate }
        if draft.mode == .copy {
            try storeOwnedCopy(slug: draft.slug, from: source, licenses: licenses, origin: draft.origin, category: draft.category)
        } else {
            try prepareRoots()
            let libraryEntry = libraryURL.appendingPathComponent(draft.slug, isDirectory: true)
            guard !fileManager.fileExists(atPath: libraryEntry.path), !isLink(libraryEntry) else {
                throw SkillLibraryError.duplicate
            }
            try fileManager.createSymbolicLink(at: libraryEntry, withDestinationURL: source)
            var meta = try loadMeta()
            meta.origins[draft.slug] = draft.origin
            let category = draft.category.trimmingCharacters(in: .whitespacesAndNewlines)
            if !category.isEmpty { meta.categories[draft.slug] = category }
            do { try writeMeta(meta) }
            catch {
                try? fileManager.removeItem(at: libraryEntry)
                throw error
            }
        }
        return try requireSkill(draft.slug)
    }

    /// 把一份不跟随来源的技能放进 custom，并在技能库建立同名软链。调用方已确认内容指纹。
    func storeOwnedCopy(slug: String, from source: URL, licenses: [String: Data], origin: SourceSkillOrigin, category: String) throws {
        try validateSlug(slug)
        try prepareRoots()
        let destination = customURL.appendingPathComponent(slug, isDirectory: true)
        let libraryEntry = libraryURL.appendingPathComponent(slug, isDirectory: true)
        guard !fileManager.fileExists(atPath: destination.path),
              !fileManager.fileExists(atPath: libraryEntry.path), !isLink(libraryEntry) else {
            throw SkillLibraryError.duplicate
        }
        var created: URL?
        defer { if let created { try? fileManager.removeItem(at: created) } }
        let copied = try SkillAssetCopier.copy(from: source, to: destination)
        created = destination
        guard copied.contentHash == origin.contentHash else { throw SourceSkillImportError.changed }
        let git = destination.appendingPathComponent(".git")
        if fileManager.fileExists(atPath: git.path) { try fileManager.removeItem(at: git) }
        if !licenses.isEmpty {
            var name = "_source_licenses"
            while fileManager.fileExists(atPath: destination.appendingPathComponent(name).path) { name += "_" }
            let directory = destination.appendingPathComponent(name)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            for (file, data) in licenses { try data.write(to: directory.appendingPathComponent(file), options: .atomic) }
        }
        try linkLibrary(name: slug, to: destination)
        var meta = try loadMeta()
        meta.origins[slug] = origin
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { meta.categories[slug] = trimmed }
        do { try writeMeta(meta) }
        catch {
            try? fileManager.removeItem(at: libraryEntry)
            throw error
        }
        created = nil
    }

    /// 软链表示跟随来源，复制表示留下实体。批量写入时逐项处理，元数据一次写回。
    func importSourceBatch(
        _ packages: [SourceSkillBatchPackage],
        mode: SkillInstallMethod,
        category: String
    ) -> [SourceSkillBatchItemResult] {
        guard !packages.isEmpty else { return [] }
        var meta: SkillLibraryMeta
        var existing: Set<String>
        do {
            let loaded = try loadLibrary()
            meta = try loadMeta()
            existing = Set(loaded.records.map(\.entry.slug))
            try prepareRoots()
        } catch {
            // 元数据读坏时不能用空记录覆盖原文件，也不能留下无法追溯的技能。
            return packages.map { package in
                SourceSkillBatchItemResult(
                    path: package.path, slug: package.slug,
                    status: .failed(code: SkillSetService.failureCode(error))
                )
            }
        }
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        var results: [SourceSkillBatchItemResult] = []
        var createdLinks: [URL] = []
        var createdDirectories: [URL] = []
        var pendingOrigins: [String: SourceSkillOrigin] = [:]
        var pendingCategories: [String: String] = [:]

        for package in packages {
            do {
                guard !existing.contains(package.slug) else { throw SkillLibraryError.duplicate }
                let entry = try writeBatchPackage(
                    package, mode: mode, createdLinks: &createdLinks, createdDirectories: &createdDirectories
                )
                existing.insert(package.slug)
                pendingOrigins[package.slug] = package.origin
                if !trimmedCategory.isEmpty { pendingCategories[package.slug] = trimmedCategory }
                results.append(SourceSkillBatchItemResult(
                    path: package.path, slug: package.slug, status: .imported(entry)
                ))
            } catch SkillLibraryError.duplicate {
                results.append(SourceSkillBatchItemResult(
                    path: package.path, slug: package.slug, status: .skipped(code: SkillLibraryError.duplicate.code)
                ))
            } catch {
                results.append(SourceSkillBatchItemResult(
                    path: package.path, slug: package.slug, status: .failed(code: SkillSetService.failureCode(error))
                ))
            }
        }

        guard !pendingOrigins.isEmpty else { return results }
        for (slug, origin) in pendingOrigins { meta.origins[slug] = origin }
        for (slug, value) in pendingCategories { meta.categories[slug] = value }
        do {
            try writeMeta(meta)
        } catch {
            // 来源证据写不回去时不留下无法追溯的条目，整批回退。
            for link in createdLinks { try? fileManager.removeItem(at: link) }
            for directory in createdDirectories { try? fileManager.removeItem(at: directory) }
            return results.map { result in
                guard case .imported = result.status else { return result }
                return SourceSkillBatchItemResult(
                    path: result.path, slug: result.slug,
                    status: .failed(code: SkillSetService.failureCode(error))
                )
            }
        }
        return results
    }

    /// 写入一项来源技能。软链直接指向来源检出目录；复制放进 custom，库里只留同名软链。
    private func writeBatchPackage(
        _ package: SourceSkillBatchPackage,
        mode: SkillInstallMethod,
        createdLinks: inout [URL],
        createdDirectories: inout [URL]
    ) throws -> SkillEntry {
        try validateSlug(package.slug)
        let document = try String(contentsOf: package.source.appendingPathComponent("SKILL.md"), encoding: .utf8)
        _ = try Self.metadata(document)
        let libraryEntry = libraryURL.appendingPathComponent(package.slug, isDirectory: true)
        guard !fileManager.fileExists(atPath: libraryEntry.path), !isLink(libraryEntry) else {
            throw SkillLibraryError.duplicate
        }
        var createdDirectory: URL?
        var createdLink = false
        var committed = false
        defer {
            // 单项失败不能把半成品留在 custom，下次扫描会把它当成独立自建技能。
            if !committed {
                if createdLink { try? fileManager.removeItem(at: libraryEntry) }
                if let createdDirectory { try? fileManager.removeItem(at: createdDirectory) }
            }
        }
        switch mode {
        case .copy:
            let destination = customURL.appendingPathComponent(package.slug, isDirectory: true)
            guard !fileManager.fileExists(atPath: destination.path), !isLink(destination) else {
                throw SkillLibraryError.duplicate
            }
            createdDirectory = destination
            let copied = try SkillAssetCopier.copy(from: package.source, to: destination)
            guard copied.contentHash == package.origin.contentHash else {
                throw SourceSkillImportError.changed
            }
            let git = destination.appendingPathComponent(".git")
            if fileManager.fileExists(atPath: git.path) { try fileManager.removeItem(at: git) }
            if !package.licenses.isEmpty {
                var name = "_source_licenses"
                while fileManager.fileExists(atPath: destination.appendingPathComponent(name).path) { name += "_" }
                let directory = destination.appendingPathComponent(name)
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                for (file, data) in package.licenses {
                    try data.write(to: directory.appendingPathComponent(file), options: .atomic)
                }
            }
            try fileManager.createSymbolicLink(at: libraryEntry, withDestinationURL: destination)
            createdLink = true
            // 技能库扫描到的是复制后的实体，指纹与文件数以落地结果为准。
            let landed = try SkillAssetCopier.analyze(from: destination)
            createdDirectories.append(destination)
            createdLinks.append(libraryEntry)
            committed = true
            return makeLibraryEntry(
                slug: package.slug, analysis: landed, sourceId: Self.sourceID,
                declaredName: package.origin.declaredName, documentURL: destination.appendingPathComponent("SKILL.md")
            )
        case .symlink:
            try fileManager.createSymbolicLink(at: libraryEntry, withDestinationURL: package.source)
            createdLinks.append(libraryEntry)
            committed = true
            return makeLibraryEntry(
                slug: package.slug, analysis: package.analysis, sourceId: Self.linkedSourceID,
                declaredName: package.origin.declaredName, documentURL: package.source.appendingPathComponent("SKILL.md")
            )
        }
    }

    /// 按技能库扫描的同一口径生成条目，避免列表里显示的指纹与重新读取后不一致。
    private func makeLibraryEntry(
        slug: String,
        analysis: SkillAssetCopyResult,
        sourceId: String,
        declaredName: String?,
        documentURL: URL
    ) -> SkillEntry {
        let parsed = (try? String(contentsOf: documentURL, encoding: .utf8)).flatMap { try? Self.metadata($0) }
        return SkillEntry(
            id: slug, slug: slug, declaredName: parsed?.name ?? declaredName ?? slug,
            description: parsed?.description ?? "", declaredVersion: parsed?.version,
            metadataReview: "not-schema-validated", sourceId: sourceId,
            path: "\(sourceId)/\(slug)", contentHash: analysis.contentHash,
            fileCount: analysis.fileManifest.count, bytes: analysis.bytes,
            integrity: "snapshotted", issues: [], excludedPaths: []
        )
    }

    /// 库内已有条目的名称。普通文件按去掉扩展名计入，与扫描口径一致。
    private func libraryEntryNames() -> Set<String> {
        guard fileManager.fileExists(atPath: libraryURL.path) else { return [] }
        let children = (try? fileManager.contentsOfDirectory(atPath: libraryURL.path)) ?? []
        var names: Set<String> = []
        for child in children {
            let item = libraryURL.appendingPathComponent(child)
            if isLink(item) {
                names.insert(child)
                continue
            }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                let name = (child as NSString).deletingPathExtension
                if !name.isEmpty { names.insert(name) }
                continue
            }
            names.insert(child)
        }
        return names
    }

    public func remove(_ entry: SkillEntry) throws {
        guard entry.sourceId == Self.sourceID || entry.sourceId == Self.linkedSourceID || entry.sourceId == Self.copiedSourceID else {
            throw SkillLibraryError.stale
        }
        var meta = try loadMeta()
        let records = try scan(origins: meta.origins)
        guard records.contains(where: { $0.entry.id == entry.id && $0.entry.contentHash == entry.contentHash }) else {
            throw SkillLibraryError.stale
        }
        let directory = try sourceURL(for: entry, repositoryRoot: nil)
        guard try SkillAssetCopier.analyze(from: directory).contentHash == entry.contentHash else {
            throw SkillLibraryError.stale
        }
        let libraryEntry = libraryURL.appendingPathComponent(entry.slug)
        if fileManager.fileExists(atPath: libraryEntry.path) || isLink(libraryEntry) {
            try fileManager.removeItem(at: libraryEntry)
        }
        if entry.sourceId == Self.sourceID, fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        meta.origins[entry.slug] = nil
        meta.categories[entry.slug] = nil
        meta.hiddenIDs = []
        try writeMeta(meta)
    }

    /// 来源重新预览后生成新的 checkout 目录；将库内指向旧 checkout 的软链平滑切换到新目录，使同步模式下的技能保持有效。
    func retargetSourceLinks(from oldCheckout: URL, to newCheckout: URL, commit: String) throws {
        guard fileManager.fileExists(atPath: libraryURL.path), !isLink(libraryURL) else { return }
        let oldPrefix = oldCheckout.standardizedFileURL.path + "/"
        let newBase = newCheckout.standardizedFileURL
        var meta = try loadMeta()
        var changedMeta = false
        let children = try fileManager.contentsOfDirectory(at: libraryURL, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles])
        for child in children {
            let link = libraryURL.appendingPathComponent(child.lastPathComponent)
            guard isLink(link),
                  let rawTarget = try? fileManager.destinationOfSymbolicLink(atPath: link.path) else { continue }
            let resolvedTarget = URL(fileURLWithPath: rawTarget, relativeTo: libraryURL).standardizedFileURL
            let relative: String
            if resolvedTarget.path == oldCheckout.standardizedFileURL.path {
                relative = "."
            } else if resolvedTarget.path.hasPrefix(oldPrefix) {
                relative = String(resolvedTarget.path.dropFirst(oldPrefix.count))
            } else {
                continue
            }
            let updatedTarget = relative == "." ? newBase : newBase.appendingPathComponent(relative, isDirectory: true).standardizedFileURL
            try linkLibrary(name: child.lastPathComponent, to: updatedTarget)
            if var origin = meta.origins[child.lastPathComponent],
               let analysis = try? SkillAssetCopier.analyze(from: updatedTarget) {
                origin = SourceSkillOrigin(
                    url: origin.url, commit: commit, path: origin.path,
                    contentHash: analysis.contentHash, licenseEvidence: origin.licenseEvidence,
                    licenseHashes: origin.licenseHashes, declaredName: origin.declaredName
                )
                meta.origins[child.lastPathComponent] = origin
                changedMeta = true
            }
        }
        if changedMeta {
            try writeMeta(meta)
        }
    }

    func sourceURL(for entry: SkillEntry, repositoryRoot: URL?) throws -> URL {
        switch entry.sourceId {
        case Self.sourceID:
            let url = customURL.appendingPathComponent(entry.slug, isDirectory: true)
            try ensureInside(url, customURL)
            return url
        case Self.copiedSourceID:
            let url = libraryURL.appendingPathComponent(entry.slug, isDirectory: true)
            try ensureInside(url, libraryURL)
            return url
        case Self.linkedSourceID:
            let link = libraryURL.appendingPathComponent(entry.slug)
            let destination = try fileManager.destinationOfSymbolicLink(atPath: link.path)
            let url = URL(fileURLWithPath: destination, relativeTo: libraryURL).standardizedFileURL
            guard url.path != libraryURL.path, !url.path.hasPrefix(libraryURL.path + "/") else {
                throw SkillLibraryError.unsafePath
            }
            return url
        default:
            guard let repositoryRoot else { throw SkillSetServiceError.repositoryNotFound }
            let source = repositoryRoot.appendingPathComponent(entry.path).standardizedFileURL
            try checkPath(source, inside: repositoryRoot)
            return source
        }
    }

    private func requireSkill(_ slug: String) throws -> SkillEntry {
        let records = try scan(origins: try loadMeta().origins)
        guard let entry = records.first(where: { $0.entry.slug == slug })?.entry else { throw SkillLibraryError.stale }
        return entry
    }

    private func scan(origins: [String: SourceSkillOrigin]) throws -> [LibrarySkillRecord] {
        // 自建技能的实体在 custom，即使库存里没有同名软链也要算进库里。
        let customSkills = customSkillDirectories(origins: origins)
        guard fileManager.fileExists(atPath: libraryURL.path) else {
            return try customSkills.map { try record(for: $0.lastPathComponent, at: $0, origins: origins) }
        }
        // 库根本身被换成软链时，扫描会跟到库外。拒绝这种根，子项软链仍然允许。
        guard !isLink(libraryURL) else { throw SkillLibraryError.unsafePath }
        var names: [String: URL] = [:]
        let children = try fileManager.contentsOfDirectory(at: libraryURL, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles])
        for child in children.sorted(by: { $0.path < $1.path }) {
            let item = libraryURL.appendingPathComponent(child.lastPathComponent)
            let linked = isLink(item)
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: item.resolvingSymlinksInPath().path, isDirectory: &isDirectory)
            let name: String
            if linked || isDirectory.boolValue {
                name = item.lastPathComponent
            } else if exists {
                name = (item.lastPathComponent as NSString).deletingPathExtension
                guard !name.isEmpty else { continue }
            } else {
                name = item.lastPathComponent
            }
            if names[name] != nil { throw SkillLibraryError.duplicate }
            names[name] = item
        }
        for skill in customSkills where names[skill.lastPathComponent] == nil {
            names[skill.lastPathComponent] = skill
        }
        return try names.keys.sorted().map { name in
            try record(for: name, at: names[name]!, origins: origins)
        }
    }

    /// custom 目录下的技能实体。缺 SKILL.md 的目录不算技能。
    /// 跟随技能来源复制进来的实体不算自建技能，它们由来源记录跟踪。
    private func customSkillDirectories(origins: [String: SourceSkillOrigin]) -> [URL] {
        guard fileManager.fileExists(atPath: customURL.path), !isLink(customURL) else { return [] }
        let children = (try? fileManager.contentsOfDirectory(
            at: customURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return children.filter { child in
            var isDirectory: ObjCBool = false
            return !isLink(child)
                && fileManager.fileExists(atPath: child.appendingPathComponent("SKILL.md").path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
                && !followsSkillSource(origins[child.lastPathComponent])
        }
    }

    private func record(for name: String, at item: URL, origins: [String: SourceSkillOrigin]) throws -> LibrarySkillRecord {
        let linked = isLink(item)
        let target = try linked
            ? URL(fileURLWithPath: fileManager.destinationOfSymbolicLink(atPath: item.path), relativeTo: libraryURL).standardizedFileURL
            : item
        let insideCustom = target.deletingLastPathComponent().standardizedFileURL.path == customURL.standardizedFileURL.path
        let sourceId: String
        if linked {
            sourceId = insideCustom ? Self.sourceID : Self.linkedSourceID
        } else if insideCustom {
            sourceId = Self.sourceID
        } else {
            sourceId = Self.copiedSourceID
        }
        let content = (existsDirectory(target) ? target : item).resolvingSymlinksInPath()
        let analysis = try? SkillAssetCopier.analyze(from: content)
        let origin = origins[name]
        let skillFile = content.appendingPathComponent("SKILL.md")
        let parsed = (try? String(contentsOf: skillFile, encoding: .utf8)).flatMap { try? Self.metadata($0) }
        let entry = SkillEntry(
            id: name, slug: name, declaredName: parsed?.name ?? origin?.declaredName ?? name,
            description: parsed?.description ?? "",
            declaredVersion: parsed?.version, metadataReview: "not-schema-validated", sourceId: sourceId,
            path: "\(sourceId)/\(name)",
            contentHash: analysis?.contentHash ?? "", fileCount: analysis?.fileManifest.count ?? 0,
            bytes: analysis?.bytes ?? 0, integrity: analysis == nil ? "blocked" : "snapshotted", issues: [],
            excludedPaths: []
        )
        return LibrarySkillRecord(entry: entry, originID: origin.map { $0.url + "#" + $0.path }, sourceOrigin: origin)
    }

    private func linkLibrary(name: String, to destination: URL) throws {
        try ensureRealDirectory(libraryURL)
        let link = libraryURL.appendingPathComponent(name)
        if isLink(link) || fileManager.fileExists(atPath: link.path) {
            try fileManager.removeItem(at: link)
        }
        try fileManager.createSymbolicLink(at: link, withDestinationURL: destination)
    }

    private func validateSlug(_ slug: String) throws {
        guard slug.range(of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) != nil,
              slug.count <= 80 else { throw SkillLibraryError.invalidSlug }
    }

    private func prepareRoots() throws {
        try fileManager.createDirectory(at: customURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        try ensureRealDirectory(customURL)
        try ensureRealDirectory(libraryURL)
    }

    /// custom 或库根被换成指向外部的软链时，后续写入会落到预期目录之外。
    private func ensureRealDirectory(_ url: URL) throws {
        guard !isLink(url) else { throw SkillLibraryError.unsafePath }
        var directory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else {
            throw SkillLibraryError.unsafePath
        }
    }

    private func ensureInside(_ url: URL, _ root: URL) throws {
        let root = root.standardizedFileURL
        let url = url.standardizedFileURL
        guard url.path == root.path || url.path.hasPrefix(root.path + "/") else { throw SkillLibraryError.unsafePath }
    }

    func checkPath(_ url: URL, inside root: URL) throws {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else {
            throw SkillLibraryError.unsafePath
        }
    }

    private func loadMeta() throws -> SkillLibraryMeta {
        guard fileManager.fileExists(atPath: categoriesURL.path) else { return SkillLibraryMeta() }
        do { return try JSONDecoder().decode(SkillLibraryMeta.self, from: Data(contentsOf: categoriesURL)) }
        catch { throw SkillLibraryError.corrupt }
    }

    private func writeMeta(_ meta: SkillLibraryMeta) throws {
        try fileManager.createDirectory(at: categoriesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(meta).write(to: categoriesURL, options: .atomic)
    }

    private func isInside(_ url: URL, _ root: URL) -> Bool {
        let root = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }

    /// 软链指向来源检出时继续跟随来源。http(s) 与 git 地址是技能来源留下的证据。
    private func followsSkillSource(_ origin: SourceSkillOrigin?) -> Bool {
        guard let origin else { return false }
        let url = origin.url
        return url.hasPrefix("https://") || url.hasPrefix("http://") || url.hasPrefix("git@") || url.hasPrefix("ssh://")
    }

    private func isFollowedSourceCheckout(_ url: URL, cacheSourcesRoot: URL) -> Bool {
        if isInside(url, customURL) { return false }
        let localImports = sourcesURL.appendingPathComponent("local-imports")
        if isInside(url, localImports) { return false }
        return isInside(url, sourcesURL) || isInside(url, cacheSourcesRoot)
    }

    private func isLink(_ url: URL) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private func existsDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return fileManager.fileExists(atPath: url.resolvingSymlinksInPath().path, isDirectory: &directory) && directory.boolValue
    }

    /// 库里指向版本包或其他外部目录的软链，改成 custom 里的副本。指向技能来源检出的软链保持不动。
    func absorbExternalLibraryEntries(cacheSourcesRoot: URL) throws {
        guard fileManager.fileExists(atPath: libraryURL.path), !isLink(libraryURL) else { return }
        let children = try fileManager.contentsOfDirectory(at: libraryURL, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles])
        guard children.contains(where: { isLink(libraryURL.appendingPathComponent($0.lastPathComponent)) }) else { return }
        try prepareRoots()
        for child in children {
            let item = libraryURL.appendingPathComponent(child.lastPathComponent)
            guard isLink(item) else { continue }
            let name = item.lastPathComponent
            guard (try? validateSlug(name)) != nil else { continue }
            let resolved = item.resolvingSymlinksInPath().standardizedFileURL
            if isInside(resolved, customURL) { continue }
            if isFollowedSourceCheckout(resolved, cacheSourcesRoot: cacheSourcesRoot) { continue }
            guard fileManager.fileExists(atPath: resolved.appendingPathComponent("SKILL.md").path) else { continue }
            let destination = customURL.appendingPathComponent(name, isDirectory: true)
            if fileManager.fileExists(atPath: destination.path) || isLink(destination) {
                let existing = try SkillAssetCopier.analyze(from: destination).contentHash
                let incoming = try SkillAssetCopier.analyze(from: resolved).contentHash
                guard existing == incoming else { continue }
            } else {
                _ = try SkillAssetCopier.copy(from: resolved, to: destination)
                let git = destination.appendingPathComponent(".git")
                if fileManager.fileExists(atPath: git.path) { try fileManager.removeItem(at: git) }
            }
            try linkLibrary(name: name, to: destination)
        }
    }

    /// custom 里已有、但技能库还没有入口的自建技能，补上同名软链。从技能来源加入的记录不补。
    func linkUnreferencedCustomSkills() throws {
        guard fileManager.fileExists(atPath: customURL.path), !isLink(customURL) else { return }
        try prepareRoots()
        let existing = libraryEntryNames()
        let meta = try loadMeta()
        let children = try fileManager.contentsOfDirectory(at: customURL, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles])
        for child in children {
            let name = child.lastPathComponent
            guard !existing.contains(name), (try? validateSlug(name)) != nil else { continue }
            guard !isLink(child) else { continue }
            guard fileManager.fileExists(atPath: child.appendingPathComponent("SKILL.md").path) else { continue }
            if followsSkillSource(meta.origins[name]) { continue }
            try linkLibrary(name: name, to: child)
        }
    }

    /// 旧版技能库放在通用目录 ~/.agents/skills。一次性把指向栖集目录的软链复制进私有库存，
    /// 旧位置原样保留，通用目录里的技能对 Codex 等宿主仍然可用。迁移只做一次，
    /// 否则用户移除的技能会在下次启动时被重新收进库。
    func migrateLibraryEntries(from legacyURL: URL, acceptedRoots: [URL], markerURL: URL) throws {
        let manager = fileManager
        guard !manager.fileExists(atPath: markerURL.path) else { return }
        guard manager.fileExists(atPath: legacyURL.path), !isLink(legacyURL) else {
            try linkUnreferencedCustomSkills()
            try writeMigrationMarker(markerURL)
            return
        }
        let children = try manager.contentsOfDirectory(
            at: legacyURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        try prepareRoots()
        for child in children {
            let name = child.lastPathComponent
            let item = legacyURL.appendingPathComponent(name)
            guard (try? validateSlug(name)) != nil else { continue }
            let entry = libraryURL.appendingPathComponent(name)
            guard !manager.fileExists(atPath: entry.path), !isLink(entry) else { continue }
            if isLink(item) {
                guard let rawTarget = try? manager.destinationOfSymbolicLink(atPath: item.path) else { continue }
                let target = URL(fileURLWithPath: rawTarget, relativeTo: legacyURL).standardizedFileURL
                guard acceptedRoots.contains(where: { isInside(target, $0) }) else { continue }
                // 指向已删除目标的软链不再收进库存，否则库里会出现永远阻塞的条目。
                guard manager.fileExists(atPath: target.resolvingSymlinksInPath().path) else { continue }
                try manager.createSymbolicLink(at: entry, withDestinationURL: target)
            }
        }
        try linkUnreferencedCustomSkills()
        try writeMigrationMarker(markerURL)
    }

    private func writeMigrationMarker(_ markerURL: URL) throws {
        try fileManager.createDirectory(at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: markerURL)
    }

    /// 技能库里的实体目录改放到 custom。已占用的 custom 名字跳过，避免覆盖另一份技能。
    private func adoptOwnedDirectories() throws {
        guard fileManager.fileExists(atPath: libraryURL.path), !isLink(libraryURL) else { return }
        let children = try fileManager.contentsOfDirectory(at: libraryURL, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles])
        guard children.contains(where: { !isLink(libraryURL.appendingPathComponent($0.lastPathComponent)) }) else { return }
        try prepareRoots()
        for child in children {
            let item = libraryURL.appendingPathComponent(child.lastPathComponent)
            guard !isLink(item) else { continue }
            var directory: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &directory), directory.boolValue else { continue }
            let name = item.lastPathComponent
            let destination = customURL.appendingPathComponent(name, isDirectory: true)
            guard !fileManager.fileExists(atPath: destination.path), !isLink(destination) else { continue }
            try fileManager.moveItem(at: item, to: destination)
            do { try linkLibrary(name: name, to: destination) }
            catch {
                try? fileManager.moveItem(at: destination, to: item)
                throw error
            }
        }
    }

    /// 旧索引里的个人技能搬到 custom，并在技能库留下同名软链。已占用的名字跳过。
    private func migrateLegacyPackagesIfNeeded() throws {
        let stateRoot = categoriesURL.deletingLastPathComponent()
        let legacyIndex = stateRoot.appendingPathComponent("skills/index.json")
        let marker = sourcesURL.appendingPathComponent(".migrated-skill-packages")
        guard fileManager.fileExists(atPath: legacyIndex.path), !fileManager.fileExists(atPath: marker.path) else { return }
        let index: LibraryIndex
        do { index = try JSONDecoder().decode(LibraryIndex.self, from: Data(contentsOf: legacyIndex)) }
        catch { return }
        try prepareRoots()
        var meta = (try? loadMeta()) ?? SkillLibraryMeta()
        for record in index.records {
            let slug = record.entry.slug
            guard (try? validateSlug(slug)) != nil else { continue }
            let package = stateRoot.appendingPathComponent("skills").appendingPathComponent(record.entry.path)
            guard fileManager.fileExists(atPath: package.path) else { continue }
            let libraryEntry = libraryURL.appendingPathComponent(slug)
            guard !fileManager.fileExists(atPath: libraryEntry.path), !isLink(libraryEntry) else { continue }
            if record.entry.sourceId == "personal" {
                let destination = customURL.appendingPathComponent(slug, isDirectory: true)
                guard !fileManager.fileExists(atPath: destination.path) else { continue }
                _ = try SkillAssetCopier.copy(from: package, to: destination)
                try linkLibrary(name: slug, to: destination)
            } else {
                _ = try SkillAssetCopier.copy(from: package, to: libraryEntry)
            }
            if let origin = record.sourceOrigin { meta.origins[slug] = origin }
        }
        try writeMeta(meta)
        try Data().write(to: marker)
    }

    /// 仅提取展示所需字段；保留完整原文和未知字段，不宣称完成 YAML schema 校验。
    static func metadata(_ text: String) throws -> (name: String, description: String, version: String?) {
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
