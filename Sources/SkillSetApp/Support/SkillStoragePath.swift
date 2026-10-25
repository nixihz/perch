import Foundation
import SkillSetCore

/// 技能实体的存放位置。技能库目录只保留软链，展示时必须指向实体所在的位置。
enum SkillStoragePath {
    /// 优先用库扫描出的真实路径；不在本机库里的条目回退到目录里的相对路径。
    static func display(_ entry: SkillEntry, storageURLs: [String: URL]) -> String {
        if let url = storageURLs[entry.id] { return url.standardizedFileURL.path }
        return entry.path
    }
}
