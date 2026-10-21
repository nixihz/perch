import AppKit
import SwiftUI
import XCTest
@testable import SkillSetApp

@MainActor
final class SidebarSelectionTests: XCTestCase {
    func testNativeKeyboardSelectionSkipsHeadingsAndUpdatesBinding() async throws {
        var selected = NavigationItem.plugins
        let binding = Binding(get: { selected }, set: { selected = $0 })
        let controller = NSHostingController(rootView: SidebarList(selection: binding, skillCount: 150))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentViewController = controller
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(80))
        controller.view.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(findTable(in: controller.view))
        XCTAssertEqual(table.selectedRow, 4)
        XCTAssertNotNil(
            table.rowView(atRow: table.selectedRow, makeIfNecessary: true) as? SidebarSelectionRow,
            "实际侧栏必须接入品牌选中态，而非只单独测试绘制类"
        )
        let rowFrame = table.rect(ofRow: table.selectedRow)
        let bitmap = try XCTUnwrap(table.bitmapImageRepForCachingDisplay(in: rowFrame))
        table.cacheDisplay(in: rowFrame, to: bitmap)
        let selectionPixel = try XCTUnwrap(bitmap.colorAt(
            x: bitmap.pixelsWide - 12,
            y: bitmap.pixelsHigh / 2
        )?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(
            selectionPixel.redComponent, selectionPixel.blueComponent + 0.2,
            "真实窗口的表格合成结果不能被系统蓝色高亮覆盖"
        )
        window.makeFirstResponder(table)
        let down = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}",
            isARepeat: false, keyCode: 125
        ))
        table.keyDown(with: down)
        XCTAssertEqual(selected, .sources, "上下键必须跳过治理分组标题")
        XCTAssertEqual(table.selectedRow, 6)

        selected = .aiAccess
        controller.rootView = SidebarList(selection: binding, skillCount: 151)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(table.selectedRow, 10, "菜单快捷键改变绑定时，原生侧栏必须同步")
        let skillCell = try XCTUnwrap(table.view(atColumn: 0, row: 2, makeIfNecessary: true) as? SidebarDestinationCell)
        XCTAssertEqual(skillCell.subtitleLabel.stringValue, AppPreferences.shared.language.resolved() == .english ? "151 source-tracked records" : "151 条来源化记录")

        selected = .settings
        controller.rootView = SidebarList(selection: binding, skillCount: 152)
        try await Task.sleep(for: .milliseconds(80))
        let settingsTable = try XCTUnwrap(findTable(in: controller.view))
        XCTAssertEqual(settingsTable.selectedRow, -1, "设置位于固定底部入口，不应同时高亮旧页面")
        XCTAssertEqual(selected, .settings)
        selected = .projects
        controller.rootView = SidebarList(selection: binding, skillCount: 153)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(try XCTUnwrap(findTable(in: controller.view)).selectedRow, 1, "离开设置后应恢复工作区选择")
    }

    func testSelectionDrawsTerracottaInBothAppearancesEvenWhenUnfocused() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            for emphasized in [true, false] {
                let row = SidebarSelectionRow(frame: NSRect(x: 0, y: 0, width: 240, height: 52))
                row.appearance = NSAppearance(named: name)
                row.selectionHighlightStyle = .regular
                row.isSelected = true
                row.isEmphasized = emphasized
                let bitmap = try XCTUnwrap(row.bitmapImageRepForCachingDisplay(in: row.bounds))
                row.cacheDisplay(in: row.bounds, to: bitmap)
                let pixel = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
                XCTAssertGreaterThan(pixel.redComponent, pixel.greenComponent + 0.15, "\(name) 选中底色必须为陶土红")
                XCTAssertGreaterThan(pixel.redComponent, pixel.blueComponent + 0.2, "失焦后也不能回退成系统蓝或灰色")
            }
        }
    }

    private func findTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { self.findTable(in: $0) }.first
    }
}
