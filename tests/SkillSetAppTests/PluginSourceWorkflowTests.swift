import AppKit
import SwiftUI
import XCTest
@testable import SkillSetCore
@testable import SkillSetApp

@MainActor
final class PluginSourceWorkflowTests: XCTestCase {
    func testSourceAndScanPagesFitMinimumWindowAndKeepOriginalPackage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let previous = ProcessInfo.processInfo.environment["SKILLSET_HOME"]
        setenv("SKILLSET_HOME", root.appendingPathComponent("home").path, 1)
        defer {
            if let previous { setenv("SKILLSET_HOME", previous, 1) } else { unsetenv("SKILLSET_HOME") }
        }
        let source = root.appendingPathComponent("home/.claude/plugins/cache/fixture/workflow-plugin/1")
        try FileManager.default.createDirectory(at: source.appendingPathComponent(".claude-plugin"), withIntermediateDirectories: true)
        let manifest = Data(#"{"name":"workflow-plugin","version":"1","description":"Original plugin description","hooks":{}}"#.utf8)
        try manifest.write(to: source.appendingPathComponent(".claude-plugin/plugin.json"))
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let library = PluginSourceLibrary(stateRoot: paths.applicationSupportRoot)
        _ = try library.save(address: source.path)
        let model = AppModel(runtimePaths: paths)
        model.section = .plugins
        let output = URL(fileURLWithPath: "/tmp/perch-plugin-ui")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let views: [(String, AnyView, NSSize)] = [
            ("sources", AnyView(ContentView(model: model)), NSSize(width: 1080, height: 700)),
            ("configuration", AnyView(PluginConfigurationView(model: model, host: .claudeCode, projectID: nil, onPlan: {}).padding(24)), NSSize(width: 1000, height: 680)),
            ("scan", AnyView(PluginScanSheet(model: model, library: library)), NSSize(width: 780, height: 660))
        ]
        for (name, view, size) in views {
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = controller
            window.setContentSize(size)
            window.orderFront(nil)
            defer { window.close() }
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: appearance)
                try await Task.sleep(for: .milliseconds(160))
                controller.view.layoutSubtreeIfNeeded()
                XCTAssertLessThanOrEqual(controller.view.fittingSize.width, size.width + 1, name)
                XCTAssertLessThanOrEqual(controller.view.fittingSize.height, size.height + 1, name)
                let bitmap = try XCTUnwrap(controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
                controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("\(name)-\(appearance == .aqua ? "light" : "dark").png"))
            }
        }
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent(".claude-plugin/plugin.json")), manifest)
        XCTAssertFalse(model.planPresented)
        XCTAssertNil(model.preparedPlan)
        XCTAssertTrue(try DeploymentPlanStore(rootURL: paths.plansRoot).list().isEmpty)
    }
}
