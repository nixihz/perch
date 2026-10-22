import Foundation
import XCTest
@testable import SkillSetCore

final class PackagedLibraryTests: XCTestCase {
    func testInstalledApplicationStartsWithoutImportingBundledSkills() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? manager.removeItem(at: root) }
        let contents = root.appendingPathComponent("Applications/Perch.app/Contents")
        let library = contents.appendingPathComponent("Resources/SkillSetLibrary")
        try manager.createDirectory(at: library.appendingPathComponent("registry"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: library.appendingPathComponent("registry/catalog.json"))
        try String(repeating: "a", count: 64).write(to: library.appendingPathComponent("package-revision"), atomically: true, encoding: .utf8)
        let state = root.appendingPathComponent("state")
        let paths = SkillSetRuntimePaths.detect(environment: [:],
            executableURL: contents.appendingPathComponent("MacOS/SkillSet"),
            currentDirectoryURL: root, applicationSupportRoot: state)
        XCTAssertNil(paths.repositoryRoot)
        XCTAssertFalse(manager.fileExists(atPath: state.path), "查找路径不应复制内置技能快照")
        let service = try SkillSetService(paths: paths)
        XCTAssertTrue(service.skills(query: "").isEmpty)
        XCTAssertTrue(service.snapshot.sources.sources.isEmpty)
        XCTAssertEqual(try Data(contentsOf: library.appendingPathComponent("registry/catalog.json")), Data("{}".utf8))
    }
}
