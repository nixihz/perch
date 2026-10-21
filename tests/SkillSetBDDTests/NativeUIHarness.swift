import AppKit
import Darwin
import Foundation
import SkillSetCore

enum NativeUIHarnessError: Error, LocalizedError {
    case executableNotFound([String])
    case applicationNotReady(pid_t)
    case windowNotFound
    case sidebarNotFound
    case searchFieldNotFound
    case elementNotFound(String)
    case accessibilityFailure(AXError, String)
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case let .executableNotFound(candidates):
            return "找不到原生应用可执行文件：\(candidates.joined(separator: "、"))"
        case let .applicationNotReady(pid):
            return "原生应用进程 \(pid) 未在限定时间内提供主窗口。"
        case .windowNotFound:
            return "原生应用未提供标题为 Skill Set 的窗口。"
        case .sidebarNotFound:
            return "原生界面没有可访问的侧栏 outline。"
        case .searchFieldNotFound:
            return "原生界面没有可访问的搜索字段。"
        case let .elementNotFound(name):
            return "原生界面找不到可访问元素：\(name)"
        case let .accessibilityFailure(error, context):
            return "原生界面可访问性调用失败（\(error.rawValue)）：\(context)"
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

/// 通过独立的原生进程和 macOS accessibility tree 驱动界面，避免测试进程自身无法暴露 AX 树。
@MainActor
final class NativeUIHarness {
    let applicationSupportRoot: URL

    static var canRunInCurrentEnvironment: Bool {
        ProcessInfo.processInfo.environment["CI"] != "true" && AXIsProcessTrusted()
    }

    static let unavailableReason =
        "原生 UI BDD 需要交互式 macOS 桌面会话和 Accessibility 权限；CI 或未授权环境会跳过该场景。"

    private let process: Process
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
        applicationSupportRoot = home.appendingPathComponent(
            "Library/Application Support/Skill Set",
            isDirectory: true
        )
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
        let child = Process()
        child.executableURL = executable
        child.currentDirectoryURL = repositoryRoot
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.path
        environment["CFFIXED_USER_HOME"] = home.path
        environment["SKILLSET_HOME"] = home.path
        environment["CODEX_HOME"] = codex.path
        environment["SKILLSET_REPOSITORY_ROOT"] = repositoryRoot.path
        if let executable = pluginFixture?.executableURL {
            environment["SKILLSET_CLAUDE_BIN"] = executable.path
        }
        child.environment = environment
        // Argument Domain 只影响该子进程，确保中文场景不受本机语言偏好影响。
        child.arguments = ["-app.language", "zh-Hans"]
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice

        do {
            try child.run()
        } catch {
            throw NativeUIHarnessError.executableNotFound([executable.path])
        }
        process = child
        application = AXUIElementCreateApplication(child.processIdentifier)
        for _ in 0..<60 {
            if try hasWindow() { break }
            pump(for: 0.1)
        }
        guard try hasWindow() else {
            stop()
            throw NativeUIHarnessError.applicationNotReady(child.processIdentifier)
        }
        NSRunningApplication(processIdentifier: child.processIdentifier)?.activate(options: [])
        try waitUntil("主窗口出现") {
            !self.nodes().filter {
                $0.role == kAXWindowRole as String && $0.title == "Skill Set"
            }.isEmpty
        }
        // 主窗口先于内容树出现，提前操作会让场景误报侧栏缺失。
        try waitUntil("侧栏出现") {
            (try? self.sidebar()) != nil
        }
    }

    deinit {
        if !isStopped {
            process.terminate()
        }
    }

    func hasWindow() throws -> Bool {
        !nodes().filter {
            $0.role == kAXWindowRole as String && $0.title == "Skill Set"
        }.isEmpty
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
        let outline = try sidebar()
        let error = AXUIElementSetAttributeValue(
            outline.element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        guard error == .success else {
            throw NativeUIHarnessError.accessibilityFailure(error, "聚焦侧栏")
        }
    }

    func pressDownArrow() throws {
        try pressKey(CGKeyCode(125))
    }

    func pressCommandThree() throws {
        try pressKey(CGKeyCode(20), flags: .maskCommand)
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
        let order = ["项目", "技能库", "MCP 服务", "插件", "来源", "预设", "指令模板", "AI 接入"]
        guard let targetIndex = order.firstIndex(of: title) else {
            throw NativeUIHarnessError.elementNotFound("侧栏项 \(title)")
        }
        let current = try sidebarSelection()
        guard let currentIndex = order.firstIndex(where: { current.hasPrefix($0) }) else {
            throw NativeUIHarnessError.elementNotFound("当前侧栏选中项")
        }
        try focusSidebar()
        let keyCode = targetIndex > currentIndex ? CGKeyCode(125) : CGKeyCode(126)
        for _ in 0..<abs(targetIndex - currentIndex) {
            try pressKey(keyCode)
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

    func setText(fieldMatching text: String, to value: String) throws {
        guard let field = nodes().first(where: { node in
            guard node.role == kAXTextFieldRole as String else { return false }
            return [
                node.placeholder,
                node.title,
                node.label,
                node.identifier,
                titleUIElementText(node.element)
            ].contains {
                !text.isEmpty && $0.contains(text)
            }
        }) else {
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
        try pressKey(CGKeyCode(0), flags: .maskCommand)
        typeText(value)
        try waitUntil("文本字段 \(text) 接受输入") {
            self.nodes().contains {
                $0.role == kAXTextFieldRole as String && $0.value.contains(value)
            }
        }
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
        try pressButton("预览变更")
        try waitUntil("变更计划 sheet 出现") {
            try self.sheetPresent()
        }
    }

    func sheetPresent() throws -> Bool {
        nodes().contains { $0.role == kAXSheetRole as String }
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

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        guard process.isRunning else { return }
        process.terminate()
        for _ in 0..<20 where process.isRunning {
            pump(for: 0.1)
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
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
        down?.postToPid(process.processIdentifier)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        up?.postToPid(process.processIdentifier)
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
        down?.postToPid(process.processIdentifier)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        up?.postToPid(process.processIdentifier)
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

    private func XCTUnwrapOptional<T>(
        _ value: T?,
        _ error: NativeUIHarnessError
    ) throws -> T {
        guard let value else { throw error }
        return value
    }
}
