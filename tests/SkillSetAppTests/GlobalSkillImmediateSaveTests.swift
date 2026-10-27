import Foundation
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class GlobalSkillImmediateSaveTests: XCTestCase {
    func testClickSavesAndRemovesEachTargetWithoutDeployingPendingChoices() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let global = fixture.model
        let rule = TemplateRecord(title: "待保存规则", body: "待保存正文", purpose: "隔离待保存选择")
        _ = try TemplateStore(rootURL: fixture.paths.applicationSupportRoot).save(rule, initial: [])
        for target in SkillConfigurationTarget.allCases {
            global.setSkill(fixture.pending.id, enabled: true, host: target)
            if target != .agents { global.setInstruction(rule.id, enabled: true, host: target) }
        }
        for target in SkillConfigurationTarget.allCases {
            let saved = await global.saveSkill(fixture.skill, enabled: true, host: target, catalog: fixture.entries)
            XCTAssertTrue(saved, global.error ?? "")
            let installed = fixture.locations.skillsRoot(target).appendingPathComponent("click-save/SKILL.md")
            XCTAssertTrue(try String(contentsOf: installed, encoding: .utf8).contains("点击保存正文"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.locations.skillsRoot(target).appendingPathComponent("pending").path))
            if let rules = fixture.locations.rulesURL(for: target) {
                XCTAssertFalse(FileManager.default.fileExists(atPath: rules.path))
            }
            let removed = await global.saveSkill(fixture.skill, enabled: false, host: target, catalog: fixture.entries)
            XCTAssertTrue(removed, global.error ?? "")
            XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path))
            XCTAssertEqual(try fixture.manager.inspect(host: target).selection.skillIDs, [])
            XCTAssertEqual(try fixture.manager.draft(host: target).skillIDs, [fixture.pending.id])
        }
        let restarted = GlobalConfigurationModel(paths: fixture.paths, locations: fixture.locations)
        restarted.refresh()
        for target in SkillConfigurationTarget.allCases {
            XCTAssertTrue(restarted.isSkillSelected(fixture.pending.id, host: target))
            XCTAssertFalse(restarted.isSkillSelected(fixture.skill.id, host: target))
            XCTAssertEqual(try fixture.manager.history(host: target).count, 2)
            let cancelledPending = await restarted.saveSkill(fixture.pending, enabled: false, host: target, catalog: fixture.entries)
            XCTAssertTrue(cancelledPending, restarted.error ?? "")
            XCTAssertTrue(try fixture.manager.draft(host: target).skillIDs.isEmpty)
            XCTAssertEqual(try fixture.manager.history(host: target).count, 2)
        }
    }

    func testConflictKeepsExistingFileAndSelectionAndRetryCanSucceed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let target = fixture.locations.skillsRoot(.agents).appendingPathComponent("click-save/SKILL.md")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "本机已有内容".write(to: target, atomically: true, encoding: .utf8)
        let failed = await fixture.model.saveSkill(fixture.skill, enabled: true, host: .agents, catalog: fixture.entries)
        XCTAssertFalse(failed)
        XCTAssertNotNil(fixture.model.error)
        XCTAssertNil(fixture.model.skillSaveMessage)
        XCTAssertFalse(fixture.model.isSkillSelected(fixture.skill.id, host: .agents))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "本机已有内容")
        XCTAssertTrue(try fixture.manager.draft(host: .agents).skillIDs.isEmpty)
        XCTAssertTrue(try fixture.manager.history(host: .agents).isEmpty)
        try FileManager.default.removeItem(at: target.deletingLastPathComponent())
        let saved = await fixture.model.saveSkill(fixture.skill, enabled: true, host: .agents, catalog: fixture.entries)
        XCTAssertTrue(saved, fixture.model.error ?? "")
        XCTAssertNil(fixture.model.error)
        XCTAssertNotNil(fixture.model.skillSaveMessage)
    }

    func testClickAppliesInstallChoiceAndAdoptsExistingSkillWithoutPreview() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let target = fixture.locations.skillsRoot(.agents).appendingPathComponent("click-save")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try "本机已有内容".write(to: target.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        fixture.model.setInstallMethod(.copy, host: .agents)
        fixture.model.takeOverExisting = true

        let saved = await fixture.model.saveSkill(fixture.skill, enabled: true, host: .agents, catalog: fixture.entries)

        XCTAssertTrue(saved, fixture.model.error ?? "")
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("SKILL.md"), encoding: .utf8),
                       "---\nname: click-save\ndescription: 点击保存\n---\n点击保存正文\n")
        XCTAssertFalse(try target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        XCTAssertTrue(try fixture.manager.inspect(host: .agents).resources.contains { $0.path == target.path && $0.managed })
    }

    func testModifiedInstalledFileBlocksRemovalAndKeepsSelectedState() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.model.setInstallMethod(.copy, host: .codex)
        let saved = await fixture.model.saveSkill(fixture.skill, enabled: true, host: .codex, catalog: fixture.entries)
        XCTAssertTrue(saved, fixture.model.error ?? "")
        let target = fixture.locations.skillsRoot(.codex).appendingPathComponent("click-save/SKILL.md")
        try "用户编辑内容".write(to: target, atomically: true, encoding: .utf8)
        let removed = await fixture.model.saveSkill(fixture.skill, enabled: false, host: .codex, catalog: fixture.entries)
        XCTAssertFalse(removed)
        XCTAssertNotNil(fixture.model.error)
        XCTAssertTrue(fixture.model.isSkillSelected(fixture.skill.id, host: .codex))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "用户编辑内容")
        XCTAssertEqual(try fixture.manager.history(host: .codex).count, 1)
    }

    func testInstructionImmediateSaveWritesRulesFileDirectly() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let rule = TemplateRecord(title: "代码规范", body: "全部使用中文注释。", purpose: "即时保存测试")
        _ = try TemplateStore(rootURL: fixture.paths.applicationSupportRoot).save(rule, initial: [])

        // 即时保存到 Codex (AGENTS.md)
        let savedCodex = await fixture.model.saveInstruction(rule, enabled: true, host: .codex)
        XCTAssertTrue(savedCodex, fixture.model.error ?? "")
        let codexRulesURL = try XCTUnwrap(fixture.locations.rulesURL(for: .codex))
        XCTAssertTrue(FileManager.default.fileExists(atPath: codexRulesURL.path))
        XCTAssertTrue(try String(contentsOf: codexRulesURL, encoding: .utf8).contains("全部使用中文注释。"))

        // 即时保存到 Claude Code (CLAUDE.md)
        let savedClaude = await fixture.model.saveInstruction(rule, enabled: true, host: .claudeCode)
        XCTAssertTrue(savedClaude, fixture.model.error ?? "")
        let claudeRulesURL = try XCTUnwrap(fixture.locations.rulesURL(for: .claudeCode))
        XCTAssertTrue(FileManager.default.fileExists(atPath: claudeRulesURL.path))
        XCTAssertTrue(try String(contentsOf: claudeRulesURL, encoding: .utf8).contains("全部使用中文注释。"))

        // 取消保存直接移除
        let removedCodex = await fixture.model.saveInstruction(rule, enabled: false, host: .codex)
        XCTAssertTrue(removedCodex, fixture.model.error ?? "")
        let codexContent = (try? String(contentsOf: codexRulesURL, encoding: .utf8)) ?? ""
        XCTAssertFalse(codexContent.contains("全部使用中文注释。"))
    }

    func testMCPLibraryImmediateSaveWritesConfigDirectly() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.locations.codexRoot, withIntermediateDirectories: true)
        let library = MCPLibraryModel(paths: fixture.paths, locations: fixture.locations)
        let entry = MCPLibraryEntry(name: "sqlite-tools", commandOrURL: "uvx mcp-server-sqlite")
        XCTAssertTrue(library.save(entry))

        // 即时保存到 Codex
        let saved = await library.saveSelection(entry.id, name: entry.name, enabled: true, host: .codex, projectID: nil)
        XCTAssertTrue(saved, library.error ?? "")
        let codexConfigURL = fixture.locations.codexRoot.appendingPathComponent("config.toml")
        XCTAssertTrue(FileManager.default.fileExists(atPath: codexConfigURL.path))
        let codexConfig = try String(contentsOf: codexConfigURL, encoding: .utf8)
        XCTAssertTrue(codexConfig.contains("sqlite-tools"))

        // 取消保存直接移除
        let cancelled = await library.saveSelection(entry.id, name: entry.name, enabled: false, host: .codex, projectID: nil)
        XCTAssertTrue(cancelled, library.error ?? "")
        let updatedCodexConfig = (try? String(contentsOf: codexConfigURL, encoding: .utf8)) ?? ""
        XCTAssertFalse(updatedCodexConfig.contains("sqlite-tools"))
    }

    @MainActor
    private struct Fixture {
        let root: URL
        let paths: SkillSetRuntimePaths
        let locations: GlobalConfigurationLocations
        let model: GlobalConfigurationModel
        let skill: SkillEntry
        let pending: SkillEntry
        var entries: [SkillEntry] { [skill, pending] }
        var manager: GlobalConfigurationManager { GlobalConfigurationManager(paths: paths, locations: locations) }

        init() throws {
            root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("global-click-save-\(UUID())")
            paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
            locations = GlobalConfigurationLocations(home: root.appendingPathComponent("home"), stateRoot: paths.applicationSupportRoot)
            try FileManager.default.createDirectory(at: locations.codexRoot, withIntermediateDirectories: true)
            let library = paths.makeLibraryStore()
            skill = try library.save(SkillEditorDraft(slug: "click-save", document: "---\nname: click-save\ndescription: 点击保存\n---\n点击保存正文\n"), repositoryRoot: nil)
            pending = try library.save(SkillEditorDraft(slug: "pending", document: "---\nname: pending\ndescription: 待保存\n---\n待保存正文\n"), repositoryRoot: nil)
            model = GlobalConfigurationModel(paths: paths, locations: locations)
            model.refresh()
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
