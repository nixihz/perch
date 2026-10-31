import Foundation
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class ProjectRemovalTests: XCTestCase {
    func testRemovingProjectKeepsProjectFolderAndWrittenFiles() throws {
        try fixture { root, paths, locations in
            let projectURL = root.appendingPathComponent("kept-project", isDirectory: true)
            try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
            let writtenFile = projectURL.appendingPathComponent(".agents/skills/demo/SKILL.md")
            try FileManager.default.createDirectory(
                at: writtenFile.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try "# demo".write(to: writtenFile, atomically: true, encoding: .utf8)

            let model = AppModel(runtimePaths: paths, globalLocations: locations)
            XCTAssertTrue(model.registerProject(projectURL))
            let projectID = try XCTUnwrap(UUID(uuidString: model.selectedProject?.id ?? ""))

            XCTAssertTrue(model.unregisterProject(projectID), model.lastAction)

            XCTAssertTrue(model.projects.isEmpty, "删除后项目列表不应再保留该项目")
            XCTAssertTrue(
                try ProjectStore(rootURL: paths.applicationSupportRoot).list().isEmpty,
                "删除后本机登记中不应再保留该项目"
            )
            XCTAssertNil(
                try ProjectDraftStore(rootURL: paths.applicationSupportRoot).load(projectID: projectID),
                "删除后不应保留该项目的配置草稿"
            )
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: projectURL.path),
                "删除项目不应删除项目文件夹"
            )
            XCTAssertEqual(
                try String(contentsOf: writtenFile, encoding: .utf8),
                "# demo",
                "删除项目不应改动已写入项目的文件"
            )
        }
    }

    func testRemovingProjectKeepsOtherProjectsAndMovesSelection() throws {
        try fixture { root, paths, locations in
            let firstURL = root.appendingPathComponent("alpha", isDirectory: true)
            let secondURL = root.appendingPathComponent("beta", isDirectory: true)
            try FileManager.default.createDirectory(at: firstURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: secondURL, withIntermediateDirectories: true)

            let model = AppModel(runtimePaths: paths, globalLocations: locations)
            XCTAssertTrue(model.registerProject(firstURL))
            XCTAssertTrue(model.registerProject(secondURL))
            let removedID = try XCTUnwrap(UUID(uuidString: model.selectedProject?.id ?? ""))
            let remainingID = try XCTUnwrap(
                model.projects.first(where: { $0.id != removedID.uuidString })?.id
            )

            XCTAssertTrue(model.unregisterProject(removedID), model.lastAction)

            XCTAssertEqual(model.projects.count, 1)
            XCTAssertEqual(model.selectedProject?.id, remainingID, "删除后应选中剩下的项目")
            XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
        }
    }

    func testRemovingUnknownProjectFailsWithoutTouchingRegistry() throws {
        try fixture { root, paths, locations in
            let projectURL = root.appendingPathComponent("project", isDirectory: true)
            try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
            let model = AppModel(runtimePaths: paths, globalLocations: locations)
            XCTAssertTrue(model.registerProject(projectURL))

            XCTAssertFalse(model.unregisterProject(UUID()))
            XCTAssertEqual(model.projects.count, 1)
        }
    }

    private func fixture(_ body: (URL, SkillSetRuntimePaths, GlobalConfigurationLocations) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("project-removal-\(UUID().uuidString)")
        let paths = SkillSetRuntimePaths(
            applicationSupportRoot: root.appendingPathComponent("state"),
            repositoryRoot: nil
        )
        let locations = GlobalConfigurationLocations(home: root.appendingPathComponent("home"),
                                                     stateRoot: paths.applicationSupportRoot)
        let keys = ["CFFIXED_USER_HOME", "SKILLSET_HOME", "CODEX_HOME", "CLAUDE_CONFIG_DIR"]
        let saved = ProcessInfo.processInfo.environment
        for key in keys { setenv(key, root.appendingPathComponent(key).path, 1) }
        defer {
            for key in keys { if let value = saved[key] { setenv(key, value, 1) } else { unsetenv(key) } }
            try? FileManager.default.removeItem(at: root)
        }
        try body(root, paths, locations)
    }
}
