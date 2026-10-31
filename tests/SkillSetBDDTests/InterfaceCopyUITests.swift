import Foundation
import XCTest
import SkillSetCore

/// 冗余界面文案的回归：删掉的解释句不再出现，承担信息的控件、徽标和计数仍然可见。
@MainActor
final class InterfaceCopyUITests: XCTestCase {
    func testAIConnectDetailsDoNotHardcodeToolCount() throws {
        try XCTSkipUnless(NativeUIHarness.canRunInCurrentEnvironment, NativeUIHarness.unavailableReason)
        let harness = try makeHarness()
        defer { harness.stop() }

        try harness.selectSidebarItem("AI 接入")
        try harness.waitForStaticText("把栖集接入 AI 工具")
        try harness.enlargeWindowForLongPage()
        try harness.clickDisclosureLabel(title: "工具与兼容性详情", identifier: "aiAccess.technicalDetails")
        try harness.waitForStaticText("AI 可以生成计划和执行已批准的计划；MCP 不提供批准工具。")
        XCTAssertTrue(try harness.hasStaticText(containing: "目前仅验证了 stdio 连接"))
        XCTAssertFalse(try harness.hasStaticText(containing: "个工具；"),
                       "工具数量随接口增减变化，界面不写死")
        XCTAssertFalse(try harness.hasStaticText(containing: "mcp_batch"))
    }

    func testNewSkillFormKeepsSaveLocationWithoutRepeatingDraftSteps() throws {
        try XCTSkipUnless(NativeUIHarness.canRunInCurrentEnvironment, NativeUIHarness.unavailableReason)
        let harness = try makeHarness()
        defer { harness.stop() }

        try harness.selectSidebarItem("技能库")
        try harness.pressButton(identifier: "skills.create")
        try harness.waitForStaticText("新增技能")
        XCTAssertFalse(try harness.hasStaticText(containing: "编辑完整 SKILL.md"))
        XCTAssertFalse(try harness.hasStaticText(containing: "项目草稿"),
                       "写入项目的步骤由项目页说明一次即可")
        XCTAssertTrue(try harness.hasStaticText("保存位置"), "保存位置仍要告诉用户技能写到哪里")
    }

    func testMCPLibraryKeepsUsageScopeCardWithoutRedundantStateExplanation() throws {
        try XCTSkipUnless(NativeUIHarness.canRunInCurrentEnvironment, NativeUIHarness.unavailableReason)
        let harness = try makeHarness()
        defer { harness.stop() }

        try harness.selectSidebarItem("MCP 服务")
        try harness.waitForStaticText("MCP 配置库")
        try harness.pressButton(identifier: "mcp.library.add")
        try harness.waitForStaticText("MCP 服务配置")
        try harness.setText(fieldMatching: "名称", to: "documentation")
        try harness.setText(fieldMatching: "启动命令", to: "/usr/bin/true")
        try harness.pressButton("保存到配置库")
        try harness.waitForStaticText("使用范围")
        XCTAssertTrue(try harness.hasStaticText(containing: "还没有使用这项服务"))
        XCTAssertFalse(try harness.hasStaticText("草稿选择、历史写入和 AI 工具加载是三个状态。写入记录不代表服务正在运行。"),
                       "使用状态由徽标逐项说明，不再补一段解释")
    }

    func testSnippetUseSheetShowsCountsInsteadOfDraftSentence() throws {
        try XCTSkipUnless(NativeUIHarness.canRunInCurrentEnvironment, NativeUIHarness.unavailableReason)
        let projectURL = try makeProjectDirectory(named: "snippet-copy")
        let harness = try makeHarness(projectURL: projectURL)
        defer { harness.stop() }

        try harness.selectSidebarItem("AGENTS 片段")
        try harness.pressButton(identifier: "templates.create")
        try harness.waitForStaticText("新增片段")
        try harness.setText(fieldMatching: "templates.editor.title", to: "接口可靠性")
        try harness.setText(fieldMatching: "规则正文", to: "# 接口规则\n检查超时和重试上限。")
        try harness.pressButton(identifier: "templates.editor.save")
        try harness.waitForButton("用于配置…")
        try harness.pressButton(identifier: "templates.use")
        try harness.waitForButton("加入草稿并预览…")
        XCTAssertTrue(try harness.hasStaticText(containing: "个技能 · "),
                      "草稿内容用计数说明，不再用整句描述")
        XCTAssertTrue(try harness.hasStaticText(containing: "个片段"))
        XCTAssertFalse(try harness.hasStaticText(containing: "这份配置草稿包含"))
    }

    func testProjectPlanConfirmationKeepsChangeSummaryWithoutRepeatingApprovalBoundary() throws {
        try XCTSkipUnless(NativeUIHarness.canRunInCurrentEnvironment, NativeUIHarness.unavailableReason)
        let projectURL = try makeProjectDirectory(named: "plan-copy")
        let harness = try makeHarness(projectURL: projectURL)
        defer { harness.stop() }

        try harness.selectSidebarItem("AGENTS 片段")
        try harness.pressButton(identifier: "templates.create")
        try harness.waitForStaticText("新增片段")
        try harness.setText(fieldMatching: "templates.editor.title", to: "接口可靠性")
        try harness.setText(fieldMatching: "规则正文", to: "# 接口规则\n检查超时和重试上限。")
        try harness.pressButton(identifier: "templates.editor.save")
        try harness.waitForButton("用于配置…")
        try harness.pressButton(identifier: "templates.use")
        try harness.waitForButton("加入草稿并预览…")
        try harness.pressButton(identifier: "templates.use.preview")
        try harness.waitForButton("批准并写入项目")
        try harness.pressButton("批准并写入项目")
        try harness.waitForConfirmationAlert()
        XCTAssertTrue(try harness.hasStaticText(containing: "项内容。文件内容改变后需要重新生成计划。"),
                      "确认框仍要说明这次会改什么")
        XCTAssertFalse(try harness.hasStaticText(containing: "批准只对本次计划有效"),
                       "批准边界由「批准前须知」说明一次即可")
        try harness.pressEscapeToDismissConfirmation()
    }

    private func makeHarness(
        projectURL: URL? = nil,
        skillIDs: [String] = [],
        instructionIDs: [String] = [],
        agents: [String] = ["codex"],
        librarySkillDocuments: [String: String] = [:]
    ) throws -> NativeUIHarness {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("perch-interface-copy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        return try NativeUIHarness(
            repositoryRoot: try Self.locateRepositoryRoot(),
            temporaryRoot: temporaryRoot,
            projectURL: projectURL,
            projectName: projectURL?.lastPathComponent,
            skillIDs: skillIDs,
            instructionIDs: instructionIDs,
            agents: agents,
            librarySkillDocuments: librarySkillDocuments
        )
    }

    private func makeProjectDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("perch-interface-copy-project-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func locateRepositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while true {
            let candidate = directory.appendingPathComponent("registry/catalog.json")
            if FileManager.default.fileExists(atPath: candidate.path) { return directory }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                throw XCTSkip("找不到包含 registry/catalog.json 的仓库根目录")
            }
            directory = parent
        }
    }
}
