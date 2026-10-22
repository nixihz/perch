import Foundation
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class MCPLibraryExperienceTests: XCTestCase {
    func testGivenSameNameInTwoHostsWhenChangingSourceThenOnlyLatestCandidateIsSelected() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try #"{"mcpServers":{"docs":{"command":"claude-docs"},"search":{"command":"search"}}}"#
            .write(to: fixture.home.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)
        try "[mcp_servers.docs]\ncommand = \"codex-docs\"\n"
            .write(to: fixture.home.appendingPathComponent(".codex/config.toml"), atomically: true, encoding: .utf8)
        let library = fixture.model.mcpLibrary
        library.scan()
        let copies = library.candidates.filter { $0.name == "docs" }
        XCTAssertEqual(copies.count, 2)
        let search = try XCTUnwrap(library.candidates.first { $0.name == "search" })
        XCTAssertEqual(library.unambiguousCandidateIDs, [search.id])
        var selected = library.updatingScanSelection([search.id], candidateID: copies[0].id, enabled: true)
        selected = library.updatingScanSelection(selected, candidateID: copies[1].id, enabled: true)
        XCTAssertEqual(selected, [search.id, copies[1].id])
        XCTAssertTrue(library.importCandidates(selected), library.error ?? "")
        XCTAssertEqual(library.entries.first { $0.name == "docs" }?.commandOrURL, copies[1].entry?.commandOrURL)
        XCTAssertEqual(Set(library.entries.map(\.name)), ["docs", "search"])
        XCTAssertEqual(Set(library.lastImportedIDs), Set(library.entries.map(\.id)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent(".mcp.json").path))
    }

    func testGivenLibraryEntryWhenUsingInProjectThenPreviewIncludesExistingDraftWithoutWritingHost() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let library = fixture.model.mcpLibrary
        let docs = MCPLibraryEntry(name: "docs", commandOrURL: "docs")
        let search = MCPLibraryEntry(name: "search", commandOrURL: "search")
        XCTAssertTrue(library.save(docs))
        XCTAssertTrue(library.save(search))
        XCTAssertTrue(library.select(docs.id, enabled: true, host: .claudeCode, projectID: fixture.registration.id))
        let plan = try XCTUnwrap(library.prepareUse(search, host: .claudeCode, projectID: fixture.registration.id), library.error ?? "")
        XCTAssertEqual(plan.approvalState, .pending)
        XCTAssertEqual(Set(try library.store.selectedIDs(host: .claudeCode, projectID: fixture.registration.id)), [docs.id, search.id])
        let target = try XCTUnwrap(library.usageTargets.first { $0.projectID == fixture.registration.id })
        XCTAssertEqual(target.configPath, URL(fileURLWithPath: fixture.registration.canonicalPath).appendingPathComponent(".mcp.json").path)
        XCTAssertTrue(target.appliedEntries.isEmpty)
        XCTAssertTrue(target.observedNames.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.configPath))
        XCTAssertTrue(try library.store.selectedIDs(host: .claudeCode, projectID: nil).isEmpty)
    }

    func testGivenUnsupportedCodexProjectWhenSelectingThenNoDraftOrPlanIsCreated() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let library = fixture.model.mcpLibrary
        let docs = MCPLibraryEntry(name: "docs", commandOrURL: "docs")
        XCTAssertTrue(library.save(docs))
        XCTAssertNil(library.prepareUse(docs, host: .codex, projectID: fixture.registration.id))
        XCTAssertNotNil(library.error)
        XCTAssertTrue(try library.store.selectedIDs(host: .codex, projectID: fixture.registration.id).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.store.rootURL.appendingPathComponent("drafts").path))
    }

    func testGivenStaleClaudeProjectWhenEnteringLibraryFromCodexGlobalThenPreviewKeepsGlobalTarget() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model
        let library = model.mcpLibrary
        model.selectedProjectID = fixture.registration.id.uuidString
        model.section = .projects
        model.selectProjectHost(.claude)
        model.section = .mcp
        library.refreshUsage()
        XCTAssertEqual(library.initialUsageTargetID(fallbackHost: .codex),
                       library.store.selectionKey(host: .claudeCode, projectID: fixture.registration.id))

        model.section = .globalConfiguration
        model.globalConfiguration.selectHost(.codex)
        model.section = .mcp
        library.refreshUsage()
        let targetID = library.initialUsageTargetID(fallbackHost: model.globalConfiguration.host)
        let target = try XCTUnwrap(library.usageTargets.first { $0.id == targetID })
        XCTAssertEqual(target.host, .codex)
        XCTAssertNil(target.projectID)
        let entry = MCPLibraryEntry(name: "docs", commandOrURL: "docs")
        XCTAssertTrue(library.save(entry))
        let plan = try XCTUnwrap(library.prepareUse(entry, host: target.host, projectID: target.projectID))
        XCTAssertEqual(plan.approvalState, .pending)
        XCTAssertEqual(try library.store.selectedIDs(host: .codex, projectID: nil), [entry.id])
        XCTAssertTrue(try library.store.selectedIDs(host: .claudeCode, projectID: fixture.registration.id).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.configPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent(".mcp.json").path))

        model.section = .sources
        model.section = .mcp
        XCTAssertEqual(library.initialUsageTargetID(fallbackHost: .codex), targetID)
        model.section = .projects
        model.selectProjectHost(.codex)
        model.section = .mcp
        XCTAssertEqual(library.initialUsageTargetID(fallbackHost: .claudeCode), targetID)
    }

    func testGivenUnknownOrEmptyScanSelectionWhenImportingThenNoFalseSuccessOrLibraryWrite() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let library = fixture.model.mcpLibrary
        library.scan()
        XCTAssertFalse(library.importCandidates([]))
        XCTAssertFalse(library.importCandidates(["obsolete-candidate"]))
        XCTAssertNotNil(library.error)
        XCTAssertTrue(library.lastImportedIDs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.store.documentURL.path))
    }

    func testGivenExternalSameNameConnectionWhenInspectingUsageThenItIsNotClaimedAsLibraryWrite() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try #"{"mcpServers":{"docs":{"command":"external-docs"}}}"#
            .write(to: fixture.project.appendingPathComponent(".mcp.json"), atomically: true, encoding: .utf8)
        let library = fixture.model.mcpLibrary
        let entry = MCPLibraryEntry(name: "docs", commandOrURL: "library-docs")
        XCTAssertTrue(library.save(entry))
        library.refreshUsage()
        let target = try XCTUnwrap(library.usageTargets.first { $0.projectID == fixture.registration.id })
        XCTAssertEqual(target.observedNames, ["docs"])
        XCTAssertFalse(target.references(entry))
        XCTAssertTrue(target.appliedEntries.isEmpty)
        XCTAssertNil(library.prepareUse(entry, host: .claudeCode, projectID: fixture.registration.id))
        XCTAssertNotNil(library.error)
        let original = try String(contentsOf: fixture.project.appendingPathComponent(".mcp.json"), encoding: .utf8)
        XCTAssertTrue(original.contains("external-docs"))
        XCTAssertFalse(original.contains("library-docs"))
    }

    func testGivenUnreadableConfigurationWhenInspectingUsageThenDiagnosticDetailsStayHidden() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let library = fixture.model.mcpLibrary
        let entry = MCPLibraryEntry(name: "docs", commandOrURL: "docs")
        XCTAssertTrue(library.save(entry))
        XCTAssertTrue(library.select(entry.id, enabled: true, host: .codex, projectID: nil))
        let config = fixture.home.appendingPathComponent(".codex/config.toml")
        let sensitiveMarker = "external-private-diagnostic"
        let malformed = "# skillset:begin mcp name=\(sensitiveMarker)\n"
        try malformed.write(to: config, atomically: true, encoding: .utf8)

        library.refreshUsage()
        let unreadable = try XCTUnwrap(library.usageTargets.first { $0.host == .codex && $0.projectID == nil })
        XCTAssertTrue(unreadable.references(entry))
        XCTAssertEqual(unreadable.issue, "MCP 配置无法读取，请检查配置文件和目录权限后重新扫描。")
        XCTAssertFalse(unreadable.issue?.contains(sensitiveMarker) ?? true)
        XCTAssertTrue(unreadable.observedNames.isEmpty)
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), malformed)

        try "[mcp_servers.docs]\ncommand = \"external-docs\"\n"
            .write(to: config, atomically: true, encoding: .utf8)
        library.refreshUsage()
        let existing = try XCTUnwrap(library.usageTargets.first { $0.host == .codex && $0.projectID == nil })
        XCTAssertEqual(existing.issue, "已有配置；可编辑或删除，批准计划后生效。")
        XCTAssertEqual(existing.observedNames, ["docs"])
        XCTAssertTrue(existing.appliedEntries.isEmpty)
    }

    func testGivenArgumentsWhenReadingConnectionThenSafeValuesRemainReadableAndCredentialsStayHidden() {
        let safe = MCPLibraryEntry(name: "docs", commandOrURL: "npx", args: ["-y", "@example/docs", "two words", "--url=https://example.test/mcp"])
        XCTAssertEqual(MCPConnectionFields.visibleArguments(safe), ["-y", "@example/docs", "two words", "--url=https://example.test/mcp"])
        for args in [["--token", "private-value"], ["https://example.test/mcp?key=private-value"],
                     ["Authorization: Bearer private-value"], ["--url=https://example.test/mcp?key=abc123"],
                     ["--url=https://user:abc123@example.test/mcp"], ["--url=https://example.test/mcp#abc123"]] {
            let sensitive = MCPLibraryEntry(name: "docs", commandOrURL: "npx", args: args)
            XCTAssertNil(MCPConnectionFields.visibleArguments(sensitive))
        }
    }

    @MainActor
    private struct Fixture {
        let root: URL
        let home: URL
        let project: URL
        let registration: ProjectRegistration
        let model: AppModel

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-experience-\(UUID())")
            home = root.appendingPathComponent("home")
            project = root.appendingPathComponent("project")
            let state = root.appendingPathComponent("state")
            try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            registration = try ProjectStore(rootURL: state).register(path: project, agents: ["claude-code"])
            model = AppModel(runtimePaths: SkillSetRuntimePaths(applicationSupportRoot: state, repositoryRoot: nil),
                globalLocations: GlobalConfigurationLocations(home: home, stateRoot: state))
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
