import Foundation
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class MCPLibraryWorkflowTests: XCTestCase {
    func testScanImportThenProjectSelectionRequiresApprovalAndSurvivesModelReload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-library-ui-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let project = root.appendingPathComponent("project")
        let state = root.appendingPathComponent("state")
        for url in [home, project] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: state, repositoryRoot: nil)
        let locations = GlobalConfigurationLocations(home: home, stateRoot: state)
        let registration = try ProjectStore(rootURL: state).register(path: project, agents: ["claude-code"])
        let source = home.appendingPathComponent(".claude.json")
        let original = #"{"mcpServers":{"docs":{"command":"docs","args":["two words"],"env":{"API_KEY":"not-copied"}}}}"#
        try original.write(to: source, atomically: true, encoding: .utf8)
        let model = AppModel(runtimePaths: paths, globalLocations: locations)
        model.mcpLibrary.scan()
        let candidate = try XCTUnwrap(model.mcpLibrary.candidates.first { $0.name == "docs" })
        XCTAssertTrue(model.mcpLibrary.importCandidates([candidate.id]), model.mcpLibrary.error ?? "")
        let entry = try XCTUnwrap(model.mcpLibrary.entries.first)
        model.mcpLibrary.select(entry.id, enabled: true, host: .claudeCode, projectID: registration.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent(".mcp.json").path))
        let reloaded = AppModel(runtimePaths: paths, globalLocations: locations)
        reloaded.mcpLibrary.loadSelection(host: .claudeCode, projectID: registration.id)
        XCTAssertEqual(reloaded.mcpLibrary.selectedIDs(host: .claudeCode, projectID: registration.id), [entry.id])
        reloaded.prepareMCPLibraryPlan(host: .claudeCode, projectID: registration.id)
        XCTAssertNil(reloaded.mcpLibrary.error)
        XCTAssertEqual(reloaded.preparedPlan?.approvalState, .pending)
        XCTAssertTrue(reloaded.planPresented)
        XCTAssertTrue(reloaded.approveAndApplyPreparedPlan(), reloaded.lastAction)
        let written = try String(contentsOf: project.appendingPathComponent(".mcp.json"), encoding: .utf8)
        XCTAssertTrue(written.contains("two words"))
        XCTAssertTrue(written.contains("${API_KEY}"))
        XCTAssertFalse(written.contains("not-copied"))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), original)
    }

    func testImportRejectsChangedScanAndPreservesCurrentLibrary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-scan-ui-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let state = root.appendingPathComponent("state")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let model = MCPLibraryModel(paths: SkillSetRuntimePaths(applicationSupportRoot: state, repositoryRoot: nil),
            locations: GlobalConfigurationLocations(home: home, stateRoot: state))
        let source = home.appendingPathComponent(".claude.json")
        try #"{"mcpServers":{"docs":{"command":"old"}}}"#.write(to: source, atomically: true, encoding: .utf8)
        model.scan()
        let candidate = try XCTUnwrap(model.candidates.first)
        try #"{"mcpServers":{"docs":{"command":"changed"}}}"#.write(to: source, atomically: true, encoding: .utf8)
        XCTAssertFalse(model.importCandidates([candidate.id]))
        XCTAssertNotNil(model.error)
        XCTAssertTrue(try model.store.entries().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.store.documentURL.path))
    }
}
