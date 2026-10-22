import Foundation

public enum PluginSourceError: Error, SkillSetCodedError, Equatable, Sendable {
    case changed, alreadyCollected
    public var code: String {
        switch self {
        case .changed: "PLUGIN_SOURCE_CHANGED"
        case .alreadyCollected: "PLUGIN_SOURCE_COLLECTED"
        }
    }
}

public struct PluginScanCandidate: Identifiable, Sendable {
    public let records: [PluginInventoryRecord]
    public let contentHash: String?
    public let collected: Bool
    public let issue: String?
    public var id: String { records[0].id }
    public var canImport: Bool { contentHash != nil && !collected && issue == nil }
}

public struct PluginImportEvidence: Codable, Sendable {
    public let scannedAt: Date
    public let contentHash: String
    public let installations: [PluginInventoryRecord]
}

/// 插件来源独立保存；来源操作不会注册宿主市场或调用插件安装器。
public struct PluginSourceLibrary: Sendable {
    public let rootURL: URL

    public init(stateRoot: URL) {
        rootURL = stateRoot.appendingPathComponent("plugins/sources", isDirectory: true)
    }

    public func sources() throws -> [SourcePreviewRecord] {
        try SourcePreviewStore(rootURL: rootURL).list()
    }

    public func save(address: String, ref: String? = nil, replacing id: UUID? = nil) throws -> SourcePreviewRecord {
        let store = SourcePreviewStore(rootURL: rootURL)
        if let id { _ = try store.load(id) }
        let preview = try SourcePreviewService(previewsRoot: rootURL).preview(urlString: address, ref: ref)
        do {
            var saved = preview
            if preview.canonicalURL.hasPrefix("/") {
                // 插件来源未必含技能，不能沿用仅依据技能候选计算的本地版本。
                let checkout = rootURL.appendingPathComponent(preview.id.uuidString).appendingPathComponent("checkout")
                let hash = try SkillAssetCopier.analyze(from: checkout).contentHash
                let plugins = try PluginInventoryManager(projectRoot: nil).inspectSource(at: checkout).records
                saved = SourcePreviewRecord(id: preview.id, inputURL: preview.inputURL,
                    requestedRef: preview.requestedRef, canonicalURL: preview.canonicalURL,
                    namespace: plugins.count == 1 ? plugins[0].name : URL(fileURLWithPath: preview.inputURL).lastPathComponent,
                    resolvedCommit: hash, createdAt: preview.createdAt, workspacePath: checkout.path,
                    licenseEvidence: preview.licenseEvidence, candidates: preview.candidates,
                    excludedCounts: preview.excludedCounts, warnings: preview.warnings)
                try store.save(saved)
            }
            if let id { try store.remove(id) }
            return saved
        } catch {
            try? store.remove(preview.id)
            throw error
        }
    }

    public func remove(_ id: UUID) throws {
        // 删除路径只由 UUID 推导，不信任记录内的 workspacePath。
        try SourcePreviewStore(rootURL: rootURL).remove(id)
    }

    public func inventory(_ id: UUID) throws -> PluginInventorySnapshot {
        _ = try SourcePreviewStore(rootURL: rootURL).load(id)
        let checkout = rootURL.appendingPathComponent(id.uuidString).appendingPathComponent("checkout")
        return try PluginInventoryManager(projectRoot: nil).inspectSource(at: checkout)
    }

    public func evidence(_ id: UUID) throws -> PluginImportEvidence? {
        let url = rootURL.appendingPathComponent(id.uuidString).appendingPathComponent("import.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(PluginImportEvidence.self, from: Data(contentsOf: url))
    }

    /// 完整包指纹用于识别重复，不能只看 manifest 而忽略 hooks 等附属内容。
    public func scan(records: [PluginInventoryRecord]) throws -> [PluginScanCandidate] {
        let known = Set(try sources().compactMap { try evidence($0.id)?.contentHash })
        var groups: [String: [PluginInventoryRecord]] = [:]
        var hashes: [String: String] = [:]
        var failures: [PluginScanCandidate] = []
        for record in records {
            do {
                let source = URL(fileURLWithPath: record.sourcePath)
                guard source.resolvingSymlinksInPath() == source.standardizedFileURL else {
                    throw PluginInventoryError.unsafeRoot(source.path)
                }
                let hash = try SkillAssetCopier.analyze(from: source).contentHash
                let key = record.host.rawValue + ":" + hash
                if groups[key]?.contains(where: { $0.id == record.id }) != true { groups[key, default: []].append(record) }
                hashes[key] = hash
            } catch {
                failures.append(PluginScanCandidate(records: [record], contentHash: nil, collected: false,
                    issue: "无法读取完整插件包，请检查文件权限、断链和包内链接。"))
            }
        }
        return groups.keys.sorted().map { key in
            PluginScanCandidate(records: groups[key]!, contentHash: hashes[key], collected: known.contains(hashes[key]!), issue: nil)
        } + failures
    }

    public func importCandidate(_ candidate: PluginScanCandidate) throws -> SourcePreviewRecord {
        guard candidate.canImport, let expected = candidate.contentHash, let original = candidate.records.first else {
            throw PluginSourceError.changed
        }
        guard try !sources().contains(where: { try evidence($0.id)?.contentHash == expected }) else {
            throw PluginSourceError.alreadyCollected
        }
        let id = UUID()
        let destination = rootURL.appendingPathComponent(id.uuidString)
        let checkout = destination.appendingPathComponent("checkout")
        var published = false
        defer { if !published { try? FileManager.default.removeItem(at: destination) } }
        // 复制前检查每个原始位置，随后核对复制结果，拒绝扫描后的内容变化。
        for record in candidate.records {
            let source = URL(fileURLWithPath: record.sourcePath)
            guard source.resolvingSymlinksInPath() == source.standardizedFileURL,
                  try SkillAssetCopier.analyze(from: source).contentHash == expected,
                  try SkillAssetCopier.sha256(Data(contentsOf: URL(fileURLWithPath: record.manifestPath))) == record.manifestDigest else {
                throw PluginSourceError.changed
            }
        }
        let copied = try SkillAssetCopier.copy(from: URL(fileURLWithPath: original.sourcePath), to: checkout)
        guard copied.contentHash == expected else { throw PluginSourceError.changed }
        let evidence = PluginImportEvidence(scannedAt: Date(), contentHash: expected, installations: candidate.records)
        try JSONEncoder().encode(evidence).write(to: destination.appendingPathComponent("import.json"), options: .atomic)
        let record = SourcePreviewRecord(id: id, inputURL: original.sourcePath, canonicalURL: original.sourcePath,
            namespace: original.name, resolvedCommit: expected, createdAt: evidence.scannedAt,
            workspacePath: checkout.path, licenseEvidence: original.license ?? "", candidates: [], excludedCounts: [:], warnings: [])
        try SourcePreviewStore(rootURL: rootURL).save(record)
        published = true
        return record
    }
}
