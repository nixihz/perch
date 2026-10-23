import AppKit
import XCTest
@testable import SkillSetApp

@MainActor
final class MainWindowLifecycleTests: XCTestCase {
    func testDockReopenRoutesToMainSceneWithAndWithoutVisibleWindows() {
        let delegate = MainWindowAppDelegate()
        var requests = 0
        delegate.openMainWindow = { requests += 1 }

        XCTAssertFalse(delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: false))
        XCTAssertEqual(requests, 1, "关闭全部窗口后，Dock 重开必须请求主场景")
        XCTAssertFalse(delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: true))
        XCTAssertEqual(requests, 2, "其他窗口可见时仍需请求主窗口，且交由单一场景避免重复")
    }

    func testReopenBeforeSceneRegistrationFallsBackToSystem() {
        let delegate = MainWindowAppDelegate()
        XCTAssertTrue(delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: false),
                      "场景尚未注册时不能吞掉系统重开事件")
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(.shared),
                       "关闭最后一个窗口应保留进程和内存中的草稿")
    }
}
