import AppKit
import SwiftUI
import XCTest
@testable import SkillSetApp

@MainActor
final class ButtonInteractionTests: XCTestCase {
    func testMouseClickTriggersStyledButtonOnceAndDisabledButtonNeverTriggers() async throws {
        for kind in [AppButtonKind.primary, .secondary, .quiet] {
            var count = 0
            let controller = NSHostingController(rootView:
                Button("操作") { count += 1 }
                    .buttonStyle(AppButtonStyle(kind: kind))
                    .disabled(false)
                    .frame(width: 220, height: 60)
            )
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 220, height: 60),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = controller
            window.makeKeyAndOrderFront(nil)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(100))
            controller.view.layoutSubtreeIfNeeded()
            try click(window: window, point: NSPoint(x: 110, y: 30))
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(count, 1, "鼠标按下再松开必须恰好执行一次：\(kind)")
            controller.rootView = Button("操作") { count += 1 }
                .buttonStyle(AppButtonStyle(kind: kind))
                .disabled(true)
                .frame(width: 220, height: 60)
            try await Task.sleep(for: .milliseconds(100))
            try click(window: window, point: NSPoint(x: 110, y: 30))
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(count, 1, "禁用后鼠标点击不能执行动作：\(kind)")
        }
    }

    private func click(window: NSWindow, point: NSPoint) throws {
        let timestamp = ProcessInfo.processInfo.systemUptime
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
            modifierFlags: [], timestamp: timestamp, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point,
            modifierFlags: [], timestamp: timestamp + 0.05, windowNumber: window.windowNumber,
            context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
        // 仅向测试窗口发送事件，不向系统鼠标或用户正在操作的应用注入输入。
        NSApp.postEvent(up, atStart: true)
        window.sendEvent(down)
        while let event = NSApp.nextEvent(matching: [.leftMouseUp], until: .distantPast, inMode: .default, dequeue: true) {
            window.sendEvent(event)
        }
    }
}
