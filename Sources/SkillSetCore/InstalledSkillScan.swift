import Foundation

public struct InstalledSkillObservation: Identifiable, Codable, Sendable {
    public let path: String
    public let resolvedPath: String
    public let contentHash: String?
    public let managed: Bool
    public let collected: Bool
    public let issue: String?
    public var id: String { path }
    public var canImport: Bool { contentHash != nil && !managed && !collected && issue == nil }
}

extension SkillSetService {
    private var localImportsRoot: URL {
        paths.applicationSupportRoot.appendingPathComponent("sources/local-imports", isDirectory: true)
    }

    /// 只读发现；一级链接和仅包含外部 SKILL.md 软链的安装入口都可收录。
    public func scanInstalledSkills(additionalRoots: [URL] = []) throws -> [InstalledSkillObservation] {
        try Self.scanInstalledSkills(paths: paths, locations: globalConfiguration.locations, additionalRoots: additionalRoots)
    }

    /// 不组装完整服务快照。界面重扫只需要安装根和技能库指纹。
    /// 官方技能目录只在首次初始化读取；之后只扫描调用方追加的目录。
    public static func scanInstalledSkills(
        paths: SkillSetRuntimePaths,
        locations: GlobalConfigurationLocations,
        additionalRoots: [URL] = []
    ) throws -> [InstalledSkillObservation] {
        try scanInstalledSkills(paths: paths, locations: locations, additionalRoots: additionalRoots, includeOfficialPaths: false)
    }

    /// 首次初始化把已安装、且不是跟随技能来源的技能放进 custom。官方目录之后不再扫描。
    static func adoptInstalledSkillsIfNeeded(paths: SkillSetRuntimePaths, locations: GlobalConfigurationLocations) throws {
        let fm = FileManager.default
        let marker = paths.sourcesRoot.appendingPathComponent(".adopted-installed-skills")
        if fm.fileExists(atPath: marker.path) { return }
        let store = paths.makeLibraryStore()
        if fm.fileExists(atPath: store.libraryURL.path),
           (try? fm.destinationOfSymbolicLink(atPath: store.libraryURL.path)) != nil { return }
        _ = try store.loadLibrary()
        try store.absorbExternalLibraryEntries(cacheSourcesRoot: paths.previewsRoot)
        let observations = try scanInstalledSkills(
            paths: paths, locations: locations, additionalRoots: [], includeOfficialPaths: true
        )
        let selected = observations.filter { item in
            item.canImport && !resolvesInsideSkillSource(item.resolvedPath, paths: paths)
        }
        if !selected.isEmpty {
            try importInstalledCopies(selected, store: store)
        }
        try store.linkUnreferencedCustomSkills()
        try fm.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: marker)
    }

    static func officialInstalledSkillRoots(_ locations: GlobalConfigurationLocations) -> [URL] {
        [
            locations.configuredSkillsRoot(.codex),
            locations.codexRoot.appendingPathComponent("skills"),
            locations.configuredSkillsRoot(.claudeCode),
        ]
    }

    /// 跟随技能来源的目录留在来源检出里，不复制进 custom。
    static func resolvesInsideSkillSource(_ path: String, paths: SkillSetRuntimePaths) -> Bool {
        let resolved = URL(fileURLWithPath: path).standardizedFileURL.path
        let sources = paths.sourcesRoot.standardizedFileURL.path
        let custom = paths.sourcesRoot.appendingPathComponent("custom").standardizedFileURL.path
        let localImports = paths.sourcesRoot.appendingPathComponent("local-imports").standardizedFileURL.path
        if resolved == custom || resolved.hasPrefix(custom + "/") { return false }
        if resolved == localImports || resolved.hasPrefix(localImports + "/") { return false }
        let cache = paths.previewsRoot.standardizedFileURL.path
        if resolved == sources || resolved.hasPrefix(sources + "/") { return true }
        if resolved == cache || resolved.hasPrefix(cache + "/") { return true }
        return false
    }

    private static func scanInstalledSkills(
        paths: SkillSetRuntimePaths,
        locations: GlobalConfigurationLocations,
        additionalRoots: [URL],
        includeOfficialPaths: Bool
    ) throws -> [InstalledSkillObservation] {
        try paths.migrateLegacyState()
        let roots = (includeOfficialPaths ? officialInstalledSkillRoots(locations) : []) + additionalRoots
        var seen = Set<String>()
        var seenEntries = Set<String>()
        var result: [InstalledSkillObservation] = []
        let fm = FileManager.default
        let library = try paths.makeLibraryStore().loadLibrary()
        // 已经在库里的技能不再当作可收录。指纹来自目录本身，不要求另写一份来源记录。
        let known = Set(library.origins.values.map(\.contentHash))
            .union(library.records.map(\.entry.contentHash).filter { !$0.isEmpty })
        let versionsRoot = paths.versionsRoot
        for root in roots where seen.insert(root.standardizedFileURL.path).inserted {
            guard fm.fileExists(atPath: root.path) else { continue }
            // Foundation 枚举目录软链时可能返回 ENOTDIR；读取真实目录，展示仍保留安装入口。
            let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
            let entries: [URL]
            do {
                entries = fm.fileExists(atPath: resolvedRoot.appendingPathComponent("SKILL.md").path)
                    ? [root] : try fm.contentsOfDirectory(at: resolvedRoot, includingPropertiesForKeys: nil)
            } catch {
                result.append(.init(path: root.path, resolvedPath: resolvedRoot.path, contentHash: nil,
                                    managed: false, collected: false, issue: "目录无法读取，请重新选择目录并检查访问权限。"))
                continue
            }
            var jobs: [InstalledScanJob] = []
            jobs.reserveCapacity(entries.count)
            for entry in entries.sorted(by: { $0.path < $1.path }) {
                let child = entries.count == 1 && entry.path == root.path ? root : root.appendingPathComponent(entry.lastPathComponent)
                guard seenEntries.insert(child.path).inserted else { continue }
                let resolved = child.resolvingSymlinksInPath().standardizedFileURL
                let linked = (try? fm.destinationOfSymbolicLink(atPath: child.path)) != nil
                guard fm.fileExists(atPath: resolved.appendingPathComponent("SKILL.md").path) || linked else { continue }
                jobs.append(InstalledScanJob(child: child, linked: linked))
            }
            // 每个技能包的指纹互不依赖。并行计算后按发现顺序回填，避免扫描结果跳动。
            result.append(contentsOf: InstalledSkillLocator.observe(jobs, known: known, versionsRoot: versionsRoot))
        }
        return result
    }

    /// 旧的 local-imports 只是一份重复副本。有内容就迁入 custom，然后删除目录和指向它的来源预览。
    @discardableResult
    public func consolidateInstalledSkillSources() throws -> Bool {
        let existed = FileManager.default.fileExists(atPath: localImportsRoot.path)
        try Self.absorbLocalImports(paths: paths, home: globalConfiguration.locations.home)
        return existed
    }

    /// 扫描到的技能直接复制进 custom，并在技能库留下同名软链。不另建 local-imports，也不改原安装。
    public func importInstalledSkills(_ selection: [InstalledSkillObservation]) throws {
        try Self.importInstalledCopies(selection, store: libraryStore())
    }

    private static func importInstalledCopies(_ selection: [InstalledSkillObservation], store: SkillLibraryStore) throws {
        guard !selection.isEmpty, selection.allSatisfy(\.canImport), Set(selection.map(\.path)).count == selection.count else {
            throw SourceSkillImportError.changed
        }
        if FileManager.default.fileExists(atPath: store.libraryURL.path),
           (try? FileManager.default.destinationOfSymbolicLink(atPath: store.libraryURL.path)) != nil {
            throw SkillLibraryError.unsafePath
        }
        var seen = Set<String>()
        for item in selection {
            guard let hash = item.contentHash, seen.insert(hash).inserted else { continue }
            let original = URL(fileURLWithPath: item.path)
            guard let source = try? InstalledSkillLocator.resolve(at: original),
                  source.url.path == item.resolvedPath,
                  source.analysis.contentHash == hash else {
                throw SourceSkillImportError.changed
            }
            let origin = SourceSkillOrigin(
                url: item.path, commit: "local-import", path: original.lastPathComponent,
                contentHash: hash, licenseEvidence: "", licenseHashes: [:], declaredName: nil
            )
            do {
                try store.storeOwnedCopy(slug: original.lastPathComponent, from: source.url, licenses: [:], origin: origin, category: "")
            } catch SkillLibraryError.duplicate, SkillLibraryError.invalidSlug {
                continue
            }
        }
    }

    /// 启动时收掉旧目录。库根本身是软链时无法写入，保留原目录以免丢掉唯一副本。
    static func absorbLocalImports(paths: SkillSetRuntimePaths, home: URL) throws {
        let fm = FileManager.default
        let root = paths.applicationSupportRoot.appendingPathComponent("sources/local-imports", isDirectory: true)
        let store = paths.makeLibraryStore()
        if fm.fileExists(atPath: store.libraryURL.path),
           (try? fm.destinationOfSymbolicLink(atPath: store.libraryURL.path)) != nil { return }
        if fm.fileExists(atPath: root.path) {
            for package in try skillPackages(in: root) {
                let slug = package.lastPathComponent
                if fm.fileExists(atPath: store.customURL.appendingPathComponent(slug).path)
                    || fm.fileExists(atPath: store.libraryURL.appendingPathComponent(slug).path)
                    || (try? fm.destinationOfSymbolicLink(atPath: store.libraryURL.appendingPathComponent(slug).path)) != nil {
                    continue
                }
                let analysis = try SkillAssetCopier.analyze(from: package)
                let origin = SourceSkillOrigin(
                    url: package.path, commit: "local-import", path: slug,
                    contentHash: analysis.contentHash, licenseEvidence: "", licenseHashes: [:], declaredName: nil
                )
                do { try store.storeOwnedCopy(slug: slug, from: package, licenses: [:], origin: origin, category: "") }
                catch SkillLibraryError.duplicate, SkillLibraryError.invalidSlug { continue }
            }
            try fm.removeItem(at: root)
        }
        let previews = SourcePreviewStore(rootURL: paths.previewsRoot)
        for preview in try previews.list() where preview.canonicalURL.contains("/sources/local-imports") || preview.inputURL.contains("/sources/local-imports") {
            try previews.remove(preview.id)
        }
    }

    private static func skillPackages(in root: URL, depth: Int = 0) throws -> [URL] {
        if depth > 4 { return [] }
        let fm = FileManager.default
        if fm.fileExists(atPath: root.appendingPathComponent("SKILL.md").path) { return [root] }
        guard fm.fileExists(atPath: root.path) else { return [] }
        let children = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        var found: [URL] = []
        for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            found.append(contentsOf: try skillPackages(in: child, depth: depth + 1))
        }
        return found
    }

    /// 删除扫描到的原安装入口；技能库收录副本与软链目标保持不变。
    public func removeInstalledSkill(_ item: InstalledSkillObservation) throws {
        try FileManager.default.removeItem(at: try validatedInstalledSkillURL(item))
    }

    /// 批量删除原安装入口；先完整校验，避免校验失败时只删除部分项目。
    public func removeInstalledSkills(_ items: [InstalledSkillObservation]) throws {
        guard !items.isEmpty, Set(items.map(\.path)).count == items.count else {
            throw SourceSkillImportError.unavailable
        }
        let urls = try items.map(validatedInstalledSkillURL)
        for url in urls { try FileManager.default.removeItem(at: url) }
    }

    private func validatedInstalledSkillURL(_ item: InstalledSkillObservation) throws -> URL {
        guard item.collected, let contentHash = item.contentHash, !contentHash.isEmpty else {
            throw SourceSkillImportError.unavailable
        }
        let original = URL(fileURLWithPath: item.path)
        guard let source = try? InstalledSkillLocator.resolve(at: original),
              source.url.path == item.resolvedPath,
              source.analysis.contentHash == contentHash else {
            throw SourceSkillImportError.changed
        }
        let roots = [globalConfiguration.locations.configuredSkillsRoot(.codex),
                     globalConfiguration.locations.codexRoot.appendingPathComponent("skills"),
                     globalConfiguration.locations.configuredSkillsRoot(.claudeCode)]
        guard !roots.contains(where: { $0.standardizedFileURL.path == original.standardizedFileURL.path }) else {
            throw SourceSkillImportError.unavailable
        }
        return original
    }

}

private struct InstalledScanJob: Sendable {
    let child: URL
    let linked: Bool
}

private struct ResolvedInstalledSkill {
    let url: URL
    let analysis: SkillAssetCopyResult
}

private final class InstalledScanSlot: @unchecked Sendable {
    var observation: InstalledSkillObservation?
}

private enum InstalledSkillLocator {
    static func observe(_ jobs: [InstalledScanJob], known: Set<String>, versionsRoot: URL) -> [InstalledSkillObservation] {
        guard jobs.count > 1 else {
            return jobs.map { observe($0, known: known, versionsRoot: versionsRoot) }
        }
        let slots = jobs.map { _ in InstalledScanSlot() }
        DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
            slots[index].observation = observe(jobs[index], known: known, versionsRoot: versionsRoot)
        }
        return slots.map { slot in
            guard let observation = slot.observation else {
                preconditionFailure("扫描任务未写回结果")
            }
            return observation
        }
    }

    static func observe(_ job: InstalledScanJob, known: Set<String>, versionsRoot: URL) -> InstalledSkillObservation {
        let resolved = job.child.resolvingSymlinksInPath().standardizedFileURL
        do {
            let source = try resolve(at: job.child)
            let managed = job.linked && (try? ManagedSkillLink.hash(job.child, versionsRoot: versionsRoot)) != nil
            return InstalledSkillObservation(
                path: job.child.path, resolvedPath: source.url.path, contentHash: source.analysis.contentHash,
                managed: managed, collected: known.contains(source.analysis.contentHash), issue: nil
            )
        } catch {
            return InstalledSkillObservation(
                path: job.child.path, resolvedPath: resolved.path, contentHash: nil,
                managed: false, collected: false, issue: "无法读取完整技能包，请检查断链、包内软链和文件权限。"
            )
        }
    }

    /// 解析成功时带回已经算好的指纹，调用方不要再把同一个目录读一遍。
    static func resolve(at entry: URL) throws -> ResolvedInstalledSkill {
        let resolved = entry.resolvingSymlinksInPath().standardizedFileURL
        if let analysis = try? SkillAssetCopier.analyze(from: resolved) {
            return ResolvedInstalledSkill(url: resolved, analysis: analysis)
        }

        let skillFile = resolved.appendingPathComponent("SKILL.md")
        guard FileManager.default.fileExists(atPath: skillFile.path),
              (try? FileManager.default.destinationOfSymbolicLink(atPath: skillFile.path)) != nil,
              let children = try? FileManager.default.contentsOfDirectory(at: resolved, includingPropertiesForKeys: nil),
              children.count == 1,
              children.first?.lastPathComponent == "SKILL.md" else {
            throw SourceSkillImportError.changed
        }

        let targetRoot = skillFile.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent()
        guard targetRoot.path != resolved.path, let analysis = try? SkillAssetCopier.analyze(from: targetRoot) else {
            throw SourceSkillImportError.changed
        }
        return ResolvedInstalledSkill(url: targetRoot, analysis: analysis)
    }
}
