import Foundation
import XCTest
@testable import SkillSetCore

final class TemplateStoreTests: XCTestCase {
    func testCreateEditAndDeleteSurviveReloadIncludingBuiltInDeletion() throws {
        try fixture { root, store in
            let initial = [TemplateRecord(id: "base", title: "初始", body: "原规则\n")]
            XCTAssertEqual(try store.list(merging: initial), initial)
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.documentURL.path))
            let project = root.appendingPathComponent("AGENTS.md")
            try "项目手写规则\n".write(to: project, atomically: true, encoding: .utf8)
            let added = TemplateRecord(title: "  我的片段  ", body: "保留正文空格  \n", purpose: "  说明  ")
            _ = try store.save(added, initial: initial)
            let reloaded = TemplateStore(rootURL: store.rootURL)
            let saved = try XCTUnwrap(reloaded.list(merging: initial).last)
            XCTAssertEqual(saved.id, added.id)
            XCTAssertEqual(saved.title, "我的片段")
            XCTAssertEqual(saved.body, "保留正文空格  \n")
            XCTAssertEqual(saved.purpose, "说明")
            XCTAssertTrue(saved.isLocal)
            _ = try store.save(TemplateRecord(id: "base", title: "初始已编辑", body: "新的正文"), initial: initial)
            XCTAssertEqual(try reloaded.list(merging: initial).map(\.id), ["base", added.id])
            XCTAssertEqual(try reloaded.list(merging: initial).first?.body, "新的正文")
            _ = try store.remove(id: "base", initial: initial)
            XCTAssertEqual(try reloaded.list(merging: initial).map(\.id), [added.id])
            _ = try store.remove(id: added.id, initial: initial)
            XCTAssertTrue(try reloaded.list(merging: initial).isEmpty)
            XCTAssertEqual(try String(contentsOf: project, encoding: .utf8), "项目手写规则\n")
        }
    }

    func testInvalidAndDuplicateSavesLeavePriorLibraryUntouched() throws {
        try fixture { _, store in
            let original = TemplateRecord(title: "Review", body: "有效规则")
            _ = try store.save(original, initial: [])
            let before = try Data(contentsOf: store.documentURL)
            let invalid = [
                TemplateRecord(title: " ", body: "规则"),
                TemplateRecord(title: "空正文", body: " \n"),
                TemplateRecord(title: " review ", body: "重名"),
                TemplateRecord(title: String(repeating: "名", count: 81), body: "规则"),
                TemplateRecord(title: "过长说明", body: "规则", purpose: String(repeating: "字", count: 501)),
                TemplateRecord(title: "过长正文", body: String(repeating: "字", count: 90_000)),
                TemplateRecord(title: "起始标记", body: ManagedBlocks.beginMarker(id: "project-rules")),
                TemplateRecord(title: "结束标记", body: ManagedBlocks.endMarker(id: "project-rules"))
            ]
            for record in invalid {
                XCTAssertThrowsError(try store.save(record, initial: []))
                XCTAssertEqual(try Data(contentsOf: store.documentURL), before)
            }
            XCTAssertThrowsError(try store.remove(id: "missing", initial: []))
            XCTAssertEqual(try Data(contentsOf: store.documentURL), before)
        }
    }

    func testCorruptOrUnsupportedLibraryIsNeverSilentlyReplaced() throws {
        try fixture { _, store in
            try FileManager.default.createDirectory(at: store.rootURL, withIntermediateDirectories: true)
            for document in ["broken", "{\"schemaVersion\":2,\"records\":[],\"deletedIDs\":[]}"] {
                try Data(document.utf8).write(to: store.documentURL)
                XCTAssertThrowsError(try store.list(merging: []))
                XCTAssertThrowsError(try store.save(TemplateRecord(title: "新片段", body: "规则"), initial: []))
                XCTAssertThrowsError(try store.remove(id: "base-zh", initial: AppSnapshot.load().templates))
                XCTAssertEqual(try String(contentsOf: store.documentURL, encoding: .utf8), document)
            }
        }
    }

    func testSavedContentReachesDeploymentPlanAndDeletedReferenceIsRejected() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: fixture.root.appendingPathComponent("state"), repositoryRoot: fixture.repository)
        let project = try ProjectStore(rootURL: paths.applicationSupportRoot).register(path: fixture.project)
        let store = TemplateStore(rootURL: paths.applicationSupportRoot)
        let initial = AppSnapshot.load(repositoryRoot: fixture.repository).templates
        let record = TemplateRecord(title: "自定义检查", body: "# 自定义规则\n请核对边界。\n")
        _ = try store.save(record, initial: initial)
        let before = fixture.project.appendingPathComponent("AGENTS.md")
        try "手写内容\n".write(to: before, atomically: true, encoding: .utf8)
        let service = try SkillSetService(paths: paths)
        let stored = try service.makePlan(projectID: project.id, skillIDs: [], instructionIDs: [record.id])
        let change = try XCTUnwrap(stored.plan.changes.first { $0.relativePath == "AGENTS.md" })
        let staged = URL(fileURLWithPath: stored.stagingPath).appendingPathComponent(change.relativePath)
        let stagedData = try Data(contentsOf: staged)
        XCTAssertEqual(try ManagedBlocks.extract(original: String(decoding: stagedData, as: UTF8.self), id: "project-rules"), "# 自定义规则\n请核对边界。")
        XCTAssertEqual(SkillAssetCopier.sha256(stagedData), change.afterHash)
        XCTAssertEqual(try String(contentsOf: before, encoding: .utf8), "手写内容\n")
        XCTAssertThrowsError(try service.apply(planID: stored.id, digest: stored.plan.digest))
        _ = try store.remove(id: record.id, initial: initial)
        let refreshed = try SkillSetService(paths: paths)
        XCTAssertThrowsError(try refreshed.makePlan(projectID: project.id, skillIDs: [], instructionIDs: [record.id])) { error in
            XCTAssertEqual((error as? SkillSetServiceError)?.code, "INSTRUCTION_NOT_FOUND")
        }
        XCTAssertEqual(try String(contentsOf: before, encoding: .utf8), "手写内容\n")
    }

    private func fixture(_ body: (URL, TemplateStore) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("template-store-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root, TemplateStore(rootURL: root.appendingPathComponent("state")))
    }
}
