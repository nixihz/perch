import AppKit
import SwiftUI
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class SelectedSkillPillsTests: XCTestCase {
    func testManySelectedSkillsWrapAndScrollWithoutHidingResourceListsInAllThreePages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("selected-pills-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let locations = GlobalConfigurationLocations(home: root.appendingPathComponent("home"), stateRoot: paths.applicationSupportRoot)
        let store = paths.makeLibraryStore()
        for index in 0..<24 {
            let name = index == 0 ? "very-long-skill-name-for-database-migration-review" : "selected-skill-\(index)"
            _ = try store.save(SkillEditorDraft(slug: name,
                document: "---\nname: \(name)\ndescription: 已选技能布局验证\n---\n正文\n"), repositoryRoot: nil)
        }
        let model = AppModel(runtimePaths: paths, globalLocations: locations)
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        XCTAssertTrue(model.registerProject(project, name: "技能组合验证"))
        model.globalConfiguration.refresh()
        var preset = PresetEditorDraft()
        preset.name = "常用技能"
        for skill in model.snapshot.catalog.entries {
            model.setSkill(skill, enabled: true, host: .codex)
            model.globalConfiguration.setSkill(skill, enabled: true, host: .codex, catalog: model.snapshot.catalog.entries)
            preset.skills.insert(skill.id)
        }
        XCTAssertTrue(model.savePreset(preset))
        let presetURL = PresetStore(rootURL: paths.applicationSupportRoot).documentURL
        let savedPreset = try Data(contentsOf: presetURL)
        for section in [NavigationItem.globalConfiguration, .projects, .presets] {
            model.section = section
            let controller = NSHostingController(rootView: ContentView(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700),
                styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = controller
            defer { window.close() }
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: appearance)
                try await Task.sleep(for: .milliseconds(200))
                controller.view.layoutSubtreeIfNeeded()
                XCTAssertLessThanOrEqual(controller.view.fittingSize.width, 1081, "\(section)")
                XCTAssertLessThanOrEqual(controller.view.fittingSize.height, 701, "\(section)")
                let scrolls = descendants(controller.view).compactMap { $0 as? NSScrollView }
                let pills = try XCTUnwrap(scrolls.first {
                    $0.bounds.height >= 28 && $0.bounds.height <= 125
                        && ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height
                }, "大量选择必须在已选区域独立滚动：\(section)")
                let document = try XCTUnwrap(pills.documentView)
                pills.contentView.scroll(to: NSPoint(x: 0, y: document.bounds.maxY - pills.contentView.bounds.height))
                pills.reflectScrolledClipView(pills.contentView)
                XCTAssertEqual(pills.documentVisibleRect.maxY, document.bounds.maxY, accuracy: 1)
                XCTAssertTrue(scrolls.contains { $0 !== pills && $0.bounds.height > 100 && $0.bounds.width > 500 },
                    "可选技能列表必须保留操作空间：\(section)，实际：\(scrolls.map { $0.bounds.size })")
                pills.contentView.scroll(to: .zero)
                pills.reflectScrolledClipView(pills.contentView)
                let bitmap = try XCTUnwrap(controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
                controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to:
                    URL(fileURLWithPath: "/tmp/perch-pills-\(section.rawValue)-\(appearance == .aqua ? "light" : "dark").png"))
            }
        }
        XCTAssertEqual(try Data(contentsOf: presetURL), savedPreset, "展示和切页不能保存预设")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: project.path).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: locations.rulesURL(.codex).path))
        XCTAssertTrue(try DeploymentPlanStore(rootURL: paths.plansRoot).list().isEmpty)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
