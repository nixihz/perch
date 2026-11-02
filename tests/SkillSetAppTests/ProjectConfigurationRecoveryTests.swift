import AppKit
import SwiftUI
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class ProjectConfigurationRecoveryTests: XCTestCase {
    func testImmediateSkillAndRuleSaveReadsExternalChangesForBothHostsAndInstallMethods() async throws {
        for method in [SkillInstallMethod.copy, .symlink] {
            for host in MCPHost.allCases {
                let fixture = try Fixture(method: method)
                defer { fixture.remove() }
                let skill = try XCTUnwrap(fixture.model.snapshot.catalog.entries.first)
                try fixture.updateSource("保存前磁盘最新正文")

                let saved = await fixture.model.saveProjectSkill(skill, enabled: true, host: host)

                XCTAssertTrue(saved, fixture.model.lastAction)
                let installed = fixture.installedSkill(host)
                XCTAssertTrue(try String(contentsOf: installed.appendingPathComponent("SKILL.md"), encoding: .utf8).contains("保存前磁盘最新正文"))
                XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installed.appendingPathComponent("scripts/run.sh").path))
                try fixture.updateSource("保存规则时的最新技能正文")
                let updatedRule = TemplateRecord(id: fixture.rule.id, title: fixture.rule.title,
                    body: "磁盘上改过的规则", purpose: fixture.rule.purpose, isLocal: true)
                _ = try TemplateStore(rootURL: fixture.paths.applicationSupportRoot).save(updatedRule, initial: [])

                let ruleSaved = await fixture.model.saveProjectInstruction(fixture.rule, enabled: true, host: host)

                XCTAssertTrue(ruleSaved, fixture.model.lastAction)
                XCTAssertTrue(try String(contentsOf: installed.appendingPathComponent("SKILL.md"), encoding: .utf8).contains("保存规则时的最新技能正文"))
                XCTAssertTrue(try String(contentsOf: fixture.rulesURL(host), encoding: .utf8).contains(updatedRule.body))
                XCTAssertNil(fixture.model.projectPlanNotice(for: fixture.model.selectedProjectID))
            }
        }
    }

    func testRuleSaveRecoversMissingSourceWithoutReSelectingInstalledSkill() async throws {
        for host in MCPHost.allCases {
            let fixture = try Fixture(method: .symlink)
            defer { fixture.remove() }
            let skill = try XCTUnwrap(fixture.model.snapshot.catalog.entries.first)
            try fixture.updateSource("来源丢失前的最后正文")
            let installed = await fixture.model.saveProjectSkill(skill, enabled: true, host: host)
            XCTAssertTrue(installed, fixture.model.lastAction)
            try FileManager.default.removeItem(at: fixture.source)

            let saved = await fixture.model.saveProjectInstruction(fixture.rule, enabled: true, host: host)

            XCTAssertTrue(saved, fixture.model.lastAction)
            XCTAssertTrue(fixture.model.isDraftSelected(skill, host: host))
            XCTAssertTrue(try String(contentsOf: fixture.installedSkill(host).appendingPathComponent("SKILL.md"), encoding: .utf8).contains("来源丢失前的最后正文"))
            XCTAssertTrue(try String(contentsOf: fixture.rulesURL(host), encoding: .utf8).contains(fixture.rule.body))
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))
        }
    }

    func testPreviewRefreshesChangedSourceAndKeepsHostDraftAndInstallMethod() async throws {
        let previousLanguage = AppPreferences.shared.language
        AppPreferences.shared.language = .chinese
        defer { AppPreferences.shared.language = previousLanguage }
        for method in [SkillInstallMethod.copy, .symlink] {
            for host in MCPHost.allCases {
                let fixture = try Fixture(method: method)
                defer { fixture.remove() }
                let model = fixture.model
                let skill = try XCTUnwrap(model.snapshot.catalog.entries.first)
                let otherHost: MCPHost = host == .codex ? .claudeCode : .codex
                model.setInstruction(fixture.rule.id, enabled: true, host: otherHost)
                model.setSkill(skill, enabled: true, host: host)
                try fixture.updateSource("预览前的新内容")
                model.prepareDeploymentPlan(host: host)
                let originalPlan = try XCTUnwrap(model.preparedPlan, model.lastAction)
                try fixture.updateSource("预览后的最新内容")

                XCTAssertFalse(model.approveAndApplyPreparedPlan())

                let refreshed = try XCTUnwrap(model.preparedPlan, model.lastAction)
                XCTAssertNotEqual(refreshed.id, originalPlan.id)
                XCTAssertEqual(refreshed.approvalState, .pending)
                XCTAssertTrue(model.planPresented)
                XCTAssertEqual(model.planError, L10n.tr("已按本机最新状态更新预览，请核对后保存。"))
                XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.installedSkill(host).path))
                if method == .copy && host == .codex {
                    try await capturePreview(model, name: "perch-project-source-recovery")
                }

                XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.planError ?? model.lastAction)

                let installed = fixture.installedSkill(host)
                XCTAssertTrue(try String(contentsOf: installed.appendingPathComponent("SKILL.md"), encoding: .utf8).contains("预览后的最新内容"))
                XCTAssertEqual((try? FileManager.default.destinationOfSymbolicLink(atPath: installed.path)) != nil, method == .symlink)
                XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.rulesURL(otherHost).path))
                XCTAssertEqual(model.selectedProject?.harnessSelections[otherHost.rawValue]?.instructionIDs, [fixture.rule.id])
            }
        }
    }

    func testPreviewRefreshesChangedTargetAndPreservesLocalRules() throws {
        let fixture = try Fixture(method: .copy)
        defer { fixture.remove() }
        let model = fixture.model
        model.setInstruction(fixture.rule.id, enabled: true, host: .codex)
        model.prepareDeploymentPlan(host: .codex)
        let rules = fixture.rulesURL(.codex)
        try "用户在预览后补充的项目约定\n".write(to: rules, atomically: true, encoding: .utf8)

        XCTAssertFalse(model.approveAndApplyPreparedPlan())
        XCTAssertTrue(model.planPresented)
        XCTAssertTrue(model.approveAndApplyPreparedPlan(), model.planError ?? model.lastAction)

        let actual = try String(contentsOf: rules, encoding: .utf8)
        XCTAssertTrue(actual.contains("用户在预览后补充的项目约定"))
        XCTAssertTrue(actual.contains(fixture.rule.body))
    }

    func testUnavailableSourceWithoutSnapshotPreservesFilesAndOriginalSelection() async throws {
        let fixture = try Fixture(method: .copy)
        defer { fixture.remove() }
        let skill = try XCTUnwrap(fixture.model.snapshot.catalog.entries.first)
        let rules = fixture.rulesURL(.codex)
        try "本机原有规则".write(to: rules, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: fixture.source)

        let saved = await fixture.model.saveProjectSkill(skill, enabled: true, host: .codex)

        XCTAssertFalse(saved)
        XCTAssertFalse(fixture.model.isDraftSelected(skill, host: .codex))
        XCTAssertEqual(try String(contentsOf: rules, encoding: .utf8), "本机原有规则")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.installedSkill(.codex).path))
        let message = try XCTUnwrap(fixture.model.projectPlanNotice(for: fixture.model.selectedProjectID)?.message)
        XCTAssertTrue(message.contains("没有可恢复的本机副本"), message)
        XCTAssertFalse(message.contains("请检查"), message)
    }

    private func capturePreview(_ model: AppModel, name: String) async throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let controller = NSHostingController(rootView: PlanSheet(model: model, savesFromPreview: true)
                .background(Color(nsColor: .windowBackgroundColor)))
            controller.view.frame = NSRect(x: 0, y: 0, width: 1080, height: 700)
            let window = NSWindow(contentRect: controller.view.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = controller
            window.appearance = NSAppearance(named: appearance)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(150))
            controller.view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
            controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
                URL(fileURLWithPath: "/tmp/\(name)-\(appearance == .aqua ? "light" : "dark").png"))
        }
    }

    @MainActor
    private struct Fixture {
        let root: URL
        let paths: SkillSetRuntimePaths
        let project: URL
        let source: URL
        let rule: TemplateRecord
        let model: AppModel

        init(method: SkillInstallMethod) throws {
            root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("project-recovery-ui-\(UUID())")
            paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
            project = root.appendingPathComponent("project")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let library = paths.makeLibraryStore()
            _ = try library.save(SkillEditorDraft(slug: "recovery", document: "---\nname: recovery\ndescription: 来源恢复\n---\n启动时正文"), repositoryRoot: nil)
            source = try XCTUnwrap(try library.loadLibrary().packageURLs["recovery"])
            rule = TemplateRecord(title: "项目规则", body: "保存前运行相关检查。", purpose: "来源恢复验证")
            _ = try TemplateStore(rootURL: paths.applicationSupportRoot).save(rule, initial: [])
            model = AppModel(runtimePaths: paths, globalLocations: .init(home: root.appendingPathComponent("home"), stateRoot: paths.applicationSupportRoot))
            model.skillInstallMethod = method
            XCTAssertTrue(model.registerProject(project))
        }

        func installedSkill(_ host: MCPHost) -> URL {
            project.appendingPathComponent("\(host == .codex ? ".agents" : ".claude")/skills/recovery")
        }

        func rulesURL(_ host: MCPHost) -> URL { project.appendingPathComponent(host == .codex ? "AGENTS.md" : "CLAUDE.md") }

        func updateSource(_ body: String) throws {
            try "---\nname: recovery\ndescription: 来源恢复\n---\n\(body)".write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            let script = source.appendingPathComponent("scripts/run.sh")
            try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "#!/bin/sh\nprintf 'current'\n".write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
