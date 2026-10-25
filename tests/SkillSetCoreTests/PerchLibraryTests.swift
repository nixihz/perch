import Foundation
import Testing
@testable import SkillSetCore

struct PerchLibraryTests {
    @Test func emptyLibraryHasNoBuiltInSourcesOrSkills() throws {
        let fixture = try PerchFixture()
        defer { fixture.cleanup() }
        let service = try fixture.service()
        #expect(service.skills(query: "").isEmpty)
        #expect(service.snapshot.sources.sources.isEmpty)
        #expect(try service.sourcePreviews().isEmpty)
    }

    @Test func localSourceStaysOutOfTheLibraryUntilImportedAndDeploymentLinksToTheLibrary() throws {
        let fixture = try PerchFixture()
        defer { fixture.cleanup() }
        let preview = try fixture.service().previewSource(urlString: fixture.source.path)
        #expect(try fixture.service().skills(query: "demo").isEmpty)
        let entry = try fixture.importSkill(previewID: preview.id)
        let service = try fixture.service()
        #expect(service.skills(query: "demo").map(\.id) == [entry.id])
        let project = try fixture.register()
        let plan = try service.makePlan(projectID: project.id, skillIDs: [entry.id], instructionIDs: [], agents: ["codex", "claude-code"])
        #expect(throws: DeploymentPlanStoreError.self) { try service.apply(planID: plan.id, digest: plan.plan.digest) }
        _ = try service.approve(planID: plan.id, digest: plan.plan.digest)
        _ = try service.apply(planID: plan.id, digest: plan.plan.digest)
        let deployed = fixture.project.appendingPathComponent(".agents/skills/demo")
        let librarySkill = fixture.root.appendingPathComponent("home/.agents/skills/demo").path
        let link = try FileManager.default.destinationOfSymbolicLink(atPath: deployed.path)
        #expect(URL(fileURLWithPath: link).standardizedFileURL.path == librarySkill)
        #expect(try Data(contentsOf: deployed.appendingPathComponent("assets/data.bin")) == Data([0, 255, 128]))
        #expect(!FileManager.default.fileExists(atPath: fixture.marker.path))
        #expect(try service.projects().first?.skillObservations.allSatisfy { $0.status == "matching" } == true)
        try service.removeSource(preview.id)
        #expect(throws: (any Error).self) { try String(contentsOf: deployed.appendingPathComponent("SKILL.md"), encoding: .utf8) }
    }

    @Test func sourceUpdatesKeepIdentityAndPinExistingLinksUntilDeploymentAndRollbackRestoresLink() throws {
        let fixture = try PerchFixture()
        defer { fixture.cleanup() }
        let first = try fixture.service().previewSource(urlString: fixture.source.path)
        let entry = try fixture.importSkill(previewID: first.id)
        var service = try fixture.service()
        let project = try fixture.register()
        let original = try service.makePlan(projectID: project.id, skillIDs: [entry.id], instructionIDs: [])
        try fixture.apply(original)
        let deployed = fixture.project.appendingPathComponent(".agents/skills/demo")
        let oldLink = try FileManager.default.destinationOfSymbolicLink(atPath: deployed.path)
        try Data("new version".utf8).write(to: fixture.source.appendingPathComponent("demo/assets/data.bin"))
        _ = try service.previewSource(urlString: fixture.source.path, replacing: first.id)
        service = try fixture.service()
        let updated = try #require(service.skills(query: "demo").first)
        #expect(updated.id == entry.id)
        #expect(updated.contentHash != entry.contentHash)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: deployed.path) == oldLink)
        let copyPlan = try service.makePlan(projectID: project.id, skillIDs: [entry.id], instructionIDs: [], installMethod: .copy)
        let operation = try fixture.apply(copyPlan)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: deployed.path)) == nil)
        #expect(try String(contentsOf: deployed.appendingPathComponent("assets/data.bin"), encoding: .utf8) == "new version")
        _ = try service.rollback(operationID: operation.operationID)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: deployed.path) == oldLink)
        #expect(try String(contentsOf: deployed.appendingPathComponent("assets/data.bin"), encoding: .utf8) == "new version")
    }

    @Test func changedLinkOrVersionBlocksApplyWithoutChangingOtherTargets() throws {
        for mutateVersion in [false, true] {
            let fixture = try PerchFixture()
            defer { fixture.cleanup() }
            let preview = try fixture.service().previewSource(urlString: fixture.source.path)
            let entry = try fixture.importSkill(previewID: preview.id)
            let service = try fixture.service()
            let project = try fixture.register()
            let first = try service.makePlan(projectID: project.id, skillIDs: [entry.id], instructionIDs: [])
            try fixture.apply(first)
            let plan = try service.makePlan(projectID: project.id, skillIDs: [entry.id], instructionIDs: [], installMethod: .copy)
            let deployed = fixture.project.appendingPathComponent(".agents/skills/demo")
            if mutateVersion {
                try Data("tampered".utf8).write(to: deployed.appendingPathComponent("SKILL.md"))
            } else {
                try FileManager.default.removeItem(at: deployed)
                try FileManager.default.createSymbolicLink(at: deployed, withDestinationURL: fixture.source.appendingPathComponent("demo"))
            }
            _ = try service.approve(planID: plan.id, digest: plan.plan.digest)
            #expect(throws: FileTransactionError.self) { try service.apply(planID: plan.id, digest: plan.plan.digest) }
            #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: deployed.path)) != nil)
        }
    }

    @Test func userMigrationBacksUpExistingDirectoryAndRollbackRestoresItsType() throws {
        let fixture = try PerchFixture()
        defer { fixture.cleanup() }
        let home = fixture.root.appendingPathComponent("home")
        let deployed = home.appendingPathComponent(".codex/skills/demo")
        try FileManager.default.createDirectory(at: deployed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture.source.appendingPathComponent("demo"), to: deployed)
        let preview = try fixture.service().previewSource(urlString: deployed.deletingLastPathComponent().path)
        let entry = try fixture.importSkill(previewID: preview.id)
        let service = try fixture.service()
        let plan = try service.makeUserSkillPlan(skillIDs: [entry.id], agents: ["codex"], adoptExistingSkills: true, homeDirectory: home)
        let result = try fixture.apply(plan)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: deployed.path)) != nil)
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("skillset.json").path))
        #expect(FileManager.default.fileExists(atPath: fixture.paths.applicationSupportRoot.appendingPathComponent("global/codex.json").path))
        _ = try service.rollback(operationID: result.operationID)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: deployed.path)) == nil)
        #expect(try Data(contentsOf: deployed.appendingPathComponent("assets/data.bin")) == Data([0, 255, 128]))
    }

    @Test func failedSyncPreservesPreviousIndexAndSourceAndLegacyMigrationKeepsOriginal() throws {
        let fixture = try PerchFixture()
        defer { fixture.cleanup() }
        let first = try fixture.service().previewSource(urlString: fixture.source.path)
        let entries = try fixture.service().skills(query: "")
        #expect(throws: (any Error).self) { try fixture.service().previewSource(urlString: fixture.root.appendingPathComponent("missing").path, replacing: first.id) }
        #expect(try fixture.service().skills(query: "") == entries)
        #expect(try fixture.service().sourcePreviews().map(\.id) == [first.id])
        let legacy = fixture.root.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent("skill-library/packages"), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: legacy.appendingPathComponent("skill-library/index.json"))
        let migrated = SkillSetRuntimePaths(applicationSupportRoot: fixture.root.appendingPathComponent("migrated"), repositoryRoot: nil)
        try migrated.migrateLegacyState(from: legacy)
        #expect(try Data(contentsOf: migrated.libraryRoot.appendingPathComponent("index.json")) == Data("fixture".utf8))
        #expect(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("skill-library/index.json").path))
    }
}

private struct PerchFixture {
    let root: URL
    let paths: SkillSetRuntimePaths
    let source: URL
    let project: URL
    let marker: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("perch-\(UUID())")
        paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        source = root.appendingPathComponent("source")
        project = root.appendingPathComponent("project")
        marker = root.appendingPathComponent("must-not-execute")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("demo/assets"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("---\nname: demo\ndescription: searchable demo\n---\n\n# demo\n".utf8).write(to: source.appendingPathComponent("demo/SKILL.md"))
        try Data([0, 255, 128]).write(to: source.appendingPathComponent("demo/assets/data.bin"))
        try Data("#!/bin/sh\ntouch '\(marker.path)'\n".utf8).write(to: source.appendingPathComponent("demo/install.sh"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.appendingPathComponent("demo/install.sh").path)
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
    func service() throws -> SkillSetService { try SkillSetService(paths: paths, globalLocations: GlobalConfigurationLocations(home: root.appendingPathComponent("home"), stateRoot: paths.applicationSupportRoot)) }
    func register() throws -> ProjectRegistration { try ProjectStore(rootURL: paths.applicationSupportRoot).register(path: project) }
    func importSkill(previewID: UUID, path: String = "demo", mode: SkillInstallMethod = .symlink) throws -> SkillEntry {
        var draft = try service().sourceSkillImportDraft(previewID: previewID, path: path)
        draft.mode = mode
        return try service().importSourceSkill(draft)
    }
    @discardableResult func apply(_ record: StoredDeploymentPlan) throws -> ApplyServiceResult {
        let service = try service()
        _ = try service.approve(planID: record.id, digest: record.plan.digest)
        return try service.apply(planID: record.id, digest: record.plan.digest)
    }
}
