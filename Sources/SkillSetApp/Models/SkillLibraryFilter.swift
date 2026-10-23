import Foundation
import SkillSetCore

enum SkillLibraryFilter: String, CaseIterable {
    case all, duplicateNames, identicalContent, blocked

    var title: String {
        switch self {
        case .all: "全部技能"
        case .duplicateNames: "重名技能"
        case .identicalContent: "同内容技能"
        case .blocked: "暂不可用"
        }
    }
}

/// 重复关系基于整个可见技能库计算，避免搜索或来源筛选隐藏另一条后丢失关系。
struct SkillLibraryIndex {
    private let names: [String: [SkillEntry]]
    private let hashes: [String: [SkillEntry]]

    init(entries: [SkillEntry]) {
        names = Dictionary(grouping: entries, by: Self.nameKey)
        hashes = Dictionary(grouping: entries.filter { !$0.contentHash.isEmpty }, by: \.contentHash)
    }

    static func nameKey(_ skill: SkillEntry) -> String {
        let name = skill.declaredName.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name.isEmpty ? skill.slug.trimmingCharacters(in: .whitespacesAndNewlines) : name).lowercased()
    }

    static func hasSameContent(_ lhs: SkillEntry, _ rhs: SkillEntry) -> Bool? {
        guard !lhs.contentHash.isEmpty, !rhs.contentHash.isEmpty else { return nil }
        return lhs.contentHash == rhs.contentHash
    }

    func namesakes(of skill: SkillEntry) -> [SkillEntry] {
        (names[Self.nameKey(skill)] ?? []).filter { $0.id != skill.id }
    }

    func matches(_ skill: SkillEntry, filter: SkillLibraryFilter) -> Bool {
        switch filter {
        case .all: true
        case .duplicateNames: (names[Self.nameKey(skill)]?.count ?? 0) > 1
        case .identicalContent: (hashes[skill.contentHash]?.count ?? 0) > 1
        case .blocked: skill.isBlocked
        }
    }
}
