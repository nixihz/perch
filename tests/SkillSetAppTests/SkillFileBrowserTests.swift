import AppKit
import SwiftUI
import XCTest
@testable import SkillSetCore
@testable import SkillSetApp

@MainActor
final class SkillFileBrowserTests: XCTestCase {
    func testSwitchingSkillAndFailedReadsClearPreviousPreviewWithoutLosingBody() throws {
        try withFixture { model, root in
            model.loadSelectedSkillDocument()
            XCTAssertEqual(model.selectedSkillFiles.map(\.path), ["README.md", "assets/image.png", "references/guide.md"])
            let readme = try XCTUnwrap(model.selectedSkillFiles.first)
            model.openSkillFile(readme)
            XCTAssertEqual(model.selectedSkillFilePreview, .text("# 使用说明\n附属文件预览\n"))
            model.closeSkillFile()
            XCTAssertNil(model.selectedSkillFile)
            XCTAssertNil(model.selectedSkillFilePreview)
            let image = model.selectedSkillFiles[1]
            model.openSkillFile(image)
            XCTAssertEqual(model.selectedSkillFilePreview, .unsupported)
            XCTAssertNotNil(model.selectedSkillFileURL())
            let guide = model.selectedSkillFiles[2]
            try FileManager.default.removeItem(at: root.appendingPathComponent("repo/skills/demo/references/guide.md"))
            model.openSkillFile(guide)
            XCTAssertNil(model.selectedSkillFilePreview)
            XCTAssertNotNil(model.skillFilePreviewError)
            XCTAssertTrue(model.selectedSkillDocument.contains("技能正文"))
            model.selectedSkillID = "workspace/single"
            model.loadSelectedSkillDocument()
            XCTAssertNil(model.selectedSkillFile)
            XCTAssertNil(model.skillFilePreviewError)
            XCTAssertTrue(model.selectedSkillFiles.isEmpty)
            XCTAssertTrue(model.selectedSkillDocument.contains("单文件正文"))
            model.openSkillFile(readme)
            XCTAssertNil(model.selectedSkillFile, "不能跨技能读取旧列表中的文件")
        }
    }

    func testListFailureDoesNotHideSkillDocumentAndReloadRecovers() throws {
        try withFixture { model, root in
            let link = root.appendingPathComponent("repo/skills/demo/unsafe.md")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("outside"))
            model.loadSelectedSkillDocument()
            XCTAssertNotNil(model.skillFilesError)
            XCTAssertNil(model.libraryError)
            XCTAssertTrue(model.selectedSkillFiles.isEmpty)
            XCTAssertTrue(model.selectedSkillDocument.contains("技能正文"))
            try FileManager.default.removeItem(at: link)
            model.loadSelectedSkillDocument()
            XCTAssertNil(model.skillFilesError)
            XCTAssertEqual(model.selectedSkillFiles.count, 3)
        }
    }

    func testFileTabsListAndPreviewFitLightAndDarkMinimumWindow() async throws {
        try await withFixture { model, root in
            let longPath = root.appendingPathComponent("repo/skills/demo/references/较长的目录名称用于核对窗口布局/更深一层的参考资料目录/这是一份较长文件名称的使用说明文档.md")
            try FileManager.default.createDirectory(at: longPath.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "长路径正文\n".write(to: longPath, atomically: true, encoding: .utf8)
            model.section = .skills
            let controller = NSHostingController(rootView: ContentView(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700),
                                  styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = controller
            defer { window.close() }
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: appearance)
                try await settle(controller.view)
                let segmented = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSSegmentedControl }.first)
                XCTAssertEqual(segmented.segmentCount, 2)
                XCTAssertEqual(segmented.selectedSegment, 0)
                segmented.selectedSegment = 1
                _ = segmented.sendAction(segmented.action, to: segmented.target)
                try await settle(controller.view)
                XCTAssertEqual(segmented.selectedSegment, 1)
                XCTAssertLessThanOrEqual(controller.view.fittingSize.width, 1081)
                XCTAssertLessThanOrEqual(controller.view.fittingSize.height, 701)
                try screenshot(controller.view, name: appearance == .aqua ? "files-light" : "files-dark")
                model.openSkillFile(try XCTUnwrap(model.selectedSkillFiles.first))
                try await settle(controller.view)
                XCTAssertLessThanOrEqual(controller.view.fittingSize.width, 1081)
                try screenshot(controller.view, name: appearance == .aqua ? "preview-light" : "preview-dark")
                model.closeSkillFile()
                segmented.selectedSegment = 0
                _ = segmented.sendAction(segmented.action, to: segmented.target)
            }
            model.selectedSkillID = "workspace/single"
            try await settle(controller.view)
            XCTAssertTrue(descendants(controller.view).compactMap { $0 as? NSSegmentedControl }.isEmpty)
            model.selectedSkillID = "workspace/demo"
            try await settle(controller.view)
            XCTAssertEqual(descendants(controller.view).compactMap { $0 as? NSSegmentedControl }.first?.selectedSegment, 0)
        }
    }

    func testBackgroundReadSwitchesDocumentAndReportsMissingFiles() async throws {
        try await withFixture { model, root in
            await model.loadSelectedSkillDocumentInBackground()
            XCTAssertTrue(model.selectedSkillDocument.contains("技能正文"))
            XCTAssertEqual(model.selectedSkillFiles.count, 3)
            model.selectedSkillID = "workspace/single"
            await model.loadSelectedSkillDocumentInBackground()
            XCTAssertTrue(model.selectedSkillDocument.contains("单文件正文"))
            XCTAssertTrue(model.selectedSkillFiles.isEmpty)
            try FileManager.default.removeItem(at: root.appendingPathComponent("repo/skills/single"))
            await model.loadSelectedSkillDocumentInBackground()
            XCTAssertTrue(model.selectedSkillDocument.contains("单文件正文"), "同一技能刷新失败保留上次可读取的正文")
            XCTAssertNotNil(model.libraryError)
            XCTAssertFalse(model.isLoadingSkillDocument)
        }
    }

    func testCancelledBackgroundReadDoesNotPublishDocument() async throws {
        try await withFixture { model, _ in
            let task = Task { await model.loadSelectedSkillDocumentInBackground() }
            task.cancel()
            await task.value
            XCTAssertTrue(model.selectedSkillDocument.isEmpty)
            XCTAssertTrue(model.selectedSkillFiles.isEmpty)
            XCTAssertFalse(model.isLoadingSkillDocument)
            await model.loadSelectedSkillDocumentInBackground()
            XCTAssertTrue(model.selectedSkillDocument.contains("技能正文"))
        }
    }

    private func settle(_ view: NSView) async throws {
        try await Task.sleep(for: .milliseconds(120))
        view.layoutSubtreeIfNeeded()
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func screenshot(_ view: NSView, name: String) throws {
        let directory = URL(fileURLWithPath: "/tmp/skillset-files-ui")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: directory.appendingPathComponent(name + ".png"))
    }

    private func withFixture<T>(_ body: (AppModel, URL) async throws -> T) async throws -> T {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        return try await body(fixture.model, fixture.root)
    }

    private func withFixture<T>(_ body: (AppModel, URL) throws -> T) throws -> T {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        return try body(fixture.model, fixture.root)
    }

    private func makeFixture() throws -> (model: AppModel, root: URL, cleanup: () -> Void) {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("file-browser-\(UUID())")
        let variables = ["CFFIXED_USER_HOME", "SKILLSET_HOME", "CODEX_HOME"]
        let environment = ProcessInfo.processInfo.environment
        for variable in variables { setenv(variable, root.appendingPathComponent(variable).path, 1) }
        let cleanup = {
            for variable in variables {
                if let value = environment[variable] { setenv(variable, value, 1) } else { unsetenv(variable) }
            }
            try? FileManager.default.removeItem(at: root)
        }
        do {
            let repo = root.appendingPathComponent("repo")
            let files = ["skills/demo/SKILL.md": "---\nname: demo\ndescription: 文件浏览演示\n---\n技能正文\n",
                         "skills/demo/README.md": "# 使用说明\n附属文件预览\n",
                         "skills/demo/references/guide.md": "参考内容\n",
                         "skills/single/SKILL.md": "---\nname: single\ndescription: 单文件技能\n---\n单文件正文\n"]
            for (path, text) in files {
                let url = repo.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: url, atomically: true, encoding: .utf8)
            }
            let assets = repo.appendingPathComponent("skills/demo/assets")
            try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
            try Data([0x89, 0, 0xff]).write(to: assets.appendingPathComponent("image.png"))
            let entries = try ["demo", "single"].map { slug in
                let analysis = try SkillAssetCopier.analyze(from: repo.appendingPathComponent("skills/" + slug))
                return SkillEntry(id: "workspace/" + slug, slug: slug, declaredName: slug, description: "文件浏览演示",
                                  declaredVersion: "1.0", metadataReview: "not-schema-validated", sourceId: "workspace",
                                  path: "skills/" + slug, contentHash: analysis.contentHash, fileCount: analysis.files.count,
                                  bytes: analysis.bytes, integrity: "snapshotted", issues: [],
                                  licenseReview: "required", excludedPaths: [])
            }
            try FileManager.default.createDirectory(at: repo.appendingPathComponent("registry"), withIntermediateDirectories: true)
            try JSONEncoder().encode(CatalogDocument(schemaVersion: 1, hashAlgorithm: "sha256:path-content-executable:v1", entries: entries))
                .write(to: repo.appendingPathComponent("registry/catalog.json"))
            let model = AppModel(snapshot: AppSnapshot.load(repositoryRoot: repo), runtimePaths: SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: repo))
            return (model, root, cleanup)
        } catch {
            cleanup()
            throw error
        }
    }
}
