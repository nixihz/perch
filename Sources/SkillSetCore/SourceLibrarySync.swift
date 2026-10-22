import Foundation

extension SkillSetService {
    /// 同步只发布本机搜索索引；已部署版本独立保留，不随来源编辑或删除而移动。
    public func synchronizeSourceLibrary(excluding excludedID: UUID? = nil) throws {
        let store = SkillLibraryStore(rootURL: paths.libraryRoot)
        var index = try store.load()
        let previous = index.records
        var records = previous.filter { !$0.entry.sourceId.hasPrefix("source-") }
        var created: [URL] = []
        var published = false
        defer { if !published { for url in created { try? FileManager.default.removeItem(at: url) } } }
        // 同一个来源保留最新配置，避免重复配置造成相同标识。
        var seen = Set<String>()
        for preview in try sourcePreviews() where preview.id != excludedID && seen.insert(preview.canonicalURL).inserted {
            let sourceID = "source-" + SkillAssetCopier.sha256(Data(preview.canonicalURL.utf8))
            for candidate in preview.candidates where candidate.issues.isEmpty && !candidate.contentHash.isEmpty {
                let validated = try sourceForImport(previewID: preview.id, path: candidate.path)
                let id = sourceID + "/" + String(SkillAssetCopier.sha256(Data(candidate.path.utf8)).prefix(12)) + "/" + candidate.slug
                if let old = previous.first(where: { $0.entry.id == id && $0.sourceOrigin == validated.origin }),
                   (try? SkillAssetCopier.analyze(from: store.packageURL(old.entry.path)).contentHash) == old.entry.contentHash {
                    records.append(old)
                    continue
                }
                try store.prepareRoot()
                let relative = "packages/\(UUID())"
                let destination = try store.packageURL(relative)
                created.append(destination)
                let copied = try SkillAssetCopier.copy(from: validated.source, to: destination)
                guard copied.contentHash == candidate.contentHash else { throw SourceSkillImportError.changed }
                let git = destination.appendingPathComponent(".git")
                if FileManager.default.fileExists(atPath: git.path) { try FileManager.default.removeItem(at: git) }
                if !validated.licenses.isEmpty {
                    var name = "_source_licenses"
                    while FileManager.default.fileExists(atPath: destination.appendingPathComponent(name).path) { name += "_" }
                    let licenses = destination.appendingPathComponent(name)
                    try FileManager.default.createDirectory(at: licenses, withIntermediateDirectories: true)
                    for (name, data) in validated.licenses { try data.write(to: licenses.appendingPathComponent(name)) }
                }
                let analysis = try SkillAssetCopier.analyze(from: destination)
                let entry = SkillEntry(
                    id: id, slug: candidate.slug, declaredName: candidate.declaredName, description: candidate.description,
                    declaredVersion: nil, metadataReview: "not-schema-validated", sourceId: sourceID,
                    path: relative, contentHash: analysis.contentHash, fileCount: analysis.files.count,
                    bytes: analysis.bytes, integrity: "snapshotted", issues: [], licenseReview: "required", excludedPaths: []
                )
                records.append(LibrarySkillRecord(entry: entry, originID: preview.canonicalURL + "#" + candidate.path, sourceOrigin: validated.origin))
            }
        }
        index.records = records
        try store.prepareRoot()
        try store.write(index)
        published = true
    }

    public func removeSource(_ id: UUID) throws {
        let store = SourcePreviewStore(rootURL: paths.previewsRoot)
        let record = try store.load(id)
        let hidden = paths.previewsRoot.appendingPathComponent(".pending-remove-\(id)")
        let directory = paths.previewsRoot.appendingPathComponent(id.uuidString)
        try FileManager.default.moveItem(at: directory, to: hidden)
        do { try synchronizeSourceLibrary() }
        catch {
            try FileManager.default.moveItem(at: hidden, to: directory)
            throw error
        }
        _ = record
        try? FileManager.default.removeItem(at: hidden)
    }
}
