import Foundation
import XCTest
@testable import SkillSetCore

/// 预设并集与差集语义。
///
/// 这些用例验证用户能观察到的结果：多个预设同时生效、重叠内容只留一份、取消一个预设只回收它独有的内容。
final class PresetMergeTests: XCTestCase {
    func testMergingTwoPresetsKeepsOverlappingContentOnce() throws {
        let first = PresetRecord(id: "first", name: "组合一", skills: ["workspace/stc", "workspace/project-guide"],
                                 instructionFragments: ["engineering"])
        let second = PresetRecord(id: "second", name: "组合二", skills: ["workspace/stc", "workspace/likec4-dsl"],
                                  instructionFragments: ["engineering", "base-zh"])
        let merged = PresetDraftMerge.merging([first, second], host: "codex", to: PresetDraftState())
        let selection = try XCTUnwrap(merged.selections["codex"])
        XCTAssertEqual(selection.skillIDs, ["workspace/likec4-dsl", "workspace/project-guide", "workspace/stc"])
        XCTAssertEqual(selection.instructionIDs, ["base-zh", "engineering"])
        XCTAssertEqual(merged.applications.map(\.presetID), ["first", "second"])
    }

    func testCancellingOnePresetRemovesOnlyItsExclusiveContent() throws {
        let first = PresetRecord(id: "first", name: "组合一", skills: ["workspace/stc", "workspace/project-guide"])
        let second = PresetRecord(id: "second", name: "组合二", skills: ["workspace/stc", "workspace/likec4-dsl"])
        let applied = PresetDraftMerge.merging([first, second], host: "codex", to: PresetDraftState())
        let cancelled = PresetDraftMerge.removing(presetIDs: ["first"], host: "codex", from: applied)
        // 重叠技能来自另一个预设，继续保留；只有第一个预设独有的技能被回收。
        XCTAssertEqual(cancelled.selections["codex"]?.skillIDs, ["workspace/likec4-dsl", "workspace/stc"])
        XCTAssertEqual(cancelled.applications.map(\.presetID), ["second"])
    }

    func testCancellingOnePresetKeepsManuallySelectedContent() throws {
        let preset = PresetRecord(id: "preset", name: "组合", skills: ["workspace/stc"])
        var state = PresetDraftState()
        state.selections["codex"] = ProjectHarnessSelection(skillIDs: ["workspace/stc", "workspace/manual"], instructionIDs: [])
        let applied = PresetDraftMerge.merging([preset], host: "codex", to: state)
        let cancelled = PresetDraftMerge.removing(presetIDs: ["preset"], host: "codex", from: applied)
        // 手动选择的技能没有对应预设记录，不能被取消预设带走。
        XCTAssertEqual(cancelled.selections["codex"]?.skillIDs, ["workspace/manual"])
    }

    func testReapplyingChangedPresetReplacesOnlyItsOwnOldContent() throws {
        let original = PresetRecord(id: "preset", name: "组合", skills: ["workspace/stc", "workspace/project-guide"])
        let other = PresetRecord(id: "other", name: "另一组合", skills: ["workspace/project-guide", "workspace/likec4-dsl"])
        let applied = PresetDraftMerge.merging([original, other], host: "codex", to: PresetDraftState())
        let changed = PresetRecord(id: "preset", name: "组合", revision: 2, skills: ["workspace/stc"])
        let refreshed = PresetDraftMerge.merging([changed], host: "codex", to: applied)
        // 旧版本独有的技能被回收，另一个预设提供的技能不受影响。
        XCTAssertEqual(refreshed.selections["codex"]?.skillIDs, ["workspace/likec4-dsl", "workspace/project-guide", "workspace/stc"])
        XCTAssertEqual(refreshed.applications.first { $0.presetID == "preset" }?.revision, 2)
    }

    func testSelectingSmallerSetCancelsUnselectedPresetByDifference() throws {
        let first = PresetRecord(id: "first", name: "组合一", skills: ["workspace/stc"])
        let second = PresetRecord(id: "second", name: "组合二", skills: ["workspace/likec4-dsl"])
        let applied = PresetDraftMerge.merging([first, second], host: "codex", to: PresetDraftState())
        let selected = PresetDraftMerge.selecting([first], host: "codex", to: applied)
        XCTAssertEqual(selected.selections["codex"]?.skillIDs, ["workspace/stc"])
        XCTAssertEqual(selected.applications.map(\.presetID), ["first"])
    }

    func testCancellingPresetOnOneHostLeavesOtherHostUntouched() throws {
        let preset = PresetRecord(id: "preset", name: "组合", skills: ["workspace/stc"])
        let applied = PresetDraftMerge.merging([preset], host: "codex", to: PresetDraftState())
        let cancelled = PresetDraftMerge.removing(presetIDs: ["preset"], host: "claude-code", from: applied)
        // 另一个 AI 工具的预设记录保持原样。
        XCTAssertEqual(cancelled.applications.map(\.presetID), ["preset"])
        XCTAssertEqual(cancelled.selections["codex"]?.skillIDs, ["workspace/stc"])
    }

    func testCancellingPresetRemovesExclusivePluginOnly() throws {
        let shared = try pluginReference(id: "shared", digest: String(repeating: "a", count: 64))
        let exclusive = try pluginReference(id: "exclusive", digest: String(repeating: "b", count: 64))
        let first = PresetRecord(id: "first", name: "组合一", plugins: [shared, exclusive])
        let second = PresetRecord(id: "second", name: "组合二", plugins: [shared])
        let applied = PresetDraftMerge.merging([first, second], host: "codex", to: PresetDraftState())
        XCTAssertEqual(Set(applied.plugins.map(\.id)), Set([shared.id, exclusive.id]))
        let cancelled = PresetDraftMerge.removing(presetIDs: ["first"], host: "codex", from: applied)
        // 共享插件仍由另一个预设提供，不能被取消。
        XCTAssertEqual(cancelled.plugins.map(\.id), [shared.id])
    }

    private func pluginReference(id: String, digest: String) throws -> PresetPluginReference {
        let json = """
        {"host":"claude-code","pluginID":"\(id)","name":"插件","manifestDigest":"\(digest)","scope":"project"}
        """
        return try JSONDecoder().decode(PresetPluginReference.self, from: Data(json.utf8))
    }
}
