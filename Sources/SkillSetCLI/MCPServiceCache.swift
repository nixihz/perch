import Foundation
import SkillSetCore

/// 进程内复用最近一次服务快照。文件身份变化后才重新解析技能库、片段和预设。
struct MCPServiceCache {
    let paths: SkillSetRuntimePaths
    private(set) var service: SkillSetService
    private(set) var generation: SkillLibraryGeneration

    init(service: SkillSetService) {
        paths = service.paths
        self.service = service
        generation = SkillLibraryGeneration.capture(paths: service.paths)
    }

    mutating func current() throws -> SkillSetService {
        let now = SkillLibraryGeneration.capture(paths: paths)
        if now.isComplete, now == generation { return service }
        return try reload()
    }

    mutating func reload() throws -> SkillSetService {
        let before = SkillLibraryGeneration.capture(paths: paths)
        var loaded = try SkillSetService(paths: paths)
        var after = SkillLibraryGeneration.capture(paths: paths)
        // 加载期间文件又被替换时再读一次，避免把旧快照标成新身份。
        if before != after {
            loaded = try SkillSetService(paths: paths)
            after = SkillLibraryGeneration.capture(paths: paths)
        }
        service = loaded
        generation = after
        return loaded
    }
}
