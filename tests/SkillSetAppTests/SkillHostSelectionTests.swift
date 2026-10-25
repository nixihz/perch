import Foundation
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class SkillHostSelectionTests: XCTestCase {
    func testProjectHostSwitchesPreserveEditingTargetRulesOtherProjectAndGlobalDraftsAcrossRestart() throws {
        try withFixture { f in
            let model = f.model
            let projectID = try XCTUnwrap(model.selectedProject?.id)
            let rule = try XCTUnwrap(model.snapshot.templates.first)
            model.toggleInstruction(rule)
            model.setSkill(f.first, enabled: true, host: .codex)
            let otherProject = f.root.appendingPathComponent("other-project")
            try FileManager.default.createDirectory(at: otherProject, withIntermediateDirectories: true)
            XCTAssertTrue(model.registerProject(otherProject))
            model.setSkill(f.second, enabled: true, host: .codex)
            let otherID = try XCTUnwrap(UUID(uuidString: model.selectedProjectID))
            let store = ProjectDraftStore(rootURL: f.paths.applicationSupportRoot)
            let otherBefore = try store.load(projectID: otherID)
            model.selectedProjectID = projectID
            model.globalConfiguration.setSkill(f.second.id, enabled: true, host: .claudeCode)
            let globalBefore = try f.manager.draft(host: .claudeCode)

            model.setSkill(f.duplicate, enabled: true, host: .claudeCode)
            XCTAssertEqual(model.selectedProject?.editingAgent, "codex")
            XCTAssertEqual(model.selectedProject?.draftSkillIDs, [f.first.id])
            XCTAssertEqual(model.selectedProject?.fragments, [rule.id])
            XCTAssertTrue(model.isDraftSelected(f.duplicate, host: .claudeCode))
            XCTAssertEqual(try store.load(projectID: otherID), otherBefore)
            XCTAssertEqual(try f.manager.draft(host: .claudeCode), globalBefore)

            let restarted = AppModel(snapshot: f.snapshot, runtimePaths: f.paths, globalLocations: f.locations)
            restarted.selectedProjectID = projectID
            XCTAssertTrue(restarted.isDraftSelected(f.first, host: .codex))
            XCTAssertTrue(restarted.isDraftSelected(f.duplicate, host: .claudeCode))
            restarted.setSkill(f.duplicate, enabled: false, host: .claudeCode)
            XCTAssertEqual(restarted.selectedProject?.editingAgent, "codex")
            XCTAssertTrue(restarted.isDraftSelected(f.first, host: .codex))
            XCTAssertEqual(restarted.selectedProject?.fragments, [rule.id])
            XCTAssertEqual(try store.load(projectID: otherID), otherBefore)
            XCTAssertEqual(try f.manager.draft(host: .claudeCode), globalBefore)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: otherProject.path).isEmpty)
            try f.assertNoHostWrites()
        }
    }

    func testProjectRejectsBlockedAndSameHostNameConflictsButCanRemoveBlockedSelection() throws {
        try withFixture { f in
            let model = f.model
            model.setSkill(f.first, enabled: true, host: .codex)
            let store = ProjectDraftStore(rootURL: f.paths.applicationSupportRoot)
            let saved = try Data(contentsOf: store.documentURL)
            let before = model.projects
            let projectID = try XCTUnwrap(model.selectedProject?.id)
            model.setSkill(f.duplicate, enabled: true, host: .codex)
            XCTAssertEqual(model.projects, before)
            XCTAssertEqual(try Data(contentsOf: store.documentURL), saved)
            let conflict = try XCTUnwrap(model.projectPlanNotice(for: projectID))
            XCTAssertEqual(conflict.tone, .error)
            XCTAssertTrue(conflict.message.contains(MCPHost.codex.displayName))
            XCTAssertTrue(conflict.message.contains(f.duplicate.slug))
            model.setSkill(f.blocked, enabled: true, host: .claudeCode)
            XCTAssertEqual(model.projects, before)
            XCTAssertEqual(try Data(contentsOf: store.documentURL), saved)
            let blocked = try XCTUnwrap(model.projectPlanNotice(for: projectID))
            XCTAssertEqual(blocked.tone, .error)
            XCTAssertTrue(blocked.message.contains(MCPHost.claudeCode.displayName))
            XCTAssertTrue(blocked.message.contains(f.blocked.slug))
            model.setSkill(f.second, enabled: false, host: .claudeCode)
            XCTAssertEqual(try Data(contentsOf: store.documentURL), saved, "关闭未选条目不能创建空宿主草稿")
            XCTAssertNil(model.selectedProject?.harnessSelections["claude-code"])

            let nowBlocked = try changedEntry(f.first, values: ["integrity": "blocked"])
            model.setSkill(nowBlocked, enabled: false, host: .codex)
            XCTAssertFalse(model.isDraftSelected(f.first, host: .codex))
            XCTAssertNil(model.projectPlanNotice(for: projectID), "成功移除后不能继续显示上一次拒绝的原因")
            let id = try XCTUnwrap(UUID(uuidString: model.selectedProjectID))
            XCTAssertEqual(try store.load(projectID: id)?.harnessSelections?["codex"]?.skillIDs, [])
            try f.assertNoHostWrites()
        }
    }

    func testProjectSaveFailureShowsInlineErrorAndSuccessfulRetryClearsIt() throws {
        try withFixture { f in
            f.model.setSkill(f.first, enabled: true, host: .codex)
            let store = ProjectDraftStore(rootURL: f.paths.applicationSupportRoot)
            let saved = try Data(contentsOf: store.documentURL)
            try Data("invalid draft".utf8).write(to: store.documentURL)
            let before = f.model.projects
            let projectID = try XCTUnwrap(f.model.selectedProject?.id)
            f.model.setSkill(f.second, enabled: true, host: .claudeCode)
            XCTAssertEqual(f.model.projects, before)
            XCTAssertFalse(f.model.isDraftSelected(f.second, host: .claudeCode))
            XCTAssertEqual(try String(contentsOf: store.documentURL, encoding: .utf8), "invalid draft")
            let failure = try XCTUnwrap(f.model.projectPlanNotice(for: projectID))
            XCTAssertEqual(failure.tone, .error)
            XCTAssertFalse(failure.message.isEmpty)
            XCTAssertEqual(f.model.selectedProject?.editingAgent, "codex")

            // 恢复可读草稿后重试同一动作，必须保存选择并移除页面上的过期错误。
            try saved.write(to: store.documentURL)
            f.model.setSkill(f.second, enabled: true, host: .claudeCode)
            XCTAssertTrue(f.model.isDraftSelected(f.second, host: .claudeCode))
            XCTAssertTrue(f.model.isDraftSelected(f.first, host: .codex))
            XCTAssertEqual(f.model.selectedProject?.editingAgent, "codex")
            XCTAssertNil(f.model.projectPlanNotice(for: projectID))
            let stored = try XCTUnwrap(store.load(projectID: try XCTUnwrap(UUID(uuidString: projectID))))
            XCTAssertEqual(stored.harnessSelections?["codex"]?.skillIDs, [f.first.id])
            XCTAssertEqual(stored.harnessSelections?["claude-code"]?.skillIDs, [f.second.id])
            try f.assertNoHostWrites()
        }
    }

    func testGlobalHostSwitchesPreserveCurrentTargetSettingsAndProjectDraftAcrossRestart() throws {
        try withFixture { f in
            let global = f.model.globalConfiguration
            f.model.setSkill(f.first, enabled: true, host: .codex)
            let store = ProjectDraftStore(rootURL: f.paths.applicationSupportRoot)
            let projectBefore = try Data(contentsOf: store.documentURL)
            global.setInstallMethod(.copy)
            let rule = try XCTUnwrap(f.model.snapshot.templates.first)
            global.setInstruction(rule.id, enabled: true)
            global.setSkill(f.first, enabled: true, host: .codex, catalog: f.entries)
            let codexBefore = global.draft
            global.setSkill(f.duplicate, enabled: true, host: .claudeCode, catalog: f.entries)
            XCTAssertEqual(global.host, .codex)
            XCTAssertEqual(global.draft, codexBefore)
            XCTAssertTrue(global.isSkillSelected(f.duplicate.id, host: .claudeCode))
            XCTAssertEqual(try Data(contentsOf: store.documentURL), projectBefore)

            let restarted = GlobalConfigurationModel(paths: f.paths, locations: f.locations)
            restarted.refresh()
            XCTAssertEqual(restarted.draft, codexBefore)
            XCTAssertTrue(restarted.isSkillSelected(f.duplicate.id, host: .claudeCode))
            restarted.setSkill(f.duplicate, enabled: false, host: .claudeCode, catalog: f.entries)
            XCTAssertEqual(restarted.host, .codex)
            XCTAssertEqual(restarted.draft, codexBefore)
            XCTAssertTrue(try f.manager.draft(host: .claudeCode).skillIDs.isEmpty)
            XCTAssertEqual(try f.manager.draft(host: .codex), codexBefore)
            XCTAssertEqual(try Data(contentsOf: store.documentURL), projectBefore)
            try f.assertNoHostWrites()
        }
    }

    func testGlobalRejectsBlockedAndSameHostNameConflictsButCanRemoveBlockedSelection() throws {
        try withFixture { f in
            let global = f.model.globalConfiguration
            global.setSkill(f.first, enabled: true, host: .codex, catalog: f.entries)
            let before = try f.manager.draft(host: .codex)
            global.setSkill(f.duplicate, enabled: true, host: .codex, catalog: f.entries)
            XCTAssertEqual(global.draft, before)
            XCTAssertEqual(try f.manager.draft(host: .codex), before)
            XCTAssertNotNil(global.error)
            global.setSkill(f.blocked, enabled: true, host: .claudeCode, catalog: f.entries)
            XCTAssertFalse(global.isSkillSelected(f.blocked.id, host: .claudeCode))
            XCTAssertTrue(try f.manager.draft(host: .claudeCode).skillIDs.isEmpty)
            XCTAssertNotNil(global.error)

            let nowBlocked = try changedEntry(f.first, values: ["integrity": "blocked"])
            global.setSkill(nowBlocked, enabled: false, host: .codex, catalog: f.entries)
            XCTAssertFalse(global.isSkillSelected(f.first.id, host: .codex))
            XCTAssertTrue(try f.manager.draft(host: .codex).skillIDs.isEmpty)
            XCTAssertNil(global.error)
            try f.assertNoHostWrites()
        }
    }

    func testGlobalLoadFailureDisablesOnlyAffectedHostAndPreservesUnreadableFile() throws {
        for fileName in ["claude-code-draft.json", "claude-code.json"] {
            try withFixture { f in
                let broken = f.paths.applicationSupportRoot.appendingPathComponent("global/\(fileName)")
                try FileManager.default.createDirectory(at: broken.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("invalid state".utf8).write(to: broken)
                let global = f.model.globalConfiguration
                global.refresh()
                XCTAssertTrue(global.canEditSkills(host: .codex))
                XCTAssertFalse(global.canEditSkills(host: .claudeCode))
                XCTAssertNotNil(global.skillEditingErrors[.claudeCode])
                global.setSkill(f.second, enabled: true, host: .claudeCode, catalog: f.entries)
                XCTAssertFalse(global.isSkillSelected(f.second.id, host: .claudeCode))
                XCTAssertEqual(try String(contentsOf: broken, encoding: .utf8), "invalid state")
                global.setSkill(f.first, enabled: true, host: .codex, catalog: f.entries)
                XCTAssertTrue(global.isSkillSelected(f.first.id, host: .codex))
                XCTAssertEqual(try f.manager.draft(host: .codex).skillIDs, [f.first.id])
                global.selectHost(.claudeCode)
                XCTAssertTrue(global.canEditSkills(host: .codex))
                XCTAssertFalse(global.canEditSkills(host: .claudeCode))
                XCTAssertNil(global.prepareDeployment())
                XCTAssertNotNil(global.error)
                try f.assertNoHostWrites()
            }
        }
    }

    func testGlobalSaveFailureKeepsBothHostSelectionsAndCurrentTarget() throws {
        try withFixture { f in
            let global = f.model.globalConfiguration
            global.setSkill(f.first, enabled: true, host: .codex, catalog: f.entries)
            let before = global.draft
            let blockedURL = f.paths.applicationSupportRoot.appendingPathComponent("global/claude-code-draft.json")
            try FileManager.default.createDirectory(at: blockedURL, withIntermediateDirectories: true)
            global.setSkill(f.second, enabled: true, host: .claudeCode, catalog: f.entries)
            XCTAssertEqual(global.host, .codex)
            XCTAssertEqual(global.draft, before)
            XCTAssertFalse(global.isSkillSelected(f.second.id, host: .claudeCode))
            XCTAssertNotNil(global.error)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: blockedURL.path).isEmpty)
            XCTAssertEqual(try f.manager.draft(host: .codex), before)
            try f.assertNoHostWrites()
        }
    }

    private func changedEntry(_ entry: SkillEntry, values: [String: String]) throws -> SkillEntry {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        for (key, value) in values { object[key] = value }
        return try JSONDecoder().decode(SkillEntry.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func withFixture(_ body: (Fixture) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("skill-host-selection-\(UUID())")
        let environment = ProcessInfo.processInfo.environment
        let keys = ["CFFIXED_USER_HOME", "SKILLSET_HOME", "CODEX_HOME", "CLAUDE_CONFIG_DIR"]
        for key in keys { setenv(key, root.appendingPathComponent(key).path, 1) }
        defer {
            for key in keys {
                if let value = environment[key] { setenv(key, value, 1) } else { unsetenv(key) }
            }
            try? FileManager.default.removeItem(at: root)
        }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let locations = GlobalConfigurationLocations(home: root.appendingPathComponent("home"), stateRoot: paths.applicationSupportRoot)
        let library = paths.makeLibraryStore(home: locations.home)
        let first = try library.save(SkillEditorDraft(slug: "first", document: "---\nname: first\ndescription: 第一份技能\n---\n第一份正文\n"), repositoryRoot: nil)
        let second = try library.save(SkillEditorDraft(slug: "second", document: "---\nname: second\ndescription: 第二份技能\n---\n第二份正文\n"), repositoryRoot: nil)
        let duplicate = try changedEntry(first, values: ["id": "fixture-source/first", "sourceId": "fixture-source"])
        let blocked = try changedEntry(first, values: ["id": "fixture-source/blocked", "slug": "blocked", "integrity": "blocked", "sourceId": "fixture-source"])
        let entries = [first, second, duplicate, blocked]
        let entryObjects = try [duplicate, blocked].map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) }
        let catalog = try JSONDecoder().decode(CatalogDocument.self, from: JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "hashAlgorithm": "sha256:path-content-executable:v1", "entries": entryObjects
        ]))
        let snapshot = AppSnapshot.load().withoutBundledSkills().replacingCatalog(catalog)
        let model = AppModel(snapshot: snapshot, runtimePaths: paths, globalLocations: locations)
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try "原有项目内容".write(to: project.appendingPathComponent("sentinel.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(model.registerProject(project))
        model.globalConfiguration.refresh()
        try body(Fixture(root: root, paths: paths, locations: locations, snapshot: snapshot, model: model,
            first: first, second: second, duplicate: duplicate, blocked: blocked, entries: entries))
    }

    private struct Fixture {
        let root: URL
        let paths: SkillSetRuntimePaths
        let locations: GlobalConfigurationLocations
        let snapshot: AppSnapshot
        let model: AppModel
        let first: SkillEntry
        let second: SkillEntry
        let duplicate: SkillEntry
        let blocked: SkillEntry
        let entries: [SkillEntry]

        var manager: GlobalConfigurationManager { GlobalConfigurationManager(paths: paths, locations: locations) }

        func assertNoHostWrites(file: StaticString = #filePath, line: UInt = #line) throws {
            let project = root.appendingPathComponent("project")
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: project.path), ["sentinel.txt"], file: file, line: line)
            XCTAssertEqual(try String(contentsOf: project.appendingPathComponent("sentinel.txt"), encoding: .utf8), "原有项目内容", file: file, line: line)
            for host in MCPHost.allCases {
                XCTAssertFalse(FileManager.default.fileExists(atPath: locations.skillsRoot(host).path), file: file, line: line)
                XCTAssertFalse(FileManager.default.fileExists(atPath: locations.rulesURL(host).path), file: file, line: line)
            }
        }
    }
}
