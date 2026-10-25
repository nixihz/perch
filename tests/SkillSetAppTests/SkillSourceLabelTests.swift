import XCTest
@testable import SkillSetApp

final class SkillSourceLabelTests: XCTestCase {
    func testCustomSourceUsesDirectoryNameDespiteImportProvenance() {
        for origin: String? in [
            "/Users/brian/.perch/sources/local-imports/installed",
            "/Users/brian/.perch/sources/custom",
            "https://github.com/mattpocock/skills",
            nil
        ] {
            XCTAssertEqual(SkillSourceLabel.title(
                sourceID: "custom", origin: origin, registeredTitle: "旧导入来源"
            ), "custom")
        }
    }

    func testRepositoryTransportsUseReadablePath() {
        for origin in [
            "https://github.com/mattpocock/skills",
            "https://github.com/mattpocock/skills.git/",
            "ssh://git@github.com:2222/mattpocock/skills.git",
            "git@github.com:mattpocock/skills.git"
        ] {
            XCTAssertEqual(SkillSourceLabel.repository(origin), "mattpocock/skills")
        }
    }

    func testLocalAndUnknownSourcesRetainIdentity() {
        let path = "/Users/brian/.perch/sources/local-imports/example"
        XCTAssertEqual(SkillSourceLabel.repository(path), path)
        XCTAssertEqual(SkillSourceLabel.repository("https://github.com"), "https://github.com")
        XCTAssertEqual(SkillSourceLabel.title(sourceID: "source-hash", origin: "https://github.com/mattpocock/skills", registeredTitle: nil), "mattpocock/skills")
        XCTAssertEqual(SkillSourceLabel.title(sourceID: "local-brian", origin: nil, registeredTitle: "Brian 的本地技能库"), "Brian 的本地技能库")
        XCTAssertEqual(SkillSourceLabel.title(sourceID: "personal", origin: nil, registeredTitle: nil), "personal")
    }
}
