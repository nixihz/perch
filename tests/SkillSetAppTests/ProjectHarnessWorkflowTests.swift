import Foundation
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class ProjectHarnessWorkflowTests: XCTestCase {
    func testTemplateEnablesNewHarnessOnlyAfterConfirmationAndKeepsOtherDraftPending() throws {
        try fixture { root, paths, locations in
            let project = root.appendingPathComponent("project")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let model = AppModel(runtimePaths: paths, globalLocations: locations)
            XCTAssertTrue(model.registerProject(project))
            var editor = TemplateEditorDraft()
            editor.title = "暂留 Codex 草稿"
            editor.body = "这条规则尚未部署。"
            XCTAssertTrue(model.saveTemplate(editor))
            let codexRule = try XCTUnwrap(model.selectedTemplate)
            model.toggleInstruction(codexRule)
            editor = TemplateEditorDraft()
            editor.title = "首次配置 Claude"
            editor.body = "仅加入 Claude 的新规则。"
            XCTAssertTrue(model.saveTemplate(editor))
            let claudeRule = try XCTUnwrap(model.selectedTemplate)
            let target = TemplateUseTarget.project(try XCTUnwrap(model.selectedProject?.id))
            let store = ProjectDraftStore(rootURL: paths.applicationSupportRoot)
            let before = try Data(contentsOf: store.documentURL)

            model.selectProjectHost(.claude)
            let preview = try model.templateUsePreview(templateID: claudeRule.id, target: target)
            XCTAssertEqual(preview.paths, [project.appendingPathComponent("CLAUDE.md").path])
            XCTAssertEqual(try Data(contentsOf: store.documentURL), before, "选目标和读取预览不会保存启用状态")
            XCTAssertNil(model.selectedProject?.harnessSelections["claude-code"])
            XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent("CLAUDE.md").path))

            model.selectProjectHost(.codex)
            XCTAssertFalse(model.prepareTemplateUse(templateID: claudeRule.id, target: target, preview: preview),
                "切换目标后旧预览不能用于启用不同宿主")
            XCTAssertEqual(try Data(contentsOf: store.documentURL), before)
            XCTAssertTrue(try DeploymentPlanStore(rootURL: paths.plansRoot).list().isEmpty)

            model.selectProjectHost(.claude)
            let refreshed = try model.templateUsePreview(templateID: claudeRule.id, target: target)
            XCTAssertTrue(model.prepareTemplateUse(templateID: claudeRule.id, target: target, preview: refreshed), model.templateError ?? "")
            let saved = try XCTUnwrap(store.load(projectID: try XCTUnwrap(UUID(uuidString: model.selectedProjectID))))
            XCTAssertEqual(saved.harnessSelections?["claude-code"]?.instructionIDs, [claudeRule.id])
            XCTAssertEqual(saved.harnessSelections?["codex"]?.instructionIDs, [codexRule.id])
            XCTAssertTrue(saved.agents.contains("claude-code"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent("CLAUDE.md").path),
                "确认加入草稿仍需独立批准文件计划")
            XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.planError ?? model.lastAction)
            XCTAssertTrue(try String(contentsOf: project.appendingPathComponent("CLAUDE.md"), encoding: .utf8).contains(claudeRule.body))
            XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent("AGENTS.md").path))
            XCTAssertEqual(model.selectedProject?.harnessSelections["codex"]?.instructionIDs, [codexRule.id])
        }
    }

    func testSwitchingHarnessKeepsDraftsIndependentAcrossRestartAndApprovedWrites() throws {
        try fixture { root, paths, locations in
            let project = root.appendingPathComponent("project")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let library = SkillLibraryStore(rootURL: paths.libraryRoot)
            let first = try library.save(SkillEditorDraft(slug: "codex-only", document: "---\nname: codex-only\ndescription: Codex 专用\n---\nCodex\n"), repositoryRoot: nil)
            let second = try library.save(SkillEditorDraft(slug: "claude-only", document: "---\nname: claude-only\ndescription: Claude 专用\n---\nClaude\n"), repositoryRoot: nil)
            let model = AppModel(runtimePaths: paths, globalLocations: locations)
            XCTAssertTrue(model.registerProject(project))
            model.toggleSkill(first)
            var rule = TemplateEditorDraft()
            rule.title = "Codex 规则"
            rule.body = "保留 Codex 工作约定。"
            XCTAssertTrue(model.saveTemplate(rule))
            let codexRule = try XCTUnwrap(model.selectedTemplate)
            model.toggleInstruction(codexRule)
            model.prepareDeploymentPlan()
            XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.planError ?? model.lastAction)
            let codexData = try Data(contentsOf: project.appendingPathComponent("AGENTS.md"))
            let codexSkill = try Data(contentsOf: project.appendingPathComponent(".agents/skills/codex-only/SKILL.md"))
            let draftFile = ProjectDraftStore(rootURL: paths.applicationSupportRoot).documentURL
            let beforeSwitch = try Data(contentsOf: draftFile)

            model.selectProjectHost(.claude)
            XCTAssertEqual(try Data(contentsOf: draftFile), beforeSwitch, "切换编辑宿主不能偷偷启用或保存选择")
            XCTAssertTrue(try XCTUnwrap(model.selectedProject).draftSkillIDs.isEmpty)
            XCTAssertNil(model.selectedProject?.harnessSelections["claude-code"])
            model.toggleSkill(second)
            rule = TemplateEditorDraft()
            rule.title = "Claude 规则"
            rule.body = "Claude 使用另一份工作约定。"
            XCTAssertTrue(model.saveTemplate(rule))
            let claudeRule = try XCTUnwrap(model.selectedTemplate)
            model.toggleInstruction(claudeRule)
            model.prepareDeploymentPlan()
            let plan = try XCTUnwrap(model.preparedPlan)
            XCTAssertFalse(plan.plan.changes.contains { $0.relativePath == "AGENTS.md" || $0.relativePath.hasPrefix(".agents/") })
            XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.planError ?? model.lastAction)
            XCTAssertEqual(try Data(contentsOf: project.appendingPathComponent("AGENTS.md")), codexData)
            XCTAssertEqual(try Data(contentsOf: project.appendingPathComponent(".agents/skills/codex-only/SKILL.md")), codexSkill)
            XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent(".agents/skills/claude-only").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent(".claude/skills/codex-only").path))
            XCTAssertTrue(try String(contentsOf: project.appendingPathComponent("CLAUDE.md"), encoding: .utf8).contains("Claude 使用另一份"))

            let restarted = AppModel(runtimePaths: paths, globalLocations: locations)
            XCTAssertEqual(restarted.selectedProject?.draftSkillIDs, [first.id])
            restarted.selectProjectHost(.claude)
            XCTAssertEqual(restarted.selectedProject?.draftSkillIDs, [second.id])
            XCTAssertEqual(restarted.selectedProject?.fragments, [claudeRule.id])
            restarted.toggleAgent(.claude)
            restarted.prepareDeploymentPlan()
            XCTAssertTrue(restarted.approveAndApplyPreparedPlan(), restarted.planError ?? restarted.lastAction)
            XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent(".claude/skills/claude-only").path))
            XCTAssertEqual(try Data(contentsOf: project.appendingPathComponent("AGENTS.md")), codexData)
            XCTAssertEqual(try Data(contentsOf: project.appendingPathComponent(".agents/skills/codex-only/SKILL.md")), codexSkill)
            restarted.selectProjectHost(.codex)
            restarted.toggleAgent(.codex)
            restarted.prepareDeploymentPlan()
            XCTAssertTrue(restarted.approveAndApplyPreparedPlan(), restarted.planError ?? restarted.lastAction)
            XCTAssertEqual(restarted.selectedProject?.pendingChanges, 0)
        }
    }

    func testPresetReplacesOnlyCurrentHarnessAndTemplatePreviewTargetsOneRulesFile() throws {
        try fixture { root, paths, locations in
            let project = root.appendingPathComponent("project")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let model = AppModel(runtimePaths: paths, globalLocations: locations)
            XCTAssertTrue(model.registerProject(project))
            var rule = TemplateEditorDraft()
            rule.title = "共享候选"
            rule.body = "仅加入选中的宿主。"
            XCTAssertTrue(model.saveTemplate(rule))
            let fragment = try XCTUnwrap(model.selectedTemplate)
            model.toggleInstruction(fragment)
            model.selectProjectHost(.claude)
            XCTAssertTrue(model.loadPreset(PresetRecord(id: "empty", name: "空组合", skills: [])))
            XCTAssertEqual(model.selectedProject?.harnessSelections["codex"]?.instructionIDs, [fragment.id])
            XCTAssertEqual(model.selectedProject?.harnessSelections["claude-code"]?.instructionIDs, [])
            let preview = try model.templateUsePreview(templateID: fragment.id, target: .project(try XCTUnwrap(model.selectedProject?.id)))
            XCTAssertEqual(preview.paths, [project.appendingPathComponent("CLAUDE.md").path])
            XCTAssertEqual(preview.projectDraft?.harnessSelections?["codex"]?.instructionIDs, [fragment.id])
            XCTAssertTrue(model.prepareTemplateUse(templateID: fragment.id,
                target: .project(try XCTUnwrap(model.selectedProject?.id)), preview: preview), model.templateError ?? "")
            XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.planError ?? model.lastAction)
            XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent("AGENTS.md").path),
                "只批准 Claude 不能顺带启用 Codex 的未部署草稿")
            XCTAssertEqual(model.selectedProject?.harnessSelections["codex"]?.instructionIDs, [fragment.id])
            model.selectProjectHost(.codex)
            XCTAssertEqual(model.selectedProject?.fragments, [fragment.id])
            model.prepareDeploymentPlan()
            XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.planError ?? model.lastAction)
            XCTAssertTrue(try String(contentsOf: project.appendingPathComponent("AGENTS.md"), encoding: .utf8).contains("仅加入选中的宿主"))
        }
    }

    private func fixture(_ body: (URL, SkillSetRuntimePaths, GlobalConfigurationLocations) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("harness-ui-\(UUID())")
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let locations = GlobalConfigurationLocations(home: root.appendingPathComponent("home"), stateRoot: paths.applicationSupportRoot)
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
