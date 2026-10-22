import AppKit
import SwiftUI
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class ConfigurationExperienceLayoutTests: XCTestCase {
    func testConnectionPageAndRelationshipMapRemainReadableAtMinimumSize() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("perch-experience-\(UUID())")
        let variables = ["CFFIXED_USER_HOME", "SKILLSET_HOME", "CODEX_HOME", "CLAUDE_CONFIG_DIR"]
        let environment = ProcessInfo.processInfo.environment
        for key in variables { setenv(key, root.appendingPathComponent(key).path, 1) }
        defer {
            for key in variables {
                if let value = environment[key] { setenv(key, value, 1) } else { unsetenv(key) }
            }
            try? FileManager.default.removeItem(at: root)
        }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let model = AppModel(runtimePaths: paths)
        let service = MCPLibraryEntry(name: "Documentation", transport: "streamable-http", commandOrURL: "https://example.com/mcp")
        XCTAssertTrue(model.mcpLibrary.save(service))
        model.section = .aiAccess
        try await verify(ContentView(model: model), size: NSSize(width: 1080, height: 700), name: "access")
        try await verify(ConfigurationMapSheet(model: model), size: NSSize(width: 760, height: 640), name: "map")
        model.section = .mcp
        try await verify(ContentView(model: model), size: NSSize(width: 1080, height: 700), name: "mcp")
        XCTAssertTrue(try DeploymentPlanStore(rootURL: paths.plansRoot).list().isEmpty,
                      "浏览接口和关系图不能生成写入计划")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("CODEX_HOME/config.toml").path))
    }

    private func verify<V: View>(_ content: V, size: NSSize, name: String) async throws {
        let controller = NSHostingController(rootView: content.background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(size)
        window.orderFront(nil)
        defer { window.close() }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(100))
            controller.view.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(controller.view.fittingSize.width, size.width + 1, "\(name) 横向溢出")
            XCTAssertLessThanOrEqual(controller.view.fittingSize.height, size.height + 1, "\(name) 纵向撑大窗口")
            let scrollViews = descendants(controller.view).compactMap { $0 as? NSScrollView }
            XCTAssertFalse(scrollViews.isEmpty)
            for scroll in scrollViews {
                let rect = scroll.convert(scroll.bounds, to: controller.view)
                XCTAssertGreaterThanOrEqual(rect.minX, -1)
                XCTAssertLessThanOrEqual(rect.maxX, size.width + 1)
                if let document = scroll.documentView, document.bounds.height > scroll.contentView.bounds.height {
                    let originalOrigin = scroll.contentView.bounds.origin
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: document.bounds.maxY - scroll.contentView.bounds.height))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    XCTAssertEqual(scroll.documentVisibleRect.maxY, document.bounds.maxY, accuracy: 1)
                    scroll.contentView.scroll(to: originalOrigin)
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
            }
            let bitmap = try XCTUnwrap(controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
            controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/perch-experience-\(name)-\(appearance == .aqua ? "light" : "dark").png"))
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
