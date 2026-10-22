import Foundation
import XCTest
import SkillSetCore

@MainActor
final class TemplateWorkflowUITests: XCTestCase {
    func testCreateSnippetChooseProjectReviewCancelThenApproveAndReadBack() throws {
        guard NativeUIHarness.canRunInCurrentEnvironment else { throw XCTSkip(NativeUIHarness.unavailableReason) }
        let world = try BDDWorld()
        defer { world.cleanup() }
        try world.registerProject(named: "snippet-demo")
        try world.launchNativeUI()
        let ui = try XCTUnwrap(world.nativeUI)
        do {
            let project = try XCTUnwrap(ProjectStore(rootURL: ui.applicationSupportRoot).list().first)
            let file = URL(fileURLWithPath: project.canonicalPath).appendingPathComponent("AGENTS.md")
            try "# 项目手写约定\n保留此行。\n".write(to: file, atomically: true, encoding: .utf8)
            try ui.selectSidebarItem("AGENTS 片段")
            try ui.pressButton(identifier: "templates.create")
            try ui.waitForStaticText("新增片段")
            XCTAssertFalse(try ui.buttonIsEnabled("保存片段"))
            try ui.setText(fieldMatching: "templates.editor.title", to: "接口可靠性")
            try ui.setText(fieldMatching: "规则正文", to: "# 接口规则\n检查超时和重试上限。")
            try ui.pressButton(identifier: "templates.editor.save")
            try ui.waitForButton("用于配置…")
            let template = try XCTUnwrap(TemplateStore(rootURL: ui.applicationSupportRoot).list(merging: []).first)
            let draftStore = ProjectDraftStore(rootURL: ui.applicationSupportRoot)
            let before = try Data(contentsOf: draftStore.documentURL)
            try ui.pressButton(identifier: "templates.use")
            try ui.waitForButton("加入草稿并预览…")
            try ui.waitForStaticText(containing: file.path)
            try ui.captureWindowScreenshot(to: URL(fileURLWithPath: "/tmp/perch-template-target.png"))
            try ui.pressEscapeToCancelPlan()
            try ui.waitForButton("用于配置…")
            XCTAssertEqual(try Data(contentsOf: draftStore.documentURL), before)
            XCTAssertTrue(try ui.planRecords().isEmpty)
            try ui.pressButton(identifier: "templates.use")
            try ui.waitForButton("加入草稿并预览…")
            try ui.pressButton(identifier: "templates.use.preview")
            try ui.waitForButton("批准并写入项目")
            XCTAssertFalse(try ui.hasStaticText(containing: "规则文件或预览内容已改变或无法读取"))
            try ui.waitForStaticText(containing: "+检查超时和重试上限。")
            try ui.captureWindowScreenshot(to: URL(fileURLWithPath: "/tmp/perch-template-diff.png"))
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "# 项目手写约定\n保留此行。\n")
            try ui.pressEscapeToCancelPlan()
            try ui.waitForButton("用于配置…")
            XCTAssertEqual(try draftStore.load(projectID: project.id)?.instructionIDs, [template.id])
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "# 项目手写约定\n保留此行。\n")
            try ui.pressButton(identifier: "templates.use")
            try ui.waitForButton("加入草稿并预览…")
            try ui.pressButton(identifier: "templates.use.preview")
            try ui.waitForButton("批准并写入项目")
            try ui.pressButton("批准并写入项目")
            try ui.waitForConfirmationAlert()
            try ui.pressButton(identifier: "action-button-1")
            try ui.waitForStaticText("规则文件已写入并回读，AI 工具加载待验证。")
            XCTAssertEqual(try ManagedBlocks.extract(original: String(contentsOf: file, encoding: .utf8), id: "project-rules"), "# 接口规则\n检查超时和重试上限。")
            XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).hasPrefix("# 项目手写约定\n保留此行。\n"))
            XCTAssertTrue(try ui.buttonIsEnabled("删除"))
            try ui.captureWindowScreenshot(to: URL(fileURLWithPath: "/tmp/perch-template-result.png"))
        } catch {
            try? ui.accessibilityDebugDescription().write(toFile: "/tmp/perch-template-ui-ax.txt", atomically: true, encoding: .utf8)
            throw error
        }
    }
    func testGlobalTargetWithoutProjectsShowsScopeAndWritesOnlyAfterApproval() throws {
        guard NativeUIHarness.canRunInCurrentEnvironment else { throw XCTSkip(NativeUIHarness.unavailableReason) }
        let world = try BDDWorld()
        defer { world.cleanup() }
        try world.launchNativeUI()
        let ui = try XCTUnwrap(world.nativeUI)
        try ui.selectSidebarItem("AGENTS 片段")
        try ui.pressButton(identifier: "templates.use")
        try ui.waitForStaticText("请先添加项目目录，再使用片段。")
        XCTAssertFalse(try ui.buttonIsEnabled("加入草稿并预览…"))
        try ui.selectRadioButton("全局配置")
        try ui.waitForButton("加入草稿并预览…")
        XCTAssertTrue(try ui.hasStaticText("影响当前用户在该 AI 工具中的全部项目。"))
        try ui.pressButton(identifier: "templates.use.preview")
        try ui.waitForButton("批准并更新全局配置")
        let plan = try XCTUnwrap(ui.planRecords().first)
        XCTAssertEqual(plan.plan.metadata?["globalHost"], "codex")
        let change = try XCTUnwrap(plan.plan.changes.first { URL(fileURLWithPath: $0.relativePath).lastPathComponent == "AGENTS.md" })
        let target = URL(fileURLWithPath: plan.plan.projectPath).appendingPathComponent(change.relativePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        try ui.pressButton("批准并更新全局配置")
        try ui.waitForConfirmationAlert()
        try ui.pressButton(identifier: "action-button-1")
        try ui.waitForStaticText("规则文件已写入并回读，AI 工具加载待验证。")
        let body = try XCTUnwrap(AppSnapshot.load().templates.first { $0.id == "base-zh" }?.body)
        XCTAssertEqual(try ManagedBlocks.extract(original: String(contentsOf: target, encoding: .utf8), id: "global-rules"), body.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertTrue(try ProjectStore(rootURL: ui.applicationSupportRoot).list().isEmpty)
    }

}
