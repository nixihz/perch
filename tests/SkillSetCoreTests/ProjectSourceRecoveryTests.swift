import Foundation
import Testing
@testable import SkillSetCore

struct ProjectSourceRecoveryTests {
    @Test(arguments: [SkillInstallMethod.copy, .symlink])
    func longLivedServicePlansCurrentSourceInsteadOfReusingOldObjects(method: SkillInstallMethod) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let service = try fixture.service()
        _ = try service.makeHarnessPlan(projectID: fixture.projectID, agent: "codex",
            selection: ProjectHarnessSelection(skillIDs: ["recovery"]), installMethod: method)
        try fixture.changeSource()

        let plan = try service.makeHarnessPlan(projectID: fixture.projectID, agent: "codex",
            selection: ProjectHarnessSelection(skillIDs: ["recovery"]), installMethod: method)
        try fixture.apply(plan, using: service)

        try fixture.expectCurrentContents(at: fixture.project.appendingPathComponent(".agents/skills/recovery"))
        let lock = try #require(try fixture.lockStore.loadLock())
        let actualHash = try SkillAssetCopier.analyze(from: fixture.source).contentHash
        #expect(lock.skills.first?.contentHash == actualHash)
    }

    @Test(arguments: [SkillInstallMethod.copy, .symlink])
    func missingSourceRecoversInstalledSelectionAfterRestartAndCanBeRemoved(method: SkillInstallMethod) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let service = try fixture.service()
        try fixture.changeSource()
        let initial = try service.makeHarnessPlan(projectID: fixture.projectID, agent: "codex",
            selection: ProjectHarnessSelection(skillIDs: ["recovery"]), installMethod: method)
        try fixture.apply(initial, using: service)
        try FileManager.default.removeItem(at: fixture.source)
        let restarted = try fixture.service()

        let recovered = try restarted.makeHarnessPlan(projectID: fixture.projectID, agent: "codex",
            selection: ProjectHarnessSelection(skillIDs: ["recovery"], instructionIDs: [fixture.rule.id]), installMethod: method)
        try fixture.apply(recovered, using: restarted)

        let target = fixture.project.appendingPathComponent(".agents/skills/recovery")
        try fixture.expectCurrentContents(at: target)
        #expect(try String(contentsOf: fixture.project.appendingPathComponent("AGENTS.md"), encoding: .utf8).contains(fixture.rule.body))
        #expect(!FileManager.default.fileExists(atPath: fixture.source.path))
        let removal = try restarted.makeHarnessPlan(projectID: fixture.projectID, agent: "codex",
            selection: ProjectHarnessSelection(instructionIDs: [fixture.rule.id]), installMethod: method)
        try fixture.apply(removal, using: restarted)
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: target.path)) == nil)
    }

    @Test func cancellingLibraryLinkAfterExternalUpdateDoesNotDeleteTheSource() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let service = try fixture.service()
        let initial = try service.makeHarnessPlan(projectID: fixture.projectID, agent: "codex",
            selection: ProjectHarnessSelection(skillIDs: ["recovery"]))
        try fixture.apply(initial, using: service)
        try fixture.changeSource()
        let removal = try service.makeHarnessPlan(projectID: fixture.projectID, agent: "codex", selection: ProjectHarnessSelection())
        try fixture.apply(removal, using: service)
        try fixture.expectCurrentContents(at: fixture.source)
        #expect(!FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent(".agents/skills/recovery").path))
    }

    private struct Fixture {
        let root: URL
        let paths: SkillSetRuntimePaths
        let project: URL
        let projectID: UUID
        let source: URL
        let rule: TemplateRecord

        var lockStore: ProjectLockStore { ProjectLockStore(projectRoot: project, stateRoot: paths.applicationSupportRoot) }

        init() throws {
            root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("project-source-\(UUID())")
            paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
            project = root.appendingPathComponent("project")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            projectID = try ProjectStore(rootURL: paths.applicationSupportRoot).register(path: project).id
            let library = paths.makeLibraryStore()
            _ = try library.save(SkillEditorDraft(slug: "recovery", document: "---\nname: recovery\ndescription: 来源恢复\n---\n旧正文"), repositoryRoot: nil)
            source = try #require(try library.loadLibrary().packageURLs["recovery"])
            rule = TemplateRecord(title: "恢复验证", body: "保存其他规则不应依赖旧技能来源。", purpose: "验证来源恢复")
            _ = try TemplateStore(rootURL: paths.applicationSupportRoot).save(rule, initial: [])
        }

        func service() throws -> SkillSetService {
            try SkillSetService(paths: paths, globalLocations: .init(home: root.appendingPathComponent("home"), stateRoot: paths.applicationSupportRoot))
        }

        func changeSource() throws {
            try "---\nname: recovery\ndescription: 来源恢复\n---\n磁盘上的新正文".write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            let script = source.appendingPathComponent("scripts/run.sh")
            try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "#!/bin/sh\nprintf 'current'\n".write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        }

        func expectCurrentContents(at target: URL) throws {
            #expect(try String(contentsOf: target.appendingPathComponent("SKILL.md"), encoding: .utf8).contains("磁盘上的新正文"))
            let script = target.appendingPathComponent("scripts/run.sh")
            #expect(try String(contentsOf: script, encoding: .utf8).contains("current"))
            #expect(FileManager.default.isExecutableFile(atPath: script.path))
        }

        func apply(_ plan: StoredDeploymentPlan, using service: SkillSetService) throws {
            _ = try service.approve(planID: plan.id, digest: plan.plan.digest)
            _ = try service.apply(planID: plan.id, digest: plan.plan.digest)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
