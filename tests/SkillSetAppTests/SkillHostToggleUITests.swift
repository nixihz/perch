import AppKit
import SwiftUI
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class SkillHostToggleUITests: XCTestCase {
    func testMouseClicksChangeOnlyTheChosenHostAndClickingAgainTurnsItOff() async throws {
        let state = HostToggleState()
        let controller = NSHostingController(rootView: HostToggleFixture(state: state))
        let window = makeWindow(controller, size: NSSize(width: 120, height: 60))
        defer { window.close() }
        try await settle(controller.view)

        try click(window: window, point: NSPoint(x: 39, y: 30))
        try await settle(controller.view)
        XCTAssertEqual(state.selected, [.codex])
        XCTAssertEqual(state.changes.count, 1, "一次按下和松开只能保存一次草稿")
        XCTAssertEqual(state.changes.last?.host, .codex)
        XCTAssertEqual(state.changes.last?.enabled, true)

        try click(window: window, point: NSPoint(x: 81, y: 30))
        try await settle(controller.view)
        XCTAssertEqual(state.selected, [.codex, .claudeCode], "开启 Claude 不能取消 Codex")
        XCTAssertEqual(state.changes.count, 2)
        XCTAssertEqual(state.changes.last?.host, .claudeCode)

        try click(window: window, point: NSPoint(x: 39, y: 30))
        try await settle(controller.view)
        XCTAssertEqual(state.selected, [.claudeCode], "再次点击 Codex 只关闭 Codex")
        XCTAssertEqual(state.changes.count, 3)
        XCTAssertEqual(state.changes.last?.enabled, false)

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            try await settle(controller.view)
            try capture(controller.view, name: "buttons-\(appearance == .aqua ? "light" : "dark")")
        }
    }

    func testBlockedSkillCannotBeEnabledButExistingSelectionCanBeTurnedOff() async throws {
        let state = HostToggleState(selected: [.codex], blocked: true)
        let controller = NSHostingController(rootView: HostToggleFixture(state: state))
        let window = makeWindow(controller, size: NSSize(width: 120, height: 60))
        defer { window.close() }
        try await settle(controller.view)

        try click(window: window, point: NSPoint(x: 81, y: 30))
        try await settle(controller.view)
        XCTAssertEqual(state.selected, [.codex])
        XCTAssertTrue(state.changes.isEmpty, "阻塞且未选的 Claude 按钮不能调用保存动作")

        try click(window: window, point: NSPoint(x: 39, y: 30))
        try await settle(controller.view)
        XCTAssertTrue(state.selected.isEmpty, "完整性阻塞不能阻止用户关闭已有选择")
        XCTAssertEqual(state.changes.count, 1)
        XCTAssertEqual(state.changes.last?.host, .codex)
        XCTAssertEqual(state.changes.last?.enabled, false)

        try click(window: window, point: NSPoint(x: 39, y: 30))
        try await settle(controller.view)
        XCTAssertTrue(state.selected.isEmpty)
        XCTAssertEqual(state.changes.count, 1, "关闭后变为禁用，不能再次开启阻塞技能")
    }

    func testLongSkillNamesKeepProjectAndGlobalPagesInsideMinimumWindow() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("perch-host-toggle-\(UUID())")
        let home = root.appendingPathComponent("home")
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let variables = ["CFFIXED_USER_HOME", "SKILLSET_HOME", "CODEX_HOME", "CLAUDE_CONFIG_DIR"]
        let saved = ProcessInfo.processInfo.environment
        // 页面会自动观察宿主配置；所有观察与草稿保存均指向临时目录。
        for key in variables { setenv(key, root.appendingPathComponent(key).path, 1) }
        defer {
            for key in variables {
                if let value = saved[key] { setenv(key, value, 1) } else { unsetenv(key) }
            }
            try? FileManager.default.removeItem(at: root)
        }
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let locations = GlobalConfigurationLocations(home: home, stateRoot: paths.applicationSupportRoot)
        let slug = "long-skill-name-with-many-segments-that-must-leave-both-host-buttons-accessible"
        let description = String(repeating: "长说明需要换行，右侧两个工具的开关仍须保留。", count: 4)
        let skill = try paths.makeLibraryStore(home: home).save(SkillEditorDraft(
            slug: slug,
            document: "---\nname: \(slug)\ndescription: \(description)\n---\n测试技能正文。\n"
        ), repositoryRoot: nil)
        let model = AppModel(runtimePaths: paths, globalLocations: locations)
        XCTAssertTrue(model.registerProject(project, name: "长名称技能测试"))
        model.setSkill(skill, enabled: true, host: .codex)
        model.globalConfiguration.refresh()
        model.globalConfiguration.setSkill(skill.id, enabled: true, host: .claudeCode)
        let controller = NSHostingController(rootView: ContentView(model: model))
        let size = NSSize(width: 1080, height: 700)
        let window = makeWindow(controller, size: size)
        defer { window.close() }

        for section in [NavigationItem.projects, .globalConfiguration] {
            model.section = section
            let page = section == .projects ? "projects" : "global"
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: appearance)
                try await settle(controller.view)
                XCTAssertLessThanOrEqual(controller.view.fittingSize.width, size.width + 1, "\(page) 横向撑大窗口")
                XCTAssertLessThanOrEqual(controller.view.fittingSize.height, size.height + 1, "\(page) 纵向撑大窗口")
                let scrolls = descendants(controller.view).compactMap { $0 as? NSScrollView }
                XCTAssertFalse(scrolls.isEmpty)
                for scroll in scrolls {
                    let frame = scroll.convert(scroll.bounds, to: controller.view)
                    XCTAssertGreaterThanOrEqual(frame.minX, -1, "\(page) 左边界溢出")
                    XCTAssertLessThanOrEqual(frame.maxX, size.width + 1, "\(page) 右边界溢出")
                    if let document = scroll.documentView {
                        XCTAssertLessThanOrEqual(document.bounds.width, scroll.contentView.bounds.width + 1,
                            "\(page) 长技能名称造成横向滚动或裁剪")
                    }
                }
                // 技能选择位于页面中段；滚动截图同时保留卡片与真实技能行。
                if let pageScroll = scrolls.filter({ !($0.documentView is NSTableView) })
                    .max(by: { $0.bounds.width < $1.bounds.width }), let document = pageScroll.documentView {
                    let offset = min(620, max(0, document.bounds.height - pageScroll.contentView.bounds.height))
                    pageScroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
                    pageScroll.reflectScrolledClipView(pageScroll.contentView)
                    try await settle(controller.view)
                    try capture(controller.view, name: "\(page)-\(appearance == .aqua ? "light" : "dark")")
                    pageScroll.contentView.scroll(to: .zero)
                    pageScroll.reflectScrolledClipView(pageScroll.contentView)
                }
            }
        }
        XCTAssertTrue(try DeploymentPlanStore(rootURL: paths.plansRoot).list().isEmpty,
            "渲染页面和选择草稿不能生成部署计划")
        for path in [project.appendingPathComponent(".agents"), project.appendingPathComponent(".claude"),
                     locations.skillsRoot(.codex), locations.skillsRoot(.claudeCode)] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: path.path), "布局验收不能写入技能目标目录")
        }
    }

    private func makeWindow<V: View>(_ controller: NSHostingController<V>, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        controller.view.frame = NSRect(origin: .zero, size: size)
        window.contentViewController = controller
        window.setContentSize(size)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func settle(_ view: NSView) async throws {
        try await Task.sleep(for: .milliseconds(100))
        view.layoutSubtreeIfNeeded()
    }

    private func click(window: NSWindow, point: NSPoint) throws {
        let timestamp = ProcessInfo.processInfo.systemUptime
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
            modifierFlags: [], timestamp: timestamp, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point,
            modifierFlags: [], timestamp: timestamp + 0.05, windowNumber: window.windowNumber,
            context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
        // 只向测试窗口发送事件，不移动系统鼠标或操作用户应用。
        NSApp.postEvent(up, atStart: true)
        window.sendEvent(down)
        while let event = NSApp.nextEvent(matching: [.leftMouseUp], until: .distantPast,
            inMode: .default, dequeue: true) {
            window.sendEvent(event)
        }
    }

    private func capture(_ view: NSView, name: String) throws {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/tmp/perch-skill-host-\(name).png"))
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}

@MainActor
private final class HostToggleState: ObservableObject {
    @Published var selected: Set<MCPHost>
    let blocked: Bool
    var changes: [(host: MCPHost, enabled: Bool)] = []

    init(selected: Set<MCPHost> = [], blocked: Bool = false) {
        self.selected = selected
        self.blocked = blocked
    }

    func setSelected(_ host: MCPHost, enabled: Bool) {
        changes.append((host, enabled))
        if enabled { selected.insert(host) } else { selected.remove(host) }
    }
}

private struct HostToggleFixture: View {
    @ObservedObject var state: HostToggleState

    var body: some View {
        SkillHostToggles(
            skillName: "UI 行为测试技能",
            identifierPrefix: "test.skill",
            isSelected: { state.selected.contains($0) },
            isEnabled: { !state.blocked || state.selected.contains($0) },
            setSelected: { state.setSelected($0, enabled: $1) }
        )
        .frame(width: 120, height: 60)
        .background(AppColor.surface)
    }
}
