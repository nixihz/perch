import Foundation
import Testing
@testable import SkillSetCore

struct ProjectInstallationTests {
    @Test func installsSkillsThenPresetWithoutRemovingExistingSkillsRulesOrHosts() throws {
        let fixture = try InstallationFixture()
        defer { fixture.cleanup() }
        let first = try fixture.saveSkill("first")
        let second = try fixture.saveSkill("second")
        let service = try SkillSetService(paths: fixture.paths)
        let initial = try service.makeInstallationPlan(projectPath: fixture.project.path, skillIDs: [first.id], agents: ["codex"])
        #expect(throws: DeploymentPlanStoreError.self) {
            try service.apply(planID: initial.id, digest: initial.plan.digest)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.project.path).isEmpty)
        _ = try service.approve(planID: initial.id, digest: initial.plan.digest)
        _ = try service.apply(planID: initial.id, digest: initial.plan.digest)

        let preset = PresetRecord(id: "review", name: "审查组合", skills: [second.id], instructionFragments: ["base-zh"])
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
        #expect(manifest.instructions == ["base-zh"])
        for directory in [".agents", ".claude"] {
            for slug in ["first", "second"] {
                let document = try String(contentsOf: fixture.project.appendingPathComponent("\(directory)/skills/\(slug)/SKILL.md"), encoding: .utf8)
                #expect(document.contains("name: \(slug)"))
            }
        }
        #expect(try String(contentsOf: fixture.project.appendingPathComponent("CLAUDE.md"), encoding: .utf8).contains("skillset:begin"))
    }

    @Test func rejectsMissingAmbiguousUnregisteredTargetsAndUnknownPresetsWithoutPlans() throws {
        let fixture = try InstallationFixture()
        defer { fixture.cleanup() }
        let service = try SkillSetService(paths: fixture.paths)
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
        let service = try SkillSetService(paths: fixture.paths)
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
        try SkillLibraryStore(rootURL: paths.libraryRoot).save(
            SkillEditorDraft(slug: slug, document: "---\nname: \(slug)\ndescription: 用于验证项目安装\n---\n\n# \(slug)\n"), repositoryRoot: nil
        )
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
