import Foundation
import Testing
@testable import SkillSetCore

struct LegacyLicenseMetadataTests {
    @Test func oldCatalogSourceAndLockMetadataStillDecodeWithoutRecreatingReviewState() throws {
        let snapshot = AppSnapshot.load()
        let skill = try JSONDecoder().decode(SkillEntry.self, from: Data(#"""
        {
          "id": "fixture/example",
          "slug": "example",
          "declaredName": "example",
          "description": "测试技能",
          "declaredVersion": null,
          "metadataReview": "not-schema-validated",
          "sourceId": "fixture",
          "path": "fixtures/example",
          "contentHash": "abc",
          "fileCount": 1,
          "bytes": 10,
          "integrity": "snapshotted",
          "issues": [],
          "excludedPaths": []
        }
        """#.utf8))
        let source = try #require(snapshot.sources.sources.first)
        let revision = LockedSkillRevision(id: skill.id, sourceId: skill.sourceId, sourcePath: skill.path,
            declaredVersion: skill.declaredVersion, contentHash: skill.contentHash, files: [])
        try checkLegacyField(skill)
        try checkLegacyField(source)
        try checkLegacyField(revision)
    }

    private func checkLegacyField<Value: Codable & Equatable>(_ original: Value) throws {
        let encoder = JSONEncoder()
        var oldRecord = try #require(JSONSerialization.jsonObject(with: encoder.encode(original)) as? [String: Any])
        oldRecord["licenseReview"] = "required"
        let loaded = try JSONDecoder().decode(Value.self, from: JSONSerialization.data(withJSONObject: oldRecord))
        #expect(loaded == original)
        let saved = try #require(JSONSerialization.jsonObject(with: encoder.encode(loaded)) as? [String: Any])
        #expect(saved["licenseReview"] == nil)
    }
}
