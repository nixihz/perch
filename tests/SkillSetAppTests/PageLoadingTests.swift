import AppKit
import SwiftUI
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class PageLoadingTests: XCTestCase {
    func testHostSwitchBlocksEditsUntilTheNewDraftIsLoaded() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let global = fixture.model.globalConfiguration
        let manager = GlobalConfigurationManager(paths: fixture.paths, locations: fixture.locations)
        let original = GlobalConfigurationDraft(skillIDs: ["existing-skill"], instructionIDs: ["existing-rule"], installMethod: .copy)
        try manager.saveDraft(original, host: .claudeCode)
        // 该测试只验证宿主切换期间的并发保护；显式声明占位条目属于当前目录，避免被悬空引用修复逻辑清理。
        global.setAvailableReferences(skillIDs: ["existing-skill"], instructionIDs: ["existing-rule"])
        global.refresh()
        global.selectHost(.claudeCode, inBackground: true)
        XCTAssertTrue(global.isRefreshing)
        XCTAssertFalse(global.canEditSkills(host: .claudeCode))
        global.setInstruction("early-rule", enabled: true)
        global.setInstallMethod(.symlink)
        XCTAssertEqual(try manager.draft(host: .claudeCode), original, "后台读取开始前也不能用空草稿覆盖已有选择")

        await global.refreshInBackground()
        XCTAssertEqual(global.draft, original)
        XCTAssertTrue(global.canEditSkills(host: .claudeCode))
        global.setInstruction("new-rule", enabled: true)
        let saved = try manager.draft(host: .claudeCode)
        XCTAssertEqual(saved.skillIDs, ["existing-skill"])
        XCTAssertEqual(saved.instructionIDs, ["existing-rule", "new-rule"])
        XCTAssertEqual(saved.installMethod, .copy)
    }

    func testSkillRefreshKeepsPublishedContentOnCancellationAndFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let model = fixture.model
        let firstDocument = "---\nname: first\ndescription: 刷新回归测试\n---\n上次成功读取的正文\n"
        XCTAssertTrue(model.saveSkill(SkillEditorDraft(slug: "first", document: firstDocument)))
        let first = try XCTUnwrap(model.selectedSkill)
        let package = fixture.paths.sourcesRoot.appendingPathComponent(first.path)
        try "附属文件正文\n".write(to: package.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let secondDocument = "---\nname: second\ndescription: 切换回归测试\n---\n第二个技能正文\n"
        XCTAssertTrue(model.saveSkill(SkillEditorDraft(slug: "second", document: secondDocument)))
        let second = try XCTUnwrap(model.selectedSkill)
        model.selectedSkillID = first.id
        await model.loadSelectedSkillDocumentInBackground()
        let file = try XCTUnwrap(model.selectedSkillFiles.first)
        model.openSkillFile(file)
        XCTAssertEqual(model.selectedSkillFilePreview, .text("附属文件正文\n"))
        try FileManager.default.removeItem(at: package)

        let cancelled = Task { await model.loadSelectedSkillDocumentInBackground() }
        cancelled.cancel()
        await cancelled.value
        XCTAssertEqual(model.selectedSkillDocument, firstDocument)
        XCTAssertEqual(model.selectedSkillFiles, [file])
        XCTAssertEqual(model.selectedSkillFilePreview, .text("附属文件正文\n"))
        XCTAssertNil(model.libraryError)

        await model.loadSelectedSkillDocumentInBackground()
        XCTAssertEqual(model.selectedSkillDocument, firstDocument)
        XCTAssertEqual(model.selectedSkillFiles, [file])
        XCTAssertNotNil(model.libraryError)
        XCTAssertNotNil(model.skillFilesError)
        XCTAssertFalse(model.isLoadingSkillDocument)

        model.selectedSkillID = second.id
        XCTAssertTrue(model.selectedSkillDocument.isEmpty, "新技能不能短暂显示旧技能的正文")
        XCTAssertTrue(model.selectedSkillFiles.isEmpty)
        XCTAssertNil(model.selectedSkillFilePreview)
        await model.loadSelectedSkillDocumentInBackground()
        XCTAssertEqual(model.selectedSkillDocument, secondDocument)
        XCTAssertNil(model.libraryError)
        XCTAssertNil(model.skillFilesError)
    }

    func testFailedMCPUsageRefreshKeepsPublishedTargetsAndReportsError() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let library = fixture.model.mcpLibrary
        let entry = MCPLibraryEntry(name: "test-service", commandOrURL: "test-program")
        XCTAssertTrue(library.save(entry))
        XCTAssertTrue(library.select(entry.id, enabled: true, host: .codex, projectID: nil))
        await library.refreshUsageInBackground()
        let target = try XCTUnwrap(library.usageTargets.first { $0.host == .codex && $0.projectID == nil })
        XCTAssertTrue(target.references(entry))
        let draftURL = library.store.rootURL.appendingPathComponent("drafts/\(target.id).json")
        let original = try Data(contentsOf: draftURL)
        try Data("broken".utf8).write(to: draftURL)

        await library.refreshUsageInBackground()
        XCTAssertNotNil(library.usageError)
        XCTAssertTrue(library.usageTargets.contains { $0.id == target.id && $0.references(entry) })
        XCTAssertEqual(library.selectedIDs(host: .codex, projectID: nil), [entry.id])
        XCTAssertEqual(try String(contentsOf: draftURL, encoding: .utf8), "broken")

        try original.write(to: draftURL)
        await library.refreshUsageInBackground()
        XCTAssertNil(library.usageError)
        XCTAssertTrue(library.usageTargets.contains { $0.id == target.id && $0.references(entry) })
    }

    func testProjectSwitchHidesPreviousMCPPathAndBackgroundReadUsesNewScope() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let model = fixture.model
        let first = try fixture.project("first", server: "alpha")
        XCTAssertTrue(model.registerProject(first))
        let firstID = model.selectedProjectID
        let second = try fixture.project("second", server: "beta")
        XCTAssertTrue(model.registerProject(second))
        await model.refreshMCPConfigurationsInBackground()
        XCTAssertEqual(model.mcpAccessInspection(host: .codex, scope: .project)?.servers.map(\.name), ["beta"])
        model.selectedProjectID = firstID
        XCTAssertNil(model.mcpAccessInspection(host: .codex, scope: .project), "旧项目路径不能冒充当前项目")
        XCTAssertTrue(model.mcpConfigInspections.isEmpty)
        XCTAssertTrue(model.mcpServers.isEmpty)
        await model.refreshMCPConfigurationsInBackground()
        let observed = try XCTUnwrap(model.mcpAccessInspection(host: .codex, scope: .project))
        XCTAssertEqual(observed.configPath, first.appendingPathComponent(".codex/config.toml").path)
        XCTAssertEqual(observed.servers.map(\.name), ["alpha"])
        XCTAssertFalse(model.isRefreshingMCPConfigurations)
        XCTAssertTrue(model.mcpServers.allSatisfy { $0.name != "beta" })
    }

    func testCancelledMCPReadKeepsPublishedResultAndNextRefreshSeesExternalEdit() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let project = try fixture.project("project", server: "before")
        let model = fixture.model
        XCTAssertTrue(model.registerProject(project))
        await model.refreshMCPConfigurationsInBackground()
        let config = project.appendingPathComponent(".codex/config.toml")
        let changed = "[mcp_servers.after]\ncommand = \"after-program\"\n"
        try changed.write(to: config, atomically: true, encoding: .utf8)
        let cancelled = Task { await model.refreshMCPConfigurationsInBackground() }
        cancelled.cancel()
        await cancelled.value
        XCTAssertEqual(model.mcpAccessInspection(host: .codex, scope: .project)?.servers.map(\.name), ["before"])
        XCTAssertFalse(model.isRefreshingMCPConfigurations)
        await model.refreshMCPConfigurationsInBackground()
        XCTAssertEqual(model.mcpAccessInspection(host: .codex, scope: .project)?.servers.map(\.name), ["after"])
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), changed)
    }

    func testBackgroundTemplateReferencesReportDraftWithoutWritingAndSurfaceCorruption() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let model = fixture.model
        let project = try fixture.project("rules-project")
        XCTAssertTrue(model.registerProject(project))
        var draft = TemplateEditorDraft()
        draft.title = "引用测试"; draft.body = "提交前核对变更。"
        XCTAssertTrue(model.saveTemplate(draft))
        let template = try XCTUnwrap(model.selectedTemplate)
        model.toggleInstruction(template)
        let references = try await model.templateReferencesInBackground(template.id)
        XCTAssertEqual(references.count, 1)
        XCTAssertEqual(references.first?.target, .project(model.selectedProjectID, .codex))
        XCTAssertTrue(references.first?.inDraft == true)
        XCTAssertFalse(references.first?.isApplied == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent("AGENTS.md").path))
        let cancelled = Task { try await model.templateReferencesInBackground(template.id) }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("取消的读取必须停止发布") }
        catch is CancellationError {}
        let draftURL = ProjectDraftStore(rootURL: fixture.paths.applicationSupportRoot).documentURL
        try "broken".write(to: draftURL, atomically: true, encoding: .utf8)
        do { _ = try await model.templateReferencesInBackground(template.id); XCTFail("读取失败不能显示为未使用") }
        catch {}
        XCTAssertEqual(try String(contentsOf: draftURL, encoding: .utf8), "broken")
    }

    func testCachedProgramIsRevalidatedBeforePreparingAccessPlan() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let program = fixture.root.appendingPathComponent("dist/skillset")
        let resources = program.deletingLastPathComponent().appendingPathComponent("SkillSet_SkillSetCore.bundle")
        try FileManager.default.createDirectory(at: resources.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 1\n".write(to: program, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
        let info = ["CFBundleIdentifier": "test.page-reader.resources", "CFBundlePackageType": "BNDL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: resources.appendingPathComponent("Info.plist"))
        try "{}".write(to: resources.appendingPathComponent("Resources/catalog.json"), atomically: true, encoding: .utf8)
        // 配置计划要求目标宿主目录已存在；本测试只隔离程序消失这一失败条件。
        try FileManager.default.createDirectory(at: fixture.locations.codexRoot, withIntermediateDirectories: true)
        let configURL = fixture.locations.codexRoot.appendingPathComponent("config.toml")
        let model = fixture.model
        await model.refreshAIAccessInBackground()
        XCTAssertEqual(model.mcpAccessInstallation?.executableURL, program)
        XCTAssertFalse(model.isRefreshingAIAccess)
        XCTAssertTrue(model.prepareAIAccess(host: .codex), model.lastAction)
        XCTAssertNotNil(model.preparedPlan)
        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path), "预览不得写入宿主配置")
        try FileManager.default.removeItem(at: program)
        XCTAssertNotNil(model.mcpAccessInstallation, "页面展示使用缓存，预览负责重新验证")
        XCTAssertFalse(model.prepareAIAccess(host: .codex))
        XCTAssertNil(model.mcpAccessInstallation)
        XCTAssertNil(model.preparedPlan)
        XCTAssertNotNil(model.aiAccessError)
    }

    func testManyProjectsKeepSelectorCompactAndLastProjectReachableInBothAppearances() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let model = fixture.model
        XCTAssertTrue(model.registerProject(try fixture.project("current")))
        model.projects += (1...40).map { index in
            ProjectRecord(id: UUID().uuidString, name: "\(index) · 长项目名称用于核对省略和滚动行为",
                path: fixture.root.appendingPathComponent("project-\(index)").path, adapter: "Codex · Claude Code",
                inherited: "", draftSkillIDs: [], appliedSkillIDs: [], agents: ["Codex", "Claude Code"],
                fragments: [], pendingChanges: 0)
        }
        let controller = NSHostingController(rootView: ContentView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer { window.close() }
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(150))
            controller.view.layoutSubtreeIfNeeded()
            let rail = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSScrollView }.first {
                $0.bounds.height >= 44 && $0.bounds.height <= 48 && ($0.documentView?.frame.width ?? 0) > 1000
            })
            XCTAssertLessThanOrEqual(rail.bounds.height, 48)
            let document = try XCTUnwrap(rail.documentView)
            document.scroll(NSPoint(x: document.bounds.maxX, y: 0))
            try await Task.sleep(for: .milliseconds(100))
            controller.view.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(rail.contentView.bounds.origin.x, 0)
            // 横向项目选择器不能因为项目数量增长而增高，末项仍可滚到。
            XCTAssertLessThanOrEqual(document.bounds.maxX - rail.documentVisibleRect.maxX, 12)
            XCTAssertLessThanOrEqual(controller.view.fittingSize.height, 701)
            let bitmap = try XCTUnwrap(controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
            controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
                to: URL(fileURLWithPath: "/tmp/perch-projects-many-\(appearance == .aqua ? "light" : "dark").png"))
        }
    }

    @MainActor
    private struct Fixture {
        let root: URL
        let paths: SkillSetRuntimePaths
        let locations: GlobalConfigurationLocations
        let model: AppModel
        let environment: [String: String]
        let keys = ["CFFIXED_USER_HOME", "SKILLSET_HOME", "CODEX_HOME", "CLAUDE_CONFIG_DIR"]

        init() throws {
            root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("page-loading-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: root)
            locations = GlobalConfigurationLocations(home: root.appendingPathComponent("home"), stateRoot: paths.applicationSupportRoot)
            environment = ProcessInfo.processInfo.environment
            for key in keys { setenv(key, root.appendingPathComponent(key).path, 1) }
            model = AppModel(runtimePaths: paths, globalLocations: locations)
        }

        func project(_ name: String, server: String? = nil) throws -> URL {
            let project = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: project.appendingPathComponent(".codex"), withIntermediateDirectories: true)
            if let server {
                try "[mcp_servers.\(server)]\ncommand = \"\(server)-program\"\n".write(
                    to: project.appendingPathComponent(".codex/config.toml"), atomically: true, encoding: .utf8)
            }
            return project
        }

        func cleanup() {
            for key in keys {
                if let value = environment[key] { setenv(key, value, 1) } else { unsetenv(key) }
            }
            try? FileManager.default.removeItem(at: root)
        }
    }
}
