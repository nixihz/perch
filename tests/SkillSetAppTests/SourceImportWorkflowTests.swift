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
            var draft = try XCTUnwrap(prepared)
            draft.mode = .copy
            XCTAssertTrue(draft.document.contains("来源正文"))
            XCTAssertNil(model.importedSkillID(preview: preview, candidate: preview.candidates[0]), "未导入前不自动写入技能库")
            XCTAssertFalse(model.snapshot.catalog.entries.contains { $0.id == "import-workflow" }, "审阅不应创建个人副本")
            model.query = "an-unrelated-search"
            let succeeded = await model.importSourceSkill(draft)
            XCTAssertTrue(succeeded, model.sourceImportError ?? "")
            let entry = try XCTUnwrap(model.snapshot.catalog.entries.first { $0.id == "import-workflow" })
            XCTAssertEqual(model.skillSourceLabels[entry.sourceId], "custom")
            XCTAssertEqual(model.skillSourceTitle(entry), "custom")
            XCTAssertEqual(model.importedSkillID(preview: preview, candidate: preview.candidates[0]), entry.id)
            XCTAssertEqual(model.query, "")
            XCTAssertTrue(model.selectedProject?.draftSkillIDs.isEmpty == true)
            XCTAssertTrue(try DeploymentPlanStore(rootURL: model.runtimePaths.plansRoot).list().isEmpty)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: project.path).isEmpty)
            model.removeSourcePreview(preview.id)
            model.showLibrarySkill(entry.id)
            XCTAssertEqual(model.section, .skills)
            await model.loadSelectedSkillDocumentInBackground()
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
            XCTAssertNil(model.importedSkillID(preview: preview, candidate: preview.candidates[0]), "导入失败不应产生已导入记录")
            XCTAssertEqual(model.sourcePreviews.count, 1)
            XCTAssertFalse(model.snapshot.catalog.entries.contains { $0.id == "import-workflow" })
        }
    }

    func testSyncedSourceAndLibraryEmptyStateFitMinimumWindow() async throws {
        try await withFixture { model, preview, _ in
            let controller = NSHostingController(rootView: ContentView(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = controller
            defer { window.close() }
            let output = URL(fileURLWithPath: "/tmp/perch-source-ui")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: appearance)
                for section in [NavigationItem.sources, .skills] {
                    model.section = section
                    try await Task.sleep(for: .milliseconds(120))
                    controller.view.layoutSubtreeIfNeeded()
                    XCTAssertLessThanOrEqual(controller.view.fittingSize.width, 1081)
                    XCTAssertLessThanOrEqual(controller.view.fittingSize.height, 701)
                    let bitmap = try XCTUnwrap(controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
                    controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("\(section.rawValue)-\(appearance == .aqua ? "light" : "dark").png"))
                }
            }
            model.removeSourcePreview(preview.id)
            XCTAssertTrue(model.snapshot.catalog.entries.isEmpty)
            model.section = .skills
            try await Task.sleep(for: .milliseconds(120))
            controller.view.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(controller.view.fittingSize.width, 1081)
            XCTAssertLessThanOrEqual(controller.view.fittingSize.height, 701)
        }
    }

    func testInstalledScanSheetFitsBothAppearancesWithoutWritingHost() async throws {
        try await withFixture { model, _, root in
            let locations = model.globalConfiguration.locations
            let skill = locations.skillsRoot(.codex).appendingPathComponent("existing")
            try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
            let body = Data("---\nname: existing\ndescription: local\n---\n# Existing".utf8)
            try body.write(to: skill.appendingPathComponent("SKILL.md"))
            let controller = NSHostingController(rootView: InstalledSkillScanSheet(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 620), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = controller
            window.orderFront(nil)
            defer { window.close() }
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: appearance)
                try await Task.sleep(for: .milliseconds(120))
                controller.view.layoutSubtreeIfNeeded()
                XCTAssertLessThanOrEqual(controller.view.fittingSize.width, 781)
                XCTAssertLessThanOrEqual(controller.view.fittingSize.height, 621)
            }
            XCTAssertEqual(try Data(contentsOf: skill.appendingPathComponent("SKILL.md")), body)
            XCTAssertNil(try? FileManager.default.destinationOfSymbolicLink(atPath: skill.path))
            XCTAssertEqual(try model.scanInstalledSkills(additionalRoots: []).filter(\.canImport).count, 0)
            XCTAssertFalse(model.snapshot.catalog.entries.contains { $0.slug == "existing" })
            XCTAssertEqual(try Data(contentsOf: skill.appendingPathComponent("SKILL.md")), body)
        }
    }

    func testBatchImportAddsOnlySelectedSkillsAndLeavesProjectsUntouched() async throws {
        try await withFixture { model, preview, root in
            let project = root.appendingPathComponent("project")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            XCTAssertTrue(model.registerProject(project))
            let items = preview.candidates.map { SourceSkillBatchItem(path: $0.path, slug: $0.slug) }
            XCTAssertEqual(items.count, 2)

            let raw = await model.importSourceSkills(
                previewID: preview.id, items: items, mode: .symlink, category: "review"
            )
            let outcome = try XCTUnwrap(raw)
            XCTAssertEqual(outcome.count, 2)
            XCTAssertTrue(outcome.allSatisfy { if case .imported = $0.status { return true } else { return false } })
            XCTAssertTrue(model.snapshot.catalog.entries.contains { $0.id == "import-workflow" })
            XCTAssertTrue(model.snapshot.catalog.entries.contains { $0.id == "import-second" })
            XCTAssertNotNil(model.importedSkillID(preview: preview, candidate: preview.candidates[0]))
            XCTAssertNotNil(model.importedSkillID(preview: preview, candidate: preview.candidates[1]))
            XCTAssertTrue(model.sourceOrigins["import-workflow"]?.path == "skills/import-workflow")
            // 批量加入只写技能库，不写项目，也不生成部署计划。
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: project.path).isEmpty)
            XCTAssertTrue(try DeploymentPlanStore(rootURL: model.runtimePaths.plansRoot).list().isEmpty)
        }
    }

    func testBatchImportSkipsOccupiedIdentifierInsteadOfOverwriting() async throws {
        try await withFixture { model, preview, _ in
            let firstRaw = await model.importSourceSkills(
                previewID: preview.id, items: [SourceSkillBatchItem(path: "skills/import-workflow", slug: "import-workflow")],
                mode: .copy, category: ""
            )
            let first = try XCTUnwrap(firstRaw)
            XCTAssertEqual(first.count, 1)
            let entry = try XCTUnwrap(model.snapshot.catalog.entries.first { $0.id == "import-workflow" })
            let documentBefore = try model.runtimePaths.makeLibraryStore()
                .document(for: entry, repositoryRoot: nil)

            let secondRaw = await model.importSourceSkills(
                previewID: preview.id, items: [SourceSkillBatchItem(path: "skills/import-second", slug: "import-workflow")],
                mode: .copy, category: ""
            )
            let second = try XCTUnwrap(secondRaw)
            XCTAssertEqual(second.count, 1)
            guard case .skipped(let code) = second[0].status else {
                return XCTFail("标识已被占用时应跳过")
            }
            XCTAssertEqual(code, SkillLibraryError.duplicate.code)
            XCTAssertEqual(model.snapshot.catalog.entries.count, 1)
            let documentAfter = try model.runtimePaths.makeLibraryStore()
                .document(for: entry, repositoryRoot: nil)
            XCTAssertEqual(documentBefore, documentAfter)
        }
    }

    func testBatchSheetFitsBothAppearancesWithoutWritingLibrary() async throws {
        try await withFixture { model, preview, _ in
            let draft = SourceSkillBatchDraft(
                preview: preview,
                items: preview.candidates.map { SourceSkillBatchItem(path: $0.path, slug: $0.slug) }
            )
            let controller = NSHostingController(rootView: SourceSkillBatchImportSheet(model: model, draft: draft))
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
            XCTAssertTrue(model.snapshot.catalog.entries.isEmpty)
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
        let secondPackage = paths.previewsRoot.appendingPathComponent(id.uuidString).appendingPathComponent("checkout/skills/import-second")
        try FileManager.default.createDirectory(at: secondPackage, withIntermediateDirectories: true)
        try "---\nname: import-second\ndescription: 第二个来源技能\n---\n\n# 第二个正文\n".write(to: secondPackage.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let secondAnalysis = try SkillAssetCopier.analyze(from: secondPackage)
        let second = SourceSkillCandidate(id: "fixture/import-second", path: "skills/import-second", slug: "import-second", declaredName: "import-second", description: "第二个来源技能", category: "other", state: .other, contentHash: secondAnalysis.contentHash, fileCount: 1, bytes: secondAnalysis.bytes, issues: [])
        let preview = SourcePreviewRecord(id: id, inputURL: "https://github.com/fixture/skills", canonicalURL: "https://github.com/fixture/skills", namespace: "fixture-skills", resolvedCommit: String(repeating: "b", count: 40), createdAt: Date(), workspacePath: package.deletingLastPathComponent().path, licenseEvidence: "", candidates: [candidate, second], excludedCounts: ["other": 1], warnings: [])
        try SourcePreviewStore(rootURL: paths.previewsRoot).save(preview)
        let model = AppModel(runtimePaths: paths)
        try await body(model, preview, root)
    }
}
