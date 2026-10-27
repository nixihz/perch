import Foundation

/// 共享技能目录没有对应的 MCP、规则或插件宿主，必须与工具类型分开。
public enum SkillConfigurationTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case agents
    case codex
    case claudeCode = "claude-code"

    public var id: String { rawValue }

    public init(_ host: MCPHost) {
        self = host == .codex ? .codex : .claudeCode
    }

    public var mcpHost: MCPHost? {
        switch self {
        case .agents: nil
        case .codex: .codex
        case .claudeCode: .claudeCode
        }
    }

    public var displayName: String {
        switch self {
        case .agents: "Agents"
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        }
    }
}
