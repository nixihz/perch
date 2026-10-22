import SwiftUI

enum NavigationItem: String, CaseIterable, Identifiable {
    case globalConfiguration
    case projects
    case skills
    case mcp
    case plugins
    case sources
    case presets
    case templates
    case aiAccess
    case settings

    var id: String { rawValue }

    // 菜单、侧栏共用任务顺序；快捷键保留已有的 1 / 2 / 3 习惯。
    static let groups: [(title: String, items: [NavigationItem])] = [
        ("配置", [.globalConfiguration, .projects, .presets]),
        ("能力库", [.skills, .templates, .mcp]),
        ("来源", [.sources, .plugins]),
        ("对外接口", [.aiAccess])
    ]

    var keyboardShortcut: String {
        switch self {
        case .globalConfiguration: "9"
        case .projects: "1"
        case .skills: "2"
        case .mcp: "3"
        case .presets: "4"
        case .templates: "5"
        case .sources: "6"
        case .plugins: "7"
        case .aiAccess: "8"
        case .settings: ","
        }
    }

    @MainActor var title: String {
        switch self {
        case .globalConfiguration: L10n.tr("全局配置")
        case .projects: L10n.tr("项目")
        case .skills: L10n.tr("技能库")
        case .mcp: L10n.tr("MCP 服务")
        case .plugins: L10n.tr("插件来源")
        case .sources: L10n.tr("技能来源")
        case .presets: L10n.tr("预设")
        case .templates: L10n.tr("AGENTS 片段")
        case .aiAccess: L10n.tr("AI 接入")
        case .settings: L10n.tr("设置")
        }
    }

    @MainActor var subtitle: String {
        switch self {
        case .globalConfiguration: L10n.tr("管理当前用户的技能与规则")
        case .projects: L10n.tr("选择技能，预览并写入项目")
        case .skills: L10n.tr("查找、阅读和编辑技能")
        case .mcp: L10n.tr("保存连接，选择在哪里使用")
        case .plugins: L10n.tr("管理来源与扫描收录插件")
        case .sources: L10n.tr("从仓库发现更多技能")
        case .presets: L10n.tr("保存组合，用于不同项目")
        case .templates: L10n.tr("用于项目或全局的 AGENTS.md 片段")
        case .aiAccess: L10n.tr("通过 MCP 让 AI 调用栖集")
        case .settings: L10n.tr("外观与语言")
        }
    }

    var systemImage: String {
        switch self {
        case .globalConfiguration: "globe"
        case .projects: "square.stack.3d.up"
        case .skills: "wand.and.stars"
        case .mcp: "point.3.connected.trianglepath.dotted"
        case .plugins: "puzzlepiece.extension"
        case .sources: "arrow.down.doc"
        case .presets: "rectangle.3.group"
        case .templates: "text.badge.checkmark"
        case .aiAccess: "bubble.left.and.bubble.right"
        case .settings: "gearshape"
        }
    }
}

enum AgentHost: String, CaseIterable, Identifiable {
    case codex = "Codex"
    case claude = "Claude Code"

    var id: String { rawValue }
}

enum BadgeTone {
    case neutral
    case positive
    case warning
    case danger
    case accent

    var color: Color {
        switch self {
        case .neutral: .secondary
        case .positive: AppColor.positive
        case .warning: .orange
        case .danger: .red
        case .accent: AppColor.accentText
        }
    }
}
