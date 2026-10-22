import AppKit
import SwiftUI
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class SkillEditorTests: XCTestCase {
    func testEditorAndModelKeepInvalidDraftThenSaveSearchEditAndRemove() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("editor-\(UUID())")
        let variables = ["CFFIXED_USER_HOME", "SKILLSET_HOME", "CODEX_HOME"]
        let environment = ProcessInfo.processInfo.environment
        for variable in variables { setenv(variable, root.appendingPathComponent(variable).path, 1) }
        defer {
            for variable in variables {
                if let value = environment[variable] { setenv(variable, value, 1) } else { unsetenv(variable) }
            }
            try? FileManager.default.removeItem(at: root)
        }
        let model = AppModel(runtimePaths: SkillSetRuntimePaths(applicationSupportRoot: root, repositoryRoot: nil))
        let originalCount = model.snapshot.catalog.entries.count
        var draft = SkillEditorDraft(slug: "ui-demo", document: "无头部")
        XCTAssertFalse(model.saveSkill(draft))
        XCTAssertNotNil(model.libraryError)
        XCTAssertEqual(model.snapshot.catalog.entries.count, originalCount)
        let controller = NSHostingController(rootView: SkillEditorSheet(model: model, initialDraft: draft))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 620), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer { window.close() }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(80))
            controller.view.layoutSubtreeIfNeeded()
            let textView = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSTextView }.first)
            XCTAssertTrue(textView.isEditable)
            XCTAssertEqual(textView.string, "无头部")
            XCTAssertLessThanOrEqual(controller.view.fittingSize.height, 620)
            XCTAssertLessThanOrEqual(controller.view.fittingSize.width, 720)
            if let destination = ProcessInfo.processInfo.environment["SKILLSET_EDITOR_SCREENSHOT_DIR"],
               let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) {
                controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
                let url = URL(fileURLWithPath: destination).appendingPathComponent("skill-editor-\(appearance == .aqua ? "light" : "dark").png")
                try bitmap.representation(using: .png, properties: [:])?.write(to: url)
            }
        }
        draft.document = "---\nname: ui-demo\ndescription: 界面验证\n---\n\n# 测试\n完整正文\n"
        XCTAssertTrue(model.saveSkill(draft))
        XCTAssertNil(model.libraryError)
        XCTAssertEqual(model.selectedSkill?.id, "personal/ui-demo")
        XCTAssertTrue(model.selectedSkillDocument.contains("完整正文"))
        model.updateQuery("界面验证")
        XCTAssertEqual(model.filteredSkills.map(\.id), ["personal/ui-demo"])
        var editing = try XCTUnwrap(model.editorDraft(for: try XCTUnwrap(model.selectedSkill)))
        editing.document += "\n新增约束\n"
        XCTAssertTrue(model.saveSkill(editing))
        XCTAssertTrue(model.selectedSkillDocument.contains("新增约束"))
        model.removeSkill(try XCTUnwrap(model.selectedSkill))
        XCTAssertEqual(model.snapshot.catalog.entries.count, originalCount)
        XCTAssertFalse(model.snapshot.catalog.entries.contains { $0.id == "personal/ui-demo" })
    }

    func testBatchRemovalStopsAtStaleEntryAndKeepsRemainingSkillsForRetry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("batch-removal-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root, repositoryRoot: nil)
        let model = AppModel(snapshot: AppSnapshot.load(), runtimePaths: paths)
        for slug in ["batch-first", "batch-stale", "batch-last"] {
            XCTAssertTrue(model.saveSkill(SkillEditorDraft(
                slug: slug, document: "---\nname: \(slug)\ndescription: 批量移除验证\n---\n正文\n"
            )))
        }
        let first = try XCTUnwrap(model.snapshot.catalog.entries.first { $0.slug == "batch-first" })
        let stale = try XCTUnwrap(model.snapshot.catalog.entries.first { $0.slug == "batch-stale" })
        let last = try XCTUnwrap(model.snapshot.catalog.entries.first { $0.slug == "batch-last" })
        var editing = try XCTUnwrap(model.editorDraft(for: stale))
        editing.document += "\n更新正文\n"
        XCTAssertTrue(model.saveSkill(editing))
        let updated = try XCTUnwrap(model.selectedSkill)
        XCTAssertEqual(model.removeSkills([first, stale, last]), [first.id])
        XCTAssertNotNil(model.skillRemovalError)
        XCTAssertFalse(model.snapshot.catalog.entries.contains { $0.id == first.id })
        XCTAssertTrue(model.snapshot.catalog.entries.contains { $0.id == stale.id })
        XCTAssertTrue(model.snapshot.catalog.entries.contains { $0.id == last.id })
        let source = try XCTUnwrap(model.snapshot.catalog.entries.first { $0.sourceId != SkillLibraryStore.sourceID })
        let hiddenCount = model.hiddenSkillCount
        XCTAssertEqual(model.removeSkills([updated, last, last, source]), [updated.id, last.id, source.id])
        XCTAssertNil(model.skillRemovalError)
        XCTAssertEqual(model.hiddenSkillCount, hiddenCount + 1)
        let restarted = AppModel(snapshot: AppSnapshot.load(), runtimePaths: paths)
        XCTAssertFalse(restarted.snapshot.catalog.entries.contains { [first.id, stale.id, last.id, source.id].contains($0.id) })
        restarted.restoreHiddenSkills()
        XCTAssertTrue(restarted.snapshot.catalog.entries.contains { $0.id == source.id })
        XCTAssertFalse(restarted.snapshot.catalog.entries.contains { [first.id, stale.id, last.id].contains($0.id) })
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
