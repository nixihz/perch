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
    /// 只读发现；一级链接可作为安装入口，包内链接仍由资产校验拒绝。
    public func scanInstalledSkills(additionalRoots: [URL] = []) throws -> [InstalledSkillObservation] {
        let locations = globalConfiguration.locations
        let roots = [locations.configuredSkillsRoot(.codex), locations.codexRoot.appendingPathComponent("skills"),
                     locations.configuredSkillsRoot(.claudeCode)] + additionalRoots
        var seen = Set<String>()
        var seenEntries = Set<String>()
        var result: [InstalledSkillObservation] = []
        let fm = FileManager.default
        let known = Set(try SkillLibraryStore(rootURL: paths.libraryRoot).load().records.compactMap { $0.sourceOrigin?.contentHash })
        for root in roots where seen.insert(root.standardizedFileURL.path).inserted {
            guard fm.fileExists(atPath: root.path) else { continue }
            let entries = fm.fileExists(atPath: root.appendingPathComponent("SKILL.md").path)
                ? [root] : try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            for entry in entries.sorted(by: { $0.path < $1.path }) {
                let child = entries.count == 1 && entry.path == root.path ? root : root.appendingPathComponent(entry.lastPathComponent)
                guard seenEntries.insert(child.path).inserted else { continue }
                let resolved = child.resolvingSymlinksInPath().standardizedFileURL
                let linked = (try? fm.destinationOfSymbolicLink(atPath: child.path)) != nil
                guard fm.fileExists(atPath: resolved.appendingPathComponent("SKILL.md").path) || linked else { continue }
                do {
                    let hash = try SkillAssetCopier.analyze(from: resolved).contentHash
                    let managed = linked && (try? ManagedSkillLink.hash(child, versionsRoot: paths.versionsRoot)) != nil
                    result.append(.init(path: child.path, resolvedPath: resolved.path, contentHash: hash, managed: managed, collected: known.contains(hash), issue: nil))
                } catch {
                    result.append(.init(path: child.path, resolvedPath: resolved.path, contentHash: nil, managed: false, collected: false,
                                        issue: "无法读取完整技能包，请检查断链、包内软链和文件权限。"))
                }
            }
        }
        return result
    }

    /// 保留发现证据，发布独立本地来源；不移动原件，不修改宿主配置。
    public func importInstalledSkills(_ selection: [InstalledSkillObservation]) throws -> SourcePreviewRecord {
        guard !selection.isEmpty, selection.allSatisfy(\.canImport), Set(selection.map(\.path)).count == selection.count else {
            throw SourceSkillImportError.changed
        }
        let fm = FileManager.default
        let root = paths.applicationSupportRoot.appendingPathComponent("sources/local-imports/\(UUID())")
        var published = false
        defer { if !published { try? fm.removeItem(at: root) } }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var seen = Set<String>()
        for item in selection {
            let original = URL(fileURLWithPath: item.path)
            guard original.resolvingSymlinksInPath().standardizedFileURL.path == item.resolvedPath,
                  try SkillAssetCopier.analyze(from: original.resolvingSymlinksInPath()).contentHash == item.contentHash else {
                throw SourceSkillImportError.changed
            }
            guard seen.insert(item.contentHash!).inserted else { continue }
            // 哈希目录区分同名异内容，末级目录保留技能 slug。
            let destination = root.appendingPathComponent(item.contentHash!).appendingPathComponent(original.lastPathComponent)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let copied = try SkillAssetCopier.copy(from: original.resolvingSymlinksInPath(), to: destination)
            guard copied.contentHash == item.contentHash else { throw SourceSkillImportError.changed }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(selection).write(to: root.appendingPathComponent("installed-origins.json"), options: .atomic)
        try Data(ISO8601DateFormatter().string(from: Date()).utf8).write(to: root.appendingPathComponent("scanned-at.txt"))
        let record = try previewSource(urlString: root.path)
        published = true
        return record
    }
}
