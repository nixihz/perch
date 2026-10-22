import Foundation
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class MCPAccessSetupTests: XCTestCase {
    func testDetectionRejectsGUIAndIncompleteCLIThenPrefersBundledHelper() throws {
        try withFixture { root in
            let app = root.appendingPathComponent("栖集.app")
            let repository = root.appendingPathComponent("repository")
            // 只有 GUI 时必须显示缺失，不能把大小写不敏感的 SkillSet 当作 CLI。
            _ = try executable(at: app.appendingPathComponent("Contents/MacOS/SkillSet"))
            XCTAssertNil(MCPAccessInstallation.detect(bundleURL: app, repositoryRoot: repository))
            let helper = try executable(at: app.appendingPathComponent("Contents/Helpers/skillset"))
            XCTAssertNil(MCPAccessInstallation.detect(bundleURL: app, repositoryRoot: repository), "缺资源时不能显示程序完整")
            let development = try executable(at: repository.appendingPathComponent("dist/skillset"))
            try resources(beside: development)
            XCTAssertEqual(MCPAccessInstallation.detect(bundleURL: app, repositoryRoot: repository)?.executableURL, development)
            try resources(beside: helper)
            let installation = try XCTUnwrap(MCPAccessInstallation.detect(bundleURL: app, repositoryRoot: repository))
            XCTAssertEqual(installation.executableURL, helper)
            XCTAssertEqual(installation.origin, .bundled)
        }
    }

    func testDraftKeepsSpaceContainingPathsAsIndividualArgumentsAndSelectsRequestedHost() throws {
        try withFixture { root in
            let installation = MCPAccessInstallation(executableURL: root.appendingPathComponent("App With Spaces/Helpers/skillset"), origin: .bundled)
            let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("Application Support/state"), repositoryRoot: root.appendingPathComponent("my skills"))
            let draft = installation.draft(host: .claudeCode, paths: paths)
            XCTAssertEqual(draft.host, .claudeCode)
            XCTAssertEqual(draft.scope, .user)
            XCTAssertEqual(draft.commandOrURL, installation.executableURL.path)
            XCTAssertTrue(draft.validationIssues().isEmpty)
            XCTAssertEqual(draft.args, ["--state", paths.applicationSupportRoot.path, "--repository", paths.repositoryRoot!.path, "mcp", "serve", "--transport", "stdio"])
            let standalone = installation.draft(host: .codex, paths: SkillSetRuntimePaths(applicationSupportRoot: paths.applicationSupportRoot, repositoryRoot: nil))
            XCTAssertFalse(standalone.args.contains("--repository"))
        }
    }

    func testConnectionDistinguishesManagedPathChangesExternalNamesAndUnreadableConfiguration() {
        let installation = MCPAccessInstallation(executableURL: URL(fileURLWithPath: "/Applications/栖集.app/Contents/Helpers/skillset"), origin: .bundled)
        func inspection(_ servers: [MCPObservedServer], issues: [String] = []) -> MCPConfigurationInspection {
            MCPConfigurationInspection(host: .codex, scope: .user, configPath: "/fixture/config.toml", exists: true, servers: servers, issues: issues)
        }
        func server(_ command: String, managed: Bool, name: String = "skillset") -> MCPObservedServer {
            MCPObservedServer(host: .codex, scope: .user, name: name, transport: "stdio", command: command, argumentCount: 4, envKeys: [], configPath: "/fixture/config.toml", managed: managed)
        }
        XCTAssertEqual(MCPAccessConnectionState.inspect(inspection([]), installation: installation), .unconfigured)
        XCTAssertEqual(MCPAccessConnectionState.inspect(inspection([], issues: ["invalid"]), installation: installation), .unreadable)
        XCTAssertEqual(MCPAccessConnectionState.inspect(inspection([server(installation.executableURL.path, managed: true)]), installation: installation), .configured)
        XCTAssertEqual(MCPAccessConnectionState.inspect(inspection([server("/old/skillset", managed: true)]), installation: installation), .updateNeeded)
        XCTAssertEqual(MCPAccessConnectionState.inspect(inspection([server("/other/program", managed: false)]), installation: installation), .external)
        XCTAssertEqual(MCPAccessConnectionState.inspect(inspection([server(installation.executableURL.path, managed: false, name: "perch")]), installation: installation), .external)
        XCTAssertEqual(MCPAccessConnectionState.inspect(nil, installation: installation), .unreadable)
    }

    func testSetupPlanDoesNotWriteHostConfigurationUntilApprovedAndPreservesOtherServers() throws {
        try withFixture { root in
            let executable = try executable(at: root.appendingPathComponent("dist/skillset"))
            try resources(beside: executable)
            let codex = root.appendingPathComponent("CODEX_HOME")
            try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
            let config = codex.appendingPathComponent("config.toml")
            let original = "# 用户已有配置\n[mcp_servers.neighbor]\ncommand = \"/usr/bin/true\"\n"
            try original.write(to: config, atomically: true, encoding: .utf8)
            let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: root)
            let model = AppModel(runtimePaths: paths)
            XCTAssertTrue(model.prepareAIAccess(host: .codex), model.lastAction)
            let plan = try XCTUnwrap(model.preparedPlan)
            XCTAssertEqual(plan.approvalState, .pending)
            XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), original)
            XCTAssertTrue(model.planPresented)
            XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.lastAction)
            let written = try String(contentsOf: config, encoding: .utf8)
            XCTAssertTrue(written.hasPrefix(original))
            XCTAssertTrue(written.contains("[mcp_servers.skillset]"))
            XCTAssertTrue(written.contains(executable.path))
            XCTAssertTrue(written.contains("\"--state\""))
            model.refreshAIAccess()
            XCTAssertEqual(MCPAccessConnectionState.inspect(model.mcpAccessInspection(host: .codex), installation: model.mcpAccessInstallation), .configured)
            XCTAssertTrue(model.pendingPlans.isEmpty)
        }
    }

    func testMissingProgramLeavesConfigurationUntouchedAndGivesRecoveryText() throws {
        try withFixture { root in
            let model = AppModel(runtimePaths: SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: root))
            XCTAssertFalse(model.prepareAIAccess(host: .codex))
            XCTAssertNotNil(model.aiAccessError)
            XCTAssertFalse(model.planPresented)
            XCTAssertNil(model.preparedPlan)
            XCTAssertTrue(try DeploymentPlanStore(rootURL: model.runtimePaths.plansRoot).list().isEmpty)
        }
    }

    func testExternalSameNameConfigurationIsNotOverwrittenAndErrorRemainsVisible() throws {
        try withFixture { root in
            let program = try executable(at: root.appendingPathComponent("dist/skillset"))
            try resources(beside: program)
            let config = root.appendingPathComponent("CODEX_HOME/config.toml")
            try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
            let original = "[mcp_servers.skillset]\ncommand = \"/another/program\"\n"
            try original.write(to: config, atomically: true, encoding: .utf8)
            let model = AppModel(runtimePaths: SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: root))
            XCTAssertEqual(MCPAccessConnectionState.inspect(model.mcpAccessInspection(host: .codex), installation: model.mcpAccessInstallation), .external)
            XCTAssertFalse(model.prepareAIAccess(host: .codex))
            XCTAssertNotNil(model.aiAccessError)
            XCTAssertNil(model.preparedPlan)
            XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), original)
        }
    }

    private func executable(at url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\necho should-not-run\nexit 1\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func resources(beside executable: URL) throws {
        let bundle = executable.deletingLastPathComponent().appendingPathComponent("SkillSet_SkillSetCore.bundle/Contents")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "fixture.\(UUID().uuidString)", "CFBundlePackageType": "BNDL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Info.plist"))
        try "{}".write(to: bundle.appendingPathComponent("Resources/catalog.json"), atomically: true, encoding: .utf8)
    }

    private func withFixture(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-access-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let variables = ["CODEX_HOME", "CFFIXED_USER_HOME", "SKILLSET_HOME"]
        let saved = ProcessInfo.processInfo.environment
        for variable in variables { setenv(variable, root.appendingPathComponent(variable).path, 1) }
        defer {
            for variable in variables {
                if let value = saved[variable] { setenv(variable, value, 1) } else { unsetenv(variable) }
            }
            try? FileManager.default.removeItem(at: root)
        }
        try body(root)
    }
}
