import Foundation
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class UserLibraryTests: XCTestCase {
    func testBrokenLibraryReportsFailureAndReloadRecoversCopiedContentWithoutRestart() throws {
        try fixture { _, paths in
            let store = TemplateStore(rootURL: paths.applicationSupportRoot)
            try FileManager.default.createDirectory(at: store.rootURL, withIntermediateDirectories: true)
            try Data("broken".utf8).write(to: store.documentURL)
            let model = AppModel(runtimePaths: paths)
            XCTAssertNotNil(model.templateLibraryError)
            XCTAssertNil(model.selectedTemplate)
            let copy = Data(#"{"records":[{"title":"来自另一台电脑","body":"应显示这条规则。"}]}"#.utf8)
            try copy.write(to: store.documentURL)
            model.reloadTemplates()
            XCTAssertNil(model.templateLibraryError)
            XCTAssertEqual(model.selectedTemplate?.title, "来自另一台电脑")
            XCTAssertEqual(model.snapshot.templates.count, 1)
            XCTAssertEqual(try Data(contentsOf: store.documentURL), copy)
        }
    }

    func testNormalLaunchHasNoSeedContentAndKeepsOnlyUserEditedLegacyEntries() throws {
        try fixture { root, paths in
            let empty = AppModel(runtimePaths: paths)
            XCTAssertTrue(empty.snapshot.templates.isEmpty)
            XCTAssertTrue(empty.snapshot.presets.isEmpty)
            XCTAssertNil(empty.selectedTemplate)
            XCTAssertNil(empty.selectedPreset)
            // 同标识的本机编辑属于用户数据，不能与旧示例一起丢弃。
            _ = try TemplateStore(rootURL: paths.applicationSupportRoot).save(
                TemplateRecord(id: "engineering", title: "我自己的约定", body: "仅保留用户编辑内容。"), initial: [])
            _ = try PresetStore(rootURL: paths.applicationSupportRoot).save(
                PresetRecord(id: "personal-base", name: "我的组合", instructionFragments: ["engineering"]), initial: [])
            let reloaded = AppModel(runtimePaths: paths)
            XCTAssertEqual(reloaded.snapshot.templates.map(\.title), ["我自己的约定"])
            XCTAssertEqual(reloaded.snapshot.presets.map(\.name), ["我的组合"])
            XCTAssertEqual(try SkillSetService(paths: paths).snapshot.templates.map(\.body), ["仅保留用户编辑内容。"])
            let project = root.appendingPathComponent("project")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            XCTAssertTrue(reloaded.registerProject(project))
            XCTAssertTrue(reloaded.loadPreset(try XCTUnwrap(reloaded.selectedPreset), into: reloaded.selectedProjectID))
            let drafts = ProjectDraftStore(rootURL: paths.applicationSupportRoot)
            let before = try Data(contentsOf: drafts.documentURL)
            reloaded.removePreset(try XCTUnwrap(reloaded.selectedPreset))
            XCTAssertNil(reloaded.presetError)
            XCTAssertEqual(try Data(contentsOf: drafts.documentURL), before)
            XCTAssertTrue(AppModel(runtimePaths: paths).snapshot.presets.isEmpty)
            reloaded.removeTemplate(try XCTUnwrap(reloaded.selectedTemplate))
            XCTAssertNil(reloaded.templateError)
            let final = AppModel(runtimePaths: paths)
            XCTAssertTrue(final.snapshot.templates.isEmpty)
            XCTAssertTrue(final.snapshot.presets.isEmpty)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: project.path), [])
        }
    }

    func testCorruptLibraryCannotBeOverwrittenByDeletion() throws {
        try fixture { _, paths in
            try FileManager.default.createDirectory(at: paths.applicationSupportRoot, withIntermediateDirectories: true)
            for name in ["presets.json", "templates.json"] {
                try Data("broken".utf8).write(to: paths.applicationSupportRoot.appendingPathComponent(name))
            }
            XCTAssertThrowsError(try PresetStore(rootURL: paths.applicationSupportRoot).remove(id: "anything"))
            XCTAssertThrowsError(try TemplateStore(rootURL: paths.applicationSupportRoot).remove(id: "anything", initial: []))
            for name in ["presets.json", "templates.json"] {
                XCTAssertEqual(try String(contentsOf: paths.applicationSupportRoot.appendingPathComponent(name), encoding: .utf8), "broken")
            }
        }
    }

    private func fixture(_ body: (URL, SkillSetRuntimePaths) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("user-library-\(UUID())")
        let keys = ["CFFIXED_USER_HOME", "SKILLSET_HOME", "CODEX_HOME", "CLAUDE_CONFIG_DIR", "SKILLSET_REPOSITORY_LIBRARY"]
        let saved = ProcessInfo.processInfo.environment
        for key in keys { setenv(key, root.appendingPathComponent(key).path, 1) }
        setenv("SKILLSET_REPOSITORY_LIBRARY", "0", 1)
        defer {
            for key in keys { if let value = saved[key] { setenv(key, value, 1) } else { unsetenv(key) } }
            try? FileManager.default.removeItem(at: root)
        }
        try body(root, SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil))
    }
}
