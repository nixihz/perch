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
        applicationSupportRoot.appendingPathComponent("previews", isDirectory: true)
    }

    public var libraryRoot: URL {
        applicationSupportRoot.appendingPathComponent("skill-library", isDirectory: true)
    }

    public var repositoryCatalogURL: URL? {
        repositoryRoot?.appendingPathComponent("registry/catalog.json")
    }

    public static func detect(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        executableURL: URL? = Bundle.main.executableURL,
        currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
        applicationSupportRoot: URL = ProjectStore.defaultRootURL
    ) -> SkillSetRuntimePaths {
        var candidates: [URL] = []
        if let configured = environment["SKILLSET_REPOSITORY_ROOT"], !configured.isEmpty {
            candidates.append(URL(fileURLWithPath: configured, isDirectory: true))
        }
        if let executableURL {
            // 安装包先使用随包快照；对象存储会写入，因此复制到本机状态目录，避免修改签名资源。
            let directory = executableURL.deletingLastPathComponent()
            for library in [
                directory.appendingPathComponent("SkillSetLibrary"),
                directory.deletingLastPathComponent().appendingPathComponent("Resources/SkillSetLibrary")
            ] {
                if let root = try? preparePackagedLibrary(library, stateRoot: applicationSupportRoot) {
                    candidates.append(root)
                    break
                }
            }
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

    private static func preparePackagedLibrary(_ library: URL, stateRoot: URL) throws -> URL? {
        let revision = try String(contentsOf: library.appendingPathComponent("package-revision"), encoding: .utf8)
        guard revision.count == 64, revision.allSatisfy({ $0.isHexDigit }) else { return nil }
        let manager = FileManager.default
        let parent = stateRoot.appendingPathComponent("bundled-libraries", isDirectory: true)
        let target = parent.appendingPathComponent(revision, isDirectory: true)
        if !manager.fileExists(atPath: target.path) {
            try manager.createDirectory(at: parent, withIntermediateDirectories: true)
            let temporary = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? manager.removeItem(at: temporary) }
            try manager.copyItem(at: library, to: temporary)
            do { try manager.moveItem(at: temporary, to: target) }
            catch { if !manager.fileExists(atPath: target.path) { throw error } }
        }
        return target
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
