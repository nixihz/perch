import Foundation
import CryptoKit

public enum SourceSkillImportError: Error, SkillSetCodedError, Equatable, Sendable {
    case changed, unavailable, unsafePath

    public var code: String {
        switch self {
        case .changed: "SOURCE_IMPORT_CHANGED"
        case .unavailable: "SOURCE_IMPORT_UNAVAILABLE"
        case .unsafePath: "PATH_OUTSIDE_ROOT"
        }
    }
}

/// 来源证据随本机技能保留，不依赖可删除的预览缓存。
public struct SourceSkillOrigin: Codable, Equatable, Sendable {
    public let url: String
    public let commit: String
    public let path: String
    public let contentHash: String
    public let licenseEvidence: String
    public let licenseHashes: [String: String]
    /// 导入时的来源名称属于身份依据；本机编辑 SKILL.md 不改变这份证据。
    public let declaredName: String?
}

public struct SourceSkillImportDraft: Identifiable, Sendable {
    public let id = UUID()
    public let previewID: UUID
    public let origin: SourceSkillOrigin
    public let document: String
    public let files: [SkillAssetFile]
    public var slug: String
    /// 同一次导入只用一种方式。软链表示跟随来源，复制表示留下实体。
    public var mode: SkillInstallMethod = .symlink
    public var category: String = ""
}

/// 来源技能的本机标识规则。界面预填与核心写入共用，避免两边算出不同的标识。
public enum SourceSkillSlug {
    /// 把来源里的名字清洗成本机标识：小写字母、数字和连字符，最长 80 个字符。
    public static func normalized(_ raw: String) -> String {
        let cleaned = raw.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let trimmed = String(cleaned.prefix(80)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "imported-skill" : trimmed
    }

    /// 避开已有标识：依次尝试 -2、-3。只加序号，不覆盖技能库里的同名条目。
    public static func unique(_ base: String, existing: Set<String>) -> String {
        guard existing.contains(base) else { return base }
        var index = 2
        while index < 1000 {
            let suffix = "-\(index)"
            let stem = String(base.prefix(max(1, 80 - suffix.count)))
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            let candidate = stem + suffix
            if !existing.contains(candidate) { return candidate }
            index += 1
        }
        return base
    }
}

/// 批量加入技能库的一项：来源预览里的相对路径与本机技能标识。
public struct SourceSkillBatchItem: Sendable, Hashable {
    public let path: String
    public let slug: String

    public init(path: String, slug: String) {
        self.path = path
        self.slug = slug
    }
}

/// 批量加入技能库的请求。整批共用一种存放方式与分类。
public struct SourceSkillBatchRequest: Sendable {
    public let previewID: UUID
    public let items: [SourceSkillBatchItem]
    public let mode: SkillInstallMethod
    public let category: String

    public init(previewID: UUID, items: [SourceSkillBatchItem], mode: SkillInstallMethod, category: String) {
        self.previewID = previewID
        self.items = items
        self.mode = mode
        self.category = category
    }
}

/// 单项结果。跳过与失败只保留稳定错误码，文案由界面层映射。
public struct SourceSkillBatchItemResult: Sendable {
    public enum Status: Sendable {
        case imported(SkillEntry)
        case skipped(code: String)
        case failed(code: String)
    }

    public let path: String
    public let slug: String
    public let status: Status

    public init(path: String, slug: String, status: Status) {
        self.path = path
        self.slug = slug
        self.status = status
    }
}

/// 技能库写入阶段的一项：已经通过来源校验的完整技能包。
struct SourceSkillBatchPackage {
    let path: String
    let slug: String
    let source: URL
    let licenses: [String: Data]
    let origin: SourceSkillOrigin
    let analysis: SkillAssetCopyResult
}

extension SkillSetService {
    public func sourceSkillImportDraft(previewID: UUID, path: String) throws -> SourceSkillImportDraft {
        let validated = try sourceForImport(previewID: previewID, path: path)
        let documentURL = validated.source.appendingPathComponent("SKILL.md")
        guard (try documentURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 2 * 1_024 * 1_024 else {
            throw SkillLibraryError.invalidDocument
        }
        let document = try String(contentsOf: documentURL, encoding: .utf8)
        return SourceSkillImportDraft(
            previewID: previewID, origin: validated.origin, document: document,
            files: validated.analysis.fileManifest.filter { $0.path != "SKILL.md" && $0.path != ".git" && !$0.path.hasPrefix(".git/") },
            slug: SourceSkillSlug.normalized(validated.candidate.slug)
        )
    }

    public func importSourceSkill(_ draft: SourceSkillImportDraft) throws -> SkillEntry {
        let validated = try sourceForImport(previewID: draft.previewID, path: draft.origin.path)
        guard validated.origin == draft.origin else { throw SourceSkillImportError.changed }
        return try libraryStore().importSource(
            draft, source: validated.source, licenses: validated.licenses
        )
    }

    /// 批量加入技能库。逐项用同一套来源校验，校验通过才写入技能库；单项失败不影响同批其他项，
    /// 已写入的条目保留。返回顺序与请求一致。
    public func importSourceSkills(_ request: SourceSkillBatchRequest) -> [SourceSkillBatchItemResult] {
        guard !request.items.isEmpty else { return [] }
        var outcomes: [SourceSkillBatchItemResult.Status?] = Array(repeating: nil, count: request.items.count)
        var packages: [SourceSkillBatchPackage] = []
        var seenPaths: Set<String> = []

        for (index, item) in request.items.enumerated() {
            // 同一个来源路径只导入一次；重复的标识由技能库按已占用处理。
            guard seenPaths.insert(item.path).inserted else {
                outcomes[index] = .skipped(code: SkillLibraryError.duplicate.code)
                continue
            }
            do {
                let validated = try sourceForImport(previewID: request.previewID, path: item.path)
                packages.append(SourceSkillBatchPackage(
                    path: item.path, slug: item.slug, source: validated.source,
                    licenses: validated.licenses, origin: validated.origin, analysis: validated.analysis
                ))
            } catch {
                outcomes[index] = .failed(code: Self.failureCode(error))
            }
        }

        if !packages.isEmpty {
            let written = libraryStore().importSourceBatch(packages, mode: request.mode, category: request.category)
            var byPath: [String: SourceSkillBatchItemResult.Status] = [:]
            for result in written { byPath[result.path] = result.status }
            for (index, item) in request.items.enumerated() where outcomes[index] == nil {
                outcomes[index] = byPath[item.path] ?? .failed(code: SourceSkillImportError.unavailable.code)
            }
        }

        return request.items.indices.map { index in
            SourceSkillBatchItemResult(
                path: request.items[index].path,
                slug: request.items[index].slug,
                status: outcomes[index] ?? .failed(code: SourceSkillImportError.unavailable.code)
            )
        }
    }

    /// 批量结果的失败原因只保留稳定错误码，界面层再翻译成用户文案。
    static func failureCode(_ error: Error) -> String {
        (error as? any SkillSetCodedError)?.code ?? "UNCLASSIFIED"
    }

    func sourceForImport(previewID: UUID, path: String) throws -> (
        source: URL, candidate: SourceSkillCandidate, origin: SourceSkillOrigin,
        analysis: SkillAssetCopyResult, licenses: [String: Data]
    ) {
        let record = try sourcePreview(id: previewID)
        guard record.id == previewID, record.schemaVersion == 1,
              let candidate = record.candidates.first(where: { $0.path == path }),
              candidate.issues.isEmpty, !candidate.contentHash.isEmpty else { throw SourceSkillImportError.unavailable }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard path == "." || (!path.hasPrefix("/") && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && $0 != ".git" }) else {
            throw SourceSkillImportError.unsafePath
        }
        // 工作区只能从存储根和 UUID 推导；不使用记录中的任意绝对路径。
        let root = paths.previewsRoot.appendingPathComponent(previewID.uuidString).appendingPathComponent("checkout").standardizedFileURL
        let source = path == "." ? root : root.appendingPathComponent(path).standardizedFileURL
        guard root.resolvingSymlinksInPath().path == root.path,
              source.resolvingSymlinksInPath().path == source.path,
              source.path == root.path || source.path.hasPrefix(root.path + "/") else { throw SourceSkillImportError.unsafePath }
        let document = source.appendingPathComponent("SKILL.md")
        guard document.resolvingSymlinksInPath().path == document.path,
              try document.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw SourceSkillImportError.unsafePath
        }
        let analysis = try SkillAssetCopier.analyze(from: source)
        guard analysis.contentHash == candidate.contentHash else { throw SourceSkillImportError.changed }
        var licenses: [String: Data] = [:]
        // 仓库级许可也复制到技能包，删除缓存后仍可追溯原文。
        if path != "." {
            let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
            for item in files {
                let file = root.appendingPathComponent(item.lastPathComponent).standardizedFileURL
                let name = file.lastPathComponent.uppercased()
                guard ["LICENSE", "LICENCE", "COPYING", "NOTICE"].contains(where: { name == $0 || name.hasPrefix($0 + ".") || name.hasPrefix($0 + "-") }) else { continue }
                guard file.resolvingSymlinksInPath().path == file.path else { throw SourceSkillImportError.unsafePath }
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true else { continue }
                guard (values.fileSize ?? 0) <= 2 * 1_024 * 1_024, licenses.count < 32 else { throw SourceSkillImportError.unavailable }
                licenses[file.lastPathComponent] = try Data(contentsOf: file)
            }
        }
        let origin = SourceSkillOrigin(
            url: record.canonicalURL, commit: record.resolvedCommit, path: path,
            contentHash: candidate.contentHash, licenseEvidence: record.licenseEvidence,
            licenseHashes: licenses.mapValues { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() },
            declaredName: candidate.declaredName
        )
        return (source, candidate, origin, analysis, licenses)
    }
}
