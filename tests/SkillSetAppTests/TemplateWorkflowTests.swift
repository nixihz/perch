import Foundation
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class TemplateWorkflowTests: XCTestCase {
    func testProjectReferenceNavigatesToOwningHarnessWithoutChangingDraftOrFiles() throws {
        try fixture { root, paths, locations in
            let project = root.appendingPathComponent("目标项目")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let model = AppModel(runtimePaths: paths, globalLocations: locations)
            XCTAssertTrue(model.registerProject(project))
            let projectID = try XCTUnwrap(model.selectedProject).id
            let template = try save(model, name: "Claude 专用规则", body: "仅用于 Claude。")
            model.selectProjectHost(.claude)
            model.toggleInstruction(template)
            model.prepareDeploymentPlan()
            XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.planError ?? model.lastAction)
            model.selectProjectHost(.codex)

            let anotherProject = root.appendingPathComponent("当前项目")
            try FileManager.default.createDirectory(at: anotherProject, withIntermediateDirectories: true)
            XCTAssertTrue(model.registerProject(anotherProject))
            XCTAssertNotEqual(model.selectedProjectID, projectID)
            let draftURL = ProjectDraftStore(rootURL: paths.applicationSupportRoot).documentURL
            let draftBefore = try Data(contentsOf: draftURL)
            let ruleURL = project.appendingPathComponent("CLAUDE.md")
            let ruleBefore = try Data(contentsOf: ruleURL)
            let plansBefore = try DeploymentPlanStore(rootURL: paths.plansRoot).list().map(\.id)

            let references = try model.templateReferences(template.id)
            XCTAssertEqual(references.count, 1)
            let reference = try XCTUnwrap(references.first)
            XCTAssertEqual(reference.name, "目标项目 · Claude Code")
            XCTAssertTrue(reference.inDraft)
            XCTAssertTrue(reference.isApplied)
            model.showTemplateReference(reference)

            XCTAssertEqual(model.section, .projects)
            XCTAssertEqual(model.selectedProjectID, projectID)
            XCTAssertEqual(model.selectedProject?.editingAgent, "claude-code")
            XCTAssertEqual(model.selectedProject?.fragments, [template.id])
            XCTAssertEqual(try Data(contentsOf: draftURL), draftBefore, "查看使用位置不能修改任何宿主的草稿")
            XCTAssertEqual(try Data(contentsOf: ruleURL), ruleBefore)
            XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent("AGENTS.md").path))
            XCTAssertEqual(try DeploymentPlanStore(rootURL: paths.plansRoot).list().map(\.id), plansBefore)
        }
    }

    func testProjectReferenceStatusesSeparateUnappliedDraftFromPendingRemoval() throws {
        try fixture { root, paths, locations in
            let project = root.appendingPathComponent("分开配置")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let model = AppModel(runtimePaths: paths, globalLocations: locations)
            XCTAssertTrue(model.registerProject(project))
            let template = try save(model, name: "分别使用的规则", body: "需要核对的正文。")
            model.selectProjectHost(.claude)
            model.toggleInstruction(template)
            model.prepareDeploymentPlan()
            XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.planError ?? model.lastAction)
            model.toggleInstruction(template)
            model.selectProjectHost(.codex)
            model.toggleInstruction(template)
            var updated = TemplateEditorDraft(template: template)
            updated.body = "已经更新但尚未写入的正文。"
            XCTAssertTrue(model.saveTemplate(updated))

            let references = try model.templateReferences(template.id)
            XCTAssertEqual(references.count, 2)
            XCTAssertEqual(Set(references.map(\.id)).count, 2)
            let codex = try XCTUnwrap(references.first { $0.name == "分开配置 · Codex" })
            XCTAssertTrue(codex.inDraft)
            XCTAssertFalse(codex.isApplied)
            XCTAssertFalse(codex.needsUpdate)
            let claude = try XCTUnwrap(references.first { $0.name == "分开配置 · Claude Code" })
            XCTAssertFalse(claude.inDraft)
            XCTAssertTrue(claude.isApplied)
            XCTAssertTrue(claude.needsUpdate)
            model.showTemplateReference(claude)
            XCTAssertEqual(model.selectedProject?.editingAgent, "claude-code")
            XCTAssertTrue(try XCTUnwrap(model.selectedProject).fragments.isEmpty)
            model.showTemplateReference(codex)
            XCTAssertEqual(model.selectedProject?.editingAgent, "codex")
            XCTAssertEqual(model.selectedProject?.fragments, [template.id])
            XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent("AGENTS.md").path))
            let written = try String(contentsOf: project.appendingPathComponent("CLAUDE.md"), encoding: .utf8)
            XCTAssertTrue(written.contains("需要核对的正文。"))
            XCTAssertFalse(written.contains(updated.body))
        }
    }

    func testProjectPreviewApprovalUpdateAndRemovalPreserveOtherSelectionsAndHandwrittenRules() throws {
        try fixture { root, paths, locations in
            let projectURL = root.appendingPathComponent("项目 空格")
            try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
            for name in ["AGENTS.md", "CLAUDE.md"] {
                try "# 手写约定\n不要删除这一行。\n".write(to: projectURL.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
            let skill = try SkillLibraryStore(rootURL: paths.libraryRoot).save(
                SkillEditorDraft(slug: "keep", document: "---\nname: keep\ndescription: 保留既有选择\n---\n技能正文\n"), repositoryRoot: nil)
            let model = AppModel(runtimePaths: paths, globalLocations: locations)
            XCTAssertTrue(model.registerProject(projectURL))
            let other = try save(model, name: "另一条规则", body: "保留其他片段。")
            model.toggleInstruction(other)
            model.toggleSkill(skill)
            model.toggleAgent(.claude)
            model.selectProjectHost(.codex)
            let template = try save(model, name: "接口约定", body: "检查超时。")
            let target = TemplateUseTarget.project(try XCTUnwrap(model.selectedProject).id)
            let draftFile = ProjectDraftStore(rootURL: paths.applicationSupportRoot).documentURL
            let originalDraft = try Data(contentsOf: draftFile)
            let preview = try model.templateUsePreview(templateID: template.id, target: target)
            XCTAssertEqual(preview.skillCount, 1)
            XCTAssertTrue(preview.body.contains("保留其他片段。"))
            XCTAssertEqual(Set(preview.paths.map { URL(fileURLWithPath: $0).lastPathComponent }), ["AGENTS.md"])
            XCTAssertEqual(try Data(contentsOf: draftFile), originalDraft, "仅打开选择窗口不保存草稿")
            XCTAssertTrue(model.prepareTemplateUse(templateID: template.id, target: target, preview: preview), model.templateError ?? "")
            let plan = try XCTUnwrap(model.preparedPlan)
            XCTAssertFalse(plan.plan.warnings.map { UserFacingText.diagnostic($0, context: .plan) }.contains { $0.contains("无法识别") })
            XCTAssertThrowsError(try SkillSetService(paths: paths, globalLocations: locations).apply(planID: plan.id, digest: plan.plan.digest))
            for path in preview.paths { XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "# 手写约定\n不要删除这一行。\n") }
            let change = try XCTUnwrap(plan.plan.changes.first { $0.relativePath == "AGENTS.md" })
            let content = try RuleFilePreview.load(record: plan, change: change)
            XCTAssertEqual(content.before, "# 手写约定\n不要删除这一行。\n")
            XCTAssertTrue(try XCTUnwrap(content.after).contains("检查超时。"))
            XCTAssertTrue(content.diff.contains("+检查超时。"))
            model.dismissPlan()
            XCTAssertFalse(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent(".agents/skills/keep").path))
            let next = try model.templateUsePreview(templateID: template.id, target: target)
            XCTAssertTrue(model.prepareTemplateUse(templateID: template.id, target: target, preview: next))
            XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.planError ?? model.lastAction)
            XCTAssertEqual(model.lastTemplateWritePaths.count, 1)
            XCTAssertTrue(try model.templateReferences(template.id).contains { $0.isApplied && $0.inDraft })
            var edit = TemplateEditorDraft(template: template)
            edit.body = "检查超时和重试上限。"
            XCTAssertTrue(model.saveTemplate(edit))
            XCTAssertTrue(try model.templateReferences(template.id).contains { $0.isApplied && $0.needsUpdate })
            for path in preview.paths { XCTAssertFalse(try String(contentsOfFile: path, encoding: .utf8).contains("重试上限")) }
            let updated = try model.templateUsePreview(templateID: template.id, target: target)
            XCTAssertTrue(model.prepareTemplateUse(templateID: template.id, target: target, preview: updated))
            XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.planError ?? model.lastAction)
            for path in preview.paths {
                let text = try String(contentsOfFile: path, encoding: .utf8)
                XCTAssertTrue(text.hasPrefix("# 手写约定\n不要删除这一行。\n"))
                XCTAssertTrue(text.contains("重试上限"))
                XCTAssertTrue(text.contains("保留其他片段。"))
            }
            model.toggleInstructionID(template.id)
            model.prepareDeploymentPlan()
            XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.lastAction)
            XCTAssertTrue(try model.templateReferences(template.id).isEmpty)
            model.removeTemplate(template)
            XCTAssertFalse(model.snapshot.templates.contains { $0.id == template.id })
            XCTAssertNil(model.templateError)
            XCTAssertEqual(try String(contentsOf: projectURL.appendingPathComponent(".agents/skills/keep/SKILL.md"), encoding: .utf8), "---\nname: keep\ndescription: 保留既有选择\n---\n技能正文\n")
            for path in preview.paths {
                let text = try String(contentsOfFile: path, encoding: .utf8)
                XCTAssertFalse(text.contains("检查超时"))
                XCTAssertTrue(text.contains("保留其他片段。"))
                XCTAssertTrue(text.hasPrefix("# 手写约定"))
            }
        }
    }

    func testBothGlobalHostsWriteAndRemoveRulesWithoutTouchingOtherHost() throws {
        try fixture { _, paths, locations in
            let model = AppModel(runtimePaths: paths, globalLocations: locations)
            let template = try save(model, name: "全局约定", body: "全局接口约定。")
            for host in MCPHost.allCases {
                let file = locations.rulesURL(host)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try "手写全局约定\n".write(to: file, atomically: true, encoding: .utf8)
                let preview = try model.templateUsePreview(templateID: template.id, target: .global(host))
                XCTAssertEqual(preview.paths, [file.path])
                XCTAssertTrue(model.prepareTemplateUse(templateID: template.id, target: .global(host), preview: preview), model.templateError ?? "")
                let plan = try XCTUnwrap(model.preparedPlan)
                let change = try XCTUnwrap(plan.plan.changes.first { URL(fileURLWithPath: $0.relativePath).lastPathComponent == file.lastPathComponent })
                XCTAssertTrue(try XCTUnwrap(RuleFilePreview.load(record: plan, change: change).after).contains("全局接口约定。"))
                XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "手写全局约定\n")
                XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.planError ?? model.lastAction)
                XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).contains("全局接口约定。"))
            }
            XCTAssertEqual(try model.templateReferences(template.id).filter(\.isApplied).count, 2)
            let claudeBefore = try Data(contentsOf: locations.rulesURL(.claudeCode))
            model.globalConfiguration.selectHost(.codex)
            model.globalConfiguration.setInstruction(template.id, enabled: false)
            model.preparedPlan = try XCTUnwrap(model.globalConfiguration.prepareDeployment(), model.globalConfiguration.error ?? "")
            XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.lastAction)
            XCTAssertEqual(try String(contentsOf: locations.rulesURL(.codex), encoding: .utf8), "手写全局约定\n")
            XCTAssertEqual(try Data(contentsOf: locations.rulesURL(.claudeCode)), claudeBefore)
            XCTAssertEqual(try model.templateReferences(template.id).filter(\.isApplied).count, 1)
        }
    }

    func testChangedDraftCannotBeSubmittedUsingAnOldPreview() throws {
        try fixture { root, paths, locations in
            let project = root.appendingPathComponent("project")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let model = AppModel(runtimePaths: paths, globalLocations: locations)
            XCTAssertTrue(model.registerProject(project))
            let template = try save(model, name: "目标检查", body: "核对目标。")
            let target = TemplateUseTarget.project(try XCTUnwrap(model.selectedProject).id)
            let preview = try model.templateUsePreview(templateID: template.id, target: target)
            let another = try save(model, name: "其他规则", body: "更新草稿。")
            model.toggleInstructionID(another.id)
            XCTAssertFalse(model.prepareTemplateUse(templateID: template.id, target: target, preview: preview))
            XCTAssertNotNil(model.templateError)
            XCTAssertNil(model.preparedPlan)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: project.path), [])
            XCTAssertTrue(try DeploymentPlanStore(rootURL: paths.plansRoot).list().isEmpty)
        }
    }

    func testExternalEditAfterPlanIsNotOverwrittenAndFailureIsVisibleInsidePlan() throws {
        try fixture { root, paths, locations in
            let project = root.appendingPathComponent("project")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let model = AppModel(runtimePaths: paths, globalLocations: locations)
            XCTAssertTrue(model.registerProject(project))
            let template = try save(model, name: "规则检查", body: "检查规则。")
            let target = TemplateUseTarget.project(try XCTUnwrap(model.selectedProject).id)
            let preview = try model.templateUsePreview(templateID: template.id, target: target)
            XCTAssertTrue(model.prepareTemplateUse(templateID: template.id, target: target, preview: preview))
            let plan = try XCTUnwrap(model.preparedPlan)
            let change = try XCTUnwrap(plan.plan.changes.first { $0.relativePath == "AGENTS.md" })
            let file = project.appendingPathComponent("AGENTS.md")
            try "刚刚新增的外部编辑\n".write(to: file, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try RuleFilePreview.load(record: plan, change: change))
            model.planPresented = true
            XCTAssertFalse(model.approveAndApplyPreparedPlan())
            XCTAssertNotNil(model.planError)
            XCTAssertTrue(model.planPresented)
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "刚刚新增的外部编辑\n")
            XCTAssertTrue(model.lastTemplateWritePaths.isEmpty)
        }
    }

    func testCorruptReferenceStoreDoesNotPreventDeletingOwnLibraryEntry() throws {
        try fixture { _, paths, locations in
            let model = AppModel(runtimePaths: paths, globalLocations: locations)
            let template = try save(model, name: "保留片段", body: "必须保留。")
            try Data("broken".utf8).write(to: paths.applicationSupportRoot.appendingPathComponent("presets.json"))
            model.removeTemplate(template)
            XCTAssertNil(model.templateError)
            XCTAssertFalse(try TemplateStore(rootURL: paths.applicationSupportRoot).list(merging: []).contains { $0.id == template.id })
            XCTAssertEqual(try String(contentsOf: paths.applicationSupportRoot.appendingPathComponent("presets.json"), encoding: .utf8), "broken")
        }
    }

    func testEnablingUnconfiguredHostStillRejectsChangedStagingBeforeWritingProject() throws {
        try fixture { root, paths, locations in
            let project = root.appendingPathComponent("project")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let model = AppModel(runtimePaths: paths, globalLocations: locations)
            XCTAssertTrue(model.registerProject(project))
            let template = try save(model, name: "预览核对", body: "必须审阅这行。")
            let target = TemplateUseTarget.project(try XCTUnwrap(model.selectedProject).id)
            model.toggleAgent(.codex)
            let draftURL = ProjectDraftStore(rootURL: paths.applicationSupportRoot).documentURL
            let beforePreview = try Data(contentsOf: draftURL)
            let preview = try model.templateUsePreview(templateID: template.id, target: target)
            XCTAssertEqual(try Data(contentsOf: draftURL), beforePreview)
            XCTAssertNil(model.selectedProject?.harnessSelections["codex"])
            XCTAssertTrue(model.prepareTemplateUse(templateID: template.id, target: target, preview: preview))
            let plan = try XCTUnwrap(model.preparedPlan)
            let change = try XCTUnwrap(plan.plan.changes.first { $0.relativePath == "AGENTS.md" })
            let staged = URL(fileURLWithPath: plan.stagingPath).appendingPathComponent("AGENTS.md")
            try "替换了已预览正文。".write(to: staged, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try RuleFilePreview.load(record: plan, change: change))
            XCTAssertFalse(model.approveAndApplyPreparedPlan())
            XCTAssertNotNil(model.planError)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: project.path), [])
        }
    }

    private func save(_ model: AppModel, name: String, body: String) throws -> TemplateRecord {
        var draft = TemplateEditorDraft()
        draft.title = name; draft.body = body
        XCTAssertTrue(model.saveTemplate(draft), model.templateError ?? "")
        return try XCTUnwrap(model.selectedTemplate)
    }

    private func fixture(_ body: (URL, SkillSetRuntimePaths, GlobalConfigurationLocations) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("template-workflow-\(UUID())")
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
