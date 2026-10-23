import Foundation
import XCTest
import SkillSetCore
@testable import SkillSetApp

final class SkillLibraryFilterTests: XCTestCase {
    func testNamesUseDeclaredNameAcrossDifferentDirectoriesAndFallBackToSlug() throws {
        let first = try entry(id: "one/a", slug: "folder-a", name: " Review ", hash: "first")
        let second = try entry(id: "two/b", slug: "folder-b", name: "review", hash: "second")
        let fallback = try entry(id: "three/review", slug: "review", name: "  ", hash: "third")
        let unique = try entry(id: "four/a", slug: "folder-a", name: "other", hash: "fourth")
        let entries = [first, second, fallback, unique]
        let index = SkillLibraryIndex(entries: entries)
        XCTAssertEqual(entries.filter { index.matches($0, filter: .duplicateNames) }.map(\.id),
                       ["one/a", "two/b", "three/review"])
        XCTAssertEqual(index.namesakes(of: first).map(\.id), ["two/b", "three/review"])
        XCTAssertFalse(index.matches(first, filter: .identicalContent), "重名但指纹不同，不能判为同内容")
    }

    func testContentFilterExcludesUnknownHashesAndTracksRemoval() throws {
        let entries = try [
            entry(id: "a/one", slug: "one", hash: "same"),
            entry(id: "b/two", slug: "two", hash: "same"),
            entry(id: "c/three", slug: "three", hash: ""),
            entry(id: "d/four", slug: "four", hash: "")
        ]
        let index = SkillLibraryIndex(entries: entries)
        XCTAssertEqual(entries.filter { index.matches($0, filter: .identicalContent) }.map(\.id), ["a/one", "b/two"])
        let remaining = Array(entries.dropFirst())
        XCTAssertTrue(remaining.filter { SkillLibraryIndex(entries: remaining).matches($0, filter: .identicalContent) }.isEmpty)
    }

    func testSearchAndSourceKeepDuplicateRelationshipFromFullLibrary() throws {
        let entries = try [
            entry(id: "a/review", slug: "review", name: "review", hash: "one", blocked: true),
            entry(id: "b/review", slug: "review", name: "review", hash: "two"),
            entry(id: "a/unique", slug: "unique", hash: "three")
        ]
        let index = SkillLibraryIndex(entries: entries)
        let searched = matchingSkills(entries, query: "review", sourceID: "a")
        XCTAssertEqual(searched.filter { index.matches($0, filter: .duplicateNames) }.map(\.id), ["a/review"])
        XCTAssertEqual(entries.filter { index.matches($0, filter: .blocked) }.map(\.id), ["a/review"])
        XCTAssertEqual(entries.filter { index.matches($0, filter: .all) }.count, 3)
    }

    func testNamesakeContentWithoutFingerprintIsUnknown() throws {
        let unknown = try entry(id: "a/review", slug: "review", hash: "")
        let otherUnknown = try entry(id: "b/review", slug: "review", hash: "")
        let known = try entry(id: "c/review", slug: "review", hash: "known")
        let identical = try entry(id: "d/review", slug: "review", hash: "known")
        let different = try entry(id: "e/review", slug: "review", hash: "changed")
        XCTAssertNil(SkillLibraryIndex.hasSameContent(unknown, otherUnknown), "缺失指纹不能证明内容相同")
        XCTAssertNil(SkillLibraryIndex.hasSameContent(known, unknown), "缺失指纹也不能证明内容不同")
        XCTAssertEqual(SkillLibraryIndex.hasSameContent(known, identical), true)
        XCTAssertEqual(SkillLibraryIndex.hasSameContent(known, different), false)
    }

    private func entry(id: String, slug: String, name: String = "", hash: String, blocked: Bool = false) throws -> SkillEntry {
        let values: [String: Any] = [
            "id": id, "slug": slug, "declaredName": name, "description": "fixture", "metadataReview": "reviewed",
            "sourceId": String(id.split(separator: "/")[0]), "path": slug, "contentHash": hash,
            "fileCount": 1, "bytes": 10, "integrity": blocked ? "blocked" : "snapshotted",
            "issues": [], "licenseReview": "reviewed", "excludedPaths": []
        ]
        return try JSONDecoder().decode(SkillEntry.self, from: JSONSerialization.data(withJSONObject: values))
    }
}
