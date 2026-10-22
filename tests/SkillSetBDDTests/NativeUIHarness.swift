import AppKit
import Darwin
import Foundation
import SkillSetCore

enum NativeUIHarnessError: Error, LocalizedError {
    case executableNotFound([String])
    case applicationLaunchFailed(String)
    case applicationNotReady(pid_t)
    case windowNotFound
    case sidebarNotFound
    case searchFieldNotFound
    case elementNotFound(String)
    case accessibilityFailure(AXError, String)
    case mouseEventUnavailable
    case mouseRoutingFailed(String)
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case let .executableNotFound(candidates):
            return "找不到原生应用可执行文件：\(candidates.joined(separator: "、"))"
        case let .applicationLaunchFailed(reason):
            return "无法启动隔离的原生应用：\(reason)"
        case let .applicationNotReady(pid):
            return "原生应用进程 \(pid) 未在限定时间内提供主窗口。"
        case .windowNotFound:
            return "原生应用未提供可访问的主窗口。"
        case .sidebarNotFound:
            return "原生界面没有可访问的侧栏 outline。"
        case .searchFieldNotFound:
            return "原生界面没有可访问的搜索字段。"
        case let .elementNotFound(name):
            return "原生界面找不到可访问元素：\(name)"
        case let .accessibilityFailure(error, context):
            return "原生界面可访问性调用失败（\(error.rawValue)）：\(context)"
        case .mouseEventUnavailable:
            return "无法创建用于原生界面测试的全局鼠标事件。"
        case let .mouseRoutingFailed(reason):
            return "原生界面鼠标路由失败：\(reason)"
        case let .timeout(context):
            return "原生界面等待超时：\(context)"
        }
    }
}

struct NativeUINode {
    let element: AXUIElement
    let role: String
    let title: String
    let label: String
    let identifier: String
    let value: String
    let placeholder: String
    let enabled: Bool
}

/// LaunchServices 的回调与同步场景之间只通过锁保护的结果交接。
private final class NativeUILaunchResult: @unchecked Sendable {
    private let lock = NSLock()
    private var result: (application: NSRunningApplication?, error: Error?)?

    func complete(application: NSRunningApplication?, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        result = (application, error)
    }

    func snapshot() -> (application: NSRunningApplication?, error: Error?)? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}

/// 通过独立的原生进程和 macOS accessibility tree 驱动界面，避免测试进程自身无法暴露 AX 树。
@MainActor
final class NativeUIHarness {
    let applicationSupportRoot: URL
    private let codexConfigurationURL: URL

    static var canRunInCurrentEnvironment: Bool {
        ProcessInfo.processInfo.environment["CI"] != "true" && AXIsProcessTrusted()
    }

    static let unavailableReason =
        "原生 UI BDD 需要交互式 macOS 桌面会话和 Accessibility 权限；CI 或未授权环境会跳过该场景。"

    private let processIdentifier: pid_t
    private let application: AXUIElement
    private var isStopped = false
    private let pluginHostInvocationLogURL: URL?

    init(
        repositoryRoot: URL,
        temporaryRoot: URL,
        projectURL: URL?,
        projectName: String?,
        skillIDs: [String],
        instructionIDs: [String],
        agents: [String],
        prepareRiskyPluginFixture: Bool = false
    ) throws {
        let uiRoot = temporaryRoot.appendingPathComponent("native-ui", isDirectory: true)
        let home = uiRoot.appendingPathComponent("home", isDirectory: true)
        let codex = uiRoot.appendingPathComponent("codex", isDirectory: true)
        codexConfigurationURL = codex.appendingPathComponent("config.toml")
        applicationSupportRoot = home.appendingPathComponent(".perch", isDirectory: true)
        try FileManager.default.createDirectory(
            at: applicationSupportRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        let pluginFixture = prepareRiskyPluginFixture
            ? try Self.createRiskyPluginFixture(home: home, uiRoot: uiRoot)
            : nil
        pluginHostInvocationLogURL = pluginFixture?.logURL

        if let projectURL {
            let registration = try ProjectStore(rootURL: applicationSupportRoot).register(
                path: projectURL,
                name: projectName
            )
            try ProjectDraftStore(rootURL: applicationSupportRoot).save(
                projectID: registration.id,
                skillIDs: skillIDs,
                instructionIDs: instructionIDs,
                agents: agents
            )
        }

        let executable = try Self.locateExecutable(repositoryRoot: repositoryRoot)
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.path
        environment["CFFIXED_USER_HOME"] = home.path
        environment["SKILLSET_HOME"] = home.path
        environment["CODEX_HOME"] = codex.path
        environment["SKILLSET_REPOSITORY_ROOT"] = repositoryRoot.path
        // 夹具没有用户导入流程，显式让应用使用仓库快照，保持技能 ID 与场景一致。
        environment["SKILLSET_REPOSITORY_LIBRARY"] = "1"
        if let executable = pluginFixture?.executableURL {
            environment["SKILLSET_CLAUDE_BIN"] = executable.path
        }
        // Argument Domain 只影响该子进程，确保中文场景不受本机语言偏好影响。
        let bundle = try Self.makeApplicationBundle(executable: executable, uiRoot: uiRoot)
        let running = try Self.launchApplication(bundle: bundle, environment: environment)
        processIdentifier = running.processIdentifier
        application = AXUIElementCreateApplication(processIdentifier)
        for _ in 0..<60 {
            if try hasWindow() { break }
            pump(for: 0.1)
        }
        guard try hasWindow() else {
            stop()
            throw NativeUIHarnessError.applicationNotReady(processIdentifier)
        }
        running.activate(options: .activateAllWindows)
        try waitUntil("主窗口出现") {
            !self.nodes().filter {
                $0.role == kAXWindowRole as String
            }.isEmpty
        }
        // 主窗口先于内容树出现，提前操作会让场景误报侧栏缺失。
        try waitUntil("侧栏出现") {
            (try? self.sidebar()) != nil
        }
    }

    deinit {
        if !isStopped {
            Darwin.kill(processIdentifier, SIGTERM)
        }
    }

    func hasWindow() throws -> Bool {
        !nodes().filter {
            $0.role == kAXWindowRole as String
        }.isEmpty
    }

    func hasCodexMCPConfiguration() -> Bool {
        FileManager.default.fileExists(atPath: codexConfigurationURL.path)
    }

    func hasStaticText(_ text: String) throws -> Bool {
        nodes().contains {
            $0.role == kAXStaticTextRole as String && $0.value == text
        }
    }

    func hasStaticText(containing text: String) throws -> Bool {
        nodes().contains {
            $0.role == kAXStaticTextRole as String && $0.value.contains(text)
        }
    }

    func nonEditableTextContains(_ text: String) throws -> Bool {
        nodes().contains { node in
            guard node.role != kAXTextFieldRole as String else { return false }
            return [node.title, node.label, node.value].contains { $0.contains(text) }
        }
    }

    func hasEnabledButton(_ label: String) throws -> Bool {
        nodes().contains {
            $0.role == kAXButtonRole as String
                && $0.enabled
                && ($0.label == label || $0.title == label)
        }
    }

    func buttonIsEnabled(_ label: String) throws -> Bool {
        guard let button = nodes().first(where: {
            $0.role == kAXButtonRole as String
                && ($0.label == label || $0.title == label)
        }) else {
            throw NativeUIHarnessError.elementNotFound(label)
        }
        return button.enabled
    }

    func searchPlaceholder() throws -> String {
        try XCTUnwrapOptional(
            nodes().first { $0.role == kAXTextFieldRole as String }?.placeholder,
            .searchFieldNotFound
        )
    }

    func focusSidebar() throws {
        NSRunningApplication(processIdentifier: processIdentifier)?.activate(options: .activateAllWindows)
        pump(for: 0.15)
        let outline = try sidebar()
        let error = AXUIElementSetAttributeValue(
            outline.element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        guard error == .success else {
            throw NativeUIHarnessError.accessibilityFailure(error, "聚焦侧栏")
        }
        try waitUntil("侧栏获得键盘焦点") { try self.focusIsSidebar() }
    }

    func pressDownArrow() throws {
        try pressKey(CGKeyCode(125))
    }

    func pressCommandThree() throws {
        try pressKey(CGKeyCode(20), flags: .maskCommand)
    }

    func pressCommandTwo() throws {
        try pressKey(CGKeyCode(19), flags: .maskCommand)
    }

    func sidebarSelection() throws -> String {
        let outline = try sidebar()
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            outline.element,
            kAXSelectedRowsAttribute as CFString,
            &value
        )
        guard error == .success, let rows = value as? [AXUIElement] else {
            throw NativeUIHarnessError.accessibilityFailure(error, "读取侧栏选中项")
        }
        return rows.flatMap { row in
            collect(from: row).map(\.value).filter { !$0.isEmpty }
        }.joined(separator: " | ")
    }

    func selectSidebarItem(_ title: String) throws {
        let outline = try sidebar()
        let rows = collect(from: outline.element).filter { $0.role == kAXRowRole as String }
        guard let targetIndex = rows.firstIndex(where: {
            collect(from: $0.element).contains { $0.value == title }
        }) else {
            throw NativeUIHarnessError.elementNotFound("侧栏项 \(title)")
        }
        let current = try sidebarSelection()
        guard rows.contains(where: {
            collect(from: $0.element).contains { !$0.value.isEmpty && current.hasPrefix($0.value) }
        }) else {
            throw NativeUIHarnessError.elementNotFound("当前侧栏选中项")
        }
        try focusSidebar()
        for _ in 0..<(rows.count * 2) {
            let selection = try sidebarSelection()
            if selection.hasPrefix(title) { break }
            guard let index = rows.firstIndex(where: {
                collect(from: $0.element).contains { !$0.value.isEmpty && selection.hasPrefix($0.value) }
            }) else { throw NativeUIHarnessError.elementNotFound("当前侧栏选中项") }
            try pressKey(targetIndex > index ? CGKeyCode(125) : CGKeyCode(126))
        }
        try waitUntil("侧栏切换到 \(title)") {
            try self.sidebarSelection().hasPrefix(title)
        }
    }

    func focusIsSidebar() throws -> Bool {
        guard let focused = try applicationElement(
            kAXFocusedUIElementAttribute,
            context: "读取键盘焦点"
        ) else {
            return false
        }
        let role = stringAttribute(focused, kAXRoleAttribute)
        let description = stringAttribute(focused, kAXDescriptionAttribute)
        return [kAXOutlineRole as String, kAXTableRole as String].contains(role)
            && ["Sidebar", "侧边栏导航"].contains(description)
    }

    func pressButton(_ label: String) throws {
        guard let button = nodes().first(where: {
            $0.role == kAXButtonRole as String
                && ($0.label == label || $0.title == label)
        }) else {
            throw NativeUIHarnessError.elementNotFound(label)
        }
        let error = AXUIElementPerformAction(button.element, kAXPressAction as CFString)
        guard error == .success else {
            throw NativeUIHarnessError.accessibilityFailure(error, "点击 \(label)")
        }
    }

    func pressButton(identifier: String) throws {
        guard let button = nodes().first(where: {
            $0.role == kAXButtonRole as String && $0.identifier == identifier && $0.enabled
        }) else {
            throw NativeUIHarnessError.elementNotFound(identifier)
        }
        let error = AXUIElementPerformAction(button.element, kAXPressAction as CFString)
        guard error == .success else {
            throw NativeUIHarnessError.accessibilityFailure(error, "点击 \(identifier)")
        }
    }

    func clickDisclosureLabel(title: String, identifier: String) throws {
        try clickDisclosureTarget(title: title, identifier: identifier, whitespace: false)
    }

    func clickDisclosureWhitespace(title: String, identifier: String) throws {
        try clickDisclosureTarget(title: title, identifier: identifier, whitespace: true)
    }

    private func clickDisclosureTarget(title: String, identifier: String, whitespace: Bool) throws {
        var lastTarget = "AX 树尚未提供展开标题"
        var scrollbarRange: (lower: Double, upper: Double)?
        for _ in 0..<40 {
            let snapshot = nodes()
            guard let window = snapshot.first(where: { $0.role == kAXWindowRole as String }) else {
                throw NativeUIHarnessError.windowNotFound
            }
            let windowFrame = try frame(of: window.element)
            let detailArea = snapshot.filter { node in
                guard node.role == kAXScrollAreaRole as String,
                      let bounds = try? frame(of: node.element),
                      bounds.width > 140, bounds.height > 150 else { return false }
                return true
            }.max {
                let left = (try? frame(of: $0.element).minX) ?? 0
                let right = (try? frame(of: $1.element).minX) ?? 0
                return left < right
            }
            var scrollArea = detailArea?.element
            let detailFrame = try scrollArea.map(frame(of:)) ?? windowFrame.insetBy(dx: 20, dy: 30)
            var viewport = detailFrame.intersection(windowFrame).insetBy(dx: 2, dy: 4)
            var point: CGPoint?
            var initialHeader: CGRect?
            let disclosure = disclosureNode(title: title, identifier: identifier, in: snapshot)

            if let disclosure,
               let header = try? frame(of: disclosure.element),
               header.width > 0, header.height > 0 {
                initialHeader = header
                var rowFrame: CGRect? = header.width > 140 ? header : nil
                var ancestor = parent(of: disclosure.element)
                for _ in 0..<20 {
                    guard let element = ancestor else { break }
                    let role = stringAttribute(element, kAXRoleAttribute)
                    if let bounds = try? frame(of: element) {
                        if role == kAXScrollAreaRole as String {
                            viewport = bounds.intersection(windowFrame).insetBy(dx: 2, dy: 4)
                            scrollArea = element
                            break
                        }
                        if rowFrame == nil, bounds.width > 140 { rowFrame = bounds }
                    }
                    ancestor = parent(of: element)
                }
                if whitespace {
                    let rightEdge = min(rowFrame?.maxX ?? viewport.maxX, viewport.maxX - 40)
                    point = CGPoint(x: rightEdge - 20, y: header.midY)
                } else {
                    // 原生 representation 可能只给箭头 frame，也可能给整行 frame。
                    let titleX = header.width > 140 ? header.minX + 55
                        : header.width > 40 ? header.midX : header.maxX + 32
                    point = CGPoint(x: titleX, y: header.midY)
                }
                lastTarget = "\(disclosure.role)，标题边界 \(header)，可见区域 \(viewport)"
            }

            if var point, viewport.contains(point) {
                // 文字与右侧空白分别发送鼠标事件，避免只验证小箭头的 AXPress。
                guard let disclosure,
                      let running = NSRunningApplication(processIdentifier: processIdentifier) else {
                    throw NativeUIHarnessError.applicationNotReady(processIdentifier)
                }
                let activationRequested = running.activate(options: .activateAllWindows)
                let frontmostResult = AXUIElementSetAttributeValue(
                    application, kAXFrontmostAttribute as CFString, kCFBooleanTrue
                )
                var raiseResult: AXError?
                if actionNames(of: window.element).contains(kAXRaiseAction as String) {
                    raiseResult = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
                }
                do {
                    try waitUntil("目标 App 成为前台") {
                        NSWorkspace.shared.frontmostApplication?.processIdentifier == self.processIdentifier
                    }
                } catch {
                    throw NativeUIHarnessError.timeout(
                        "目标 App 成为前台：policy=\(running.activationPolicy.rawValue)，isActive=\(running.isActive)，"
                            + "frontmostPID=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1)，"
                            + "AXFrontmost=\(stringAttribute(application, kAXFrontmostAttribute))，"
                            + "activateRequested=\(activationRequested)，AXFrontmostResult=\(frontmostResult.rawValue)，"
                            + "AXRaiseResult=\(raiseResult?.rawValue.description ?? "未提供")"
                    )
                }
                pump(for: 0.1)
                let activeDisclosure = disclosureNode(title: title, identifier: identifier, in: nodes()) ?? disclosure
                let activeHeader = try frame(of: activeDisclosure.element)
                if let initialHeader {
                    // 激活或抬起窗口可能移动窗口，点击必须沿用激活后的全局坐标。
                    point.x += activeHeader.minX - initialHeader.minX
                    point.y += activeHeader.minY - initialHeader.minY
                }
                let before = stringAttribute(activeDisclosure.element, kAXValueAttribute)
                guard !before.isEmpty else {
                    throw NativeUIHarnessError.elementNotFound("展开标题的原生状态")
                }
                let route = try postMouseClick(at: point)
                try waitUntil("鼠标点击展开标题 \(title) 后原生状态改变（原状态 \(before)，标题 \(activeHeader)，窗口 \((try? frame(of: window.element)) ?? windowFrame)，\(route)）") {
                    guard let updated = self.disclosureNode(title: title, identifier: identifier, in: self.nodes()) else {
                        return false
                    }
                    let after = self.stringAttribute(updated.element, kAXValueAttribute)
                    return !after.isEmpty && after != before
                }
                return
            }
            guard let scrollArea else {
                throw NativeUIHarnessError.elementNotFound("技能详情的原生滚动区域")
            }
            let scrollResult = try scrollForDisclosure(
                disclosure?.element, in: scrollArea,
                upward: point.map { $0.y < viewport.minY } ?? false,
                range: &scrollbarRange
            )
            lastTarget += "；\(scrollResult)"
        }
        throw NativeUIHarnessError.timeout("将展开标题 \(title) 滚动到可点击区域：\(lastTarget)")
    }

    private func postMouseClick(at point: CGPoint) throws -> String {
        guard CGPreflightPostEventAccess() else {
            throw NativeUIHarnessError.mouseRoutingFailed("当前测试进程没有全局事件发送权限")
        }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw NativeUIHarnessError.mouseEventUnavailable
        }
        let warp = CGWarpMouseCursorPosition(point)
        guard warp == .success else {
            throw NativeUIHarnessError.mouseRoutingFailed("移动指针返回 \(warp.rawValue)")
        }
        let eventNumber = Int64(ProcessInfo.processInfo.systemUptime * 1_000)
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                     mouseCursorPosition: point, mouseButton: .left) else {
                throw NativeUIHarnessError.mouseEventUnavailable
            }
            event.flags = []
            if type != .mouseMoved {
                // CG 定义要求 1 表示单击，按下和抬起使用同一事件编号。
                event.setIntegerValueField(.mouseEventClickState, value: 1)
                event.setIntegerValueField(.mouseEventNumber, value: eventNumber)
                event.setDoubleValueField(.mouseEventPressure, value: type == .leftMouseDown ? 1 : 0)
            }
            // 由 WindowServer 按全局 AX 坐标路由，postToPid 不会完成鼠标命中测试。
            event.post(tap: .cghidEventTap)
            pump(for: 0.1)
        }
        let cursor = CGEvent(source: source)?.location ?? .zero
        return "点击点 \(point)，当前指针 \(cursor)，前台 PID \(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1)"
    }

    private func scrollForDisclosure(
        _ disclosure: AXUIElement?, in scrollArea: AXUIElement, upward: Bool,
        range: inout (lower: Double, upper: Double)?
    ) throws -> String {
        if let disclosure {
            let actions = actionNames(of: disclosure)
            if let action = actions.first(where: { $0 == "AXScrollToVisible" }) {
                let before = try? frame(of: disclosure)
                let result = AXUIElementPerformAction(disclosure, action as CFString)
                pump(for: 0.2)
                if result == .success, (try? frame(of: disclosure)) != before {
                    return "原生 ScrollToVisible 已移动标题"
                }
            }
        }

        if let bar = relatedElement(kAXVerticalScrollBarAttribute, of: scrollArea)
            ?? collect(from: scrollArea).first(where: {
                $0.role == kAXScrollBarRole as String
                    && stringAttribute($0.element, kAXOrientationAttribute) == kAXVerticalOrientationValue as String
            })?.element,
           let current = Double(stringAttribute(bar, kAXValueAttribute)),
           let minimum = Double(stringAttribute(bar, kAXMinValueAttribute)),
           let maximum = Double(stringAttribute(bar, kAXMaxValueAttribute)), maximum > minimum {
            var bounds = range ?? (lower: minimum, upper: maximum)
            if upward { bounds.upper = min(bounds.upper, current) }
            else { bounds.lower = max(bounds.lower, current) }
            range = bounds
            let next = bounds.upper - bounds.lower < 0.0001
                ? (upward ? minimum : maximum) : (bounds.lower + bounds.upper) / 2
            let result = AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, NSNumber(value: next))
            if result == .success {
                pump(for: 0.2)
                return "原生滚动条 \(current) → \(next)"
            }
        }

        let actions = actionNames(of: scrollArea)
        if let action = actions.first(where: {
            $0.localizedCaseInsensitiveContains("scroll")
                && $0.localizedCaseInsensitiveContains(upward ? "up" : "down")
        }) {
            let result = AXUIElementPerformAction(scrollArea, action as CFString)
            guard result == .success else {
                throw NativeUIHarnessError.accessibilityFailure(result, "滚动技能详情")
            }
            pump(for: 0.2)
            return "原生滚动动作 \(action)"
        }
        throw NativeUIHarnessError.elementNotFound("原生滚动条或滚动动作（\(actions.joined(separator: "、"))）")
    }

    private func actionNames(of element: AXUIElement) -> [String] {
        var value: CFArray?
        guard AXUIElementCopyActionNames(element, &value) == .success else { return [] }
        return value as? [String] ?? []
    }

    private func disclosureNode(title: String, identifier: String, in snapshot: [NativeUINode]) -> NativeUINode? {
        func matches(_ node: NativeUINode) -> Bool {
            [kAXDisclosureTriangleRole as String, kAXButtonRole as String].contains(node.role)
                && [node.title, node.label, node.value].contains(title)
        }
        if let group = snapshot.first(where: { $0.identifier == identifier }) {
            if matches(group) { return group }
            if let control = collect(from: group.element).first(where: matches) { return control }
        }
        // accessibilityRepresentation 保留原生 disclosure 角色，但可能不转发外层 identifier。
        return snapshot.first(where: matches)
    }

    func focusButton(identifier: String) throws {
        guard let button = nodes().first(where: {
            $0.role == kAXButtonRole as String && $0.identifier == identifier
        }) else {
            throw NativeUIHarnessError.elementNotFound(identifier)
        }
        let error = AXUIElementSetAttributeValue(button.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard error == .success else {
            throw NativeUIHarnessError.accessibilityFailure(error, "聚焦 \(identifier)")
        }
    }

    func setText(fieldMatching text: String, to value: String) throws {
        NSRunningApplication(processIdentifier: processIdentifier)?.activate(options: .activateAllWindows)
        try waitUntil("隔离测试窗口获得输入焦点") {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == self.processIdentifier
        }
        let fields = nodes().filter { [kAXTextFieldRole as String, kAXTextAreaRole as String].contains($0.role) }
        func labels(_ node: NativeUINode) -> [String] {
            [
                node.placeholder,
                node.title,
                node.label,
                node.identifier,
                titleUIElementText(node.element)
            ]
        }
        // 表单名称优先精确匹配，避免命中背后页面的「搜索名称或命令」。
        guard !text.isEmpty, let field = fields.first(where: { labels($0).contains(text) })
            ?? fields.first(where: { labels($0).contains { $0.contains(text) } }) else {
            throw NativeUIHarnessError.elementNotFound("文本字段 \(text)")
        }
        let focusError = AXUIElementSetAttributeValue(
            field.element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        guard focusError == .success else {
            throw NativeUIHarnessError.accessibilityFailure(focusError, "聚焦文本字段 \(text)")
        }
        pump(for: 0.1)
        // 重复编辑同一字段时，显式选中全文，避免焦点未变化时快捷键只留下局部选区。
        var range = CFRange(location: 0, length: field.value.utf16.count)
        let selected = AXValueCreate(.cfRange, &range)
        let selectionError = selected.map {
            AXUIElementSetAttributeValue(field.element, kAXSelectedTextRangeAttribute as CFString, $0)
        }
        if selectionError != .success { try pressKey(CGKeyCode(0), flags: .maskCommand) }
        typeText(value)
        try waitUntil("文本字段 \(text) 接受输入") {
            self.nodes().contains {
                [kAXTextFieldRole as String, kAXTextAreaRole as String].contains($0.role) && $0.value == value
            }
        }
    }

    func selectRadioButton(_ label: String) throws {
        guard let radio = nodes().first(where: { $0.role == kAXRadioButtonRole as String && $0.label == label }) else {
            throw NativeUIHarnessError.elementNotFound(label)
        }
        let error = AXUIElementPerformAction(radio.element, kAXPressAction as CFString)
        guard error == .success else { throw NativeUIHarnessError.accessibilityFailure(error, "选择 \(label)") }
        pump(for: 0.2)
    }

    func toggleCheckbox(containing text: String) throws {
        let checkbox = try checkboxNode(containing: text)
        let error = AXUIElementPerformAction(checkbox.element, kAXPressAction as CFString)
        guard error == .success else {
            throw NativeUIHarnessError.accessibilityFailure(error, "切换复选框 \(text)")
        }
        pump(for: 0.25)
    }

    func checkboxIsChecked(containing text: String) throws -> Bool {
        let checkbox = try checkboxNode(containing: text)
        return ["1", "true"].contains(checkbox.value.lowercased())
    }

    func previewDeploymentPlan() throws {
        try pressButton(identifier: "projects.previewChanges")
        try waitUntil("变更计划 sheet 出现") {
            try self.sheetPresent()
        }
    }

    func sheetPresent() throws -> Bool {
        nodes().contains { $0.role == kAXSheetRole as String }
    }

    func waitForNoSheet() throws {
        try waitUntil("关闭审阅窗口") { try !self.sheetPresent() }
    }

    func confirmationAlertPresent() throws -> Bool {
        nodes().contains {
            $0.role == kAXSheetRole as String && $0.label == "alert"
        }
    }

    func waitForConfirmationAlert() throws {
        try waitUntil("确认对话框出现") {
            try self.confirmationAlertPresent()
        }
    }

    func pressEscapeToDismissConfirmation() throws {
        try pressKey(CGKeyCode(53))
        try waitUntil("确认对话框关闭") {
            try !self.confirmationAlertPresent()
        }
    }

    func waitForStaticText(_ text: String) throws {
        try waitUntil("出现文案 \(text)") {
            try self.hasStaticText(text)
        }
    }

    func waitForDisclosure(_ title: String) throws {
        try waitUntil("出现展开入口 \(title)") {
            self.disclosureNode(title: title, identifier: "plan.safety", in: self.nodes()) != nil
        }
    }

    func expandDisclosure(_ title: String) throws {
        try waitForDisclosure(title)
        guard let node = disclosureNode(title: title, identifier: "plan.details", in: nodes()) else {
            throw NativeUIHarnessError.elementNotFound(title)
        }
        if ["1", "true"].contains(node.value.lowercased()) { return }
        let result = AXUIElementPerformAction(node.element, kAXPressAction as CFString)
        guard result == .success else { throw NativeUIHarnessError.accessibilityFailure(result, "展开 \(title)") }
        try waitUntil("展开 \(title)") {
            guard let updated = self.disclosureNode(title: title, identifier: "plan.details", in: self.nodes()) else { return false }
            return ["1", "true"].contains(updated.value.lowercased())
        }
    }

    func waitForStaticText(containing text: String) throws {
        try waitUntil("出现含文案 \(text) 的静态文本") {
            try self.hasStaticText(containing: text)
        }
    }

    func waitForButton(_ label: String) throws {
        try waitUntil("出现可用按钮 \(label)") {
            try self.hasEnabledButton(label)
        }
    }

    func pressEscapeToCancelPlan() throws {
        try pressKey(CGKeyCode(53))
        try waitUntil("变更计划 sheet 关闭") {
            try !self.sheetPresent()
        }
    }

    func planRecords(type: String? = nil) throws -> [StoredDeploymentPlan] {
        let records = try DeploymentPlanStore(
            rootURL: applicationSupportRoot.appendingPathComponent("plans", isDirectory: true)
        ).list()
        guard let type else { return records }
        return records.filter { $0.plan.metadata?["planType"] == type }
    }

    func waitForSinglePlan(type: String? = nil) throws -> StoredDeploymentPlan {
        var latest: StoredDeploymentPlan?
        try waitUntil("原生界面保存部署计划") {
            let plans = try self.planRecords(type: type)
            latest = plans.first
            return plans.count == 1
        }
        guard let latest else {
            throw NativeUIHarnessError.timeout("部署计划没有生成")
        }
        return latest
    }

    func pluginHostInvocationCount() throws -> Int {
        guard let pluginHostInvocationLogURL else { return 0 }
        guard FileManager.default.fileExists(atPath: pluginHostInvocationLogURL.path) else {
            return 0
        }
        return try String(contentsOf: pluginHostInvocationLogURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .count
    }

    func accessibilityDebugDescription() -> String {
        nodes().map { node in
            [
                "role=\(node.role)",
                "title=\(node.title)",
                "label=\(node.label)",
                "identifier=\(node.identifier)",
                "value=\(node.value)",
                "placeholder=\(node.placeholder)",
                "enabled=\(node.enabled)"
            ].joined(separator: " | ")
        }.joined(separator: "\n")
    }

    /// 只截取当前隔离测试进程的窗口，避免把其他应用内容带进验证产物。
    func captureWindowScreenshot(to url: URL) throws {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        guard let number = windows.first(where: {
            ($0[kCGWindowOwnerPID as String] as? Int) == Int(processIdentifier)
                && ($0[kCGWindowLayer as String] as? Int) == 0
        })?[kCGWindowNumber as String] as? Int else { return }
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(number), url.path]
        capture.standardOutput = FileHandle.nullDevice
        capture.standardError = FileHandle.nullDevice
        try capture.run()
        capture.waitUntilExit()
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        guard Darwin.kill(processIdentifier, 0) == 0 else { return }
        Darwin.kill(processIdentifier, SIGTERM)
        for _ in 0..<20 where Darwin.kill(processIdentifier, 0) == 0 {
            pump(for: 0.1)
        }
        if Darwin.kill(processIdentifier, 0) == 0 {
            Darwin.kill(processIdentifier, SIGKILL)
        }
    }

    private static func makeApplicationBundle(executable: URL, uiRoot: URL) throws -> URL {
        let manager = FileManager.default
        let bundle = uiRoot.appendingPathComponent("SkillSetNativeUI.app", isDirectory: true)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        let binaries = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        let frameworks = contents.appendingPathComponent("Frameworks", isDirectory: true)
        for directory in [binaries, resources, frameworks] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try manager.copyItem(at: executable, to: binaries.appendingPathComponent("SkillSetDesktop"))
        let products = executable.resolvingSymlinksInPath().deletingLastPathComponent()
        for name in ["SkillSet_SkillSetCore.bundle", "SkillSet_SkillSetApp.bundle"] {
            let source = products.appendingPathComponent(name, isDirectory: true)
            guard manager.fileExists(atPath: source.path) else {
                throw NativeUIHarnessError.executableNotFound([source.path])
            }
            try manager.createSymbolicLink(at: resources.appendingPathComponent(name), withDestinationURL: source)
        }
        let sparkle = products.appendingPathComponent("Sparkle.framework", isDirectory: true)
        if manager.fileExists(atPath: sparkle.path) {
            try manager.createSymbolicLink(
                at: frameworks.appendingPathComponent("Sparkle.framework"), withDestinationURL: sparkle
            )
        }
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.skillset.bdd.\(UUID().uuidString.lowercased())",
            "CFBundleExecutable": "SkillSetDesktop",
            "CFBundleName": "Skill Set Native UI",
            "CFBundlePackageType": "APPL",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "0.0.0",
            "LSMinimumSystemVersion": "14.0",
            "NSPrincipalClass": "NSApplication",
            "LSUIElement": false
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
        return bundle
    }

    private static func launchApplication(bundle: URL, environment: [String: String]) throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.environment = environment
        configuration.arguments = ["-app.language", "zh-Hans"]
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false
        let result = NativeUILaunchResult()
        NSWorkspace.shared.openApplication(at: bundle, configuration: configuration) { application, error in
            result.complete(application: application, error: error)
        }
        for _ in 0..<400 {
            if let snapshot = result.snapshot() {
                guard let application = snapshot.application else {
                    throw NativeUIHarnessError.applicationLaunchFailed(
                        snapshot.error?.localizedDescription ?? "LaunchServices 未返回应用进程"
                    )
                }
                return application
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        throw NativeUIHarnessError.applicationLaunchFailed("等待 LaunchServices 返回应用进程超时")
    }

    private static func createRiskyPluginFixture(
        home: URL,
        uiRoot: URL
    ) throws -> (executableURL: URL, logURL: URL) {
        let cache = home.appendingPathComponent(
            ".claude/plugins/cache/demo/risky/1.0.0",
            isDirectory: true
        )
        let manifestDirectory = cache.appendingPathComponent(".claude-plugin", isDirectory: true)
        try FileManager.default.createDirectory(
            at: manifestDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: cache.appendingPathComponent("hooks", isDirectory: true),
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "name": "risky",
            "version": "1.0.0",
            "hooks": "./hooks/hooks.json"
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(
                to: manifestDirectory.appendingPathComponent("plugin.json"),
                options: .atomic
            )

        let executable = uiRoot.appendingPathComponent("claude-plugin-host.sh")
        let log = uiRoot.appendingPathComponent("plugin-host-invocations.log")
        let quotedLog = log.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$*" >> '\(quotedLog)'
        exit 0
        """
        try Data(script.utf8).write(to: executable, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        try? FileManager.default.removeItem(at: log)
        return (executable, log)
    }

    private static func locateExecutable(repositoryRoot: URL) throws -> URL {
        var candidates = [
            repositoryRoot.appendingPathComponent(".build/debug/SkillSetDesktop"),
            repositoryRoot.appendingPathComponent(".build/out/Products/Debug/SkillSetDesktop")
        ]
        if let executable = Bundle.main.executableURL {
            let directory = executable.deletingLastPathComponent()
            candidates.append(directory.appendingPathComponent("SkillSetDesktop"))
            candidates.append(
                directory.deletingLastPathComponent()
                    .appendingPathComponent("SkillSetDesktop")
            )
        }
        if let match = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) {
            return match
        }
        throw NativeUIHarnessError.executableNotFound(candidates.map(\.path))
    }

    private func nodes() -> [NativeUINode] {
        collect(from: application)
    }

    private func collect(from root: AXUIElement) -> [NativeUINode] {
        var output: [NativeUINode] = []
        var queue = [root]
        var index = 0
        while index < queue.count && output.count < 20_000 {
            let element = queue[index]
            index += 1
            output.append(NativeUINode(
                element: element,
                role: stringAttribute(element, kAXRoleAttribute),
                title: stringAttribute(element, kAXTitleAttribute),
                label: stringAttribute(element, kAXDescriptionAttribute),
                identifier: stringAttribute(element, kAXIdentifierAttribute),
                value: stringAttribute(element, kAXValueAttribute),
                placeholder: stringAttribute(element, kAXPlaceholderValueAttribute),
                enabled: boolAttribute(element, kAXEnabledAttribute)
            ))
            queue.append(contentsOf: children(of: element))
        }
        return output
    }

    private func sidebar() throws -> NativeUINode {
        guard let sidebar = nodes().first(where: {
            [kAXOutlineRole as String, kAXTableRole as String].contains($0.role)
                && (["Sidebar", "侧边栏导航"].contains($0.label))
        }) else {
            throw NativeUIHarnessError.sidebarNotFound
        }
        return sidebar
    }

    private func checkboxNode(containing text: String) throws -> NativeUINode {
        guard let checkbox = nodes().first(where: { node in
            guard node.role == kAXCheckBoxRole as String else { return false }
            return [node.title, node.label, node.value].contains { $0.contains(text) }
        }) else {
            throw NativeUIHarnessError.elementNotFound("复选框 \(text)")
        }
        return checkbox
    }

    private func pressKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) throws {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        down?.postToPid(processIdentifier)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        up?.postToPid(processIdentifier)
        pump(for: 0.35)
    }

    private func typeText(_ value: String) {
        let characters = Array(value.utf16)
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
        characters.withUnsafeBufferPointer { buffer in
            down?.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }
        down?.postToPid(processIdentifier)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        up?.postToPid(processIdentifier)
        pump(for: 0.35)
    }

    private func titleUIElementText(_ element: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXTitleUIElementAttribute as CFString,
            &value
        ) == .success, let titleElement = value as! AXUIElement? else {
            return ""
        }
        return stringAttribute(titleElement, kAXValueAttribute)
    }

    private func waitUntil(_ context: String, predicate: () throws -> Bool) throws {
        for _ in 0..<50 {
            if try predicate() { return }
            pump(for: 0.1)
        }
        throw NativeUIHarnessError.timeout(context)
    }

    private func pump(for seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func applicationElement(_ attribute: String, context: String) throws -> AXUIElement? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            application,
            attribute as CFString,
            &value
        )
        if error == .noValue || error == .attributeUnsupported {
            return nil
        }
        guard error == .success else {
            throw NativeUIHarnessError.accessibilityFailure(error, context)
        }
        return value as! AXUIElement?
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &value
        ) == .success else {
            return []
        }
        return (value as? [AXUIElement]) ?? []
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        relatedElement(kAXParentAttribute, of: element)
    }

    private func relatedElement(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, attribute as CFString, &value
        ) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return ""
        }
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return ""
    }

    private func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return false
        }
        return (value as? Bool) ?? (value as? NSNumber)?.boolValue ?? false
    }

    private func frame(of element: AXUIElement) throws -> CGRect {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        let positionError = AXUIElementCopyAttributeValue(
            element, kAXPositionAttribute as CFString, &positionValue
        )
        let sizeError = AXUIElementCopyAttributeValue(
            element, kAXSizeAttribute as CFString, &sizeValue
        )
        guard positionError == .success, sizeError == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            throw NativeUIHarnessError.elementNotFound("元素的可点击边界")
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            throw NativeUIHarnessError.elementNotFound("元素的可点击边界")
        }
        return CGRect(origin: position, size: size)
    }

    private func XCTUnwrapOptional<T>(
        _ value: T?,
        _ error: NativeUIHarnessError
    ) throws -> T {
        guard let value else { throw error }
        return value
    }
}
