import AppKit
import SwiftUI
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class GlobalConfigurationUITests: XCTestCase {
    func testGlobalRulesEditorLoadsTheSelectedHostFileAsEditablePlainText() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("global-rules-editor-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let locations = GlobalConfigurationLocations(home: root.appendingPathComponent("home"), stateRoot: paths.applicationSupportRoot)
        let rulesURL = locations.rulesURL(.codex)
        try FileManager.default.createDirectory(at: rulesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Codex 全局规则\n始终先查看变更。\n".write(to: rulesURL, atomically: true, encoding: .utf8)

        let controller = NSHostingController(rootView: GlobalRulesEditorSheet(host: .codex, locations: locations))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 640),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        controller.view.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSTextView }.first)
        XCTAssertTrue(textView.isEditable)
        XCTAssertEqual(textView.string, "# Codex 全局规则\n始终先查看变更。\n")
        XCTAssertLessThanOrEqual(controller.view.fittingSize.width, 821)
        XCTAssertLessThanOrEqual(controller.view.fittingSize.height, 641)
    }

    func testAgentsPlanCancellationAndSaveKeepCodexPendingDraft() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("agents-save-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let locations = GlobalConfigurationLocations(home: root.appendingPathComponent("home"), stateRoot: paths.applicationSupportRoot)
        let skill = try paths.makeLibraryStore().save(SkillEditorDraft(slug: "shared-demo",
            document: "---\nname: shared-demo\ndescription: 保存测试\n---\n共享正文\n"), repositoryRoot: nil)
        let model = AppModel(runtimePaths: paths, globalLocations: locations)
        let global = model.globalConfiguration
        global.refresh()
        global.setSkill(skill.id, enabled: true, host: .agents)
        global.setSkill(skill.id, enabled: true, host: .codex)
        global.setInstallMethod(.copy, host: .agents)
        let codexBefore = global.selection(host: .codex)
        model.preparedPlan = try XCTUnwrap(global.prepareDeployment(host: .agents), global.error ?? "")
        model.planPresented = true
        model.dismissPlan()
        let target = locations.home.appendingPathComponent(".agents/skills/shared-demo/SKILL.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        model.preparedPlan = try XCTUnwrap(global.prepareDeployment(host: .agents), global.error ?? "")
        XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.lastAction)
        XCTAssertEqual(global.host, .agents)
        XCTAssertEqual(global.inspection?.host, .agents)
        XCTAssertTrue(try String(contentsOf: target, encoding: .utf8).contains("共享正文"))
        XCTAssertEqual(global.selection(host: .codex), codexBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: locations.skillsRoot(.codex).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: locations.home.appendingPathComponent(".agents/AGENTS.md").path))
    }

    func testCorruptedSnapshotShowsRepairActionInGlobalConfiguration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-repair-ui-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let locations = GlobalConfigurationLocations(home: root.appendingPathComponent("home"), stateRoot: paths.applicationSupportRoot)
        let skill = try paths.makeLibraryStore().save(SkillEditorDraft(slug: "snapshot-demo",
            document: "---\nname: snapshot-demo\ndescription: 快照修复测试\n---\n原始正文\n"), repositoryRoot: nil)
        let model = AppModel(runtimePaths: paths, globalLocations: locations)
        let global = model.globalConfiguration
        global.refresh()
        global.setSkill(skill.id, enabled: true, host: .codex)
        model.preparedPlan = try XCTUnwrap(global.prepareDeployment(host: .codex), global.error ?? "")
        XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.lastAction)

        let target = locations.skillsRoot(.codex).appendingPathComponent("snapshot-demo")
        let snapshot = paths.versionsRoot.appendingPathComponent(String(repeating: "b", count: 64), isDirectory: true)
        let librarySource = try XCTUnwrap(paths.makeLibraryStore().sourceURLs()[skill.id])
        _ = try SkillAssetCopier.copy(from: librarySource, to: snapshot)
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: snapshot)
        let snapshotPath = try FileManager.default.destinationOfSymbolicLink(atPath: target.path)
        try "损坏快照".write(to: URL(fileURLWithPath: snapshotPath).appendingPathComponent("SKILL.md"),
                             atomically: true, encoding: .utf8)
        global.refresh()
        XCTAssertTrue(global.inspection?.resources.contains { $0.snapshotCorrupt } == true)

        let previousLanguage = AppPreferences.shared.language
        AppPreferences.shared.language = .chinese
        defer { AppPreferences.shared.language = previousLanguage }
        let controller = NSHostingController(rootView: ConfigurationResourceView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(controller.view.fittingSize.width, 0)
        let repair = try XCTUnwrap(global.prepareSnapshotRepair())
        XCTAssertEqual(repair.plan.metadata?["globalAction"], "repair-snapshot")
    }

    func testCancelledRefreshKeepsDraftAndNextRefreshReadsExternalChange() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("global-refresh-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let locations = GlobalConfigurationLocations(home: root.appendingPathComponent("home"), stateRoot: paths.applicationSupportRoot)
        let manager = GlobalConfigurationManager(paths: paths, locations: locations)
        let model = GlobalConfigurationModel(paths: paths, locations: locations)
        await model.refreshInBackground()
        XCTAssertTrue(model.canEditSkills(host: .codex))
        var changed = GlobalConfigurationDraft()
        changed.skillIDs = ["external-change"]
        try manager.saveDraft(changed, host: .codex)
        let task = Task { await model.refreshInBackground() }
        task.cancel()
        await task.value
        XCTAssertTrue(model.draft.skillIDs.isEmpty)
        XCTAssertFalse(model.isRefreshing)
        await model.refreshInBackground()
        XCTAssertEqual(model.draft.skillIDs, ["external-change"])
        XCTAssertNil(model.error)
        XCTAssertNotNil(model.inspection)
    }

    func testDraftPlanCancellationApprovalAndRestoreThroughSharedModel() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("global-ui-\(UUID())")
        let home = root.appendingPathComponent("home")
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let variables = ["CFFIXED_USER_HOME", "SKILLSET_HOME", "CODEX_HOME", "CLAUDE_CONFIG_DIR"]
        let environment = ProcessInfo.processInfo.environment
        for variable in variables { setenv(variable, home.appendingPathComponent(variable).path, 1) }
        defer {
            for variable in variables {
                if let value = environment[variable] { setenv(variable, value, 1) } else { unsetenv(variable) }
            }
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let locations = GlobalConfigurationLocations(home: home, stateRoot: paths.applicationSupportRoot)
        let library = paths.makeLibraryStore()
        let skill = try library.save(SkillEditorDraft(slug: "global-ui", document: "---\nname: global-ui\ndescription: 全局界面测试\n---\n原始正文\n"), repositoryRoot: nil)
        let savedFragment = TemplateRecord(title: "全局界面规则", body: "提交变更前说明验证结果。", purpose: "验证全局片段草稿与部署")
        _ = try TemplateStore(rootURL: paths.applicationSupportRoot).save(savedFragment, initial: [])
        let model = AppModel(runtimePaths: paths, globalLocations: locations)
        model.section = .globalConfiguration
        let global = model.globalConfiguration
        global.refresh()
        global.setSkill(skill.id, enabled: true)
        let fragment = try XCTUnwrap(model.snapshot.templates.first { $0.id == savedFragment.id })
        global.setInstruction(fragment.id, enabled: true)
        let restarted = GlobalConfigurationModel(paths: paths, locations: locations)
        restarted.refresh()
        XCTAssertEqual(restarted.draft.skillIDs, [skill.id])
        XCTAssertEqual(restarted.draft.instructionIDs, [fragment.id])

        let controller = NSHostingController(rootView: ContentView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer { window.close() }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(100))
            controller.view.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(controller.view.fittingSize.height, 701)
            XCTAssertLessThanOrEqual(controller.view.fittingSize.width, 1081)
            let table = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSTableView }.first)
            XCTAssertEqual(table.selectedRow, 1)
            let bitmap = try XCTUnwrap(controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
            controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/perch-global-\(appearance == .aqua ? "light" : "dark").png"))
        }
        let plan = try XCTUnwrap(global.prepareDeployment(), global.error ?? "")
        model.preparedPlan = plan
        model.planPresented = true
        let target = locations.skillsRoot(.codex).appendingPathComponent("global-ui/SKILL.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        model.dismissPlan()
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        model.preparedPlan = try XCTUnwrap(global.prepareDeployment())
        XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.lastAction)
        XCTAssertTrue(try String(contentsOf: target, encoding: .utf8).contains("原始正文"))
        XCTAssertTrue(global.inspection?.hasManagement == true)
        XCTAssertEqual(global.operations.count, 1)
        model.preparedPlan = try XCTUnwrap(global.prepareRestore(.baseline), global.error ?? "")
        XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.lastAction)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertTrue(global.draft.skillIDs.isEmpty)
        XCTAssertTrue(global.draft.instructionIDs.isEmpty)
        XCTAssertEqual(global.operations.count, 2)
        global.selectHost(.claudeCode)
        XCTAssertTrue(global.draft.skillIDs.isEmpty)
        XCTAssertTrue(global.operations.isEmpty)
        global.setSkill(skill.id, enabled: true)
        let claudePlan = try XCTUnwrap(global.prepareDeployment())
        global.selectHost(.codex)
        model.preparedPlan = claudePlan
        XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.lastAction)
        XCTAssertEqual(global.host, .claudeCode)
        XCTAssertEqual(global.draft.skillIDs, [skill.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: locations.skillsRoot(.claudeCode).appendingPathComponent("global-ui/SKILL.md").path))
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
