import Foundation
import AppKit
import SwiftUI
import XCTest
@testable import SkillSetCore
@testable import SkillSetApp

@MainActor
final class SourceImportWorkflowTests: XCTestCase {
    func testImportReviewKeepsScrollableDocumentInsideSheetInBothAppearances() async throws {
        try await withFixture { model, preview, _ in
            let prepared = await model.prepareSourceSkillImport(previewID: preview.id, path: "skills/import-workflow")
            let draft = try XCTUnwrap(prepared)
            let controller = NSHostingController(rootView: SourceSkillImportSheet(model: model, initialDraft: draft))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = controller
            window.setContentSize(NSSize(width: 720, height: 640))
            window.orderFront(nil)
            defer { window.close() }
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: appearance)
                try await Task.sleep(for: .milliseconds(120))
                controller.view.layoutSubtreeIfNeeded()
                XCTAssertLessThanOrEqual(controller.view.fittingSize.height, 641)
                XCTAssertLessThanOrEqual(controller.view.fittingSize.width, 721)
            }
        }
    }

    func testReviewDoesNotWriteAndImportRefreshesLibraryWithoutSelectingOrWritingProject() async throws {
        try await withFixture { model, preview, root in
            let project = root.appendingPathComponent("project")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            XCTAssertTrue(model.registerProject(project))
            let prepared = await model.prepareSourceSkillImport(previewID: preview.id, path: "skills/import-workflow")
            let draft = try XCTUnwrap(prepared)
            XCTAssertTrue(draft.document.contains("来源正文"))
            XCTAssertNil(model.importedSkillID(preview: preview, candidate: preview.candidates[0]))
            XCTAssertFalse(FileManager.default.fileExists(atPath: model.runtimePaths.libraryRoot.path), "审阅时不应产生技能副本")
            model.query = "an-unrelated-search"
            let succeeded = await model.importSourceSkill(draft)
            XCTAssertTrue(succeeded, model.sourceImportError ?? "")
            let entry = try XCTUnwrap(model.snapshot.catalog.entries.first { $0.id == "personal/import-workflow" })
            XCTAssertEqual(model.importedSkillID(preview: preview, candidate: preview.candidates[0]), entry.id)
            XCTAssertEqual(model.query, "")
            XCTAssertTrue(model.selectedProject?.draftSkillIDs.isEmpty == true)
            XCTAssertTrue(try DeploymentPlanStore(rootURL: model.runtimePaths.plansRoot).list().isEmpty)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: project.path).isEmpty)
            model.removeSourcePreview(preview.id)
            model.showLibrarySkill(entry.id)
            XCTAssertEqual(model.section, .skills)
            XCTAssertTrue(model.selectedSkillDocument.contains("来源正文"))
            XCTAssertTrue(model.selectedSkillFiles.contains { $0.path == "references/guide.md" })
            XCTAssertEqual(model.sourceOrigins[entry.id]?.commit, preview.resolvedCommit)
            model.toggleSkill(entry)
            model.prepareDeploymentPlan()
            XCTAssertNotNil(model.preparedPlan, model.lastAction)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: project.path).isEmpty)
        }
    }

    func testFailedImportKeepsReviewAvailableAndExposesRecovery() async throws {
        try await withFixture { model, preview, _ in
            let prepared = await model.prepareSourceSkillImport(previewID: preview.id, path: "skills/import-workflow")
            let draft = try XCTUnwrap(prepared)
            let checkout = model.runtimePaths.previewsRoot.appendingPathComponent(preview.id.uuidString).appendingPathComponent("checkout")
            try "changed".write(to: checkout.appendingPathComponent("skills/import-workflow/references/guide.md"), atomically: true, encoding: .utf8)
            let succeeded = await model.importSourceSkill(draft)
            XCTAssertFalse(succeeded)
            XCTAssertFalse(model.isWorking)
            XCTAssertTrue(model.sourceImportError?.contains("重新预览") == true)
            XCTAssertNil(model.importedSkillID(preview: preview, candidate: preview.candidates[0]))
            XCTAssertEqual(model.sourcePreviews.count, 1)
            XCTAssertFalse(model.snapshot.catalog.entries.contains { $0.id == "personal/import-workflow" })
        }
    }

    private func withFixture(_ body: (AppModel, SourcePreviewRecord, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("source-app-\(UUID())")
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
        let repository = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repository.appendingPathComponent("registry"), withIntermediateDirectories: true)
        let empty = CatalogDocument(schemaVersion: 1, hashAlgorithm: "sha256:path-content-executable:v1", entries: [])
        try JSONEncoder().encode(empty).write(to: repository.appendingPathComponent("registry/catalog.json"))
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: repository)
        let id = UUID()
        let package = paths.previewsRoot.appendingPathComponent(id.uuidString).appendingPathComponent("checkout/skills/import-workflow")
        try FileManager.default.createDirectory(at: package.appendingPathComponent("references"), withIntermediateDirectories: true)
        try "---\nname: import-workflow\ndescription: 来源导入\n---\n\n# 来源正文\n".write(to: package.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "# Reference\n".write(to: package.appendingPathComponent("references/guide.md"), atomically: true, encoding: .utf8)
        let analysis = try SkillAssetCopier.analyze(from: package)
        let candidate = SourceSkillCandidate(id: "fixture/import-workflow", path: "skills/import-workflow", slug: "import-workflow", declaredName: "import-workflow", description: "来源导入", category: "other", state: .other, contentHash: analysis.contentHash, fileCount: 2, bytes: analysis.bytes, issues: [])
        let preview = SourcePreviewRecord(id: id, inputURL: "https://github.com/fixture/skills", canonicalURL: "https://github.com/fixture/skills", namespace: "fixture-skills", resolvedCommit: String(repeating: "b", count: 40), createdAt: Date(), workspacePath: package.deletingLastPathComponent().path, licenseEvidence: "", candidates: [candidate], excludedCounts: ["other": 1], warnings: [])
        try SourcePreviewStore(rootURL: paths.previewsRoot).save(preview)
        let model = AppModel(runtimePaths: paths)
        try await body(model, preview, root)
    }
}
