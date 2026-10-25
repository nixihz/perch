import Foundation
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class ProjectPlanFeedbackTests: XCTestCase {
    func testUnchangedDraftShowsInlineNoticeInsteadOfSilentlyDoingNothing() throws {
        try fixture { root, paths, locations in
            let projectURL = root.appendingPathComponent("project")
            try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
            let model = AppModel(runtimePaths: paths, globalLocations: locations)
            XCTAssertTrue(model.registerProject(projectURL))
            let projectID = try XCTUnwrap(model.selectedProject?.id)

            XCTAssertTrue(model.canPrepareDeploymentPlan, "预览只依赖本机状态，不应要求仓库根目录")
            model.prepareDeploymentPlan()
            XCTAssertTrue(model.planPresented)
            XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.planError ?? model.lastAction)

            model.prepareDeploymentPlan()
            XCTAssertFalse(model.planPresented)
            XCTAssertNil(model.preparedPlan)
            let notice = try XCTUnwrap(model.projectPlanNotice(for: projectID))
            XCTAssertEqual(notice.tone, .info)
            XCTAssertEqual(
                notice.message,
                L10n.tr("草稿与项目现状一致，没有需要写入的变更。")
            )
        }
    }

    func testDraftChangePreparesPlanWithoutRepositoryRootAndClearsNotice() throws {
        try fixture { root, paths, locations in
            let projectURL = root.appendingPathComponent("project")
            try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
            let model = AppModel(runtimePaths: paths, globalLocations: locations)
            XCTAssertTrue(model.registerProject(projectURL))
            let projectID = try XCTUnwrap(model.selectedProject?.id)
            var editor = TemplateEditorDraft()
            editor.title = "接口约定"
            editor.body = "检查超时。"
            XCTAssertTrue(model.saveTemplate(editor), model.templateError ?? "")
            let template = try XCTUnwrap(model.selectedTemplate)
            model.toggleInstruction(template)

            XCTAssertNil(model.projectPlanNotice(for: projectID))
            model.prepareDeploymentPlan()

            XCTAssertTrue(model.planPresented)
            XCTAssertNotNil(model.preparedPlan)
            XCTAssertNil(model.projectPlanNotice(for: projectID))
            XCTAssertFalse(try DeploymentPlanStore(rootURL: paths.plansRoot).list().isEmpty)
        }
    }

    func testUnknownDraftSnippetIsPrunedWithoutBlockingProjectPage() throws {
        try fixture { root, paths, locations in
            let projectURL = root.appendingPathComponent("project")
            try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
            let first = AppModel(runtimePaths: paths, globalLocations: locations)
            XCTAssertTrue(first.registerProject(projectURL))
            let projectID = try XCTUnwrap(first.selectedProject?.id)
            try ProjectDraftStore(rootURL: paths.applicationSupportRoot).save(
                projectID: try XCTUnwrap(UUID(uuidString: projectID)),
                skillIDs: [],
                instructionIDs: ["9e002334-4d8d-44fa-a4aa-b75b5ea5b859"],
                agents: ["codex"]
            )

            let restarted = AppModel(runtimePaths: paths, globalLocations: locations)
            restarted.prepareDeploymentPlan()

            XCTAssertTrue(restarted.selectedProject?.fragments.isEmpty == true)
            XCTAssertFalse(restarted.lastAction.contains("已删除的 AGENTS 片段"))
        }
    }

    func testSwitchingHarnessClearsNoticeFromAnotherHarness() throws {
        try fixture { root, paths, locations in
            let projectURL = root.appendingPathComponent("project")
            try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
            let model = AppModel(runtimePaths: paths, globalLocations: locations)
            XCTAssertTrue(model.registerProject(projectURL))
            let projectID = try XCTUnwrap(model.selectedProject?.id)
            model.prepareDeploymentPlan()
            XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.planError ?? model.lastAction)
            model.prepareDeploymentPlan()
            XCTAssertEqual(model.projectPlanNotice(for: projectID)?.tone, .info)

            let draftURL = ProjectDraftStore(rootURL: paths.applicationSupportRoot).documentURL
            let draftBefore = try Data(contentsOf: draftURL)
            model.selectProjectHost(.claude)
            XCTAssertNil(model.projectPlanNotice(for: projectID))
            XCTAssertEqual(model.selectedProject?.editingAgent, "claude-code")
            XCTAssertEqual(try Data(contentsOf: draftURL), draftBefore, "切换编辑工具不修改草稿文件")
        }
    }

    func testLoadingChangedPresetClearsNoChangesNoticeAndProducesPendingPlan() throws {
        try fixture { root, paths, locations in
            let projectURL = root.appendingPathComponent("project")
            try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
            let model = AppModel(runtimePaths: paths, globalLocations: locations)
            XCTAssertTrue(model.registerProject(projectURL))
            let projectID = try XCTUnwrap(model.selectedProject?.id)
            var editor = TemplateEditorDraft()
            editor.title = "预设规则"
            editor.body = "保留用户文件。"
            XCTAssertTrue(model.saveTemplate(editor), model.templateError ?? "")
            let template = try XCTUnwrap(model.selectedTemplate)
            model.prepareDeploymentPlan()
            XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.planError ?? model.lastAction)
            model.prepareDeploymentPlan()
            XCTAssertEqual(model.projectPlanNotice(for: projectID)?.tone, .info)

            let preset = PresetRecord(id: "changed-rules", name: "新的规则", description: "", skills: [], instructionFragments: [template.id])
            XCTAssertTrue(model.loadPreset(preset))
            XCTAssertNil(model.projectPlanNotice(for: projectID))
            XCTAssertEqual(model.selectedProject?.fragments, [template.id])
            model.prepareDeploymentPlan()
            XCTAssertTrue(model.planPresented)
            XCTAssertEqual(model.preparedPlan?.approvalState, .pending)
            XCTAssertFalse(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("AGENTS.md").path))
        }
    }

    private func fixture(_ body: (URL, SkillSetRuntimePaths, GlobalConfigurationLocations) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("project-plan-feedback-\(UUID().uuidString)")
        let paths = SkillSetRuntimePaths(
            applicationSupportRoot: root.appendingPathComponent("state"),
            repositoryRoot: nil
        )
        let locations = GlobalConfigurationLocations(home: root.appendingPathComponent("home"),
                                                     stateRoot: paths.applicationSupportRoot)
        let keys = ["CFFIXED_USER_HOME", "SKILLSET_HOME", "CODEX_HOME", "CLAUDE_CONFIG_DIR"]
        let saved = ProcessInfo.processInfo.environment
        for key in keys { setenv(key, root.appendingPathComponent(key).path, 1) }
        defer {
            for key in keys { if let value = saved[key] { setenv(key, value, 1) } else { unsetenv(key) } }
            try? FileManager.default.removeItem(at: root)
        }
        try body(root, paths, locations)
    }
}
