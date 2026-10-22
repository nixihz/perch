import Foundation
import Testing
@testable import SkillSetCore

struct ProjectHarnessTests {
    @Test func singleTargetRequestMigratesSharedManifestWithoutRemovingOtherHarnessAndCleansRejectedStaging() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("legacy-harness-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let registration = try ProjectStore(rootURL: paths.applicationSupportRoot).register(path: project)
        let library = SkillLibraryStore(rootURL: paths.libraryRoot)
        let first = try library.save(SkillEditorDraft(slug: "first", document: "---\nname: first\ndescription: 原共享技能\n---\n第一份正文"), repositoryRoot: nil)
        let second = try library.save(SkillEditorDraft(slug: "second", document: "---\nname: second\ndescription: Codex 新技能\n---\n第二份正文"), repositoryRoot: nil)
        let rule = TemplateRecord(id: "legacy-rule", title: "原共享规则", body: "保留 Claude 的原规则。", purpose: "兼容验证", isLocal: true)
        _ = try TemplateStore(rootURL: paths.applicationSupportRoot).save(rule, initial: [])
        let service = try SkillSetService(paths: paths)
        let initial = try service.makePlan(projectID: registration.id, skillIDs: [first.id], instructionIDs: [rule.id],
            agents: ["codex", "claude-code"], installMethod: .copy)
        _ = try service.approve(planID: initial.id, digest: initial.plan.digest)
        _ = try service.apply(planID: initial.id, digest: initial.plan.digest)
        let state = ProjectLockStore(projectRoot: project, stateRoot: paths.applicationSupportRoot)
        #expect(try state.loadManifest()?.harnessSelections == nil)
        let claudeSkill = try Data(contentsOf: project.appendingPathComponent(".claude/skills/first/SKILL.md"))
        let claudeRules = try Data(contentsOf: project.appendingPathComponent("CLAUDE.md"))
        let codexRules = try Data(contentsOf: project.appendingPathComponent("AGENTS.md"))
        let stagingBefore = Set(try FileManager.default.contentsOfDirectory(atPath: paths.stagingRoot.path))

        // 新安装方式会改动另一宿主时，旧共享格式也必须在保存计划前拒绝。
        #expect(throws: SkillSetServiceError.otherHarnessChanges) {
            try service.makePlan(projectID: registration.id, skillIDs: [second.id], instructionIDs: [],
                agents: ["codex"], installMethod: .symlink)
        }
        #expect(try service.pendingPlans().isEmpty)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: paths.stagingRoot.path)) == stagingBefore)
        #expect(try Data(contentsOf: project.appendingPathComponent("AGENTS.md")) == codexRules)
        #expect(!FileManager.default.fileExists(atPath: project.appendingPathComponent(".agents/skills/second").path))

        let next = try service.makePlan(projectID: registration.id, skillIDs: [second.id], instructionIDs: [],
            agents: ["codex"], installMethod: .copy)
        #expect(!next.plan.changes.contains { $0.relativePath == "CLAUDE.md" || $0.relativePath.hasPrefix(".claude/") })
        _ = try service.approve(planID: next.id, digest: next.plan.digest)
        _ = try service.apply(planID: next.id, digest: next.plan.digest)
        #expect(try Data(contentsOf: project.appendingPathComponent(".claude/skills/first/SKILL.md")) == claudeSkill)
        #expect(try Data(contentsOf: project.appendingPathComponent("CLAUDE.md")) == claudeRules)
        #expect(!FileManager.default.fileExists(atPath: project.appendingPathComponent(".agents/skills/first").path))
        #expect(try String(contentsOf: project.appendingPathComponent(".agents/skills/second/SKILL.md"), encoding: .utf8).contains("第二份正文"))
        #expect(try ManagedBlocks.extract(original: String(contentsOf: project.appendingPathComponent("AGENTS.md"), encoding: .utf8), id: "project-rules") == nil)
        let migrated = try #require(try state.loadManifest())
        #expect(migrated.selection(for: "claude-code").skillIDs == [first.id])
        #expect(migrated.selection(for: "claude-code").instructionIDs == [rule.id])
        #expect(migrated.selection(for: "codex").skillIDs == [second.id])
        try #require(try state.loadLock()).validate(against: migrated)
    }

    @Test func legacySharedDraftLoadsIntoIndependentSelectionsWithoutLosingContent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-draft-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let projectID = UUID()
        let data = Data("""
        {"schemaVersion":1,"drafts":[{"projectID":"\(projectID)","skillIDs":["workspace/demo"],"instructionIDs":["base"],"agents":["claude-code","codex"],"updatedAt":"2026-10-23T00:00:00Z"}]}
        """.utf8)
        let store = ProjectDraftStore(rootURL: root)
        try data.write(to: store.documentURL)
        let draft = try #require(try store.load(projectID: projectID))
        var selections = draft.resolvedHarnessSelections
        selections["claude-code"] = ProjectHarnessSelection(instructionIDs: ["claude"])
        try store.save(projectID: projectID, skillIDs: [], instructionIDs: [], agents: draft.agents,
                       harnessSelections: selections)
        let reloaded = try #require(try store.load(projectID: projectID))
        #expect(reloaded.resolvedHarnessSelections["codex"]?.skillIDs == ["workspace/demo"])
        #expect(reloaded.resolvedHarnessSelections["codex"]?.instructionIDs == ["base"])
        #expect(reloaded.resolvedHarnessSelections["claude-code"]?.skillIDs.isEmpty == true)
        #expect(Set(reloaded.instructionIDs) == ["base", "claude"])
    }

    @Test func approvedIndependentSelectionsWriteDistinctRulesAndRemovingFinalHostLeavesNoManagedFiles() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let planner = DeploymentPlanner(catalog: fixture.catalog, repositoryRoot: fixture.repository,
            stagingRoot: fixture.staging, operationsRoot: fixture.operations)
        let selections = [
            "codex": ProjectHarnessSelection(skillIDs: ["workspace/demo"], instructionIDs: ["base"]),
            "claude-code": ProjectHarnessSelection(instructionIDs: ["claude"])
        ]
        let plan = try planner.makePlan(projectPath: fixture.project,
            request: DeploymentRequest(agents: selections.keys.sorted(), harnessSelections: selections),
            fragments: ["base": "Codex 的规则", "claude": "Claude 的规则"])
        let executor = FileTransactionExecutor(operationsRoot: fixture.operations)
        _ = try executor.apply(plan: plan, from: fixture.staging.appendingPathComponent(plan.id.uuidString))
        #expect(try String(contentsOf: fixture.project.appendingPathComponent("AGENTS.md"), encoding: .utf8).contains("Codex 的规则"))
        #expect(try String(contentsOf: fixture.project.appendingPathComponent("CLAUDE.md"), encoding: .utf8).contains("Claude 的规则"))
        #expect(!FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent(".claude/skills/demo").path))
        let manifest = try #require(try fixture.stateStore.loadManifest())
        try #require(try fixture.stateStore.loadLock()).validate(against: manifest)
        let removal = try planner.makePlan(projectPath: fixture.project,
            request: DeploymentRequest(agents: [], harnessSelections: [:]), fragments: [:])
        _ = try executor.apply(plan: removal, from: fixture.staging.appendingPathComponent(removal.id.uuidString))
        #expect(!FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent(".agents/skills/demo").path))
        #expect(try ManagedBlocks.extract(original: String(contentsOf: fixture.project.appendingPathComponent("AGENTS.md"), encoding: .utf8), id: "project-rules") == nil)
        #expect(try fixture.stateStore.loadManifest()?.agents.isEmpty == true)
        #expect(throws: DeploymentError.noChanges) {
            try planner.makePlan(projectPath: fixture.project, request: DeploymentRequest(agents: [], harnessSelections: [:]), fragments: [:])
        }
    }

    @Test func singleHarnessPlanRejectsChangingAnotherHostsInstallMethodBeforeSavingPlan() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("harness-boundary-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let registration = try ProjectStore(rootURL: paths.applicationSupportRoot).register(path: project)
        let skill = try SkillLibraryStore(rootURL: paths.libraryRoot).save(
            SkillEditorDraft(slug: "first", document: "---\nname: first\ndescription: 独立宿主\n---\n正文"), repositoryRoot: nil)
        let service = try SkillSetService(paths: paths)
        let initial = try service.makeHarnessPlan(projectID: registration.id, agent: "codex",
            selection: ProjectHarnessSelection(skillIDs: [skill.id]), installMethod: .copy)
        _ = try service.approve(planID: initial.id, digest: initial.plan.digest)
        _ = try service.apply(planID: initial.id, digest: initial.plan.digest)
        let original = try Data(contentsOf: project.appendingPathComponent(".agents/skills/first/SKILL.md"))
        #expect(throws: SkillSetServiceError.otherHarnessChanges) {
            try service.makeHarnessPlan(projectID: registration.id, agent: "claude-code",
                selection: ProjectHarnessSelection(), installMethod: .symlink)
        }
        #expect(try service.pendingPlans().isEmpty)
        #expect(try Data(contentsOf: project.appendingPathComponent(".agents/skills/first/SKILL.md")) == original)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: project.appendingPathComponent(".agents/skills/first").path)) == nil)
    }
}
