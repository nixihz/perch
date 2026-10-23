import Foundation
import SkillSetCore

enum TemplateSortOrder: String, CaseIterable {
    case original, titleAscending, titleDescending

    var title: String {
        switch self {
        case .original: "默认顺序"
        case .titleAscending: "标题升序"
        case .titleDescending: "标题降序"
        }
    }

    func sorted(_ templates: [TemplateRecord], displayTitle: (TemplateRecord) -> String = { $0.title }) -> [TemplateRecord] {
        guard self != .original else { return templates }
        return templates.sorted { lhs, rhs in
            let comparison = displayTitle(lhs).localizedStandardCompare(displayTitle(rhs))
            // 同名时使用稳定标识打破平局，避免编辑后列表位置不确定。
            if comparison == .orderedSame { return lhs.id < rhs.id }
            return self == .titleAscending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }
}
