import Foundation
import XCTest
@testable import SkillSetCore
@testable import SkillSetApp

@MainActor
final class InstalledSkillScanModelTests: XCTestCase {
    func testFailedRescanKeepsSuccessfulResultsAndSelectionUntilIndexRecovers() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("installed-scan-\(UUID())")
        defer { try? manager.removeItem(at: root) }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let locations = GlobalConfigurationLocations(home: root.appendingPathComponent("home"), stateRoot: paths.applicationSupportRoot)
        let original = locations.skillsRoot(.codex).appendingPathComponent("existing")
        try manager.createDirectory(at: original, withIntermediateDirectories: true)
        let document = Data("---\nname: existing\ndescription: fixture\n---\nOriginal installation\n".utf8)
        try document.write(to: original.appendingPathComponent("SKILL.md"))
        try manager.createDirectory(at: paths.applicationSupportRoot, withIntermediateDirectories: true)
        let indexURL = paths.applicationSupportRoot.appendingPathComponent("skill-categories.json")
        let validIndex = Data(#"{"categories":{},"origins":{},"hiddenIDs":[]}"#.utf8)
        try validIndex.write(to: indexURL)
        let model = InstalledSkillScanModel()

        await model.scan(paths: paths, locations: locations, roots: [])
        XCTAssertNil(model.error)
        XCTAssertFalse(model.scanning)
        XCTAssertEqual(model.items.map(\.path), [original.path])
        let observed = try XCTUnwrap(model.items.first)
        XCTAssertTrue(observed.canImport)
        model.selected = [original.path]

        // 真实索引读取失败必须保留用户正在处理的结果，不能静默清空勾选。
        try Data("BROKEN-INDEX-MARKER".utf8).write(to: indexURL)
        await model.scan(paths: paths, locations: locations, roots: [])
        XCTAssertEqual(model.error, "本机技能库索引无法读取，请检查应用数据目录；已有版本仍保留在 packages 中。")
        XCTAssertFalse(model.scanning)
        XCTAssertEqual(model.items.map(\.path), [original.path])
        XCTAssertEqual(model.items.first?.contentHash, observed.contentHash)
        XCTAssertEqual(model.selected, Set([original.path]))
        XCTAssertEqual(try Data(contentsOf: original.appendingPathComponent("SKILL.md")), document)

        try validIndex.write(to: indexURL)
        let added = locations.skillsRoot(.codex).appendingPathComponent("added-after-failure")
        try manager.createDirectory(at: added, withIntermediateDirectories: true)
        try Data("---\nname: added\ndescription: fixture\n---\nNew installation\n".utf8)
            .write(to: added.appendingPathComponent("SKILL.md"))
        await model.scan(paths: paths, locations: locations, roots: [])
        XCTAssertNil(model.error)
        XCTAssertFalse(model.scanning)
        XCTAssertEqual(Set(model.items.map(\.path)), Set([original.path, added.path]))
        XCTAssertEqual(model.selected, Set([original.path]))
        XCTAssertEqual(try Data(contentsOf: original.appendingPathComponent("SKILL.md")), document)
    }
}
