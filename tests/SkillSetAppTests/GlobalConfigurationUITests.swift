import AppKit
import SwiftUI
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class GlobalConfigurationUITests: XCTestCase {
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
        let library = SkillLibraryStore(rootURL: paths.libraryRoot)
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
