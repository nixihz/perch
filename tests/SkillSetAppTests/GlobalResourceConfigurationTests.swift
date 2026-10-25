import Foundation
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class GlobalResourceConfigurationTests: XCTestCase {
    func testIndependentSnippetAndInstallChoicesPreviewOnlyTheRequestedHost() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let locations = GlobalConfigurationLocations(home: root.appendingPathComponent("home"), stateRoot: paths.applicationSupportRoot)
        let snippet = TemplateRecord(title: "测试规则", body: "提交前运行相关测试。", purpose: "验证独立宿主")
        _ = try TemplateStore(rootURL: paths.applicationSupportRoot).save(snippet, initial: [])
        let model = GlobalConfigurationModel(paths: paths, locations: locations)
        model.refresh()
        model.setInstruction(snippet.id, enabled: true, host: .claudeCode)
        model.setInstallMethod(.copy, host: .claudeCode)
        XCTAssertEqual(model.host, .codex)
        XCTAssertFalse(model.isInstructionSelected(snippet.id, host: .codex))
        XCTAssertTrue(model.draft.instructionIDs.isEmpty)
        let manager = GlobalConfigurationManager(paths: paths, locations: locations)
        XCTAssertEqual(try manager.draft(host: .claudeCode).installMethod, .copy)
        let plan = try XCTUnwrap(model.prepareDeployment(host: .claudeCode), model.error ?? "")
        XCTAssertEqual(model.host, .codex, "预览不能切换或清空另一工具的编辑状态")
        XCTAssertFalse(FileManager.default.fileExists(atPath: locations.rulesURL(.claudeCode).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: locations.rulesURL(.codex).path))
        XCTAssertEqual(plan.plan.metadata?["globalHost"], "claude-code")
        let store = DeploymentPlanStore(rootURL: paths.plansRoot)
        _ = try store.approve(id: plan.id, digest: plan.plan.digest)
        _ = try SkillSetService(paths: paths, globalLocations: locations).apply(planID: plan.id, digest: plan.plan.digest)
        XCTAssertTrue(try String(contentsOf: locations.rulesURL(.claudeCode), encoding: .utf8).contains(snippet.body))
        XCTAssertFalse(FileManager.default.fileExists(atPath: locations.rulesURL(.codex).path))
        let restarted = GlobalConfigurationModel(paths: paths, locations: locations)
        restarted.refresh()
        XCTAssertTrue(restarted.isInstructionSelected(snippet.id, host: .claudeCode))
        restarted.setInstruction(snippet.id, enabled: false, host: .claudeCode)
        XCTAssertTrue(try manager.draft(host: .claudeCode).instructionIDs.isEmpty)
        XCTAssertTrue(try String(contentsOf: locations.rulesURL(.claudeCode), encoding: .utf8).contains(snippet.body), "取消选择仍需预览保存")
    }

    func testPluginDraftSurvivesRestartWithoutChangingHostsOrPersistingRiskApproval() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let home = root.appendingPathComponent("home")
        try plugin(home: home, host: "codex", name: "codex-example")
        try plugin(home: home, host: "claude", name: "claude-example")
        let config = home.appendingPathComponent(".codex/config.toml")
        let original = "[plugins.\"codex-example@fixture\"]\nenabled = true\n"
        try original.write(to: config, atomically: true, encoding: .utf8)
        let model = PluginSelectionModel(paths: paths, home: home)
        await model.refresh()
        let codex = try XCTUnwrap(model.plugins.first { $0.host == .codex })
        let claude = try XCTUnwrap(model.plugins.first { $0.host == .claudeCode })
        XCTAssertTrue(codex.installed)
        XCTAssertTrue(model.selected(codex))
        model.select(codex, enabled: false)
        model.select(claude, enabled: true)
        XCTAssertEqual(model.action(codex), .uninstall)
        XCTAssertEqual(model.action(claude), .install)
        model.acknowledgedRisk = true
        let restarted = PluginSelectionModel(paths: paths, home: home)
        await restarted.refresh()
        XCTAssertFalse(restarted.selected(codex))
        XCTAssertTrue(restarted.selected(claude))
        XCTAssertFalse(restarted.acknowledgedRisk)
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude/plugins/installed_plugins.json").path))
        XCTAssertTrue(try DeploymentPlanStore(rootURL: paths.plansRoot).list().isEmpty)
        restarted.select(claude, enabled: false)
        XCTAssertNil(restarted.action(claude))
    }

    func testUnreadablePluginDraftIsPreservedAndRefreshRecoversAfterRepair() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let home = root.appendingPathComponent("home")
        try plugin(home: home, host: "claude", name: "example")
        let model = PluginSelectionModel(paths: paths, home: home)
        await model.refresh()
        let record = try XCTUnwrap(model.plugins.first)
        let draft = paths.applicationSupportRoot.appendingPathComponent("global/plugin-draft.json")
        try FileManager.default.createDirectory(at: draft.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: draft)
        await model.refresh()
        XCTAssertFalse(model.isReady)
        XCTAssertNotNil(model.error)
        model.select(record, enabled: true)
        XCTAssertEqual(try String(contentsOf: draft, encoding: .utf8), "invalid")
        try Data("{}".utf8).write(to: draft)
        await model.refresh()
        XCTAssertTrue(model.isReady)
        XCTAssertNil(model.error)
        model.select(record, enabled: true)
        XCTAssertTrue(model.selected(record))
    }

    func testPluginDraftDoesNotReinstallAfterInstallationScopeChangesAndUninstall() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let home = root.appendingPathComponent("home")
        try plugin(home: home, host: "claude", name: "example")
        let model = PluginSelectionModel(paths: paths, home: home)
        await model.refresh()
        let cached = try XCTUnwrap(model.plugins.first)
        model.select(cached, enabled: true)
        let index = home.appendingPathComponent(".claude/plugins/installed_plugins.json")
        let package = home.appendingPathComponent(".claude/plugins/cache/fixture/example/1")
        try JSONSerialization.data(withJSONObject: ["plugins": ["example@fixture": [[
            "installPath": package.path, "scope": "user", "enabled": true
        ]]]]).write(to: index)
        await model.refresh()
        let installed = try XCTUnwrap(model.plugins.first)
        XCTAssertTrue(installed.installed)
        XCTAssertNotEqual(cached.id, installed.id)
        model.select(installed, enabled: false)
        XCTAssertEqual(model.action(installed), .disable)
        try FileManager.default.removeItem(at: index)
        await model.refresh()
        let removed = try XCTUnwrap(model.plugins.first)
        XCTAssertFalse(model.selected(removed))
        XCTAssertNil(model.action(removed), "移除安装记录后不能重新命中旧的安装草稿")
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("global-resources-\(UUID())")
    }

    private func plugin(home: URL, host: String, name: String) throws {
        let root = home.appendingPathComponent(".\(host)/plugins/cache/fixture/\(name)/1/.\(host)-plugin")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["name": name, "version": "1.0", "description": "测试插件"])
            .write(to: root.appendingPathComponent("plugin.json"))
    }
}
