import AppKit
import SwiftUI
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class TemplateEditorTests: XCTestCase {
    func testModelSavesSearchesAndRemovesWithoutChangingProjectOrSilentlyDroppingReferences() throws {
        try fixture { root, paths in
            let project = root.appendingPathComponent("project")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let file = project.appendingPathComponent("AGENTS.md")
            try "手写规则\n".write(to: file, atomically: true, encoding: .utf8)
            let model = AppModel(runtimePaths: paths)
            XCTAssertTrue(model.registerProject(project, name: "片段验证"))
            var draft = TemplateEditorDraft()
            XCTAssertFalse(model.saveTemplate(draft))
            XCTAssertNotNil(model.templateError)
            draft.title = "检查接口"
            draft.purpose = "发布前核对"
            draft.body = "检查超时和取消请求。"
            XCTAssertTrue(model.saveTemplate(draft))
            let saved = try XCTUnwrap(model.selectedTemplate)
            for query in ["检查接口", "发布前", "取消请求"] {
                XCTAssertEqual(model.matchingTemplates(query).map(\.id), [saved.id])
            }
            model.toggleInstruction(saved)
            var preset = PresetEditorDraft()
            preset.name = "含自定义片段"
            preset.instructions = [saved.id]
            XCTAssertTrue(model.savePreset(preset))
            var editing = TemplateEditorDraft(template: saved)
            editing.body = "检查重试上限。"
            XCTAssertTrue(model.saveTemplate(editing))
            XCTAssertEqual(model.selectedTemplate?.id, saved.id)
            XCTAssertEqual(model.selectedTemplate?.body, "检查重试上限。")
            model.removeTemplate(try XCTUnwrap(model.selectedTemplate))
            XCTAssertFalse(model.snapshot.templates.contains { $0.id == saved.id })
            XCTAssertTrue(model.selectedProject?.fragments.contains(saved.id) == true)
            XCTAssertTrue(model.selectedPreset?.instructionFragments.contains(saved.id) == true)
            XCTAssertFalse(model.savePreset(preset))
            model.toggleInstructionID(saved.id)
            XCTAssertFalse(model.selectedProject?.fragments.contains(saved.id) == true)
            XCTAssertFalse(AppModel(runtimePaths: paths).snapshot.templates.contains { $0.id == saved.id })
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "手写规则\n")
            XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent("skillset.json").path))
        }
    }

    func testLocalMetadataStaysOriginalEvenWhenItMatchesAnEnglishTranslationKey() throws {
        try fixture { _, paths in
            let model = AppModel(runtimePaths: paths)
            let initial = try XCTUnwrap(model.snapshot.templates.first { $0.id == "base-zh" })
            XCTAssertEqual(UserFacingText.templateTitle(initial, language: .english), "Chinese Collaboration")
            var draft = TemplateEditorDraft(template: initial)
            draft.title = "中文协作"
            draft.purpose = "工程质量"
            XCTAssertTrue(model.saveTemplate(draft))
            let local = try XCTUnwrap(AppModel(runtimePaths: paths).selectedTemplate)
            XCTAssertEqual(UserFacingText.templateTitle(local, language: .english), "中文协作")
            XCTAssertEqual(UserFacingText.templatePurpose(local, language: .english), "工程质量")
        }
    }

    func testLongLibraryScrollsAtMinimumWindowAndEditorKeepsEditableBodyInBothAppearances() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("template-ui-\(UUID())")
        let saved = isolateHostEnvironment(root)
        defer { restoreHostEnvironment(saved); try? FileManager.default.removeItem(at: root) }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let store = TemplateStore(rootURL: paths.applicationSupportRoot)
        for index in 0..<24 {
            _ = try store.save(TemplateRecord(title: "规则 \(index)", body: "规则正文 \(index)", purpose: "在界面交付前检查"), initial: [])
        }
        let model = AppModel(runtimePaths: paths)
        model.section = .templates
        let controller = NSHostingController(rootView: ContentView(model: model))
        let window = makeWindow(controller, size: NSSize(width: 1080, height: 700))
        defer { window.close() }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(100))
            controller.view.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(controller.view.fittingSize.height, 701)
            XCTAssertLessThanOrEqual(controller.view.fittingSize.width, 1081)
            let scroll = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSScrollView }.first {
                ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height + 100
            })
            let document = try XCTUnwrap(scroll.documentView)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: document.bounds.maxY - scroll.contentView.bounds.height))
            scroll.reflectScrolledClipView(scroll.contentView)
            XCTAssertEqual(scroll.documentVisibleRect.maxY, document.bounds.maxY, accuracy: 1)
            if appearance == .aqua, let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) {
                controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/skillset-templates-crud.png"))
            }
        }
        var draft = TemplateEditorDraft()
        draft.title = "待保存的规则"
        draft.body = "请保留未保存的正文。"
        let editor = NSHostingController(rootView: TemplateEditorSheet(model: model, initialDraft: draft))
        let editorWindow = makeWindow(editor, size: NSSize(width: 720, height: 620))
        defer { editorWindow.close() }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            editorWindow.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(80))
            editor.view.layoutSubtreeIfNeeded()
            let text = try XCTUnwrap(descendants(editor.view).compactMap { $0 as? NSTextView }.first { $0.string == draft.body })
            XCTAssertTrue(text.isEditable)
            XCTAssertLessThanOrEqual(editor.view.fittingSize.height, 621)
            XCTAssertLessThanOrEqual(editor.view.fittingSize.width, 721)
            if appearance == .aqua, let bitmap = editor.view.bitmapImageRepForCachingDisplay(in: editor.view.bounds) {
                editor.view.cacheDisplay(in: editor.view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/skillset-template-editor.png"))
            }
        }
    }

    private func makeWindow<V: View>(_ controller: NSHostingController<V>, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(size)
        return window
    }

    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }

    private func isolateHostEnvironment(_ root: URL) -> [String: String] {
        let saved = ProcessInfo.processInfo.environment
        for key in ["CFFIXED_USER_HOME", "SKILLSET_HOME", "CODEX_HOME"] { setenv(key, root.appendingPathComponent(key).path, 1) }
        return saved
    }

    private func restoreHostEnvironment(_ saved: [String: String]) {
        for key in ["CFFIXED_USER_HOME", "SKILLSET_HOME", "CODEX_HOME"] {
            if let value = saved[key] { setenv(key, value, 1) } else { unsetenv(key) }
        }
    }

    private func fixture(_ body: (URL, SkillSetRuntimePaths) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("template-model-\(UUID())")
        let saved = isolateHostEnvironment(root)
        defer { restoreHostEnvironment(saved); try? FileManager.default.removeItem(at: root) }
        try body(root, SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil))
    }
}
