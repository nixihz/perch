import Foundation
import XCTest
@testable import SkillSetCore

final class PresetStoreTests: XCTestCase {
    func testEditingInitialPresetSurvivesReloadWithoutDuplicatingOrHidingOtherPresets() throws {
        try fixture { _, store in
            let initial = [
                PresetRecord(id: "daily", name: "日常", revision: 4, skills: ["workspace/stc"], status: "draft"),
                PresetRecord(id: "research", name: "研究", skills: ["local-brian/research"], status: "draft")
            ]
            let before = try store.list(merging: initial)
            XCTAssertEqual(before.map(\.id), ["daily", "research"])
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.documentURL.path))
            let edited = PresetRecord(id: "daily", name: "我的工程", instructionFragments: ["engineering"])
            let saved = try store.save(edited, initial: initial)
            XCTAssertEqual(saved.map(\.id), ["daily", "research"])
            XCTAssertEqual(saved.first?.revision, 5)
            let reloaded = try PresetStore(rootURL: store.rootURL).list(merging: initial)
            XCTAssertEqual(reloaded, saved)
            XCTAssertEqual(reloaded.first?.name, "我的工程")
            XCTAssertEqual(reloaded.first?.skills, [])
            XCTAssertEqual(reloaded.first?.instructionFragments, ["engineering"])
            XCTAssertEqual(reloaded.last, initial.last)
            // 原名称已释放；后续新预设不能被已覆盖的初始值误判为重名。
            let added = try store.save(PresetRecord(name: "日常", skills: ["workspace/stc"]), initial: initial)
            XCTAssertEqual(added.count, 3)
            let updated = try store.save(edited, initial: initial)
            XCTAssertEqual(updated.first?.revision, 6)
            XCTAssertEqual(updated.count, 3)
        }
    }

    func testCreatingAndUpdatingPresetPersistsAllComponentTypesWithoutWritingProject() throws {
        try fixture { root, store in
            let sentinel = root.appendingPathComponent("project/AGENTS.md")
            try FileManager.default.createDirectory(at: sentinel.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "已有规则\n".write(to: sentinel, atomically: true, encoding: .utf8)
            let json = """
            {"schemaVersion":2,"id":"custom","name":"  工程组合  ","description":"常用开发工具","revision":1,
             "skills":["workspace/stc"],"instructionFragments":["engineering"],
             "plugins":[{"host":"claude-code","pluginID":"tools@example","name":"Tools","manifestDigest":"\(String(repeating: "a", count: 64))","scope":"project"}],
             "mcpServers":[{"name":"docs","host":"codex","scope":"project","transport":"stdio","commandOrURL":"/usr/bin/true","args":["one argument with spaces"],"envKeys":["API_TOKEN"]}],
             "mergePolicy":"explicit-selection","status":"local"}
            """
            let preset = try JSONDecoder().decode(PresetRecord.self, from: Data(json.utf8))
            _ = try store.save(preset, initial: [])
            let saved = try XCTUnwrap(PresetStore(rootURL: store.rootURL).list().first)
            XCTAssertEqual(saved.name, "工程组合")
            XCTAssertEqual(saved.plugins.first?.manifestDigest, String(repeating: "a", count: 64))
            XCTAssertEqual(saved.mcpServers.first?.args, ["one argument with spaces"])
            XCTAssertEqual(saved.mcpServers.first?.scope, .project)
            XCTAssertEqual(saved.instructionFragments, ["engineering"])
            _ = try store.save(PresetRecord(id: "custom", name: "新组合", skills: ["workspace/project-guide"]), initial: [])
            let updated = try store.list()
            XCTAssertEqual(updated.count, 1)
            XCTAssertEqual(updated.first?.revision, 2)
            XCTAssertEqual(updated.first?.skills, ["workspace/project-guide"])
            XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "已有规则\n")
        }
    }

    func testInvalidDuplicateAndCorruptSavesNeverReplaceExistingData() throws {
        try fixture { _, store in
            let preset = PresetRecord(name: "工程", skills: ["workspace/stc"])
            _ = try store.save(preset, initial: [])
            let before = try Data(contentsOf: store.documentURL)
            let invalid = [
                PresetRecord(name: " ", skills: ["workspace/stc"]),
                PresetRecord(name: "空组合"),
                PresetRecord(name: "工程", skills: ["workspace/project-guide"]),
                PresetRecord(name: "重复 MCP", mcpServers: [server(), server()]),
                PresetRecord(name: "规范化后重复 MCP", mcpServers: [server(), MCPConfigurationDraft(name: " docs ", scope: .user, commandOrURL: "/usr/bin/true")]),
                PresetRecord(name: "凭据值", mcpServers: [MCPConfigurationDraft(name: "api", scope: .user, commandOrURL: "true", envKeys: ["API_KEY=secret"])])
            ]
            for value in invalid {
                XCTAssertThrowsError(try store.save(value, initial: []))
                XCTAssertEqual(try Data(contentsOf: store.documentURL), before)
            }
            let initial = PresetRecord(id: "initial", name: "初始组合", revision: 4, skills: ["workspace/project-guide"])
            let edited = PresetRecord(id: "initial", name: "初始组合已修改", skills: ["workspace/stc"])
            _ = try store.save(edited, initial: [initial])
            let merged = try store.list(merging: [initial])
            XCTAssertEqual(merged.filter { $0.id == "initial" }.count, 1)
            XCTAssertEqual(merged.first { $0.id == "initial" }?.revision, 5)
            XCTAssertEqual(merged.first { $0.id == "initial" }?.skills, ["workspace/stc"])
            try Data("invalid".utf8).write(to: store.documentURL)
            XCTAssertThrowsError(try store.save(PresetRecord(name: "另一个", skills: ["workspace/stc"]), initial: []))
            XCTAssertEqual(try String(contentsOf: store.documentURL, encoding: .utf8), "invalid")
        }
    }

    func testLegacyDraftDecodesAndOrdinarySkillSaveKeepsPresetComponents() throws {
        try fixture { root, _ in
            let projectID = UUID()
            let store = ProjectDraftStore(rootURL: root)
            try """
            {"schemaVersion":1,"drafts":[{"projectID":"\(projectID)","skillIDs":[],"instructionIDs":["base-zh"],"agents":["codex"],"updatedAt":"2026-10-21T00:00:00Z"}]}
            """.write(to: store.documentURL, atomically: true, encoding: .utf8)
            XCTAssertEqual(try store.load(projectID: projectID)?.mcpServers.count, 0)
            _ = try store.save(projectID: projectID, skillIDs: [], instructionIDs: ["base-zh"], agents: ["codex"], mcpServers: [server()])
            _ = try store.save(projectID: projectID, skillIDs: ["workspace/stc"], instructionIDs: [], agents: ["claude-code"])
            let saved = try XCTUnwrap(store.load(projectID: projectID))
            XCTAssertEqual(saved.mcpServers.first?.name, "docs")
            XCTAssertEqual(saved.skillIDs, ["workspace/stc"])
            XCTAssertEqual(saved.agents, ["claude-code"])
        }
    }

    private func server() -> MCPConfigurationDraft {
        MCPConfigurationDraft(name: "docs", scope: .user, commandOrURL: "/usr/bin/true")
    }

    private func fixture(_ body: (URL, PresetStore) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("preset-store-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root, PresetStore(rootURL: root.appendingPathComponent("state")))
    }
}
