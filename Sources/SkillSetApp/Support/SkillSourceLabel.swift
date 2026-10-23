import Foundation

enum SkillSourceLabel {
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
        if let origin, !origin.isEmpty { return repository(origin) }
        if let registeredTitle, !registeredTitle.isEmpty { return registeredTitle }
        return sourceID
    }
}
