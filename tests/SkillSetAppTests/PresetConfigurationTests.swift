import AppKit
import SwiftUI
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class PresetConfigurationTests: XCTestCase {
    func testSavingOnePresetClearsOnlyItsDraftAndDoesNotWriteProjectsOrHostConfiguration() throws {
        try fixture { root, model, first, second in
            var changed = PresetEditorDraft(preset: first)
            changed.name = "修改后的组合"
            changed.instructions = Set(model.snapshot.templates.map(\.id))
            var pending = PresetEditorDraft(preset: second)
            pending.description = "另一份尚未保存的修改"
            model.presetDrafts[first.id] = changed
            model.presetDrafts[second.id] = pending
            let store = PresetStore(rootURL: model.runtimePaths.applicationSupportRoot)
            let before = try Data(contentsOf: store.documentURL)
            model.selectedPresetID = second.id
            model.selectedPresetID = first.id
            XCTAssertEqual(try Data(contentsOf: store.documentURL), before)
            let projectBefore = model.projects
            let presetOrder = model.snapshot.presets.map(\.id)
            XCTAssertTrue(model.savePreset(changed))
            XCTAssertEqual(model.snapshot.presets.map(\.id), presetOrder, "保存不能让顶部预设按钮跳到末尾")
            XCTAssertNil(model.presetDrafts[first.id])
            XCTAssertEqual(model.presetDrafts[second.id], pending)
            XCTAssertEqual(model.selectedPreset?.name, changed.name)
            XCTAssertEqual(model.selectedPreset?.revision, first.revision + 1)
            XCTAssertEqual(model.projects, projectBefore)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("project/sentinel.txt"), encoding: .utf8), "unchanged")
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("project").path), ["sentinel.txt"])
            XCTAssertFalse(FileManager.default.fileExists(atPath: model.globalConfiguration.locations.rulesURL(.codex).path))
            XCTAssertTrue(try DeploymentPlanStore(rootURL: model.runtimePaths.plansRoot).list().isEmpty)
            let restarted = AppModel(runtimePaths: model.runtimePaths, globalLocations: model.globalConfiguration.locations)
            XCTAssertEqual(restarted.snapshot.presets.first { $0.id == first.id }?.name, changed.name)
        }
    }

    func testFailedSaveKeepsBothDraftsAndTheSavedPresetBytes() throws {
        try fixture { _, model, first, second in
            var duplicate = PresetEditorDraft(preset: first)
            duplicate.name = second.name
            model.presetDrafts[first.id] = duplicate
            let other = PresetEditorDraft(preset: second)
            model.presetDrafts[second.id] = other
            let url = PresetStore(rootURL: model.runtimePaths.applicationSupportRoot).documentURL
            let before = try Data(contentsOf: url)
            XCTAssertFalse(model.savePreset(duplicate))
            XCTAssertNotNil(model.presetError)
            XCTAssertEqual(model.presetDrafts[first.id], duplicate)
            XCTAssertEqual(model.presetDrafts[second.id], other)
            XCTAssertEqual(try Data(contentsOf: url), before)
        }
    }

    func testPresetSelectorAndSavePreviewFitBothAppearancesWithoutSaving() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, first, _) = try seed(root)
        model.section = .presets
        let url = PresetStore(rootURL: model.runtimePaths.applicationSupportRoot).documentURL
        let before = try Data(contentsOf: url)
        let controller = NSHostingController(rootView: ContentView(model: model))
        let window = makeWindow(controller, size: NSSize(width: 1080, height: 700))
        defer { window.close() }
        var proposed = PresetEditorDraft(preset: first)
        proposed.name = "预览但不保存"
        let review = NSHostingController(rootView: PresetSavePreview(model: model, draft: proposed,
            initial: PresetEditorDraft(preset: first), onSaved: {}))
        let reviewWindow = makeWindow(review, size: NSSize(width: 760, height: 620))
        defer { reviewWindow.close() }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            reviewWindow.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(150))
            controller.view.layoutSubtreeIfNeeded(); review.view.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(controller.view.fittingSize.width, 1081)
            XCTAssertLessThanOrEqual(controller.view.fittingSize.height, 701)
            XCTAssertLessThanOrEqual(review.view.fittingSize.width, 761)
            XCTAssertLessThanOrEqual(review.view.fittingSize.height, 621)
            let scrolls = descendants(controller.view).compactMap { $0 as? NSScrollView }
            let table = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSTableView }.first)
            let content = scrolls.filter { $0 !== table.enclosingScrollView }
            let selector = try XCTUnwrap(content.first { $0.bounds.height >= 44 && $0.bounds.height <= 48 })
            let resources = try XCTUnwrap(content.first { $0.bounds.height > 100 })
            let selectionRect = selector.convert(selector.bounds, to: controller.view)
            let resourceRect = resources.convert(resources.bounds, to: controller.view)
            XCTAssertFalse(selectionRect.intersects(resourceRect))
            XCTAssertGreaterThanOrEqual(resourceRect.width, controller.view.bounds.width - 420)
        }
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertTrue(try DeploymentPlanStore(rootURL: model.runtimePaths.plansRoot).list().isEmpty)
    }

    private func fixture(_ body: (URL, AppModel, PresetRecord, PresetRecord) throws -> Void) throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, first, second) = try seed(root)
        try body(root, model, first, second)
    }

    private func seed(_ root: URL) throws -> (AppModel, PresetRecord, PresetRecord) {
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let locations = GlobalConfigurationLocations(home: root.appendingPathComponent("home"), stateRoot: paths.applicationSupportRoot)
        let skill = try paths.makeLibraryStore().save(SkillEditorDraft(slug: "fixture",
            document: "---\nname: fixture\ndescription: 预设界面测试\n---\n测试正文\n"), repositoryRoot: nil)
        _ = try TemplateStore(rootURL: paths.applicationSupportRoot).save(TemplateRecord(title: "代码工程", body: "提交前测试。"), initial: [])
        let model = AppModel(runtimePaths: paths, globalLocations: locations)
        var draft = PresetEditorDraft()
        draft.name = "工程组合"; draft.skills = [skill.id]
        XCTAssertTrue(model.savePreset(draft))
        let first = try XCTUnwrap(model.selectedPreset)
        draft = PresetEditorDraft(); draft.name = "界面组合"; draft.skills = [skill.id]
        XCTAssertTrue(model.savePreset(draft))
        let second = try XCTUnwrap(model.selectedPreset)
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try "unchanged".write(to: project.appendingPathComponent("sentinel.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(model.registerProject(project))
        return (model, first, second)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("preset-config-\(UUID())")
    }
    private func makeWindow<V: View>(_ controller: NSHostingController<V>, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentViewController = controller
        return window
    }
    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
}
