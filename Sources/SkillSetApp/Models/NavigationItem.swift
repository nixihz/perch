import SwiftUI

enum NavigationItem: String, CaseIterable, Identifiable {
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

    @MainActor var title: String {
        switch self {
        case .projects: L10n.tr("项目")
        case .skills: L10n.tr("技能库")
        case .mcp: L10n.tr("MCP 服务")
        case .plugins: L10n.tr("插件")
        case .sources: L10n.tr("来源")
        case .presets: L10n.tr("预设")
        case .templates: L10n.tr("指令模板")
        case .aiAccess: L10n.tr("AI 接入")
        case .settings: L10n.tr("设置")
        }
    }

    @MainActor var subtitle: String {
        switch self {
        case .projects: L10n.tr("为项目选择技能")
        case .skills: L10n.tr("查看技能与来源")
        case .mcp: L10n.tr("管理 Codex 与 Claude Code 连接")
        case .plugins: L10n.tr("查看插件与运行风险")
        case .sources: L10n.tr("可追溯的上游")
        case .presets: L10n.tr("可复现的组合")
        case .templates: L10n.tr("AGENTS / CLAUDE 片段")
        case .aiAccess: L10n.tr("本应用提供的 MCP")
        case .settings: L10n.tr("外观与语言")
        }
    }

    var systemImage: String {
        switch self {
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
