import Foundation
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class ExternalSkillLibraryRefreshTests: XCTestCase {
    func testExternalDeletionUpdatesListSearchSelectionAndDetailWithoutRestart() async throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let model = fixture.model
        let first = try fixture.save("first")
        _ = try fixture.save("second")
        await model.refreshLibraryIfChanged()
        model.selectedSkillID = first.id
        await model.loadSelectedSkillDocumentInBackground()
        model.updateQuery("first")
        XCTAssertEqual(model.filteredSkills.map(\.id), [first.id])
        XCTAssertFalse(model.selectedSkillDocument.isEmpty)

        // 独立服务实例复用 MCP 的删除入口，应用模型在此之前已经加载旧快照。
        try SkillSetService(paths: fixture.paths, globalLocations: fixture.locations).libraryStore().remove(first)
        await model.refreshLibraryIfChanged()
        XCTAssertEqual(model.snapshot.catalog.entries.map(\.id), ["second"])
        XCTAssertTrue(model.filteredSkills.isEmpty)
        XCTAssertNil(model.selectedSkillID)
        XCTAssertTrue(model.selectedSkillDocument.isEmpty)
        XCTAssertTrue(model.selectedSkillFiles.isEmpty)
        XCTAssertNil(model.skillStorageURLs[first.id])
        model.updateQuery("")
        XCTAssertEqual(model.filteredSkills.map(\.id), ["second"])
    }

    func testExternalEditRefreshesSameSelectionAndUnchangedCheckPreservesFilePreview() async throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let model = fixture.model
        let first = try fixture.save("first")
        let package = fixture.paths.sourcesRoot.appendingPathComponent(first.path)
        try "附属文件".write(to: package.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        await model.refreshLibraryIfChanged()
        let file = try XCTUnwrap(model.selectedSkillFiles.first)
        model.openSkillFile(file)
        await model.refreshLibraryIfChanged()
        XCTAssertEqual(model.selectedSkillFilePreview, .text("附属文件"))

        let updated = fixture.document("first", body: "外部修改后的正文")
        try updated.write(to: package.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        await model.refreshLibraryIfChanged()
        XCTAssertEqual(model.selectedSkillID, first.id)
        XCTAssertEqual(model.selectedSkillDocument, updated)
        XCTAssertNotEqual(model.selectedSkill?.contentHash, first.contentHash)
        XCTAssertNil(model.selectedSkillFilePreview)
    }

    func testFailedRefreshKeepsPublishedSkillsAndRecoversOnNextCheck() async throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let first = try fixture.save("first")
        let model = fixture.model
        await model.refreshLibraryIfChanged()
        let metadata = fixture.paths.applicationSupportRoot.appendingPathComponent("skill-categories.json")
        let original = try? Data(contentsOf: metadata)
        try Data("broken".utf8).write(to: metadata)
        await model.refreshLibraryIfChanged()
        XCTAssertEqual(model.snapshot.catalog.entries.map(\.id), [first.id])
        XCTAssertNotNil(model.libraryError)
        if let original { try original.write(to: metadata) }
        else { try FileManager.default.removeItem(at: metadata) }
        _ = try fixture.save("second")
        await model.refreshLibraryIfChanged()
        XCTAssertEqual(model.snapshot.catalog.entries.map(\.id), ["first", "second"])
        XCTAssertNil(model.libraryError)
    }

    func testObservationLoopSeesExternalCreationAndStopsPublishingAfterCancellation() async throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let model = fixture.model
        let observer = Task { await model.observeLibraryChanges(interval: .milliseconds(20)) }
        defer { observer.cancel() }
        _ = try fixture.save("first")
        let deadline = ContinuousClock.now + .seconds(5)
        while model.snapshot.catalog.entries.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.snapshot.catalog.entries.map(\.id), ["first"])
        observer.cancel()
        await observer.value
        _ = try fixture.save("second")
        let cancelled = Task { await model.refreshLibraryIfChanged() }
        cancelled.cancel()
        await cancelled.value
        XCTAssertEqual(model.snapshot.catalog.entries.map(\.id), ["first"])
    }

    @MainActor
    private struct Fixture {
        let root: URL
        let paths: SkillSetRuntimePaths
        let locations: GlobalConfigurationLocations
        let model: AppModel

        init() {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("external-library-\(UUID())")
            paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
            locations = GlobalConfigurationLocations(home: root.appendingPathComponent("home"), stateRoot: paths.applicationSupportRoot)
            model = AppModel(runtimePaths: paths, globalLocations: locations)
        }

        func document(_ slug: String, body: String = "外部创建的正文") -> String {
            "---\nname: \(slug)\ndescription: 外部变更回归\n---\n\(body)\n"
        }

        func save(_ slug: String) throws -> SkillEntry {
            try paths.makeLibraryStore().save(SkillEditorDraft(slug: slug, document: document(slug)), repositoryRoot: nil)
        }

        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }
}
