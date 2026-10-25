import Foundation
import Testing
@testable import SkillSetCore

struct ProjectInstallationTests {
    @Test func installationAfterRemovingLastHarnessUsesDefaultTargetAndRejectsExplicitEmptyTargets() throws {
        let fixture = try InstallationFixture()
        defer { fixture.cleanup() }
        let first = try fixture.saveSkill("first")
        let second = try fixture.saveSkill("second")
        let service = try SkillSetService(paths: fixture.paths, globalLocations: .init(home: fixture.root.appendingPathComponent("home"), stateRoot: fixture.paths.applicationSupportRoot))
        let initial = try service.makeInstallationPlan(projectID: fixture.registration.id, skillIDs: [first.id], agents: ["codex"])
        _ = try service.approve(planID: initial.id, digest: initial.plan.digest)
        _ = try service.apply(planID: initial.id, digest: initial.plan.digest)
        let removal = try service.makeHarnessPlan(projectID: fixture.registration.id, agent: "codex", selection: nil)
        _ = try service.approve(planID: removal.id, digest: removal.plan.digest)
        _ = try service.apply(planID: removal.id, digest: removal.plan.digest)
        #expect(!FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent(".agents/skills/first").path))

        #expect(throws: ProjectLockError.self) {
            try service.makeInstallationPlan(projectID: fixture.registration.id, skillIDs: [second.id], agents: [])
        }
        #expect(try service.pendingPlans().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent(".agents/skills/second").path))

        let next = try service.makeInstallationPlan(projectID: fixture.registration.id, skillIDs: [second.id])
        _ = try service.approve(planID: next.id, digest: next.plan.digest)
        _ = try service.apply(planID: next.id, digest: next.plan.digest)
        #expect(try String(contentsOf: fixture.project.appendingPathComponent(".agents/skills/second/SKILL.md"), encoding: .utf8).contains("name: second"))
        #expect(!FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent(".claude/skills/second").path))
        let manifest = try #require(try ProjectLockStore(projectRoot: fixture.project, stateRoot: fixture.paths.applicationSupportRoot).loadManifest())
        #expect(manifest.agents == ["codex"])
        #expect(manifest.selection(for: "codex").skillIDs == [second.id])
    }

    @Test func installsSkillsThenPresetWithoutRemovingExistingSkillsRulesOrHosts() throws {
        let fixture = try InstallationFixture()
        defer { fixture.cleanup() }
        let first = try fixture.saveSkill("first")
        let second = try fixture.saveSkill("second")
        // 正常用户库从空片段开始，安装测试显式建立自己的规则输入。
        let rule = TemplateRecord(id: "installation-rule", title: "安装规则", body: "安装后核对当前工具的配置。", purpose: "安装测试夹具", isLocal: true)
        _ = try TemplateStore(rootURL: fixture.paths.applicationSupportRoot).save(rule, initial: [])
        let service = try SkillSetService(paths: fixture.paths, globalLocations: .init(home: fixture.root.appendingPathComponent("home"), stateRoot: fixture.paths.applicationSupportRoot))
        let initial = try service.makeInstallationPlan(projectPath: fixture.project.path, skillIDs: [first.id], agents: ["codex"])
        #expect(throws: DeploymentPlanStoreError.self) {
            try service.apply(planID: initial.id, digest: initial.plan.digest)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.project.path).isEmpty)
        _ = try service.approve(planID: initial.id, digest: initial.plan.digest)
        _ = try service.apply(planID: initial.id, digest: initial.plan.digest)

        let preset = PresetRecord(id: "review", name: "审查组合", skills: [second.id], instructionFragments: [rule.id])
        _ = try fixture.presets.save(preset, initial: [])
        // 不重启服务，查询与安装都应采用 UI 刚保存的本机预设。
        #expect(try service.presets(query: "审查").map(\.id) == [preset.id])
        let expanded = try service.makeInstallationPlan(projectID: fixture.registration.id, presetID: preset.id, agents: ["claude-code"])
        #expect(!FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent(".claude/skills/second").path))
        _ = try service.approve(planID: expanded.id, digest: expanded.plan.digest)
        _ = try service.apply(planID: expanded.id, digest: expanded.plan.digest)
        let manifest = try #require(try ProjectLockStore(projectRoot: fixture.project, stateRoot: fixture.paths.applicationSupportRoot).loadManifest())
        #expect(manifest.skills == [first.id, second.id])
        #expect(manifest.agents == ["claude-code", "codex"])
        #expect(manifest.instructions == [rule.id])
        #expect(try String(contentsOf: fixture.project.appendingPathComponent(".agents/skills/first/SKILL.md"), encoding: .utf8).contains("name: first"))
        #expect(try String(contentsOf: fixture.project.appendingPathComponent(".claude/skills/second/SKILL.md"), encoding: .utf8).contains("name: second"))
        #expect(!FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent(".agents/skills/second").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent(".claude/skills/first").path))
        #expect(manifest.selection(for: "codex").instructionIDs.isEmpty)
        #expect(manifest.selection(for: "claude-code").instructionIDs == [rule.id])
        #expect(try String(contentsOf: fixture.project.appendingPathComponent("CLAUDE.md"), encoding: .utf8).contains(rule.body))
        #expect(!FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent("AGENTS.md").path))
    }

    @Test func rejectsMissingAmbiguousUnregisteredTargetsAndUnknownPresetsWithoutPlans() throws {
        let fixture = try InstallationFixture()
        defer { fixture.cleanup() }
        let service = try SkillSetService(paths: fixture.paths, globalLocations: .init(home: fixture.root.appendingPathComponent("home"), stateRoot: fixture.paths.applicationSupportRoot))
        for arguments: (UUID?, String?) in [(nil, nil), (fixture.registration.id, fixture.project.path), (nil, "relative")] {
            #expect(throws: ProjectInstallationError.self) {
                try service.makeInstallationPlan(projectID: arguments.0, projectPath: arguments.1, skillIDs: ["personal/demo"])
            }
        }
        #expect(throws: ProjectInstallationError.self) {
            try service.makeInstallationPlan(projectPath: fixture.root.path, skillIDs: ["personal/demo"])
        }
        #expect(try ProjectStore(rootURL: fixture.paths.applicationSupportRoot).list().count == 1)
        #expect(throws: ProjectInstallationError.self) {
            try service.makeInstallationPlan(projectID: fixture.registration.id, presetID: "missing")
        }
        #expect(try service.pendingPlans().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.project.path).isEmpty)
    }

    @Test func listsLocalOverrideAndRefusesToSilentlySkipMixedPresetComponents() throws {
        let fixture = try InstallationFixture()
        defer { fixture.cleanup() }
        let skill = try fixture.saveSkill("demo")
        _ = try fixture.presets.save(PresetRecord(id: "personal-base", name: "本机组合", skills: [skill.id]), initial: [])
        let service = try SkillSetService(paths: fixture.paths, globalLocations: .init(home: fixture.root.appendingPathComponent("home"), stateRoot: fixture.paths.applicationSupportRoot))
        let override = try service.presets().filter { $0.id == "personal-base" }
        #expect(override.count == 1)
        #expect(override.first?.name == "本机组合")
        let mixed = PresetRecord(id: "mixed", name: "混合组合", skills: [skill.id], mcpServers: [
            MCPConfigurationDraft(name: "fixture", host: .claudeCode, scope: .project, commandOrURL: "/usr/bin/true")
        ])
        _ = try fixture.presets.save(mixed, initial: [])
        #expect(throws: ProjectInstallationError.self) {
            try service.makeInstallationPlan(projectID: fixture.registration.id, presetID: mixed.id)
        }
        #expect(try service.pendingPlans().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent(".mcp.json").path))
    }
}

private struct InstallationFixture {
    let root: URL
    let project: URL
    let paths: SkillSetRuntimePaths
    let registration: ProjectRegistration
    var presets: PresetStore { PresetStore(rootURL: paths.applicationSupportRoot) }

    init() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("perch-install-\(UUID())")
        project = root.appendingPathComponent("project with spaces")
        paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        registration = try ProjectStore(rootURL: paths.applicationSupportRoot).register(path: project)
    }

    func saveSkill(_ slug: String) throws -> SkillEntry {
        try paths.makeLibraryStore(home: root.appendingPathComponent("home")).save(
            SkillEditorDraft(slug: slug, document: "---\nname: \(slug)\ndescription: 用于验证项目安装\n---\n\n# \(slug)\n"), repositoryRoot: nil
        )
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
