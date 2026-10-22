import AppKit
import SwiftUI
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class ControlFormLayoutTests: XCTestCase {
    func testMCPFieldsKeepEqualWidthsAndLastFieldRemainsReachable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("control-form-\(UUID())")
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
        let controller = NSHostingController(rootView: MCPConfigSheet(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 620), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer { window.close() }

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(100))
            controller.view.layoutSubtreeIfNeeded()
            // 比较实际渲染的原生输入区域，防止标签长度重新影响输入宽度。
            let fields = descendants(controller.view).compactMap { $0 as? NSTextField }.filter(\.isEditable)
            XCTAssertGreaterThanOrEqual(fields.count, 3, "名称、命令和环境变量必须可编辑")
            let first = try XCTUnwrap(fields.first)
            let reference = first.convert(first.bounds, to: controller.view)
            XCTAssertGreaterThan(reference.width, 480, "输入应利用表单宽度")
            for field in fields {
                let rect = field.convert(field.bounds, to: controller.view)
                XCTAssertEqual(rect.minX, reference.minX, accuracy: 1)
                XCTAssertEqual(rect.width, reference.width, accuracy: 1)
            }
            XCTAssertLessThanOrEqual(controller.view.fittingSize.width, 600)
            XCTAssertLessThanOrEqual(controller.view.fittingSize.height, 620)
            let scroll = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSScrollView }.first)
            let document = try XCTUnwrap(scroll.documentView)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.bounds.maxY - scroll.contentView.bounds.height)))
            scroll.reflectScrolledClipView(scroll.contentView)
            XCTAssertGreaterThanOrEqual(scroll.documentVisibleRect.maxY + 1, document.bounds.maxY)
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)

            if let destination = ProcessInfo.processInfo.environment["SKILLSET_CONTROL_SCREENSHOT_DIR"],
               let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) {
                controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
                let url = URL(fileURLWithPath: destination).appendingPathComponent("mcp-form-\(appearance == .aqua ? "light" : "dark").png")
                try bitmap.representation(using: .png, properties: [:])?.write(to: url)
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("CODEX_HOME/config.toml").path))
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
