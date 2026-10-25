import Darwin
import Foundation
import SkillSetCore

/// 技能索引、片段和预设的文件身份。这些文件决定服务快照；项目、计划和 MCP 配置仍在每次调用时读盘。
struct MCPLibraryGeneration: Equatable {
    var files: [FileStamp]

    struct FileStamp: Equatable {
        var exists: Bool
        var device: UInt64
        var inode: UInt64
        var size: UInt64
        var modifiedSeconds: Int
        var modifiedNanoseconds: Int

        init(url: URL) {
            var info = Darwin.stat()
            // 使用 lstat，避免和 Darwin 的 stat 类型重名；路径被替换时 inode 或 mtime 会变。
            let result = url.withUnsafeFileSystemRepresentation { pointer -> Int32 in
                guard let pointer else { return -1 }
                return lstat(pointer, &info)
            }
            guard result == 0 else {
                exists = false
                device = 0
                inode = 0
                size = 0
                modifiedSeconds = 0
                modifiedNanoseconds = 0
                return
            }
            exists = true
            device = UInt64(info.st_dev)
            inode = UInt64(info.st_ino)
            size = UInt64(info.st_size)
            modifiedSeconds = Int(info.st_mtimespec.tv_sec)
            modifiedNanoseconds = Int(info.st_mtimespec.tv_nsec)
        }
    }

    static func capture(paths: SkillSetRuntimePaths) -> MCPLibraryGeneration {
        MCPLibraryGeneration(files: watchedURLs(paths: paths).map(FileStamp.init(url:)))
    }

    /// 与 `AppSnapshot.load` 和本机库实际读取的文件对齐。未启用仓库技能库时，catalog 不进入快照，不必监视。
    private static func watchedURLs(paths: SkillSetRuntimePaths) -> [URL] {
        let root = paths.applicationSupportRoot
        let home = GlobalConfigurationLocations.detect(stateRoot: root).home
        let libraryRoot = home.appendingPathComponent(".agents/skills", isDirectory: true)
        var urls = [
            libraryRoot,
            paths.sourcesRoot.appendingPathComponent("index.json"),
            root.appendingPathComponent("skill-categories.json"),
            root.appendingPathComponent("presets.json"),
            root.appendingPathComponent("templates.json")
        ]
        if let items = try? FileManager.default.contentsOfDirectory(at: libraryRoot, includingPropertiesForKeys: nil) {
            for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where !item.lastPathComponent.hasPrefix(".") {
                urls.append(item)
                urls.append(item.appendingPathComponent("SKILL.md"))
            }
        }
        guard SkillSetService.usesRepositoryLibrary, let repository = paths.repositoryRoot else { return urls }
        urls.append(repository.appendingPathComponent("registry/catalog.json"))
        urls.append(repository.appendingPathComponent("registry/sources.json"))
        for name in ["personal-base", "frontend-workbench", "research-first"] {
            urls.append(repository.appendingPathComponent("presets/\(name).json"))
        }
        for name in ["base-zh", "engineering", "ui-craft"] {
            urls.append(repository.appendingPathComponent("templates/agents/\(name).md"))
        }
        return urls
    }
}

/// 进程内复用最近一次服务快照。文件身份变化后才重新解析技能库、片段和预设。
struct MCPServiceCache {
    let paths: SkillSetRuntimePaths
    private(set) var service: SkillSetService
    private(set) var generation: MCPLibraryGeneration

    init(service: SkillSetService) {
        paths = service.paths
        self.service = service
        generation = MCPLibraryGeneration.capture(paths: service.paths)
    }

    mutating func current() throws -> SkillSetService {
        let now = MCPLibraryGeneration.capture(paths: paths)
        if now == generation { return service }
        return try reload()
    }

    mutating func reload() throws -> SkillSetService {
        let before = MCPLibraryGeneration.capture(paths: paths)
        var loaded = try SkillSetService(paths: paths)
        var after = MCPLibraryGeneration.capture(paths: paths)
        // 加载期间文件又被替换时再读一次，避免把旧快照标成新身份。
        if before != after {
            loaded = try SkillSetService(paths: paths)
            after = MCPLibraryGeneration.capture(paths: paths)
        }
        service = loaded
        generation = after
        return loaded
    }
}
