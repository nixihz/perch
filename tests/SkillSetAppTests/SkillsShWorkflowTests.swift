import AppKit
import SwiftUI
import XCTest
@testable import SkillSetCore
@testable import SkillSetApp

@MainActor
final class SkillsShWorkflowTests: XCTestCase {
    func testSearchStoresResultsAndShortQueryClearsPreviousState() async throws {
        try await withIsolatedModel(client: SkillsShDirectoryClient { _ in (Self.searchResponse, 200) }) { model in
            model.skillsShQuery = "react"
            await model.searchSkillsSh()

            XCTAssertEqual(model.skillsShResults.map(\.skillId), ["react-review"])
            XCTAssertNil(model.skillsShError)
            XCTAssertFalse(model.isSearchingSkillsSh)

            model.skillsShQuery = "r"
            await model.searchSkillsSh()
            XCTAssertTrue(model.skillsShResults.isEmpty)
            XCTAssertNil(model.skillsShError)
        }
    }

    func testSearchFailureExposesActionableMessageAndKeepsResultsEmpty() async throws {
        try await withIsolatedModel(client: SkillsShDirectoryClient { _ in (Data(), 503) }) { model in
            model.skillsShQuery = "react"
            await model.searchSkillsSh()

            XCTAssertTrue(model.skillsShResults.isEmpty)
            XCTAssertEqual(model.skillsShError, "skills.sh 搜索失败，请检查网络后重试。")
        }
    }

    func testUninstallRemovesOnlyIndexEntryAndKeepsPackageAndDeployedFiles() throws {
        try withLibraryFixture(
            packages: [("skills/review-demo", "review-demo")],
            deployFirstToProject: true
        ) { model, _, entries, hit, packages, deployed in
            let entry = try XCTUnwrap(entries.first)
            let package = try XCTUnwrap(packages.first)
            let deployed = try XCTUnwrap(deployed)
            XCTAssertEqual(model.sourceOrigins[entry.id]?.url, hit.repositoryURL)
            XCTAssertEqual(model.installedSkillsShEntry(for: hit)?.id, entry.id)
            XCTAssertTrue(FileManager.default.fileExists(atPath: deployed.path))

            XCTAssertTrue(model.uninstallSkillsSh(hit))

            XCTAssertFalse(model.snapshot.catalog.entries.contains { $0.id == entry.id })
            XCTAssertNil(model.sourceOrigins[entry.id])
            XCTAssertTrue(FileManager.default.fileExists(atPath: package.appendingPathComponent("SKILL.md").path))
            XCTAssertEqual(
                try String(contentsOf: deployed.appendingPathComponent("SKILL.md"), encoding: .utf8),
                Self.document(name: "review-demo")
            )
        }
    }

    func testUninstallRejectsAmbiguousInstalledMatchesWithoutRemovingEither() throws {
        try withLibraryFixture(
            packages: [("skills/react-a", "react"), ("skills/react-b", "react")],
            deployFirstToProject: false
        ) { model, _, entries, hit, packages, _ in
            XCTAssertEqual(entries.count, 2)
            XCTAssertNil(model.installedSkillsShEntry(for: hit))

            XCTAssertFalse(model.uninstallSkillsSh(hit))

            XCTAssertEqual(
                model.skillsShError,
                L10n.tr("技能库中有多个已安装技能匹配这个目录条目，请先在技能库中核对再卸载。")
            )
            for entry in entries {
                XCTAssertTrue(model.snapshot.catalog.entries.contains { $0.id == entry.id })
            }
            for package in packages {
                XCTAssertTrue(FileManager.default.fileExists(atPath: package.appendingPathComponent("SKILL.md").path))
            }
        }
    }

    func testRenamingImportedSkillDoesNotClaimOrUninstallAnotherDirectorySkill() throws {
        try withLibraryFixture(packages: [("skills/review-demo", "review-demo")], deployFirstToProject: false) {
            model, paths, entries, originalHit, _, _ in
            let entry = try XCTUnwrap(entries.first)
            var editor = try XCTUnwrap(model.editorDraft(for: entry))
            editor.document = Self.document(name: "other-review")
            XCTAssertTrue(model.saveSkill(editor), model.libraryError ?? "")
            let otherHit = SkillsShHit(id: "fixture/skills/other-review", source: "fixture/skills",
                                      skillId: "other-review", name: "other-review", installs: 1)
            // 重新启动也应使用持久化的来源身份，而不是编辑后的显示名称。
            let restarted = AppModel(runtimePaths: paths)
            XCTAssertEqual(restarted.sourceOrigins[entry.id]?.declaredName, "review-demo")
            XCTAssertEqual(restarted.installedSkillsShEntry(for: originalHit)?.id, entry.id)
            XCTAssertNil(restarted.installedSkillsShEntry(for: otherHit))
            XCTAssertFalse(restarted.uninstallSkillsSh(otherHit))
            XCTAssertTrue(restarted.snapshot.catalog.entries.contains { $0.id == entry.id })
            XCTAssertTrue(restarted.uninstallSkillsSh(originalHit))
            XCTAssertFalse(restarted.snapshot.catalog.entries.contains { $0.id == entry.id })
        }
    }

    func testLegacyOriginWithoutOriginalNameDoesNotUseEditedMetadataForUninstall() throws {
        try withLibraryFixture(packages: [("skills/review-demo", "review-demo")], deployFirstToProject: false) {
            model, paths, entries, originalHit, _, _ in
            let entry = try XCTUnwrap(entries.first)
            var editor = try XCTUnwrap(model.editorDraft(for: entry))
            editor.document = Self.document(name: "other-review")
            XCTAssertTrue(model.saveSkill(editor), model.libraryError ?? "")
            let indexURL = paths.libraryRoot.appendingPathComponent("index.json")
            var index = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any])
            var records = try XCTUnwrap(index["records"] as? [[String: Any]])
            for offset in records.indices {
                var origin = try XCTUnwrap(records[offset]["sourceOrigin"] as? [String: Any])
                origin.removeValue(forKey: "declaredName")
                records[offset]["sourceOrigin"] = origin
            }
            index["records"] = records
            try JSONSerialization.data(withJSONObject: index).write(to: indexURL, options: .atomic)
            let restarted = AppModel(runtimePaths: paths)
            let otherHit = SkillsShHit(id: "fixture/skills/other-review", source: "fixture/skills",
                                      skillId: "other-review", name: "other-review", installs: 1)
            XCTAssertNil(restarted.sourceOrigins[entry.id]?.declaredName)
            XCTAssertEqual(restarted.installedSkillsShEntry(for: originalHit)?.id, entry.id)
            XCTAssertNil(restarted.installedSkillsShEntry(for: otherHit))
            XCTAssertFalse(restarted.uninstallSkillsSh(otherHit))
            XCTAssertTrue(restarted.snapshot.catalog.entries.contains { $0.id == entry.id })
        }
    }

    func testBrowserSheetFitsMinimumWindowInBothAppearancesWithResults() async throws {
        try await withIsolatedModel(client: SkillsShDirectoryClient { _ in (Self.searchResponse, 200) }) { model in
            model.skillsShQuery = "react"
            await model.searchSkillsSh()
            let controller = NSHostingController(rootView: SkillsShBrowserSheet(model: model))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 680),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentViewController = controller
            window.setContentSize(NSSize(width: 820, height: 680))
            window.orderFront(nil)
            defer { window.close() }

            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: appearance)
                try await Task.sleep(for: .milliseconds(120))
                controller.view.layoutSubtreeIfNeeded()
                XCTAssertLessThanOrEqual(controller.view.fittingSize.width, 821)
                XCTAssertLessThanOrEqual(controller.view.fittingSize.height, 681)
            }
        }
    }

    private func withIsolatedModel(
        client: SkillsShDirectoryClient,
        body: (AppModel) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skills-sh-app-\(UUID())")
        let keys = ["CFFIXED_USER_HOME", "SKILLSET_HOME", "CODEX_HOME"]
        let saved = ProcessInfo.processInfo.environment
        for key in keys { setenv(key, root.appendingPathComponent(key).path, 1) }
        defer {
            for key in keys {
                if let value = saved[key] { setenv(key, value, 1) }
                else { unsetenv(key) }
            }
            try? FileManager.default.removeItem(at: root)
        }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        try await body(AppModel(runtimePaths: paths, skillsShClient: client))
    }

    private func withLibraryFixture(
        packages: [(path: String, name: String)],
        deployFirstToProject: Bool,
        body: (AppModel, SkillSetRuntimePaths, [SkillEntry], SkillsShHit, [URL], URL?) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("skills-sh-library-\(UUID())")
        let keys = ["CFFIXED_USER_HOME", "SKILLSET_HOME", "CODEX_HOME", "SKILLSET_REPOSITORY_LIBRARY"]
        let saved = ProcessInfo.processInfo.environment
        for key in keys { setenv(key, root.appendingPathComponent(key).path, 1) }
        setenv("SKILLSET_REPOSITORY_LIBRARY", "0", 1)
        defer {
            for key in keys {
                if let value = saved[key] { setenv(key, value, 1) }
                else { unsetenv(key) }
            }
            try? FileManager.default.removeItem(at: root)
        }

        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let previewID = UUID()
        let checkout = paths.previewsRoot.appendingPathComponent(previewID.uuidString).appendingPathComponent("checkout")
        var candidates: [SourceSkillCandidate] = []
        for package in packages {
            let directory = checkout.appendingPathComponent(package.path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.document(name: package.name).write(
                to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
            )
            let analysis = try SkillAssetCopier.analyze(from: directory)
            let slug = (package.path as NSString).lastPathComponent
            candidates.append(SourceSkillCandidate(
                id: "fixture-skills/\(slug)", path: package.path, slug: slug,
                declaredName: package.name, description: "Fixture", category: "other",
                state: .other, contentHash: analysis.contentHash, fileCount: analysis.files.count,
                bytes: analysis.bytes, issues: []
            ))
        }
        let record = SourcePreviewRecord(
            id: previewID, inputURL: "https://github.com/fixture/skills",
            canonicalURL: "https://github.com/fixture/skills", namespace: "fixture-skills",
            resolvedCommit: String(repeating: "b", count: 40), createdAt: Date(),
            workspacePath: checkout.path, licenseEvidence: "", candidates: candidates,
            excludedCounts: ["other": candidates.count], warnings: []
        )
        try SourcePreviewStore(rootURL: paths.previewsRoot).save(record)

        let service = try SkillSetService(paths: paths)
        var entries: [SkillEntry] = []
        for candidate in candidates {
            let draft = try service.sourceSkillImportDraft(previewID: previewID, path: candidate.path)
            entries.append(try service.importSourceSkill(draft))
        }
        // 与真实目录安装一致：导入完成后删除临时预览，避免初始化同步再生成同源条目。
        try SourcePreviewStore(rootURL: paths.previewsRoot).remove(previewID)

        var deployed: URL?
        if deployFirstToProject, let first = entries.first {
            let project = root.appendingPathComponent("project")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let registration = try ProjectStore(rootURL: paths.applicationSupportRoot).register(path: project)
            // 部署服务必须重新读取导入后的技能库，不能复用导入前的目录快照。
            let deploymentService = try SkillSetService(paths: paths)
            let plan = try deploymentService.makePlan(
                projectID: registration.id, skillIDs: [first.id], instructionIDs: [], agents: ["codex"]
            )
            _ = try deploymentService.approve(planID: plan.id, digest: plan.plan.digest)
            _ = try deploymentService.apply(planID: plan.id, digest: plan.plan.digest)
            deployed = project.appendingPathComponent(".agents/skills/\(first.slug)")
        }

        let store = SkillLibraryStore(rootURL: paths.libraryRoot)
        let packageURLs = entries.compactMap { try? store.sourceURLs()[$0.id] }
        let hit = SkillsShHit(
            id: "fixture/skills/\(packages[0].name)", source: "fixture/skills",
            skillId: packages[0].name, name: packages[0].name, installs: 10
        )
        try body(AppModel(runtimePaths: paths), paths, entries, hit, packageURLs, deployed)
    }

    private static func document(name: String) -> String {
        "---\nname: \(name)\ndescription: Fixture skill\n---\n\n# \(name)\n"
    }

    nonisolated private static let searchResponse = Data(#"""
    {"skills":[{"id":"fixture/skills/react-review","source":"fixture/skills","skillId":"react-review","name":"react-review","installs":7}]}
    """#.utf8)
}
