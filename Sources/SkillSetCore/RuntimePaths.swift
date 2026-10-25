import Foundation

public struct SkillSetRuntimePaths: Sendable {
    public let applicationSupportRoot: URL
    public let repositoryRoot: URL?

    public init(applicationSupportRoot: URL = ProjectStore.defaultRootURL, repositoryRoot: URL?) {
        self.applicationSupportRoot = applicationSupportRoot.standardizedFileURL
        self.repositoryRoot = repositoryRoot?.resolvingSymlinksInPath().standardizedFileURL
    }

    public var plansRoot: URL {
        applicationSupportRoot.appendingPathComponent("plans", isDirectory: true)
    }

    public var stagingRoot: URL {
        applicationSupportRoot.appendingPathComponent("staging", isDirectory: true)
    }

    public var operationsRoot: URL {
        applicationSupportRoot.appendingPathComponent("operations", isDirectory: true)
    }

    public var previewsRoot: URL {
        applicationSupportRoot.appendingPathComponent("cache/sources", isDirectory: true)
    }

    public var libraryRoot: URL {
        applicationSupportRoot.appendingPathComponent("skills", isDirectory: true)
    }

    public var sourcesRoot: URL {
        applicationSupportRoot.appendingPathComponent("sources", isDirectory: true)
    }

    /// 技能库是主目录下的扁平目录。文件在 sources，库内子项只保留技能名。
    public func makeLibraryStore(home: URL) -> SkillLibraryStore {
        SkillLibraryStore(
            libraryURL: home.appendingPathComponent(".agents/skills", isDirectory: true),
            sourcesURL: sourcesRoot,
            categoriesURL: applicationSupportRoot.appendingPathComponent("skill-categories.json")
        )
    }

    public var versionsRoot: URL { applicationSupportRoot.appendingPathComponent("versions", isDirectory: true) }

    /// 只复制旧状态，保留原目录供回退；临时目录全部成功后才发布。
    public func migrateLegacyState(from legacyRoot: URL? = nil) throws {
        let manager = FileManager.default
        let legacy = legacyRoot ?? manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Skill Set")
        guard legacyRoot != nil || applicationSupportRoot == ProjectStore.defaultRootURL else { return }
        guard !manager.fileExists(atPath: applicationSupportRoot.path), manager.fileExists(atPath: legacy.path) else { return }
        let temporary = applicationSupportRoot.deletingLastPathComponent().appendingPathComponent(".perch-migrate-\(UUID())")
        defer { try? manager.removeItem(at: temporary) }
        try manager.copyItem(at: legacy, to: temporary)
        for (old, new) in [("skill-library", "skills"), ("previews", "cache/sources")] {
            let source = temporary.appendingPathComponent(old)
            if manager.fileExists(atPath: source.path) {
                let destination = temporary.appendingPathComponent(new)
                try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.moveItem(at: source, to: destination)
            }
        }
        // 旧计划绑定旧 staging 绝对路径，升级后必须重新预览；操作历史仍保留。
        try? manager.removeItem(at: temporary.appendingPathComponent("plans"))
        try manager.moveItem(at: temporary, to: applicationSupportRoot)
    }

    public var repositoryCatalogURL: URL? {
        repositoryRoot?.appendingPathComponent("registry/catalog.json")
    }

    public static func detect(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        executableURL: URL? = Bundle.main.executableURL,
        currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
        bundleResourceURL: URL? = Bundle.main.resourceURL,
        applicationSupportRoot: URL = ProjectStore.defaultRootURL
    ) -> SkillSetRuntimePaths {
        var candidates: [URL] = []
        if let configured = environment["SKILLSET_REPOSITORY_ROOT"], !configured.isEmpty {
            candidates.append(URL(fileURLWithPath: configured, isDirectory: true))
        }
        // 发布包把可信技能快照放在 Resources/SkillSetLibrary，不能只沿可执行文件向上找仓库。
        if let bundleResourceURL {
            candidates.append(bundleResourceURL.appendingPathComponent("SkillSetLibrary", isDirectory: true))
        }
        if let executableURL {
            candidates.append(executableURL)
        }
        candidates.append(currentDirectoryURL)

        for candidate in candidates {
            if let root = repositoryRoot(startingAt: candidate) {
                return SkillSetRuntimePaths(applicationSupportRoot: applicationSupportRoot, repositoryRoot: root)
            }
        }
        return SkillSetRuntimePaths(applicationSupportRoot: applicationSupportRoot, repositoryRoot: nil)
    }

    private static func repositoryRoot(startingAt url: URL) -> URL? {
        var cursor = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        cursor = cursor.standardizedFileURL
        for _ in 0..<12 {
            let catalog = cursor.appendingPathComponent("registry/catalog.json")
            if FileManager.default.fileExists(atPath: catalog.path) {
                return cursor.resolvingSymlinksInPath().standardizedFileURL
            }
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path { break }
            cursor = parent
        }
        return nil
    }
}
