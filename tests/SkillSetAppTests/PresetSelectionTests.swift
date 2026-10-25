import AppKit
import SwiftUI
import XCTest
@testable import SkillSetCore
@testable import SkillSetApp

@MainActor
final class PresetSelectionTests: XCTestCase {
    func testPreviewExplainsReplacementAndLoadingOnlyChangesExplicitTargetDraft() throws {
        try withFixture { model, root in
            let first = try register("first", model: model, root: root)
            let second = try register("second", model: model, root: root)
            let store = ProjectDraftStore(rootURL: model.runtimePaths.applicationSupportRoot)
            let firstBefore = try store.load(projectID: UUID(uuidString: first)!)
            let index = try XCTUnwrap(model.projects.firstIndex { $0.id == second })
            // 通过真实编辑入口建立 Claude 草稿，避免仅改展示字段留下 Codex 映射。
            model.toggleAgent(.codex)
            model.selectProjectHost(.claude)
            for id in ["workspace/stc", "local-brian/research"] {
                model.toggleSkill(try XCTUnwrap(model.snapshot.catalog.entries.first { $0.id == id }))
            }
            for id in ["base-zh", "ui-craft"] {
                model.toggleInstruction(try XCTUnwrap(model.snapshot.templates.first { $0.id == id }))
            }
            XCTAssertEqual(model.projects[index].editingAgent, "claude-code")
            XCTAssertNil(model.projects[index].harnessSelections["codex"])
            let preset = try XCTUnwrap(model.snapshot.presets.first { $0.id == "personal-base" })
            let beforePreview = model.projects
            let preview = PresetDraftPreview(preset: preset, project: model.projects[index], snapshot: model.snapshot)
            XCTAssertEqual(preview.skills.added, ["workspace/brian-working-style", "workspace/project-guide"])
            XCTAssertEqual(preview.skills.retained, ["workspace/stc"])
            XCTAssertEqual(preview.skills.removed, ["local-brian/research"])
            XCTAssertEqual(preview.instructions.added, ["engineering"])
            XCTAssertEqual(preview.instructions.retained, ["base-zh"])
            XCTAssertEqual(preview.instructions.removed, ["ui-craft"])
            XCTAssertTrue(preview.canLoad)
            XCTAssertEqual(model.projects, beforePreview, "预览不能先改动草稿")

            model.selectedProjectID = first
            model.section = .presets
            XCTAssertTrue(model.loadPreset(preset, into: second))
            XCTAssertEqual(model.selectedProjectID, second)
            XCTAssertEqual(model.section, .projects)
            let saved = try XCTUnwrap(store.load(projectID: UUID(uuidString: second)!))
            XCTAssertEqual(saved.skillIDs, ["workspace/brian-working-style", "workspace/project-guide", "workspace/stc"])
            XCTAssertEqual(saved.instructionIDs, ["base-zh", "engineering"])
            XCTAssertEqual(saved.agents, ["claude-code"])
            XCTAssertEqual(try store.load(projectID: UUID(uuidString: first)!), firstBefore)
            XCTAssertEqual(model.projects[index].agents, [AgentHost.claude.rawValue])
            XCTAssertTrue(model.pendingPlans.isEmpty)
            XCTAssertNil(model.preparedPlan)
            for name in ["first", "second"] {
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(name).path), ["sentinel.txt"])
                XCTAssertEqual(try String(contentsOf: root.appendingPathComponent(name + "/sentinel.txt"), encoding: .utf8), "项目原有内容\n")
            }
        }
    }

    func testBlockingPresetNamesTheSkillRuleOrConflictAndKeepsTheDraft() throws {
        try withFixture { model, root in
            let projectID = try register("named-block", model: model, root: root)
            let store = PresetStore(rootURL: model.runtimePaths.applicationSupportRoot)
            let preferences = AppPreferences.shared
            let languageBefore = preferences.language
            defer { preferences.language = languageBefore }
            preferences.language = .chinese

            var conflict = PresetEditorDraft()
            conflict.name = "冲突组合"
            conflict.skills = ["workspace/stc", "local-brian/stc"]
            XCTAssertFalse(model.savePreset(conflict))
            let conflictMessage = L10n.tr(try XCTUnwrap(model.presetError))
            XCTAssertTrue(conflictMessage.contains("同名冲突"))
            XCTAssertTrue(conflictMessage.contains("stc（local-brian）"))
            XCTAssertTrue(conflictMessage.contains("stc（workspace）"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.documentURL.path))

            preferences.language = .english
            XCTAssertTrue(L10n.tr(try XCTUnwrap(model.presetError)).contains("Name conflict. Keep only one:"))
            XCTAssertTrue(L10n.tr(try XCTUnwrap(model.presetError)).contains("stc（workspace）"))
            preferences.language = .chinese

            var blocked = PresetEditorDraft()
            blocked.name = "不可用技能"
            blocked.skills = ["local-brian/ponytail-review"]
            XCTAssertFalse(model.savePreset(blocked))
            let blockedMessage = L10n.tr(try XCTUnwrap(model.presetError))
            XCTAssertEqual(blockedMessage.components(separatedBy: "链接目标丢失或循环引用").count - 1, 1)
            XCTAssertTrue(blockedMessage.contains("技能「ponytail-review」暂不可用"))
            XCTAssertTrue(blockedMessage.contains("来源：local-brian"))

            var missing = PresetEditorDraft()
            missing.name = "缺失规则"
            missing.skills = ["workspace/stc"]
            missing.instructions = ["missing-rule"]
            XCTAssertFalse(model.savePreset(missing))
            XCTAssertTrue(L10n.tr(try XCTUnwrap(model.presetError)).contains("AGENTS 片段已不在库中，请从预设中移除这项引用。"))

            XCTAssertFalse(model.loadPreset(try makePreset(skills: ["missing/skill"]), into: projectID))
            XCTAssertTrue(model.lastAction.contains("技能「skill」不在技能库。请从预设中移除这项引用。"))
            XCTAssertFalse(model.lastAction.contains("missing/skill"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.documentURL.path))

            let staleID = "source-d23e91a448f2029713fda4fcc9c83a3d7aa62697a0930cb36c2ab52475178b71/b58e338b7575/emil-design-eng"
            let hiddenID = "source-d23e91a448f2029713fda4fcc9c83a3d7aa62697a0930cb36c2ab52475178b71/5580a4891f52/review-animations"
            let project = try XCTUnwrap(model.projects.first { $0.id == projectID })
            let beforeProjects = model.projects
            let preview = PresetDraftPreview(
                preset: try makePreset(skills: [staleID, hiddenID]), project: project,
                snapshot: model.snapshot
            )
            let reasons = preview.blockingReasons().map { L10n.tr($0) }.joined(separator: "\n")
            XCTAssertFalse(preview.canLoad)
            XCTAssertTrue(reasons.contains("技能「emil-design-eng」不在技能库。请从预设中移除这项引用。"))
            XCTAssertTrue(reasons.contains("技能「review-animations」不在技能库。请从预设中移除这项引用。"))
            XCTAssertFalse(reasons.contains("source-d23e"))
            XCTAssertFalse(model.loadPreset(try makePreset(skills: [staleID, hiddenID]), into: projectID))
            XCTAssertEqual(model.projects, beforeProjects)
            preferences.language = .english
            XCTAssertTrue(model.lastAction.contains("Skill “emil-design-eng” is not in the library."))
            XCTAssertTrue(model.lastAction.contains("Skill “review-animations” is not in the library."))
            preferences.language = .chinese
        }
    }

    func testUnavailableConflictingOrUnknownComponentsAreRejectedWithoutPartialReplacement() throws {
        try withFixture { model, root in
            let id = try register("project", model: model, root: root)
            let before = model.projects
            let store = ProjectDraftStore(rootURL: model.runtimePaths.applicationSupportRoot)
            let diskBefore = try Data(contentsOf: store.documentURL)
            for preset in [
                try makePreset(skills: ["workspace/stc", "missing/skill"]),
                try makePreset(skills: ["local-brian/ponytail-review"]),
                try makePreset(skills: ["workspace/stc", "local-brian/stc"]),
                try makePreset(skills: ["workspace/stc"], instructions: ["missing-rule"])
            ] {
                let preview = PresetDraftPreview(preset: preset, project: model.projects[0], snapshot: model.snapshot)
                XCTAssertFalse(preview.canLoad)
                XCTAssertFalse(model.loadPreset(preset, into: id))
                XCTAssertEqual(model.projects, before)
                XCTAssertEqual(try Data(contentsOf: store.documentURL), diskBefore)
            }
            XCTAssertFalse(model.loadPreset(try makePreset(skills: []), into: UUID().uuidString))
            XCTAssertEqual(model.projects, before)
        }
    }

    func testFailedSaveKeepsOriginalDraftAndDoesNotReportSuccessOrNavigate() throws {
        try withFixture { model, root in
            let id = try register("project", model: model, root: root)
            let before = model.projects
            let draftURL = ProjectDraftStore(rootURL: model.runtimePaths.applicationSupportRoot).documentURL
            try Data("invalid json".utf8).write(to: draftURL)
            model.section = .presets
            XCTAssertFalse(model.loadPreset(try XCTUnwrap(model.selectedPreset), into: id))
            XCTAssertEqual(model.projects, before)
            XCTAssertEqual(model.section, .presets)
            XCTAssertEqual(try String(contentsOf: draftURL, encoding: .utf8), "invalid json")
            XCTAssertNotEqual(model.actionMessage.key, "已载入「%@」草稿，尚未写入项目")
        }
    }

    func testBothEntrySheetsFitAndReviewingWithoutLoadingLeavesDraftUnchanged() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let model = fixture.model
        let id = try register("project", model: model, root: fixture.root)
        let before = model.projects
        let draftURL = ProjectDraftStore(rootURL: model.runtimePaths.applicationSupportRoot).documentURL
        let diskBefore = try Data(contentsOf: draftURL)
        let requests = [PresetSelectionRequest(projectID: id), PresetSelectionRequest(presetID: "personal-base")]
        let preferences = AppPreferences.shared
        let languageBefore = preferences.language
        defer { preferences.language = languageBefore }
        for language in [AppLanguage.chinese, .english] {
            preferences.language = language
            for (index, request) in requests.enumerated() {
                let controller = NSHostingController(rootView: PresetSelectionSheet(model: model, request: request).appPreferences())
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 620), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentViewController = controller
                window.makeKeyAndOrderFront(nil)
                defer { window.close() }
                for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                    window.appearance = NSAppearance(named: appearance)
                    try await Task.sleep(for: .milliseconds(80))
                    controller.view.layoutSubtreeIfNeeded()
                    XCTAssertLessThanOrEqual(controller.view.fittingSize.width, 860)
                    XCTAssertLessThanOrEqual(controller.view.fittingSize.height, 620)
                    let scrolls = descendants(controller.view).compactMap { $0 as? NSScrollView }
                    XCTAssertEqual(scrolls.count, 2, "预设列表与变更明细应独立滚动")
                    for scroll in scrolls {
                        let document = try XCTUnwrap(scroll.documentView)
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.bounds.maxY - scroll.contentView.bounds.height)))
                        scroll.reflectScrolledClipView(scroll.contentView)
                        XCTAssertGreaterThanOrEqual(scroll.documentVisibleRect.maxY + 1, document.bounds.maxY)
                        scroll.contentView.scroll(to: .zero)
                        scroll.reflectScrolledClipView(scroll.contentView)
                    }
                    if let destination = ProcessInfo.processInfo.environment["SKILLSET_PRESET_SCREENSHOT_DIR"],
                       let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) {
                        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
                        let url = URL(fileURLWithPath: destination).appendingPathComponent("preset-\(index)-\(language.rawValue)-\(appearance == .aqua ? "light" : "dark").png")
                        try bitmap.representation(using: .png, properties: [:])?.write(to: url)
                    }
                }
            }
        }
        XCTAssertEqual(model.projects, before)
        XCTAssertEqual(try Data(contentsOf: draftURL), diskBefore)
    }

    func testNewPresetSurvivesRestartLoadsMCPAndRulesAndExplainsChangedConfiguration() throws {
        try withFixture { model, root in
            let projectID = try register("components", model: model, root: root)
            var draft = PresetEditorDraft()
            draft.name = "项目工具箱"
            draft.skills = ["workspace/stc"]
            draft.instructions = ["engineering"]
            draft.mcpServers = [MCPConfigurationDraft(name: "docs", scope: .user, commandOrURL: "/usr/bin/true", args: ["one value"])]
            XCTAssertTrue(model.savePreset(draft))
            let restarted = AppModel(snapshot: AppSnapshot.load(), runtimePaths: model.runtimePaths)
            let preset = try XCTUnwrap(restarted.snapshot.presets.first { $0.id == draft.id })
            XCTAssertTrue(restarted.loadPreset(preset, into: projectID))
            let saved = try XCTUnwrap(ProjectDraftStore(rootURL: model.runtimePaths.applicationSupportRoot).load(projectID: UUID(uuidString: projectID)!))
            XCTAssertEqual(saved.mcpServers.first?.args, ["one value"])
            XCTAssertEqual(saved.instructionIDs, ["engineering"])
            XCTAssertEqual(saved.agents, ["codex"])
            let current = try XCTUnwrap(restarted.selectedProject)
            var newServer = draft.mcpServers[0]
            newServer.commandOrURL = "/usr/bin/false"
            let next = PresetRecord(name: "下一版", mcpServers: [newServer])
            let preview = PresetDraftPreview(preset: next, project: current, snapshot: restarted.snapshot)
            XCTAssertEqual(preview.mcpServers.updated, ["codex:user:docs"])
            XCTAssertTrue(preview.mcpServers.retained.isEmpty)
            restarted.toggleAgent(.claude)
            XCTAssertEqual(try ProjectDraftStore(rootURL: model.runtimePaths.applicationSupportRoot).load(projectID: UUID(uuidString: projectID)!)?.mcpServers.first?.name, "docs")
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("components").path), ["sentinel.txt"])
            XCTAssertTrue(restarted.pendingPlans.isEmpty)
        }
    }

    func testEditingInitialPresetPersistsAndReloadingLibraryKeepsOneUpdatedEntry() throws {
        try withFixture { model, root in
            let projectID = try register("editing", model: model, root: root)
            let drafts = ProjectDraftStore(rootURL: model.runtimePaths.applicationSupportRoot)
            let projectBefore = try Data(contentsOf: drafts.documentURL)
            let original = try XCTUnwrap(model.selectedPreset)
            model.beginEditingPreset(original)
            var editor = try XCTUnwrap(model.presetEditor)
            editor.name = "我的日常组合"
            editor.skills = ["workspace/stc"]
            editor.instructions = ["engineering"]
            XCTAssertTrue(model.savePreset(editor))
            let restarted = AppModel(snapshot: AppSnapshot.load(), runtimePaths: model.runtimePaths)
            let saved = try XCTUnwrap(restarted.snapshot.presets.first { $0.id == original.id })
            XCTAssertEqual(saved.name, "我的日常组合")
            XCTAssertEqual(saved.revision, original.revision + 1)
            XCTAssertEqual(saved.skills, ["workspace/stc"])
            XCTAssertEqual(restarted.snapshot.presets.filter { $0.id == original.id }.count, 1)
            XCTAssertEqual(restarted.snapshot.presets.first { $0.id == original.id }, saved)
            XCTAssertEqual(try Data(contentsOf: drafts.documentURL), projectBefore)
            XCTAssertTrue(restarted.loadPreset(saved, into: projectID))
            XCTAssertEqual(try drafts.load(projectID: UUID(uuidString: projectID)!)?.skillIDs, ["workspace/stc"])
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("editing").path), ["sentinel.txt"])
        }
    }

    func testDuplicatingUserPresetKeepsAllComponentsAndEditingCopyLeavesOriginalUnchanged() throws {
        try withFixture { model, _ in
            let pluginJSON = """
            {"host":"claude-code","pluginID":"tools@example","name":"Tools","manifestDigest":"\(String(repeating: "a", count: 64))","scope":"project"}
            """
            var source = PresetEditorDraft()
            source.name = "我的工具箱"
            source.description = "四类组件"
            source.skills = ["workspace/stc"]
            source.instructions = ["engineering"]
            source.plugins = [try JSONDecoder().decode(PresetPluginReference.self, from: Data(pluginJSON.utf8))]
            source.mcpServers = [MCPConfigurationDraft(name: "docs", scope: .user, commandOrURL: "/usr/bin/true", args: ["one value"], envKeys: ["API_TOKEN"])]
            XCTAssertTrue(model.savePreset(source))
            let original = try XCTUnwrap(model.selectedPreset)
            let store = PresetStore(rootURL: model.runtimePaths.applicationSupportRoot)
            let before = try Data(contentsOf: store.documentURL)
            model.beginEditingPreset(original, copy: true)
            var copy = try XCTUnwrap(model.presetEditor)
            XCTAssertNotEqual(copy.id, original.id)
            XCTAssertEqual(try Data(contentsOf: store.documentURL), before, "打开复制面板不能先保存")
            copy.name = original.name
            XCTAssertFalse(model.savePreset(copy), "复制不能覆盖同名原预设")
            XCTAssertEqual(try Data(contentsOf: store.documentURL), before)
            copy.name = "工具箱副本"
            XCTAssertTrue(model.savePreset(copy))
            let restarted = AppModel(snapshot: AppSnapshot.load(), runtimePaths: model.runtimePaths)
            let duplicated = try XCTUnwrap(restarted.snapshot.presets.first { $0.id == copy.id })
            XCTAssertEqual(duplicated.revision, 1)
            XCTAssertEqual(duplicated.description, "四类组件")
            XCTAssertEqual(duplicated.skills, original.skills)
            XCTAssertEqual(duplicated.instructionFragments, original.instructionFragments)
            XCTAssertEqual(duplicated.plugins, original.plugins)
            XCTAssertEqual(duplicated.mcpServers, original.mcpServers)
            restarted.beginEditingPreset(duplicated)
            var edit = try XCTUnwrap(restarted.presetEditor)
            edit.skills = []
            edit.mcpServers[0].commandOrURL = "/usr/bin/false"
            XCTAssertTrue(restarted.savePreset(edit))
            let saved = try store.list()
            XCTAssertEqual(saved.first { $0.id == original.id }, original)
            XCTAssertEqual(saved.first { $0.id == copy.id }?.revision, 2)
            XCTAssertEqual(saved.first { $0.id == copy.id }?.mcpServers.first?.commandOrURL, "/usr/bin/false")
        }
    }

    func testPluginPresetLoadsExactFingerprintAndRejectsChangedLocalManifestWithoutPartialSave() throws {
        try withFixture { model, root in
            let projectID = try register("plugin-components", model: model, root: root)
            let manifest = root.appendingPathComponent("plugin-components/.claude-plugin/plugin.json")
            try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try #"{"name":"preset-fixture","version":"1.0.0","description":"Plugin fixture"}"#.write(to: manifest, atomically: true, encoding: .utf8)
            model.refreshPlugins()
            let plugin = try XCTUnwrap(model.plugins.first { $0.name == "preset-fixture" })
            var draft = PresetEditorDraft()
            draft.name = "插件组合"
            draft.plugins = [PresetPluginReference(plugin: plugin, scope: .project)]
            XCTAssertTrue(model.savePreset(draft))
            let preset = try XCTUnwrap(model.selectedPreset)
            XCTAssertTrue(model.loadPreset(preset, into: projectID))
            let store = ProjectDraftStore(rootURL: model.runtimePaths.applicationSupportRoot)
            XCTAssertEqual(try store.load(projectID: UUID(uuidString: projectID)!)?.plugins.first?.manifestDigest, plugin.manifestDigest)
            let before = try Data(contentsOf: store.documentURL)
            try #"{"name":"preset-fixture","version":"2.0.0","description":"Plugin fixture"}"#.write(to: manifest, atomically: true, encoding: .utf8)
            let preferences = AppPreferences.shared
            let languageBefore = preferences.language
            defer { preferences.language = languageBefore }
            XCTAssertFalse(model.loadPreset(preset, into: projectID))
            preferences.language = .chinese
            XCTAssertTrue(model.lastAction.contains("插件「preset-fixture」的这个版本不可用"))
            preferences.language = .english
            XCTAssertTrue(model.lastAction.contains("This version of plugin “preset-fixture” is unavailable"))
            XCTAssertEqual(try Data(contentsOf: store.documentURL), before)
            XCTAssertNil(model.preparedPlan)
            XCTAssertTrue(model.pendingPlans.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("plugin-components/.claude/skills").path))
        }
    }

    func testUserPresetDetailFitsMinimumWidthInBothLanguagesAndAppearances() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.model.section = .presets
        let preferences = AppPreferences.shared
        let languageBefore = preferences.language
        defer { preferences.language = languageBefore }
        for language in [AppLanguage.chinese, .english] {
            preferences.language = language
            let controller = NSHostingController(rootView: ContentView(model: fixture.model).appPreferences())
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = controller
            window.makeKeyAndOrderFront(nil)
            defer { window.close() }
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: appearance)
                try await Task.sleep(for: .milliseconds(80))
                controller.view.layoutSubtreeIfNeeded()
                XCTAssertLessThanOrEqual(controller.view.fittingSize.width, 1081)
                XCTAssertLessThanOrEqual(controller.view.fittingSize.height, 701)
                for scroll in descendants(controller.view).compactMap({ $0 as? NSScrollView }) {
                    let rect = scroll.convert(scroll.bounds, to: controller.view)
                    XCTAssertGreaterThanOrEqual(rect.minX, -1)
                    XCTAssertLessThanOrEqual(rect.maxX, 1081)
                }
                if let destination = ProcessInfo.processInfo.environment["SKILLSET_PRESET_SCREENSHOT_DIR"],
                   let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) {
                    controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
                    let url = URL(fileURLWithPath: destination).appendingPathComponent("user-presets-\(language.rawValue)-\(appearance == .aqua ? "light" : "dark").png")
                    try bitmap.representation(using: .png, properties: [:])?.write(to: url)
                }
            }
        }
    }

    func testPresetEditorFitsBothLanguagesAndAppearancesWithoutSaving() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let prefs = AppPreferences.shared
        let before = prefs.language
        defer { prefs.language = before }
        for language in [AppLanguage.chinese, .english] {
            prefs.language = language
            let controller = NSHostingController(rootView: PresetEditorSheet(model: fixture.model, draft: PresetEditorDraft()).appPreferences())
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 670), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = controller
            window.makeKeyAndOrderFront(nil)
            defer { window.close() }
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: appearance)
                try await Task.sleep(for: .milliseconds(80))
                controller.view.layoutSubtreeIfNeeded()
                XCTAssertLessThanOrEqual(controller.view.fittingSize.width, 900)
                XCTAssertLessThanOrEqual(controller.view.fittingSize.height, 670)
                XCTAssertGreaterThanOrEqual(descendants(controller.view).compactMap { $0 as? NSScrollView }.count, 1)
                if let destination = ProcessInfo.processInfo.environment["SKILLSET_PRESET_SCREENSHOT_DIR"],
                   let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) {
                    controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
                    let url = URL(fileURLWithPath: destination).appendingPathComponent("preset-editor-\(language.rawValue)-\(appearance == .aqua ? "light" : "dark").png")
                    try bitmap.representation(using: .png, properties: [:])?.write(to: url)
                }
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: PresetStore(rootURL: fixture.model.runtimePaths.applicationSupportRoot).documentURL.path))
    }

    private func register(_ name: String, model: AppModel, root: URL) throws -> String {
        let project = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try "项目原有内容\n".write(to: project.appendingPathComponent("sentinel.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(model.registerProject(project))
        return try XCTUnwrap(model.selectedProject?.id)
    }

    private func makePreset(skills: [String], instructions: [String] = []) throws -> PresetRecord {
        let document: [String: Any] = [
            "schemaVersion": 1, "id": "fixture", "name": "测试预设", "description": "测试组合",
            "revision": 1, "skills": skills, "instructionFragments": instructions,
            "mergePolicy": "explicit-selection", "status": "draft"
        ]
        return try JSONDecoder().decode(PresetRecord.self, from: JSONSerialization.data(withJSONObject: document))
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func withFixture(_ body: (AppModel, URL) throws -> Void) throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try body(fixture.model, fixture.root)
    }

    @MainActor
    private struct Fixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("presets-\(UUID())")
        let savedEnvironment = ProcessInfo.processInfo.environment
        let variables = ["CFFIXED_USER_HOME", "SKILLSET_HOME", "CODEX_HOME"]
        let model: AppModel

        init() throws {
            for variable in variables { setenv(variable, root.appendingPathComponent(variable).path, 1) }
            model = AppModel(snapshot: AppSnapshot.load(), runtimePaths: SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil))
        }

        func cleanup() {
            for variable in variables {
                if let value = savedEnvironment[variable] { setenv(variable, value, 1) }
                else { unsetenv(variable) }
            }
            try? FileManager.default.removeItem(at: root)
        }
    }
}
