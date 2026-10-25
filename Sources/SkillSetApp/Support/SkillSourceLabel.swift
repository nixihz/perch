import Foundation
import SkillSetCore

enum SkillSourceLabel {
    static func filterKey(sourceID: String, origin: String?) -> String {
        // link/copy 表示存放方式，多个仓库会共用；筛选必须保留完整来源地址以免串组。
        if sourceID == SkillLibraryStore.sourceID { return sourceID }
        if let origin, !origin.isEmpty { return "origin:\(origin)" }
        return sourceID
    }

    static func repository(_ origin: String) -> String {
        // 本地目录保留完整路径，避免不同目录被显示成同一个来源。
        guard !origin.hasPrefix("/"), !origin.hasPrefix("file:") else { return origin }
        let path: String
        if let components = URLComponents(string: origin), components.host != nil {
            path = components.path
        } else if origin.hasPrefix("git@"), let separator = origin.firstIndex(of: ":") {
            path = String(origin[origin.index(after: separator)...])
        } else {
            return origin
        }
        var name = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if name.hasSuffix(".git") { name.removeLast(4) }
        return name.isEmpty ? origin : name
    }

    static func title(sourceID: String, origin: String?, registeredTitle: String?) -> String {
        // custom 是当前存放来源，导入时保留的原始路径只作来源证据。
        if sourceID == SkillLibraryStore.sourceID { return SkillLibraryStore.sourceID }
        if let origin, !origin.isEmpty { return repository(origin) }
        if let registeredTitle, !registeredTitle.isEmpty { return registeredTitle }
        return sourceID
    }
}
