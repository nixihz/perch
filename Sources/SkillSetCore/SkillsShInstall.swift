import Foundation

extension SkillSetService {
    /// 目录只负责发现；安装仍回到原 GitHub 仓库，读取当前提交并复制到本机技能库。
    public func installDirectorySkill(_ hit: SkillsShHit) throws -> SkillEntry {
        try installDirectorySkill(
            hit,
            previewService: SourcePreviewService(
                previewsRoot: paths.previewsRoot,
                allowedHosts: ["github.com"]
            )
        )
    }

    func installDirectorySkill(
        _ hit: SkillsShHit,
        previewService: SourcePreviewService
    ) throws -> SkillEntry {
        guard let repositoryURL = hit.repositoryURL else {
            throw SkillsShDirectoryError.nonGitHubSource(hit.source)
        }
        let slug = hit.librarySlug
        guard !slug.isEmpty, slug.count <= 80 else {
            throw SkillsShDirectoryError.invalidSkillID
        }

        let record = try previewService.preview(urlString: repositoryURL)
        defer {
            // 目录安装只借用隔离预览；成功或失败都不能把整仓登记成持久来源。
            try? SourcePreviewStore(rootURL: previewService.previewsRoot).remove(record.id)
        }
        guard record.canonicalURL == repositoryURL else {
            throw SkillsShDirectoryError.nonGitHubSource(hit.source)
        }
        let candidate = try SkillsShCandidateMatcher.match(hit, candidates: record.candidates)
        var draft = try sourceSkillImportDraft(previewID: record.id, path: candidate.path)
        draft.slug = slug
        return try importSourceSkill(draft)
    }
}
