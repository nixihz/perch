import Foundation
import Testing
@testable import SkillSetCore

struct CodexProjectMCPTests {
    @Test func directPlanRequiresApprovalPreservesOtherConfigurationAndNeverSetsTrust() throws {
        try fixture { service, projectID, project, home in
            let config = project.appendingPathComponent(".codex/config.toml")
            try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
            let original = "# 项目设置\nmodel = \"project-model\"\n[mcp_servers.existing]\ncommand = \"keep\"\n"
            try original.write(to: config, atomically: true, encoding: .utf8)
            let global = home.appendingPathComponent(".codex/config.toml")
            let globalOriginal = "# 全局设置\nmodel = \"global-model\"\n"
            try globalOriginal.write(to: global, atomically: true, encoding: .utf8)
            let neighbor = project.deletingLastPathComponent().appendingPathComponent("other/.codex/config.toml")
            try FileManager.default.createDirectory(at: neighbor.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "# 其他项目\n".write(to: neighbor, atomically: true, encoding: .utf8)
            let draft = MCPConfigurationDraft(name: "perch", host: .codex, scope: .project,
                commandOrURL: "/Applications/栖集.app/Contents/Helpers/skillset",
                args: ["--state", "/fixture/Application Support/Skill Set", "mcp", "serve", "--transport", "stdio"])
            let plan = try service.makeMCPConfigPlan(projectID: projectID, draft: draft)
            #expect(plan.plan.changes.map(\.relativePath) == [".codex/config.toml"])
            #expect(plan.plan.warnings.contains(MCPConfigurationTarget.codexProjectTrustNotice))
            #expect(try String(contentsOf: config, encoding: .utf8) == original)
            #expect(throws: (any Error).self) { try service.apply(planID: plan.id, digest: plan.plan.digest) }
            try apply(plan, service: service)
            let written = try String(contentsOf: config, encoding: .utf8)
            #expect(written.hasPrefix(original))
            #expect(written.contains("[mcp_servers.perch]"))
            #expect(!written.contains("trust_level"))
            #expect(try String(contentsOf: global, encoding: .utf8) == globalOriginal)
            #expect(try String(contentsOf: neighbor, encoding: .utf8) == "# 其他项目\n")
            let inspection = try #require(service.mcpConfigurations(projectID: projectID).first { $0.host == .codex && $0.scope == .project })
            #expect(inspection.servers.first { $0.name == "perch" }?.managed == true)
            #expect(throws: MCPConfigurationError.unsupportedTarget("codex/project")) {
                try service.makeMCPConfigPlan(projectID: nil, draft: draft)
            }
            #expect(throws: (any Error).self) { try service.makeMCPConfigPlan(projectID: UUID(), draft: draft) }
            #expect(try String(contentsOf: global, encoding: .utf8) == globalOriginal)
        }
    }

    @Test func multilineProjectConnectionCanBeScannedIntoLibraryWithoutWritingSourceOrSelectingIt() throws {
        try fixture { service, projectID, project, _ in
            let config = project.appendingPathComponent(".codex/config.toml")
            try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
            let original = """
            [mcp_servers.skillset]
            command = "/Applications/栖集.app/Contents/Helpers/skillset"
            args = [
              "--state",
              "/Users/fixture/Library/Application Support/Skill Set",
              "mcp", "serve", "--transport", "stdio",
            ]
            """
            try original.write(to: config, atomically: true, encoding: .utf8)
            let candidates = try service.scanMCPLibrary()
            let candidate = try #require(candidates.first { $0.name == "skillset" })
            #expect(candidate.source.contains(config.path))
            let entry = try #require(candidate.entry)
            #expect(entry.args == ["--state", "/Users/fixture/Library/Application Support/Skill Set", "mcp", "serve", "--transport", "stdio"])
            let library = MCPLibraryStore(rootURL: service.paths.applicationSupportRoot)
            try library.importEntries([entry])
            #expect(try library.entries().first?.commandOrURL == "/Applications/栖集.app/Contents/Helpers/skillset")
            #expect(try library.selectedIDs(host: .codex, projectID: projectID).isEmpty)
            #expect(try String(contentsOf: config, encoding: .utf8) == original)
        }
    }

    @Test func libraryUpdatesOnlyItsNodesAndRejectsExternalConflictsAndLocalEdits() throws {
        try fixture { service, projectID, project, _ in
            let config = project.appendingPathComponent(".codex/config.toml")
            try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
            let external = "# 保留项目设置\nmodel = \"example\"\n[mcp_servers.docs]\ncommand = \"external\"\n"
            try external.write(to: config, atomically: true, encoding: .utf8)
            let library = MCPLibraryStore(rootURL: service.paths.applicationSupportRoot)
            var entry = try library.save(MCPLibraryEntry(name: "docs", commandOrURL: "docs"))
            try library.saveSelection([entry.id], host: .codex, projectID: projectID)
            #expect(throws: MCPConfigurationError.configConflict("docs")) { try service.makeMCPLibraryPlan(host: .codex, projectID: projectID) }
            #expect(try String(contentsOf: config, encoding: .utf8) == external)
            let prefix = "model = \"example\"\n[mcp_servers.other]\ncommand = \"keep\"\n"
            try prefix.write(to: config, atomically: true, encoding: .utf8)
            try apply(service.makeMCPLibraryPlan(host: .codex, projectID: projectID), service: service)
            entry.commandOrURL = "new-docs"
            _ = try library.save(entry)
            try apply(service.makeMCPLibraryPlan(host: .codex, projectID: projectID), service: service)
            let updated = try String(contentsOf: config, encoding: .utf8)
            #expect(updated.hasPrefix(prefix))
            #expect(updated.contains("command = \"new-docs\""))
            let modified = updated.replacingOccurrences(of: "new-docs", with: "user-edit")
            try modified.write(to: config, atomically: true, encoding: .utf8)
            try library.saveSelection([], host: .codex, projectID: projectID)
            #expect(throws: (any Error).self) { try service.makeMCPLibraryPlan(host: .codex, projectID: projectID) }
            #expect(try String(contentsOf: config, encoding: .utf8) == modified)
            try updated.write(to: config, atomically: true, encoding: .utf8)
            let removal = try service.makeMCPLibraryPlan(host: .codex, projectID: projectID)
            try "# 计划后修改\n".appending(updated).write(to: config, atomically: true, encoding: .utf8)
            _ = try service.approve(planID: removal.id, digest: removal.plan.digest)
            #expect(throws: (any Error).self) { try service.apply(planID: removal.id, digest: removal.plan.digest) }
            #expect(try String(contentsOf: config, encoding: .utf8) == "# 计划后修改\n" + updated)
        }
    }

    @Test func symlinkedCodexDirectoryIsNeitherReadNorWritten() throws {
        try fixture { service, projectID, project, home in
            let outside = home.appendingPathComponent(".codex")
            let global = outside.appendingPathComponent("config.toml")
            let original = "[mcp_servers.globalonly]\ncommand = \"keep\"\n"
            try original.write(to: global, atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(at: project.appendingPathComponent(".codex"), withDestinationURL: outside)
            let inspection = try #require(service.mcpConfigurations(projectID: projectID).first { $0.host == .codex && $0.scope == .project })
            #expect(inspection.servers.isEmpty)
            #expect(!inspection.issues.isEmpty)
            let candidate = try #require(service.scanMCPLibrary().first { $0.source == project.appendingPathComponent(".codex/config.toml").path })
            #expect(candidate.entry == nil)
            #expect(throws: (any Error).self) {
                try service.makeMCPConfigPlan(projectID: projectID, draft: MCPConfigurationDraft(name: "docs", commandOrURL: "docs"))
            }
            #expect(try String(contentsOf: global, encoding: .utf8) == original)
        }
    }

    private func apply(_ plan: StoredDeploymentPlan, service: SkillSetService) throws {
        _ = try service.approve(planID: plan.id, digest: plan.plan.digest)
        _ = try service.apply(planID: plan.id, digest: plan.plan.digest)
    }

    private func fixture(_ work: (SkillSetService, UUID, URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-project-mcp-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project")
        let home = root.appendingPathComponent("home")
        let state = root.appendingPathComponent("state")
        for url in [project, home.appendingPathComponent(".codex")] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let service = try SkillSetService(paths: SkillSetRuntimePaths(applicationSupportRoot: state, repositoryRoot: nil),
            globalLocations: GlobalConfigurationLocations(home: home, stateRoot: state))
        let projectID = try ProjectStore(rootURL: state).register(path: project).id
        try work(service, projectID, project, home)
    }
}
