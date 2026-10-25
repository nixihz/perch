import Foundation
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class SkillStoragePathTests: XCTestCase {
    /// 技能实体放在 sources/custom，私有库存目录只留软链。展示路径必须指向实体位置。
    func testSavedSkillPointsAtSourceDirectoryInsteadOfLibraryDirectory() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("storage-\(UUID())")
        let variables = ["SKILLSET_HOME", "CODEX_HOME", "CFFIXED_USER_HOME"]
        let environment = ProcessInfo.processInfo.environment
        for variable in variables { setenv(variable, root.appendingPathComponent(variable).path, 1) }
        defer {
            for variable in variables {
                if let value = environment[variable] { setenv(variable, value, 1) } else { unsetenv(variable) }
            }
            try? FileManager.default.removeItem(at: root)
        }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let model = AppModel(runtimePaths: paths)
        XCTAssertTrue(model.saveSkill(SkillEditorDraft(
            slug: "demo-skill", document: "---\nname: demo-skill\ndescription: 存储路径验证\n---\n\n正文\n"
        )))
        let expected = paths.sourcesRoot.appendingPathComponent("custom/demo-skill", isDirectory: true).standardizedFileURL
        XCTAssertEqual(model.skillStorageURLs["demo-skill"]?.standardizedFileURL, expected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path))
        // 私有库存只保留软链，不存放实体。
        let libraryEntry = model.runtimePaths.libraryDirectoryURL.appendingPathComponent("demo-skill")
        XCTAssertEqual(
            URL(fileURLWithPath: try FileManager.default.destinationOfSymbolicLink(atPath: libraryEntry.path)).standardizedFileURL.path,
            expected.path
        )
    }

    /// 展示时不能把相对路径拼到库目录下，那会指向一个并不存在的位置。
    func testDisplayUsesScannedPathAndFallsBackToRelativePath() throws {
        let entry = try JSONDecoder().decode(SkillEntry.self, from: JSONSerialization.data(withJSONObject: [
            "id": "demo-skill", "slug": "demo-skill", "declaredName": "demo-skill", "description": "路径展示",
            "declaredVersion": "", "metadataReview": "reviewed", "sourceId": SkillLibraryStore.sourceID,
            "path": "custom/demo-skill", "contentHash": String(repeating: "a", count: 64),
            "fileCount": 1, "bytes": 32, "integrity": "snapshotted",
            "issues": [], "licenseReview": "reviewed", "excludedPaths": []
        ]))
        let scanned = URL(fileURLWithPath: "/tmp/perch/sources/custom/demo-skill", isDirectory: true)
        XCTAssertEqual(
            SkillStoragePath.display(entry, storageURLs: ["demo-skill": scanned]),
            scanned.standardizedFileURL.path
        )
        XCTAssertEqual(SkillStoragePath.display(entry, storageURLs: [:]), "custom/demo-skill")
    }
}
