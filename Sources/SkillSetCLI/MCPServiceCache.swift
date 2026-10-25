import Darwin
import Foundation
import SkillSetCore

/// 监视完整技能包的元数据，避免附属脚本变化后继续使用旧指纹；缓存检查不读取文件正文。
struct MCPLibraryGeneration: Equatable {
    var files: [FileStamp]
    var isComplete: Bool

    struct FileStamp: Equatable {
        var path: String
        var exists: Bool
        var device: UInt64
        var inode: UInt64
        var size: UInt64
        var modifiedSeconds: Int
        var modifiedNanoseconds: Int
        var mode: UInt16 = 0
        var changedSeconds: Int = 0
        var changedNanoseconds: Int = 0

        init(url: URL) {
            path = url.path
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
            mode = info.st_mode
            changedSeconds = Int(info.st_ctimespec.tv_sec)
            changedNanoseconds = Int(info.st_ctimespec.tv_nsec)
        }
    }

    static func capture(paths: SkillSetRuntimePaths) -> MCPLibraryGeneration {
        let watched = watchedURLs(paths: paths)
        return MCPLibraryGeneration(files: watched.urls.map(FileStamp.init(url:)), isComplete: watched.isComplete)
    }

    /// 与 `AppSnapshot.load` 和本机库实际读取的文件对齐。未启用仓库技能库时，catalog 不进入快照，不必监视。
    private static func watchedURLs(paths: SkillSetRuntimePaths) -> (urls: [URL], isComplete: Bool) {
        let root = paths.applicationSupportRoot
        let libraryRoot = paths.libraryDirectoryURL
        var urls = [
            libraryRoot,
            root.appendingPathComponent("skill-categories.json"),
            root.appendingPathComponent("presets.json"),
            root.appendingPathComponent("templates.json")
        ]
        let manager = FileManager.default
        var isComplete = true
        // 库存里只有软链，实体在 sources/custom 或来源检出。两处都要监视，否则内容变化不会让快照失效。
        for packageRoot in [libraryRoot, paths.sourcesRoot.appendingPathComponent("custom", isDirectory: true)] {
            if manager.fileExists(atPath: packageRoot.path) {
                let items = try? manager.contentsOfDirectory(at: packageRoot, includingPropertiesForKeys: nil)
                if items == nil { isComplete = false }
                for item in items ?? [] where !item.lastPathComponent.hasPrefix(".") {
                    urls.append(item)
                    let package = item.resolvingSymlinksInPath().standardizedFileURL
                    urls.append(package)
                    var isDirectory: ObjCBool = false
                    guard manager.fileExists(atPath: package.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
                    // 枚举器不跟随包内软链；对软链调用 skipDescendants 会漏掉后续实体目录。
                    guard let enumerator = manager.enumerator(at: package, includingPropertiesForKeys: nil,
                        options: [], errorHandler: { _, _ in isComplete = false; return false }) else {
                        isComplete = false
                        continue
                    }
                    var visited = 0
                    while let file = enumerator.nextObject() as? URL {
                        visited += 1
                        guard visited <= 12_000 else { isComplete = false; break }
                        urls.append(file.standardizedFileURL)
                        if enumerator.level > 64 {
                            isComplete = false
                            enumerator.skipDescendants()
                        }
                    }
                }
            }
        }
        if SkillSetService.usesRepositoryLibrary, let repository = paths.repositoryRoot {
            urls.append(repository.appendingPathComponent("registry/catalog.json"))
            urls.append(repository.appendingPathComponent("registry/sources.json"))
            for name in ["personal-base", "frontend-workbench", "research-first"] {
                urls.append(repository.appendingPathComponent("presets/\(name).json"))
            }
            for name in ["base-zh", "engineering", "ui-craft"] {
                urls.append(repository.appendingPathComponent("templates/agents/\(name).md"))
            }
        }
        return (urls.sorted { $0.path < $1.path }, isComplete)
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
        if now.isComplete, now == generation { return service }
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
