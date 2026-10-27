import AppKit
import SwiftUI
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class ProjectConfigurationLayoutTests: XCTestCase {
    func testSharedSkillFolderExplainsFailedSaveAndPointsToTheLinkWithoutChangingIt() throws {
        try fixture { root, _, _, model in
            let project = root.appendingPathComponent("shared-skills")
            let skills = project.appendingPathComponent(".agents/skills")
            let claude = project.appendingPathComponent(".claude/skills")
            try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: claude.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(atPath: claude.path, withDestinationPath: "../.agents/skills")
            XCTAssertTrue(model.registerProject(project))
            let skill = try XCTUnwrap(model.snapshot.catalog.entries.first)
            model.setSkill(skill, enabled: true, host: .claudeCode)
            model.prepareDeploymentPlan(host: .claudeCode)
            let notice = try XCTUnwrap(model.projectPlanNotice(for: model.selectedProjectID))
            XCTAssertEqual(notice.message, "Claude Code 和 Codex 共用技能文件夹，暂时无法分别保存。请改用独立文件夹。")
            XCTAssertEqual(notice.relatedPath, claude.path)
            XCTAssertNil(model.preparedPlan)
            XCTAssertFalse(model.planPresented)
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: claude.path), "../.agents/skills")
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: skills.path).isEmpty)
            XCTAssertTrue(model.isDraftSelected(skill, host: .claudeCode))
            let notes = model.projectIssues[model.selectedProjectID] ?? []
            XCTAssertTrue(notes.contains { UserFacingText.isInformationalProjectNote($0) })
        }
    }

    func testPreviewSavesRelatedInstallUpdatesAndKeepsOtherHarnessDraft() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (paths, locations) = try seed(root)
        let model = AppModel(runtimePaths: paths, globalLocations: locations)
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        XCTAssertTrue(model.registerProject(project))
        let skill = try XCTUnwrap(model.snapshot.catalog.entries.first)
        let snippet = try XCTUnwrap(model.snapshot.templates.first)
        model.skillInstallMethod = .copy
        for host in MCPHost.allCases {
            model.setSkill(skill, enabled: true, host: host)
            model.prepareDeploymentPlan(host: host)
            XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.lastAction)
        }
        let codexSkill = project.appendingPathComponent(".agents/skills/fixture")
        let claudeSkill = project.appendingPathComponent(".claude/skills/fixture")
        let original = try Data(contentsOf: codexSkill.appendingPathComponent("SKILL.md"))
        model.setSkill(skill, enabled: false, host: .codex)
        model.setInstruction(snippet.id, enabled: true, host: .codex)
        model.skillInstallMethod = .symlink
        model.prepareDeploymentPlan(host: .claudeCode)
        let plan = try XCTUnwrap(model.preparedPlan, model.lastAction)
        XCTAssertNil(model.projectPlanNotice(for: model.selectedProjectID))
        XCTAssertTrue(model.planPresented)
        XCTAssertTrue(plan.plan.changes.contains { $0.relativePath == ".agents/skills/fixture" })
        XCTAssertTrue(plan.plan.changes.contains { $0.relativePath == ".claude/skills/fixture" })
        XCTAssertFalse(plan.plan.changes.contains { $0.relativePath == "AGENTS.md" })
        XCTAssertEqual(try Data(contentsOf: codexSkill.appendingPathComponent("SKILL.md")), original)
        XCTAssertThrowsError(try FileManager.default.destinationOfSymbolicLink(atPath: codexSkill.path))

        let controller = NSHostingController(rootView: PlanSheet(model: model, savesFromPreview: true))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 680),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(200))
        controller.view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to:
            URL(fileURLWithPath: "/tmp/perch-related-updates-preview.png"))

        XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.lastAction)
        for url in [codexSkill, claudeSkill] {
            XCTAssertFalse(try FileManager.default.destinationOfSymbolicLink(atPath: url.path).isEmpty)
            XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("SKILL.md")), original)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent("AGENTS.md").path))
        let restarted = AppModel(runtimePaths: paths, globalLocations: locations)
        XCTAssertFalse(restarted.isDraftSelected(skill, host: .codex))
        XCTAssertEqual(restarted.selectedProject?.harnessSelections["codex"]?.instructionIDs, [snippet.id])
        let manifest = try XCTUnwrap(ProjectLockStore(projectRoot: project, stateRoot: paths.applicationSupportRoot).loadManifest())
        XCTAssertEqual(manifest.selection(for: "codex").skillIDs, [skill.id])
        XCTAssertTrue(manifest.selection(for: "codex").instructionIDs.isEmpty)
    }

    func testPreviewIncludesSharedContentUpdatesWithoutInstallingOtherHarnessDraft() throws {
        try fixture { root, paths, _, model in
            let project = root.appendingPathComponent("project")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            XCTAssertTrue(model.registerProject(project))
            let skill = try XCTUnwrap(model.snapshot.catalog.entries.first)
            let snippet = try XCTUnwrap(model.snapshot.templates.first)
            model.skillInstallMethod = .copy
            for host in MCPHost.allCases {
                model.setSkill(skill, enabled: true, host: host)
                model.prepareDeploymentPlan(host: host)
                XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.lastAction)
            }
            model.setInstruction(snippet.id, enabled: true, host: .codex)
            var draft = try XCTUnwrap(model.editorDraft(for: skill))
            draft.document += "\n更新后的共享正文。\n"
            XCTAssertTrue(model.saveSkill(draft), model.lastAction)
            model.prepareDeploymentPlan(host: .claudeCode)
            let plan = try XCTUnwrap(model.preparedPlan, model.lastAction)
            XCTAssertFalse(plan.plan.changes.contains { $0.relativePath == "AGENTS.md" })
            for path in [".agents/skills/fixture", ".claude/skills/fixture"] {
                XCTAssertFalse(try String(contentsOf: project.appendingPathComponent(path + "/SKILL.md"), encoding: .utf8).contains("更新后的共享正文。"))
            }
            XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.lastAction)
            for path in [".agents/skills/fixture", ".claude/skills/fixture"] {
                XCTAssertTrue(try String(contentsOf: project.appendingPathComponent(path + "/SKILL.md"), encoding: .utf8).contains("更新后的共享正文。"))
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent("AGENTS.md").path))
            XCTAssertEqual(try ProjectDraftStore(rootURL: paths.applicationSupportRoot)
                .load(projectID: XCTUnwrap(UUID(uuidString: model.selectedProjectID)))?
                .resolvedHarnessSelections["codex"]?.instructionIDs, [snippet.id])
        }
    }

    func testProjectSwitchKeepsBothHarnessDraftsAndPreviewSavesOnlyTheRequestedTarget() throws {
        try fixture { root, paths, locations, model in
            let first = root.appendingPathComponent("first")
            let second = root.appendingPathComponent("second")
            try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
            let skill = try XCTUnwrap(model.snapshot.catalog.entries.first)
            let snippet = try XCTUnwrap(model.snapshot.templates.first)
            XCTAssertTrue(model.registerProject(first))
            let firstID = model.selectedProjectID
            model.setSkill(skill, enabled: true, host: .codex)
            model.setInstruction(snippet.id, enabled: true, host: .claudeCode)
            XCTAssertEqual(model.selectedProject?.editingAgent, "codex")
            XCTAssertTrue(model.registerProject(second))
            let secondID = model.selectedProjectID
            model.setSkill(skill, enabled: true, host: .claudeCode)
            model.setInstruction(snippet.id, enabled: true, host: .codex)
            model.selectedProjectID = firstID
            model.prepareDeploymentPlan(host: .claudeCode)
            let plan = try XCTUnwrap(model.preparedPlan, model.lastAction)
            XCTAssertTrue(plan.plan.changes.contains { $0.relativePath == "CLAUDE.md" })
            XCTAssertFalse(plan.plan.changes.contains { $0.relativePath.hasPrefix(".agents/skills/") })
            XCTAssertEqual(model.selectedProject?.editingAgent, "codex")
            model.dismissPlan()
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: first.path).isEmpty)
            model.prepareDeploymentPlan(host: .claudeCode)
            XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.lastAction)
            XCTAssertTrue(try String(contentsOf: first.appendingPathComponent("CLAUDE.md"), encoding: .utf8).contains(snippet.body))
            XCTAssertFalse(FileManager.default.fileExists(atPath: first.appendingPathComponent(".agents/skills").path))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: second.path).isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: locations.rulesURL(.claudeCode).path))
            let restarted = AppModel(runtimePaths: paths, globalLocations: locations)
            restarted.selectedProjectID = firstID
            XCTAssertTrue(restarted.isDraftSelected(skill, host: .codex))
            XCTAssertEqual(restarted.selectedProject?.harnessSelections["claude-code"]?.instructionIDs, [snippet.id])
            restarted.selectedProjectID = secondID
            XCTAssertTrue(restarted.isDraftSelected(skill, host: .claudeCode))
            XCTAssertEqual(restarted.selectedProject?.harnessSelections["codex"]?.instructionIDs, [snippet.id])
        }
    }

    func testSnippetSaveFailurePreservesMemoryAndDiskUntilSuccessfulRetry() throws {
        try fixture { root, paths, _, model in
            let project = root.appendingPathComponent("project")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            XCTAssertTrue(model.registerProject(project))
            let snippet = try XCTUnwrap(model.snapshot.templates.first)
            let url = ProjectDraftStore(rootURL: paths.applicationSupportRoot).documentURL
            let original = try Data(contentsOf: url)
            try Data("broken draft".utf8).write(to: url)
            let before = model.selectedProject
            model.setInstruction(snippet.id, enabled: true, host: .claudeCode)
            XCTAssertEqual(model.selectedProject, before)
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "broken draft")
            XCTAssertEqual(model.projectPlanNotice(for: model.selectedProjectID)?.tone, .error)
            try original.write(to: url)
            model.setInstruction(snippet.id, enabled: true, host: .claudeCode)
            XCTAssertEqual(model.selectedProject?.harnessSelections["claude-code"]?.instructionIDs, [snippet.id])
            XCTAssertNil(model.projectPlanNotice(for: model.selectedProjectID))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: project.path).isEmpty)
        }
    }

    func testSelectorStaysCompactAboveFullWidthConfigurationInBothAppearances() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (paths, locations) = try seed(root)
        let model = AppModel(runtimePaths: paths, globalLocations: locations)
        for name in ["first", "second"] {
            let project = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            XCTAssertTrue(model.registerProject(project))
        }
        let controller = NSHostingController(rootView: ContentView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer { window.close() }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(180))
            controller.view.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(controller.view.fittingSize.width, 1081)
            XCTAssertLessThanOrEqual(controller.view.fittingSize.height, 701)
            let scrolls = descendants(controller.view).compactMap { $0 as? NSScrollView }
            let table = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSTableView }.first)
            let content = scrolls.filter { $0 !== table.enclosingScrollView }
            let selector = try XCTUnwrap(content.first { $0.bounds.height >= 32 && $0.bounds.height <= 36 })
            let resources = try XCTUnwrap(content.first { $0.bounds.height > 100 })
            let selectorRect = selector.convert(selector.bounds, to: controller.view)
            let resourceRect = resources.convert(resources.bounds, to: controller.view)
            XCTAssertGreaterThanOrEqual(selectorRect.minX, resourceRect.minX)
            XCTAssertLessThanOrEqual(selectorRect.maxX, resourceRect.maxX)
            XCTAssertEqual(resourceRect.maxX, controller.view.bounds.maxX - 48, accuracy: 1)
            XCTAssertGreaterThanOrEqual(resourceRect.width, controller.view.bounds.width - 420)
            XCTAssertFalse(selectorRect.intersects(resourceRect))
            XCTAssertGreaterThan(resourceRect.height, 100)
            let bitmap = try XCTUnwrap(controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
            controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath:
                "/tmp/perch-project-stacked-\(appearance == .aqua ? "light" : "dark").png"))
        }
        XCTAssertTrue(try DeploymentPlanStore(rootURL: paths.plansRoot).list().isEmpty)
    }

    func testPluginDraftsDoNotLeakBetweenProjectsAndGlobalScope() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (paths, locations) = try seed(root)
        let manifest = locations.home.appendingPathComponent(".claude/plugins/cache/fixture/example/1/.claude-plugin")
        try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: true)
        try Data(#"{"name":"example","version":"1.0"}"#.utf8).write(to: manifest.appendingPathComponent("plugin.json"))
        let firstID = UUID(), secondID = UUID()
        let first = PluginSelectionModel(paths: paths, home: locations.home, projectID: firstID, projectRoot: root.appendingPathComponent("first"))
        let second = PluginSelectionModel(paths: paths, home: locations.home, projectID: secondID, projectRoot: root.appendingPathComponent("second"))
        let global = PluginSelectionModel(paths: paths, home: locations.home)
        await first.refresh(); await second.refresh(); await global.refresh()
        let plugin = try XCTUnwrap(first.plugins.first)
        first.select(plugin, enabled: true)
        XCTAssertFalse(second.selected(plugin))
        XCTAssertFalse(global.selected(plugin))
        let restarted = PluginSelectionModel(paths: paths, home: locations.home, projectID: firstID)
        await restarted.refresh()
        XCTAssertTrue(restarted.selected(plugin))
        XCTAssertFalse(restarted.acknowledgedRisk)
        XCTAssertTrue(try DeploymentPlanStore(rootURL: paths.plansRoot).list().isEmpty)
    }

    func testProjectResourceImmediateSaveWritesFilesDirectly() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (paths, locations) = try seed(root)
        let model = AppModel(runtimePaths: paths, globalLocations: locations)
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        XCTAssertTrue(model.registerProject(project))
        let skill = try XCTUnwrap(model.snapshot.catalog.entries.first)
        let snippet = try XCTUnwrap(model.snapshot.templates.first)

        // 即时保存项目技能
        let skillSaved = await model.saveProjectSkill(skill, enabled: true, host: .codex)
        XCTAssertTrue(skillSaved)
        let installedSkill = project.appendingPathComponent(".agents/skills/fixture/SKILL.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedSkill.path))

        // 即时保存项目规则片段到 AGENTS.md
        let instructionSaved = await model.saveProjectInstruction(snippet, enabled: true, host: .codex)
        XCTAssertTrue(instructionSaved)
        let agentsFile = project.appendingPathComponent("AGENTS.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: agentsFile.path))
        XCTAssertTrue(try String(contentsOf: agentsFile, encoding: .utf8).contains("提交前运行相关测试。"))

        // 即时取消规则片段
        let instructionCancelled = await model.saveProjectInstruction(snippet, enabled: false, host: .codex)
        XCTAssertTrue(instructionCancelled)
        let updatedAgents = (try? String(contentsOf: agentsFile, encoding: .utf8)) ?? ""
        XCTAssertFalse(updatedAgents.contains("提交前运行相关测试。"))

        // 即时取消项目技能
        let skillCancelled = await model.saveProjectSkill(skill, enabled: false, host: .codex)
        XCTAssertTrue(skillCancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installedSkill.path))
    }

    private func fixture(_ body: (URL, SkillSetRuntimePaths, GlobalConfigurationLocations, AppModel) throws -> Void) throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (paths, locations) = try seed(root)
        try body(root, paths, locations, AppModel(runtimePaths: paths, globalLocations: locations))
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("project-config-\(UUID())")
    }

    private func seed(_ root: URL) throws -> (SkillSetRuntimePaths, GlobalConfigurationLocations) {
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let locations = GlobalConfigurationLocations(home: root.appendingPathComponent("home"), stateRoot: paths.applicationSupportRoot)
        _ = try paths.makeLibraryStore().save(SkillEditorDraft(slug: "fixture",
            document: "---\nname: fixture\ndescription: 项目配置测试\n---\n规则正文\n"), repositoryRoot: nil)
        _ = try TemplateStore(rootURL: paths.applicationSupportRoot).save(TemplateRecord(title: "规则片段", body: "提交前运行相关测试。"), initial: [])
        return (paths, locations)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
