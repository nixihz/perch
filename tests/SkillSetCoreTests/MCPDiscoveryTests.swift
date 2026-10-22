import Foundation
import Testing
@testable import SkillSetCore

struct MCPDiscoveryTests {
    @Test func hidesCodexRuntimeAndSubtablesWithoutRemovingConfiguration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config.toml")
        let original = """
        [mcp_servers.computer-use]
        command = "/Applications/Codex Computer Use.app/Contents/MacOS/client"
        [mcp_servers.node_repl]
        command = "node"
        [mcp_servers.node_repl.env]
        NODE_PATH = "/runtime"
        [mcp_servers.openaiDeveloperDocs]
        url = "https://developers.openai.com/mcp"
        [mcp_servers.context7]
        command = "context7"
        [mcp_servers.context7.env]
        API_KEY = "${API_KEY}"
        [profiles.work]
        command = "unrelated-command"
        """
        try original.write(to: config, atomically: true, encoding: .utf8)
        let manager = MCPConfigurationManager(
            projectRoot: nil, applicationSupportRoot: root.appendingPathComponent("state"),
            environment: ["CODEX_HOME": root.path], homeDirectory: root
        )
        let target = try #require(manager.targets().first { $0.host == .codex })
        let inspection = manager.inspect(target)
        #expect(inspection.servers.map(\.name) == ["context7", "openaiDeveloperDocs"])
        #expect(inspection.servers.first?.command == "context7")
        #expect(inspection.issues.count == 2)
        #expect(try String(contentsOf: config, encoding: .utf8) == original)
        // 隐藏系统组件不能绕过原配置的冲突保护。
        #expect(throws: MCPConfigurationError.configConflict("computer-use")) {
            try manager.makeEdit(target: target, draft: MCPConfigurationDraft(
                name: "computer-use", host: .codex, scope: .user, transport: "stdio",
                commandOrURL: "replacement"
            ))
        }
    }
}
