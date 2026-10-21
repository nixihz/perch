import AppKit
import SwiftUI
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class NavigationLayoutTests: XCTestCase {
    func testPageHeaderDoesNotInflateSplitViewMinimumHeight() async throws {
        let controller = NSHostingController(rootView:
            NavigationSplitView {
                List { Text("菜单") }
            } detail: {
                PageHeader(
                    eyebrow: "TEST",
                    title: "页面标题",
                    detail: String(repeating: "这是一段需要自动换行的页面说明。", count: 5)
                )
            }
            .frame(minWidth: 1080, minHeight: 700)
        )
        let window = makeWindow(controller, size: NSSize(width: 1080, height: 700))
        defer { window.close() }
        try await settle(controller.view)

        let sidebar = try sidebarTable(in: controller.view)
        assertInsideWindow(try XCTUnwrap(sidebar.enclosingScrollView), window: window, context: "独立标题组件")
        XCTAssertLessThanOrEqual(controller.view.fittingSize.height, 700)
    }

    func testAllDestinationsKeepSidebarStableAndContentScrollable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let variables = ["CFFIXED_USER_HOME", "SKILLSET_HOME", "CODEX_HOME"]
        let saved = ProcessInfo.processInfo.environment
        // 宿主观察会随页面切换自动触发，测试必须让这些读取也落在隔离目录。
        for variable in variables {
            setenv(variable, root.appendingPathComponent(variable).path, 1)
        }
        defer {
            for variable in variables {
                if let value = saved[variable] { setenv(variable, value, 1) }
                else { unsetenv(variable) }
            }
            try? FileManager.default.removeItem(at: root)
        }
        let codex = root.appendingPathComponent("CODEX_HOME")
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        let configuration = (0..<24).map {
            "[mcp_servers.fixture\($0)]\ncommand = \"/usr/bin/true\"\n"
        }.joined(separator: "\n")
        try configuration.write(to: codex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        for index in 0..<24 {
            let manifest = root.appendingPathComponent("SKILLSET_HOME/.claude/plugins/cache/fixture/plugin\(index)/1/.claude-plugin")
            try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: true)
            try "{\"name\":\"fixture\(index)\",\"version\":\"1.0.0\"}".write(
                to: manifest.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8
            )
        }
        let model = AppModel(runtimePaths: SkillSetRuntimePaths(applicationSupportRoot: root, repositoryRoot: nil))
        XCTAssertEqual(model.mcpServers.count, 24)
        XCTAssertEqual(model.plugins.count, 24)
        let controller = NSHostingController(rootView: ContentView(model: model))
        let window = makeWindow(controller, size: NSSize(width: 1080, height: 700))
        defer { window.close() }

        let sizes = [NSSize(width: 1080, height: 700), NSSize(width: 1280, height: 820), NSSize(width: 1600, height: 1000)]
        let configurations = [NSAppearance.Name.aqua, .darkAqua].flatMap { appearance in
            sizes.map { (appearance, $0) }
        }
        for (appearance, size) in configurations {
            window.appearance = NSAppearance(named: appearance)
            window.setContentSize(size)
            var anchor: NSRect?
            for section in NavigationItem.allCases + NavigationItem.allCases.reversed() {
                model.section = section
                try await settle(controller.view)
                let context = "\(section.rawValue) @ \(size) / \(appearance.rawValue)"
                let table = try sidebarTable(in: controller.view)
                let sidebar = try XCTUnwrap(table.enclosingScrollView)
                assertInsideWindow(sidebar, window: window, context: context)
                let firstRow = table.convert(table.rect(ofRow: 1), to: window.contentView)
                if let anchor {
                    XCTAssertEqual(firstRow.minY, anchor.minY, accuracy: 1, "\(context) 菜单行发生位移")
                } else {
                    anchor = firstRow
                }
                XCTAssertLessThanOrEqual(controller.view.fittingSize.height, size.height + 1, context)
                let scrollViews = descendants(of: controller.view).compactMap { $0 as? NSScrollView }.filter { $0 !== sidebar }
                XCTAssertFalse(scrollViews.isEmpty, "\(context) 缺少详情滚动入口")
                for scroll in scrollViews {
                    assertInsideWindow(scroll, window: window, context: context)
                }
                if [.skills, .mcp, .plugins, .sources].contains(section) {
                    let ordered = scrollViews.sorted {
                        $0.convert($0.bounds, to: window.contentView).minX
                            < $1.convert($1.bounds, to: window.contentView).minX
                    }
                    let list = try XCTUnwrap(ordered.first)
                    let detail = try XCTUnwrap(ordered.last)
                    let listRect = list.convert(list.bounds, to: window.contentView)
                    let detailRect = detail.convert(detail.bounds, to: window.contentView)
                    let sidebarRect = sidebar.convert(sidebar.bounds, to: window.contentView)
                    // 检查真实滚动区域，避免只验证常量却漏掉页面自己的尺寸覆盖。
                    XCTAssertEqual(listRect.width, 280, accuracy: 1, "\(context) 列表卡片应为 320pt，扣除两侧各 20pt 内边距")
                    XCTAssertEqual(listRect.minX - sidebarRect.maxX, 48, accuracy: 2, "\(context) 列表左侧应对齐页面边距")
                    XCTAssertEqual(detailRect.minX - listRect.maxX, 38, accuracy: 1, "\(context) 详情应紧邻统一列表栏")
                    XCTAssertEqual(detailRect.maxX, controller.view.bounds.maxX - 28, accuracy: 1, "\(context) 详情未占满剩余宽度")
                }
                if section == .skills || section == .mcp || section == .plugins {
                    let overflow = scrollViews.filter { scroll in
                        guard let document = scroll.documentView else { return false }
                        return document.bounds.height > scroll.contentView.bounds.height + 10
                    }
                    XCTAssertFalse(overflow.isEmpty, "\(context) 长列表没有进入滚动容器")
                    for scroll in overflow {
                        let document = try XCTUnwrap(scroll.documentView)
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: document.bounds.maxY - scroll.contentView.bounds.height))
                        scroll.reflectScrolledClipView(scroll.contentView)
                        XCTAssertEqual(scroll.documentVisibleRect.maxY, document.bounds.maxY, accuracy: 1, "\(context) 末尾不可达")
                    }
                }
            }
        }
    }

    private func makeWindow<V: View>(_ controller: NSHostingController<V>, size: NSSize) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        controller.view.frame = NSRect(origin: .zero, size: size)
        window.contentViewController = controller
        window.isReleasedWhenClosed = false
        return window
    }

    private func settle(_ view: NSView) async throws {
        try await Task.sleep(for: .milliseconds(80))
        view.layoutSubtreeIfNeeded()
    }

    private func sidebarTable(in view: NSView) throws -> NSTableView {
        try XCTUnwrap(descendants(of: view).compactMap { $0 as? NSTableView }.first, "没有原生侧栏")
    }

    private func assertInsideWindow(_ view: NSView, window: NSWindow, context: String, file: StaticString = #filePath, line: UInt = #line) {
        let content = window.contentView!
        let rect = view.convert(view.bounds, to: content)
        XCTAssertGreaterThanOrEqual(rect.minY, content.bounds.minY - 1, "\(context) 下沿越界：\(rect)", file: file, line: line)
        XCTAssertLessThanOrEqual(rect.maxY, content.bounds.maxY + 1, "\(context) 上沿越界：\(rect)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(rect.minX, content.bounds.minX - 1, "\(context) 左沿越界：\(rect)", file: file, line: line)
        XCTAssertLessThanOrEqual(rect.maxX, content.bounds.maxX + 1, "\(context) 右沿越界：\(rect)", file: file, line: line)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
