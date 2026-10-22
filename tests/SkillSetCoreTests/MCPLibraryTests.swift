import Foundation
import Testing
@testable import SkillSetCore

struct MCPLibraryTests {
    @Test func savedConnectionsAndSelectionsDoNotWriteHostFilesAndSurviveReload() throws {
        try fixture { service, library, projectID, project, home in
            let entry = try library.save(MCPLibraryEntry(name: "docs", commandOrURL: "npx", args: ["-y", "@example/docs", "two words"], envKeys: ["API_KEY"]))
            try library.saveSelection([entry.id], host: .claudeCode, projectID: projectID)
            try library.saveSelection([], host: .codex, projectID: nil)
            let reopened = MCPLibraryStore(rootURL: service.paths.applicationSupportRoot)
            #expect(try reopened.entries().first?.args == ["-y", "@example/docs", "two words"])
            #expect(try reopened.selectedIDs(host: .claudeCode, projectID: projectID) == [entry.id])
            #expect(try reopened.selectedIDs(host: .claudeCode, projectID: nil).isEmpty)
            #expect(!FileManager.default.fileExists(atPath: project.appendingPathComponent(".mcp.json").path))
            #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude.json").path))
        }
    }

    @Test func oneSelectionPlanAppliesMultipleConnectionsThenUpdatesAndRemovesOnlyItsNodes() throws {
        try fixture { service, library, projectID, project, _ in
            let config = project.appendingPathComponent(".mcp.json")
            let original = #"{"theme":"dark","mcpServers":{"other":{"command":"keep","env":{"KEY":"private-value"}}}}"#
            try original.write(to: config, atomically: true, encoding: .utf8)
            let first = try library.save(MCPLibraryEntry(name: "docs", commandOrURL: "docs", args: ["two words"], envKeys: ["API_KEY"]))
            let second = try library.save(MCPLibraryEntry(name: "search", transport: "streamable-http", commandOrURL: "https://example.test/mcp"))
            try library.saveSelection([first.id, second.id], host: .claudeCode, projectID: projectID)
            let plan = try service.makeMCPLibraryPlan(host: .claudeCode, projectID: projectID)
            #expect(try String(contentsOf: config, encoding: .utf8) == original)
            #expect(throws: (any Error).self) { try service.apply(planID: plan.id, digest: plan.plan.digest) }
            try apply(plan, service: service)
            var object = try json(config)
            var nodes = try #require(object["mcpServers"] as? [String: [String: Any]])
            #expect(nodes["docs"]?["args"] as? [String] == ["two words"])
            #expect(nodes["docs"]?["env"] as? [String: String] == ["API_KEY": "${API_KEY}"])
            #expect(nodes["search"]?["type"] as? String == "http")
            #expect(nodes["other"]?["env"] as? [String: String] == ["KEY": "private-value"])
            #expect(throws: DeploymentError.noChanges) { try service.makeMCPLibraryPlan(host: .claudeCode, projectID: projectID) }
            var edited = first
            edited.commandOrURL = "new-docs"
            _ = try library.save(edited)
            try library.remove(second.id)
            try library.saveSelection([first.id], host: .claudeCode, projectID: projectID)
            try apply(service.makeMCPLibraryPlan(host: .claudeCode, projectID: projectID), service: service)
            object = try json(config)
            nodes = try #require(object["mcpServers"] as? [String: [String: Any]])
            #expect(Set(nodes.keys) == ["docs", "other"])
            #expect(nodes["docs"]?["command"] as? String == "new-docs")
            #expect(object["theme"] as? String == "dark")
            #expect(!ManagedMCPRegistry(rootURL: service.paths.applicationSupportRoot).isManaged(configPath: config.path, serverName: "search"))
            try library.saveSelection([], host: .claudeCode, projectID: projectID)
            try apply(service.makeMCPLibraryPlan(host: .claudeCode, projectID: projectID), service: service)
            let remaining = try #require(try json(config)["mcpServers"] as? [String: Any])
            #expect(Set(remaining.keys) == ["other"])
        }
    }

    @Test func externalConflictsDriftAndStalePlansAreRejectedWithoutWrites() throws {
        try fixture { service, library, projectID, project, _ in
            let config = project.appendingPathComponent(".mcp.json")
            let entry = try library.save(MCPLibraryEntry(name: "docs", commandOrURL: "docs"))
            try library.saveSelection([entry.id], host: .claudeCode, projectID: projectID)
            try #"{"mcpServers":{"docs":{"command":"external"}}}"#.write(to: config, atomically: true, encoding: .utf8)
            #expect(throws: MCPConfigurationError.configConflict("docs")) { try service.makeMCPLibraryPlan(host: .claudeCode, projectID: projectID) }
            try FileManager.default.removeItem(at: config)
            let stale = try service.makeMCPLibraryPlan(host: .claudeCode, projectID: projectID)
            try "{}".write(to: config, atomically: true, encoding: .utf8)
            _ = try service.approve(planID: stale.id, digest: stale.plan.digest)
            #expect(throws: (any Error).self) { try service.apply(planID: stale.id, digest: stale.plan.digest) }
            #expect(try String(contentsOf: config, encoding: .utf8) == "{}")
            try apply(service.makeMCPLibraryPlan(host: .claudeCode, projectID: projectID), service: service)
            let modified = #"{"mcpServers":{"docs":{"command":"user-edited","custom":true}}}"#
            try modified.write(to: config, atomically: true, encoding: .utf8)
            try library.saveSelection([], host: .claudeCode, projectID: projectID)
            #expect(throws: (any Error).self) { try service.makeMCPLibraryPlan(host: .claudeCode, projectID: projectID) }
            #expect(try String(contentsOf: config, encoding: .utf8) == modified)
        }
    }

    @Test func globalTargetsReuseOneEntryAndCodexProjectIsRejected() throws {
        try fixture { service, library, projectID, _, home in
            let entry = try library.save(MCPLibraryEntry(name: "docs", commandOrURL: "docs"))
            for host in MCPHost.allCases {
                try library.saveSelection([entry.id], host: host, projectID: nil)
                try apply(service.makeMCPLibraryPlan(host: host), service: service)
                #expect(throws: DeploymentError.noChanges) { try service.makeMCPLibraryPlan(host: host) }
            }
            #expect(try String(contentsOf: home.appendingPathComponent(".codex/config.toml"), encoding: .utf8).contains("[mcp_servers.docs]"))
            #expect(try json(home.appendingPathComponent(".claude.json"))["mcpServers"] != nil)
            try library.saveSelection([entry.id], host: .codex, projectID: projectID)
            #expect(throws: MCPConfigurationError.unsupportedTarget("codex/project")) { try service.makeMCPLibraryPlan(host: .codex, projectID: projectID) }
            try library.saveSelection([], host: .codex, projectID: nil)
            try apply(service.makeMCPLibraryPlan(host: .codex), service: service)
            #expect(!String(decoding: try Data(contentsOf: home.appendingPathComponent(".codex/config.toml")), as: UTF8.self).contains("mcp_servers.docs"))
            #expect(try json(home.appendingPathComponent(".claude.json"))["mcpServers"] != nil)
        }
    }

    @Test func scanImportsArgumentsAndVariableNamesButNeverCredentialValuesOrUnsupportedArguments() throws {
        try fixture { service, library, _, project, home in
            let claude = #"{"mcpServers":{"docs":{"command":"npx","args":["-y","@example/docs","two words"],"env":{"API_KEY":"private-value"}},"unsafe":{"command":"run","args":["--token","do-not-import"]}}}"#
            try claude.write(to: home.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)
            let codex = """
            [mcp_servers.codexdocs]
            command = "npx"
            args = [
              "-y", # 参数注释
              '@example/codex',
              "two words",
            ]
            [mcp_servers.codexdocs.env]
            CUSTOM_KEY = "do-not-copy"
            [mcp_servers.broken]
            command = "run"
            args = [1, 2]
            """
            try codex.write(to: home.appendingPathComponent(".codex/config.toml"), atomically: true, encoding: .utf8)
            try #"{"mcpServers":{"projectdocs":{"url":"https://example.test/mcp"}}}"#.write(to: project.appendingPathComponent(".mcp.json"), atomically: true, encoding: .utf8)
            let candidates = try service.scanMCPLibrary()
            #expect(candidates.count == 5)
            #expect(candidates.first { $0.name == "unsafe" }?.entry == nil)
            #expect(candidates.first { $0.name == "broken" }?.entry == nil)
            let selected = candidates.compactMap(\.entry)
            #expect(selected.first { $0.name == "codexdocs" }?.args == ["-y", "@example/codex", "two words"])
            #expect(selected.first { $0.name == "codexdocs" }?.envKeys == ["CUSTOM_KEY"])
            try library.importEntries(selected)
            let data = try String(contentsOf: library.documentURL, encoding: .utf8)
            for secret in ["private-value", "do-not-import", "do-not-copy"] { #expect(!data.contains(secret)) }
            #expect(try String(contentsOf: home.appendingPathComponent(".claude.json"), encoding: .utf8) == claude)
            #expect(try String(contentsOf: home.appendingPathComponent(".codex/config.toml"), encoding: .utf8) == codex)
            #expect(try library.selectedIDs(host: .claudeCode, projectID: nil).isEmpty)
        }
    }

    @Test func scanRejectsCredentialURLsInsideArgumentValuesAndKeepsPlainURLs() throws {
        try fixture { service, library, _, _, home in
            let claude = #"{"mcpServers":{"query":{"command":"run","args":["--url=https://example.test/mcp?key=abc123"]},"auth":{"command":"run","args":["--url=https://user:abc123@example.test/mcp"]},"fragment":{"command":"run","args":["--url=https://example.test/mcp#abc123"]},"safe":{"command":"run","args":["--url=https://example.test/mcp"]}}}"#
            let codex = """
            [mcp_servers.query]
            command = "run"
            args = ["--url=https://example.test/mcp?key=abc123"]
            """
            let claudeURL = home.appendingPathComponent(".claude.json")
            let codexURL = home.appendingPathComponent(".codex/config.toml")
            try claude.write(to: claudeURL, atomically: true, encoding: .utf8)
            try codex.write(to: codexURL, atomically: true, encoding: .utf8)

            let candidates = try service.scanMCPLibrary()
            #expect(candidates.count == 5)
            let safe = try #require(candidates.first { $0.name == "safe" }?.entry)
            #expect(safe.args == ["--url=https://example.test/mcp"])
            for blocked in candidates.filter({ $0.name != "safe" }) {
                #expect(blocked.entry == nil)
                #expect(blocked.issue != nil)
                #expect(blocked.issue?.contains("abc123") == false)
            }
            try library.importEntries(candidates.compactMap(\.entry))
            #expect(try library.entries().map(\.name) == ["safe"])
            #expect(!String(decoding: try Data(contentsOf: library.documentURL), as: UTF8.self).contains("abc123"))
            #expect(try String(contentsOf: claudeURL, encoding: .utf8) == claude)
            #expect(try String(contentsOf: codexURL, encoding: .utf8) == codex)
        }
    }

    @Test func duplicateImportAndCorruptLibraryLeaveExistingBytesUntouched() throws {
        try fixture { _, library, _, _, _ in
            _ = try library.save(MCPLibraryEntry(name: "docs", commandOrURL: "old"))
            let before = try Data(contentsOf: library.documentURL)
            #expect(throws: (any Error).self) { try library.importEntries([
                MCPLibraryEntry(name: "new", commandOrURL: "new"), MCPLibraryEntry(name: "docs", commandOrURL: "overwrite")]) }
            #expect(try Data(contentsOf: library.documentURL) == before)
            try Data("broken".utf8).write(to: library.documentURL)
            #expect(throws: (any Error).self) { try library.save(MCPLibraryEntry(name: "new", commandOrURL: "new")) }
            #expect(try Data(contentsOf: library.documentURL) == Data("broken".utf8))
        }
    }

    private func apply(_ plan: StoredDeploymentPlan, service: SkillSetService) throws {
        _ = try service.approve(planID: plan.id, digest: plan.plan.digest)
        _ = try service.apply(planID: plan.id, digest: plan.plan.digest)
    }
    private func json(_ url: URL) throws -> [String: Any] { try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]) }
    private func fixture(_ work: (SkillSetService, MCPLibraryStore, UUID, URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-library-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project")
        let home = root.appendingPathComponent("home")
        let state = root.appendingPathComponent("state")
        for url in [project, home.appendingPathComponent(".codex")] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: state, repositoryRoot: nil)
        let service = try SkillSetService(paths: paths, globalLocations: GlobalConfigurationLocations(home: home, stateRoot: state))
        let projectID = try ProjectStore(rootURL: state).register(path: project).id
        try work(service, MCPLibraryStore(rootURL: state), projectID, project, home)
    }
}
