import AppKit
import SwiftUI
import XCTest
@testable import SkillSetApp

@MainActor
final class ControlHitTargetTests: XCTestCase {
    func testButtonPaddingRespondsOnceAndDisabledButtonIgnoresIt() async throws {
        for kind in [AppButtonKind.primary, .secondary, .quiet] {
            var actions = 0
            let controller = NSHostingController(rootView:
                Button { actions += 1 } label: { Text("操作").frame(maxWidth: .infinity) }
                    .buttonStyle(AppButtonStyle(kind: kind))
                    .frame(width: 200)
                    .frame(width: 240, height: 80)
            )
            let window = makeWindow(controller)
            defer { window.close() }
            try await settle(controller.view)
            let points = [NSPoint(x: 120, y: 27), NSPoint(x: 120, y: 53),
                          NSPoint(x: 24, y: 40), NSPoint(x: 216, y: 40)]
            for (index, point) in points.enumerated() {
                try click(window, at: point)
                try await settle(controller.view)
                XCTAssertEqual(actions, index + 1, "按钮留白必须可点击且只执行一次：\(kind)，\(point)")
            }
            try click(window, at: NSPoint(x: 120, y: 20))
            XCTAssertEqual(actions, 4, "按钮外不能误触")
            let disabled = NSHostingController(rootView:
                Button { actions += 1 } label: { Text("操作").frame(maxWidth: .infinity) }
                    .buttonStyle(AppButtonStyle(kind: kind)).disabled(true)
                    .frame(width: 200).frame(width: 240, height: 80)
            )
            window.contentViewController = disabled
            try await settle(disabled.view)
            try click(window, at: points[0])
            XCTAssertEqual(actions, 4)
        }
    }

    func testCheckboxAndSegmentsRespondAboveAndBelowTheirGlyphs() async throws {
        var selected = false
        var changes = 0
        let checkbox = NSHostingController(rootView:
            Toggle("选择", isOn: Binding(get: { selected }, set: { selected = $0; changes += 1 }))
                .toggleStyle(AppCheckboxStyle(showsLabel: false))
                .frame(width: 240, height: 80)
        )
        let window = makeWindow(checkbox)
        defer { window.close() }
        try await settle(checkbox.view)
        try click(window, at: NSPoint(x: 108, y: 40))
        try await settle(checkbox.view)
        XCTAssertTrue(selected)
        XCTAssertEqual(changes, 1)
        try click(window, at: NSPoint(x: 120, y: 27))
        try await settle(checkbox.view)
        XCTAssertFalse(selected)
        XCTAssertEqual(changes, 2)

        var selection = 0
        let segments = NSHostingController(rootView:
            AppSegmentedPicker(title: "资源类型", selection: Binding(get: { selection }, set: { selection = $0 }),
                options: [(0, "技能"), (1, "片段")])
                .frame(width: 200).frame(width: 240, height: 80)
        )
        window.contentViewController = segments
        try await settle(segments.view)
        try click(window, at: NSPoint(x: 170, y: 27))
        try await settle(segments.view)
        XCTAssertEqual(selection, 1)
        XCTAssertTrue(window.firstResponder is NSSegmentedControl, "点击后键盘焦点仍交给原生分段")
        let left = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: "\u{F702}", charactersIgnoringModifiers: "\u{F702}", isARepeat: false, keyCode: 123))
        window.sendEvent(left)
        try await settle(segments.view)
        XCTAssertEqual(selection, 0, "左右键仍应切换原生分段并更新选择")
        try click(window, at: NSPoint(x: 170, y: 40))
        try await settle(segments.view)
        XCTAssertEqual(selection, 1)
        try click(window, at: NSPoint(x: 70, y: 53))
        try await settle(segments.view)
        XCTAssertEqual(selection, 0)
    }

    func testMenuTriggerFillsItsVisibleControlAndTextFieldPaddingFocusesInput() async throws {
        let menu = NSHostingController(rootView:
            AppPicker(title: "选择工具", selection: .constant(0), valueLabel: "Codex", showsLabel: false) {
                Text("Codex").tag(0)
                Text("Claude Code").tag(1)
            }.frame(width: 200).frame(width: 240, height: 80)
        )
        let window = makeWindow(menu)
        defer { window.close() }
        try await settle(menu.view)
        let observer = MenuTrackingObserver()
        NotificationCenter.default.addObserver(observer, selector: #selector(MenuTrackingObserver.menuBegan(_:)),
            name: NSMenu.didBeginTrackingNotification, object: nil)
        defer { NotificationCenter.default.removeObserver(observer) }
        for (index, point) in [NSPoint(x: 24, y: 40), NSPoint(x: 216, y: 40),
                               NSPoint(x: 120, y: 27), NSPoint(x: 120, y: 53)].enumerated() {
            try click(window, at: point)
            try await settle(menu.view)
            XCTAssertEqual(observer.openings, index + 1, "菜单留白必须能打开原生选项：\(point)")
        }

        let field = NSHostingController(rootView:
            TextField("名称", text: .constant(""))
                .textFieldStyle(AppTextFieldStyle())
                .frame(width: 200).frame(width: 240, height: 80)
        )
        window.contentViewController = field
        try await settle(field.view)
        try click(window, at: NSPoint(x: 24, y: 40))
        try await settle(field.view)
        XCTAssertTrue(window.firstResponder is NSTextView, "输入框左侧留白必须聚焦编辑器")
        window.makeFirstResponder(nil)
        try click(window, at: NSPoint(x: 120, y: 27))
        try await settle(field.view)
        XCTAssertTrue(window.firstResponder is NSTextView, "输入框底部留白必须聚焦编辑器")
    }

    func testSearchClearButtonRespondsAtBottomEdgeAndPreservesFocus() async throws {
        var query = "数据库"
        let controller = NSHostingController(rootView:
            AppSearchField(query: Binding(get: { query }, set: { query = $0 }),
                prompt: "搜索", label: "搜索技能", identifier: "test.search")
                .frame(width: 200).frame(width: 240, height: 80)
        )
        let window = makeWindow(controller)
        defer { window.close() }
        try await settle(controller.view)
        try click(window, at: NSPoint(x: 198, y: 27))
        try await settle(controller.view)
        XCTAssertEqual(query, "")
        XCTAssertTrue(window.firstResponder is NSTextView, "清空后应继续输入搜索词")
    }

    private func makeWindow<V: View>(_ controller: NSHostingController<V>) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func settle(_ view: NSView) async throws {
        try await Task.sleep(for: .milliseconds(80))
        view.layoutSubtreeIfNeeded()
    }

    private func click(_ window: NSWindow, at point: NSPoint) throws {
        let timestamp = ProcessInfo.processInfo.systemUptime
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
            modifierFlags: [], timestamp: timestamp, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point,
            modifierFlags: [], timestamp: timestamp + 0.05, windowNumber: window.windowNumber,
            context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
        // 只向测试窗口派发事件，避免影响系统鼠标及用户应用。
        NSApp.postEvent(up, atStart: true)
        window.sendEvent(down)
        while let event = NSApp.nextEvent(matching: [.leftMouseUp], until: .distantPast, inMode: .default, dequeue: true) {
            window.sendEvent(event)
        }
    }
}

@MainActor
private final class MenuTrackingObserver: NSObject {
    var openings = 0

    @objc func menuBegan(_ notification: Notification) {
        openings += 1
        // 菜单通知在主线程同步发出；下一轮菜单事件循环关闭，避免测试阻塞等待人工选择。
        (notification.object as? NSMenu)?.perform(#selector(NSMenu.cancelTrackingWithoutAnimation),
            with: nil, afterDelay: 0, inModes: [.eventTracking, .default])
    }
}
