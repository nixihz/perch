import Foundation
import XCTest
import SkillSetCore

@MainActor
final class SourceImportWorkflowUITests: XCTestCase {
    func testSynchronizedSourceAppearsInLibraryAndProjectPlan() throws {
        guard NativeUIHarness.canRunInCurrentEnvironment else { throw XCTSkip(NativeUIHarness.unavailableReason) }
        let world = try BDDWorld()
        defer { world.cleanup() }
        try world.registerProject(named: "source-import-ui")
        let state = world.temporaryRoot.appendingPathComponent("native-ui/home/.perch")
        let previewID = UUID()
        let previewRoot = state.appendingPathComponent("cache/sources")
        let checkout = previewRoot.appendingPathComponent(previewID.uuidString).appendingPathComponent("checkout")
        let package = checkout.appendingPathComponent("skills/import-ui")
        try FileManager.default.createDirectory(at: package.appendingPathComponent("references"), withIntermediateDirectories: true)
        try "---\nname: import-ui\ndescription: Source import UI fixture\n---\n\n# 来源界面测试正文\n".write(to: package.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "Reference file".write(to: package.appendingPathComponent("references/guide.md"), atomically: true, encoding: .utf8)
        let analysis = try SkillAssetCopier.analyze(from: package)
        let candidate = SourceSkillCandidate(id: "fixture/import-ui", path: "skills/import-ui", slug: "import-ui", declaredName: "import-ui", description: "Source import UI fixture", category: "other", state: .other, contentHash: analysis.contentHash, fileCount: 2, bytes: analysis.bytes, issues: [])
        let preview = SourcePreviewRecord(id: previewID, inputURL: "https://github.com/fixture/source-import", canonicalURL: "https://github.com/fixture/source-import", namespace: "fixture-source-import", resolvedCommit: String(repeating: "c", count: 40), createdAt: Date(), workspacePath: checkout.path, licenseEvidence: "", candidates: [candidate], excludedCounts: ["other": 1], warnings: [])
        try SourcePreviewStore(rootURL: previewRoot).save(preview)
        try world.launchNativeUI()
        let ui = try XCTUnwrap(world.nativeUI)
        // 来源技能要显式加入技能库，加入后来源列表显示"在技能库查看"。
        try ui.selectSidebarItem("技能来源")
        try ui.pressButton(identifier: "sources.preview.\(previewID.uuidString)")
        try ui.pressButton(identifier: "sources.import.skills/import-ui")
        try ui.waitForButton("加入技能库")
        try ui.pressButton(identifier: "sources.import.confirm")
        try ui.waitForButton("在技能库查看")
        try ui.captureWindowScreenshot(to: URL(fileURLWithPath: "/tmp/skillset-source-import-review.png"))
        try ui.pressButton(identifier: "sources.import.projects")
        let library = SkillSetRuntimePaths(applicationSupportRoot: state, repositoryRoot: nil)
            .makeLibraryStore()
        let importedID = try XCTUnwrap(
            try library.sourceURLs().keys.first { $0 == "import-ui" },
            "加入技能库后应能在技能库找到 import-ui"
        )
        // 技能库里能搜到这条技能。
        try ui.selectSidebarItem("技能库")
        try ui.setText(fieldMatching: "skills.search", to: "import-ui")
        try ui.waitForStaticText(containing: "import-ui")
        try ui.selectSidebarItem("技能来源")
        try ui.pressButton(identifier: "sources.preview.\(previewID.uuidString)")
        XCTAssertTrue(try ui.hasEnabledButton("在技能库查看"))
        XCTAssertFalse(try ui.hasEnabledButton("加入技能库…"))
        try ui.selectSidebarItem("项目")
        try ui.setText(fieldMatching: "projects.search", to: "import-ui")
        try ui.pressButton(identifier: "projects.skill.\(importedID).codex")
        try ui.previewDeploymentPlan()
        let plan = try ui.waitForSinglePlan()
        XCTAssertTrue(plan.plan.changes.contains { $0.relativePath.contains("import-ui") })
        try ui.pressEscapeToCancelPlan()
        let registration = try XCTUnwrap(ProjectStore(rootURL: state).list().first)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: registration.canonicalPath).isEmpty)
    }
}
