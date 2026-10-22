import Foundation
import XCTest
@testable import SkillSetCore

final class PackagedLibraryTests: XCTestCase {
    func testInstalledApplicationUsesWritableSnapshotWithoutChangingBundle() throws {
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
        let repository = try XCTUnwrap(paths.repositoryRoot)
        XCTAssertTrue(repository.path.hasPrefix(state.path + "/"))
        XCTAssertEqual(try Data(contentsOf: repository.appendingPathComponent("registry/catalog.json")), Data("{}".utf8))
        // 对象写入留在本机副本；再次启动继续使用同一份副本。
        try Data("local".utf8).write(to: repository.appendingPathComponent("local-object"))
        XCTAssertFalse(manager.fileExists(atPath: library.appendingPathComponent("local-object").path))
        let reopened = SkillSetRuntimePaths.detect(environment: [:],
            executableURL: contents.appendingPathComponent("Helpers/skillset"),
            currentDirectoryURL: root, applicationSupportRoot: state)
        XCTAssertEqual(reopened.repositoryRoot, repository)
        XCTAssertEqual(try Data(contentsOf: repository.appendingPathComponent("local-object")), Data("local".utf8))
    }
}
