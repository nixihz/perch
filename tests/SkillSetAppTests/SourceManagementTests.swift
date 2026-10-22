import Foundation
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class SourceManagementTests: XCTestCase {
    func testDeletingSelectedPreviewSelectsRemainingRecordAndPreservesCatalog() throws {
        try withIsolatedModel { model, store in
            let first = preview()
            let second = preview()
            try store.save(first)
            try store.save(second)
            model.sourcePreviews = [first, second]
            model.selectedPreviewID = first.id
            let catalogIDs = model.snapshot.catalog.entries.map(\.id)

            model.removeSourcePreview(first.id)
            XCTAssertEqual(model.selectedPreviewID, second.id)
            XCTAssertEqual(model.sourcePreviews.map(\.id), [second.id])
            XCTAssertEqual(try store.list().map(\.id), [second.id])
            XCTAssertEqual(model.snapshot.catalog.entries.map(\.id), catalogIDs)

            model.removeSourcePreview(second.id)
            XCTAssertNil(model.selectedPreviewID)
            XCTAssertNotNil(model.selectedSource, "最后一条预览删除后仍能显示内置来源")
            XCTAssertTrue(try store.list().isEmpty)
        }
    }

    func testFailedRemovalKeepsSelectionAndExposesRecoveryMessage() throws {
        try withIsolatedModel { model, _ in
            let missing = preview()
            model.sourcePreviews = [missing]
            model.selectedPreviewID = missing.id
            model.removeSourcePreview(missing.id)
            XCTAssertEqual(model.selectedPreviewID, missing.id)
            XCTAssertEqual(model.sourcePreviews.map(\.id), [missing.id])
            XCTAssertFalse(model.lastAction.contains("已删除"))
            XCTAssertFalse(model.isWorking)
        }
    }

    private func preview() -> SourcePreviewRecord {
        SourcePreviewRecord(
            id: UUID(), inputURL: "https://github.com/fixture/skills",
            canonicalURL: "https://github.com/fixture/skills", namespace: "fixture-skills",
            resolvedCommit: "abc", createdAt: Date(), workspacePath: "/unused",
            licenseEvidence: "", candidates: [], excludedCounts: [:], warnings: []
        )
    }

    private func withIsolatedModel(_ body: (AppModel, SourcePreviewStore) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let variables = ["CFFIXED_USER_HOME", "SKILLSET_HOME", "CODEX_HOME"]
        let environment = ProcessInfo.processInfo.environment
        for variable in variables { setenv(variable, root.appendingPathComponent(variable).path, 1) }
        defer {
            for variable in variables {
                if let value = environment[variable] { setenv(variable, value, 1) }
                else { unsetenv(variable) }
            }
            try? FileManager.default.removeItem(at: root)
        }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root, repositoryRoot: nil)
        let model = AppModel(runtimePaths: paths)
        try body(model, SourcePreviewStore(rootURL: paths.previewsRoot))
    }
}
