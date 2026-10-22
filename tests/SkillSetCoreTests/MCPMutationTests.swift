import Foundation
import Testing
@testable import SkillSetCore

struct MCPMutationTests {
    @Test func codexEditsPreserveSecretsAndDeletionKeepsNextTable() throws {
        try fixture(host: .codex, text: """
        # 用户设置
        [mcp_servers.demo]
        command = "old"
        args = ["one two"]
        enabled = false
        [mcp_servers.demo.env]
        API_KEY = "private-value"
        [mcp_servers.other]
        command = "other"
        """) { manager, target, config in
            let server = try #require(manager.inspect(target).servers.first { $0.name == "demo" })
            let draft = MCPConfigurationDraft(name: "demo", host: .codex, scope: .user,
                commandOrURL: "new")
            let edit = try manager.makeExistingEdit(target: target, server: server, draft: draft)
            let updated = String(decoding: edit.content, as: UTF8.self)
            #expect(updated.contains("command = \"new\""))
            #expect(updated.contains("args = [\"one two\"]"))
            #expect(updated.contains("API_KEY = \"private-value\""))
            #expect(updated.contains("enabled = false"))
            #expect(try String(contentsOf: config, encoding: .utf8).contains("command = \"old\""))
            let removal = try manager.makeExistingEdit(target: target, server: server, draft: nil)
            let removed = String(decoding: removal.content, as: UTF8.self)
            #expect(!removed.contains("mcp_servers.demo"))
            #expect(removed.contains("[mcp_servers.other]\ncommand = \"other\""))
            #expect(removed.contains("# 用户设置"))
            try edit.content.write(to: config)
            #expect(throws: MCPConfigurationError.configConflict("demo")) {
                try manager.makeExistingEdit(target: target, server: server, draft: nil)
            }
        }
    }

    @Test func claudeEditsAndDeletesOnlySelectedNode() throws {
        try fixture(host: .claudeCode, text: """
        {"theme":"dark","mcpServers":{"demo":{"command":"old","args":["one two"],"env":{"KEY":"private-value"},"custom":true},"other":{"command":"other"}}}
        """) { manager, target, _ in
            let server = try #require(manager.inspect(target).servers.first { $0.name == "demo" })
            let edit = try manager.makeExistingEdit(target: target, server: server,
                draft: MCPConfigurationDraft(name: "demo", host: .claudeCode, scope: .user,
                    commandOrURL: "new", args: ["new argument"]), replaceArguments: true)
            let object = try #require(JSONSerialization.jsonObject(with: edit.content) as? [String: Any])
            let nodes = try #require(object["mcpServers"] as? [String: [String: Any]])
            #expect(nodes["demo"]?["command"] as? String == "new")
            #expect(nodes["demo"]?["args"] as? [String] == ["new argument"])
            #expect(nodes["demo"]?["env"] as? [String: String] == ["KEY": "private-value"])
            #expect(nodes["demo"]?["custom"] as? Bool == true)
            let removal = try manager.makeExistingEdit(target: target, server: server, draft: nil)
            let removed = try #require(JSONSerialization.jsonObject(with: removal.content) as? [String: Any])
            let remaining = try #require(removed["mcpServers"] as? [String: Any])
            #expect(Set(remaining.keys) == ["other"])
            #expect(removed["theme"] as? String == "dark")
        }
    }

    @Test func rejectsUnsafeMultilineReplacementAndPreservesNextManagedBlock() throws {
        try fixture(host: .codex, text: """
        [mcp_servers.demo]
        command = "old"
        args = [
          "one",
          "two"
        ]
        # skillset:begin mcp name=other schema=1
        [mcp_servers.other]
        command = "other"
        # skillset:end mcp name=other
        """) { manager, target, config in
            let server = try #require(manager.inspect(target).servers.first { $0.name == "demo" })
            #expect(throws: (any Error).self) {
                try manager.makeExistingEdit(target: target, server: server,
                    draft: MCPConfigurationDraft(name: "demo", scope: .user, commandOrURL: "new"),
                    replaceArguments: true)
            }
            let removal = try manager.makeExistingEdit(target: target, server: server, draft: nil)
            try removal.content.write(to: config)
            let remaining = manager.inspect(target)
            #expect(remaining.servers.map(\.name) == ["other"])
            #expect(remaining.servers.first?.managed == true)
        }
    }

    @Test func redactedConnectionCanBeExplicitlyReplaced() throws {
        try fixture(host: .claudeCode, text: #"{"mcpServers":{"demo":{"type":"http","url":"https://example.test?token=private-value"}}}"#) { manager, target, _ in
            let server = try #require(manager.inspect(target).servers.first)
            #expect(server.command == "<已隐藏>")
            let edit = try manager.makeExistingEdit(target: target, server: server,
                draft: MCPConfigurationDraft(name: "demo", host: .claudeCode, scope: .user,
                    transport: "streamable-http", commandOrURL: "https://replacement.test"))
            #expect(String(decoding: edit.content, as: UTF8.self).contains("https://replacement.test"))
        }
    }

    @Test func existingServicePlansRequireApprovalAndRemoveOwnership() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = root.appendingPathComponent("project")
        let state = root.appendingPathComponent("state")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = project.appendingPathComponent(".mcp.json")
        try #"{"mcpServers":{"demo":{"command":"old","env":{"KEY":"private-value"}},"other":{"command":"other"}}}"#
            .write(to: config, atomically: true, encoding: .utf8)
        let service = try SkillSetService(paths: SkillSetRuntimePaths(applicationSupportRoot: state, repositoryRoot: nil))
        let registration = try ProjectStore(rootURL: state).register(path: project, name: "MCP")
        let observed = try #require(service.mcpConfigurations(projectID: registration.id)
            .first { $0.scope == .project }?.servers.first { $0.name == "demo" })
        let draft = MCPConfigurationDraft(name: "demo", host: .claudeCode, scope: .project, commandOrURL: "new")
        let edit = try service.makeMCPConfigPlan(projectID: registration.id, draft: draft, existingServer: observed)
        #expect(throws: DeploymentPlanStoreError.approvalRequired(edit.id.uuidString)) {
            try service.apply(planID: edit.id, digest: edit.plan.digest)
        }
        #expect(try String(contentsOf: config, encoding: .utf8).contains("old"))
        _ = try service.approve(planID: edit.id, digest: edit.plan.digest)
        _ = try service.apply(planID: edit.id, digest: edit.plan.digest)
        let updated = try #require(service.mcpConfigurations(projectID: registration.id)
            .first { $0.scope == .project }?.servers.first { $0.name == "demo" })
        #expect(updated.command == "new")
        #expect(updated.managed)
        let removal = try service.makeMCPConfigPlan(projectID: registration.id, draft: draft,
            existingServer: updated, remove: true)
        #expect(removal.plan.changes.first?.unifiedDiff.contains("删除") == true)
        #expect(throws: DeploymentPlanStoreError.approvalRequired(removal.id.uuidString)) {
            try service.apply(planID: removal.id, digest: removal.plan.digest)
        }
        _ = try service.approve(planID: removal.id, digest: removal.plan.digest)
        _ = try service.apply(planID: removal.id, digest: removal.plan.digest)
        let remaining = try #require(service.mcpConfigurations(projectID: registration.id).first { $0.scope == .project })
        #expect(remaining.servers.map(\.name) == ["other"])
        #expect(!ManagedMCPRegistry(rootURL: state).isManaged(configPath: config.path, serverName: "demo"))
    }

    private func fixture(host: MCPHost, text: String,
        body: (MCPConfigurationManager, MCPConfigurationTarget, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent(host == .codex ? "config.toml" : ".claude.json")
        try text.write(to: config, atomically: true, encoding: .utf8)
        let manager = MCPConfigurationManager(projectRoot: nil,
            applicationSupportRoot: root.appendingPathComponent("state"),
            environment: ["CODEX_HOME": root.path], homeDirectory: root)
        let target = try #require(manager.targets().first { $0.host == host })
        try body(manager, target, config)
    }
}
