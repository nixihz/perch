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
}

public struct SourceSkillImportDraft: Identifiable, Sendable {
    public let id = UUID()
    public let previewID: UUID
    public let origin: SourceSkillOrigin
    public let document: String
    public let files: [SkillAssetFile]
    public var slug: String
}

extension SkillSetService {
    public func sourceSkillImportDraft(previewID: UUID, path: String) throws -> SourceSkillImportDraft {
        let validated = try sourceForImport(previewID: previewID, path: path)
        let documentURL = validated.source.appendingPathComponent("SKILL.md")
        guard (try documentURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 2 * 1_024 * 1_024 else {
            throw SkillLibraryError.invalidDocument
        }
        let document = try String(contentsOf: documentURL, encoding: .utf8)
        let suggestedSlug = validated.candidate.slug.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return SourceSkillImportDraft(
            previewID: previewID, origin: validated.origin, document: document,
            files: validated.analysis.fileManifest.filter { $0.path != "SKILL.md" && $0.path != ".git" && !$0.path.hasPrefix(".git/") },
            slug: suggestedSlug.isEmpty ? "imported-skill" : String(suggestedSlug.prefix(80)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        )
    }

    public func importSourceSkill(_ draft: SourceSkillImportDraft) throws -> SkillEntry {
        let validated = try sourceForImport(previewID: draft.previewID, path: draft.origin.path)
        guard validated.origin == draft.origin else { throw SourceSkillImportError.changed }
        return try SkillLibraryStore(rootURL: paths.libraryRoot).importSource(
            draft, source: validated.source, licenses: validated.licenses
        )
    }

    private func sourceForImport(previewID: UUID, path: String) throws -> (
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
        // 仓库级许可也复制到技能包，删除缓存后仍可追溯原文；不自动判定许可已审核。
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
            licenseHashes: licenses.mapValues { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
        )
        return (source, candidate, origin, analysis, licenses)
    }
}
