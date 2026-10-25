import Foundation
import XCTest
@testable import SkillSetCore
@testable import SkillSetApp

@MainActor
final class SkillSourceFilterTests: XCTestCase {
    func testLinkedRepositoriesRemainSeparateDuringSearchAndLibraryRefresh() throws {
        try withLibrary([
            ("prototype", "https://github.com/emilkowalski/skills", false),
            ("prototype-matt", "https://github.com/mattpocock/skills", false),
            ("review-matt", "https://github.com/mattpocock/skills", false),
            ("local-copy", "https://github.com/mattpocock/skills", true)
        ]) { model in
            let entries = model.snapshot.catalog.entries
            let matt = try XCTUnwrap(entries.first { $0.id == "prototype-matt" })
            let emil = try XCTUnwrap(entries.first { $0.id == "prototype" })
            XCTAssertEqual(matt.sourceId, emil.sourceId, "复现不同仓库共用 link 存放标识")
            let mattKey = model.skillSourceKey(matt)
            let emilKey = model.skillSourceKey(emil)
            XCTAssertNotEqual(mattKey, emilKey)
            XCTAssertEqual(model.skillSourceLabels.count, 3)
            XCTAssertEqual(model.skillSourceLabels[mattKey], "mattpocock/skills")
            XCTAssertEqual(model.skillSourceLabels[emilKey], "emilkowalski/skills")
            XCTAssertEqual(model.skillSourceLabels["custom"], "custom")
            XCTAssertEqual(model.skills(from: mattKey).map(\.id), ["prototype-matt", "review-matt"])
            XCTAssertEqual(model.skills(from: emilKey).map(\.id), ["prototype"])
            XCTAssertEqual(model.skills(from: "custom").map(\.id), ["local-copy"])
            XCTAssertTrue(model.skills(from: "missing-source").isEmpty)

            model.updateQuery("prototype")
            XCTAssertEqual(model.skills(from: mattKey).map(\.id), ["prototype-matt"])
            XCTAssertEqual(model.skills(from: emilKey).map(\.id), ["prototype"])
            XCTAssertEqual(model.skills(from: "").map(\.id), ["prototype", "prototype-matt"])
            XCTAssertEqual(model.skillSourceLabels.count, 3, "搜索不应隐藏其他来源选项")

            model.removeSkill(matt)
            XCTAssertEqual(model.skillSourceLabels[mattKey], "mattpocock/skills", "同来源还有技能时保留选项")
            let review = try XCTUnwrap(model.snapshot.catalog.entries.first { $0.id == "review-matt" })
            model.removeSkill(review)
            XCTAssertNil(model.skillSourceLabels[mattKey], "最后一个技能移除后不再留下空来源")
            XCTAssertEqual(model.skillSourceLabels[emilKey], "emilkowalski/skills")
            XCTAssertEqual(model.skillSourceLabels["custom"], "custom")
        }
    }

    func testSameRepositoryPathOnDifferentHostsAndMissingProvenanceDoNotMerge() throws {
        try withLibrary([
            ("github-skill", "https://github.com/team/skills", false),
            ("gitlab-skill", "https://gitlab.com/team/skills", false),
            ("unknown-skill", nil, false)
        ]) { model in
            XCTAssertEqual(model.skillSourceLabels.count, 3, "可读名称相同也不能把两个地址合并")
            for (id, title) in [("github-skill", "team/skills"), ("gitlab-skill", "team/skills"), ("unknown-skill", "link")] {
                let entry = try XCTUnwrap(model.snapshot.catalog.entries.first { $0.id == id })
                let key = model.skillSourceKey(entry)
                XCTAssertEqual(model.skillSourceLabels[key], title)
                XCTAssertEqual(model.skills(from: key).map(\.id), [id])
            }
        }
    }

    private func withLibrary(
        _ skills: [(name: String, origin: String?, custom: Bool)],
        body: (AppModel) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("source-filter-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let locations = GlobalConfigurationLocations(home: root.appendingPathComponent("home"), stateRoot: paths.applicationSupportRoot)
        let store = paths.makeLibraryStore()
        try FileManager.default.createDirectory(at: store.libraryURL, withIntermediateDirectories: true)
        var origins: [String: SourceSkillOrigin] = [:]
        for skill in skills {
            let package = (skill.custom ? store.customURL : paths.sourcesRoot.appendingPathComponent("external"))
                .appendingPathComponent(skill.name)
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            try "---\nname: \(skill.name)\ndescription: 来源筛选回归\n---\n正文\n"
                .write(to: package.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(at: store.libraryURL.appendingPathComponent(skill.name), withDestinationURL: package)
            if let origin = skill.origin {
                origins[skill.name] = SourceSkillOrigin(
                    url: origin, commit: "fixture", path: "skills/\(skill.name)", contentHash: "fixture",
                    licenseEvidence: "", licenseHashes: [:], declaredName: skill.name)
            }
        }
        try JSONEncoder().encode(SkillLibraryMeta(origins: origins)).write(to: store.categoriesURL)
        try body(AppModel(runtimePaths: paths, globalLocations: locations))
    }
}
