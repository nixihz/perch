import Foundation
import Testing
@testable import SkillSetCore

struct SourceSkillImportTests {
    @Test func importsCompletePackageAndLicensesSurvivesPreviewDeletionAndDeploysWithApproval() throws {
        let fixture = try SourceImportFixture()
        defer { fixture.cleanup() }
        let draft = try fixture.draft()
        let entry = try fixture.service().importSourceSkill(draft)
        let store = SkillLibraryStore(rootURL: fixture.paths.libraryRoot)
        let package = try #require(store.sourceURLs()[entry.id])
        #expect(try Data(contentsOf: package.appendingPathComponent("assets/data.bin")) == Data([0, 255, 1, 128]))
        #expect(try String(contentsOf: package.appendingPathComponent("_source_licenses/LICENSE"), encoding: .utf8) == "MIT fixture notice\n")
        #expect(try FileManager.default.attributesOfItem(atPath: package.appendingPathComponent("scripts/run.sh").path)[.posixPermissions] as? Int == 0o755)
        #expect(!FileManager.default.fileExists(atPath: fixture.executionMarker.path))
        #expect(entry.licenseReview == "required")
        try SourcePreviewStore(rootURL: fixture.paths.previewsRoot).remove(fixture.previewID)
        let restarted = try fixture.service()
        #expect(restarted.skills(query: "import-demo").map(\.id) == [entry.id])
        let origin = try #require(store.sourceOrigins()[entry.id])
        #expect(origin.url == "https://github.com/example/skills")
        #expect(origin.commit == String(repeating: "a", count: 40))
        #expect(origin.path == "custom/import-demo")
        let project = fixture.root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let registration = try ProjectStore(rootURL: fixture.paths.applicationSupportRoot).register(path: project)
        let plan = try restarted.makePlan(projectID: registration.id, skillIDs: [entry.id], instructionIDs: [], agents: ["codex", "claude-code"])
        #expect(throws: DeploymentPlanStoreError.self) { try restarted.apply(planID: plan.id, digest: plan.plan.digest) }
        _ = try restarted.approve(planID: plan.id, digest: plan.plan.digest)
        _ = try restarted.apply(planID: plan.id, digest: plan.plan.digest)
        for host in [".agents", ".claude"] {
            let deployed = project.appendingPathComponent("\(host)/skills/import-demo")
            #expect(try String(contentsOf: deployed.appendingPathComponent("SKILL.md"), encoding: .utf8) == fixture.document)
            #expect(try Data(contentsOf: deployed.appendingPathComponent("assets/data.bin")) == Data([0, 255, 1, 128]))
            #expect(try String(contentsOf: deployed.appendingPathComponent("_source_licenses/LICENSE"), encoding: .utf8) == "MIT fixture notice\n")
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.executionMarker.path))
        let lock = try #require(try ProjectLockStore(projectRoot: project, stateRoot: fixture.paths.applicationSupportRoot).loadLock())
        #expect(lock.skills.first?.contentHash == entry.contentHash)
        #expect(try SkillObjectStore(repositoryRoot: fixture.paths.applicationSupportRoot).verify(lock: lock).checkedObjects > 0)
    }

    @Test func duplicateCanBeRenamedWithoutOverwritingAndEditsKeepOriginalSource() throws {
        let fixture = try SourceImportFixture()
        defer { fixture.cleanup() }
        var draft = try fixture.draft()
        let first = try fixture.service().importSourceSkill(draft)
        #expect(throws: SkillLibraryError.duplicate) { try fixture.service().importSourceSkill(draft) }
        draft.slug = "another-name"
        let second = try fixture.service().importSourceSkill(draft)
        let store = SkillLibraryStore(rootURL: fixture.paths.libraryRoot)
        let edited = try store.save(SkillEditorDraft(slug: second.slug, document: fixture.document + "\n本机修改\n", original: second), repositoryRoot: nil)
        #expect(try store.sourceOrigins()[edited.id]?.path == "custom/import-demo")
        #expect(try store.document(for: first, repositoryRoot: nil) == fixture.document)
        #expect(try store.document(for: edited, repositoryRoot: nil).contains("本机修改"))
        #expect(try store.catalog(merging: fixture.emptyCatalog).entries.count == 2)
    }

    @Test func driftInSkillOrLicenseRejectsImportWithoutPublishingAnyPackage() throws {
        for filename in ["custom/import-demo/assets/data.bin", "LICENSE"] {
            let fixture = try SourceImportFixture()
            defer { fixture.cleanup() }
            let draft = try fixture.draft()
            try Data("changed".utf8).write(to: fixture.checkout.appendingPathComponent(filename))
            #expect(throws: SourceSkillImportError.changed) { try fixture.service().importSourceSkill(draft) }
            #expect(!FileManager.default.fileExists(atPath: fixture.paths.libraryRoot.appendingPathComponent("index.json").path))
            #expect(!FileManager.default.fileExists(atPath: fixture.paths.libraryRoot.appendingPathComponent("packages").path))
        }
    }

    @Test func missingPreviewUnsafeCandidateAndReplacedDirectoryCannotEscapeCache() throws {
        let fixture = try SourceImportFixture()
        defer { fixture.cleanup() }
        #expect(throws: SourceSkillImportError.unavailable) { try fixture.service().sourceSkillImportDraft(previewID: fixture.previewID, path: "not-scanned") }
        let draft = try fixture.draft()
        let package = fixture.checkout.appendingPathComponent("custom/import-demo")
        let moved = fixture.root.appendingPathComponent("outside")
        try FileManager.default.moveItem(at: package, to: moved)
        try FileManager.default.createSymbolicLink(at: package, withDestinationURL: moved)
        #expect(throws: SourceSkillImportError.unsafePath) { try fixture.service().importSourceSkill(draft) }
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.libraryRoot.path))
        try fixture.savePreview(path: "../../outside")
        #expect(throws: SourceSkillImportError.unsafePath) { try fixture.service().sourceSkillImportDraft(previewID: fixture.previewID, path: "../../outside") }
        try SourcePreviewStore(rootURL: fixture.paths.previewsRoot).remove(fixture.previewID)
        #expect(throws: SourcePreviewError.self) { try fixture.service().importSourceSkill(draft) }
        #expect(try String(contentsOf: moved.appendingPathComponent("SKILL.md"), encoding: .utf8) == fixture.document)
    }

    @Test func corruptIndexIsPreservedAndInvalidDocumentCleansUpUnpublishedCopy() throws {
        let fixture = try SourceImportFixture()
        defer { fixture.cleanup() }
        let draft = try fixture.draft()
        let index = fixture.paths.libraryRoot.appendingPathComponent("index.json")
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: true)
        // 可读取的旧索引在提交前不能变成目录；损坏的索引必须被保留。
        #expect(throws: SkillLibraryError.corrupt) { try fixture.service().importSourceSkill(draft) }
        try FileManager.default.removeItem(at: fixture.paths.libraryRoot)
        try "---\nname: missing-description\n---\nbody".write(to: fixture.checkout.appendingPathComponent("custom/import-demo/SKILL.md"), atomically: true, encoding: .utf8)
        try fixture.savePreview()
        let invalid = try fixture.draft()
        #expect(throws: SkillLibraryError.invalidDocument) { try fixture.service().importSourceSkill(invalid) }
        #expect(!FileManager.default.fileExists(atPath: index.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.paths.libraryRoot.appendingPathComponent("packages").path).isEmpty)
    }

    @Test func rootSkillImportsWithoutGitMetadataAndNeverTrustsWorkspacePath() throws {
        let fixture = try SourceImportFixture(path: ".")
        defer { fixture.cleanup() }
        let draft = try fixture.service().sourceSkillImportDraft(previewID: fixture.previewID, path: ".")
        let entry = try fixture.service().importSourceSkill(draft)
        let store = SkillLibraryStore(rootURL: fixture.paths.libraryRoot)
        let package = try #require(store.sourceURLs()[entry.id])
        #expect(!FileManager.default.fileExists(atPath: package.appendingPathComponent(".git").path))
        #expect(try String(contentsOf: package.appendingPathComponent("SKILL.md"), encoding: .utf8) == fixture.document)
        #expect(try String(contentsOf: package.appendingPathComponent("LICENSE"), encoding: .utf8) == "MIT fixture notice\n")
        #expect(try store.sourceOrigins()[entry.id]?.path == ".")
    }
}

private struct SourceImportFixture {
    let root: URL
    let paths: SkillSetRuntimePaths
    let previewID = UUID()
    let emptyCatalog = CatalogDocument(schemaVersion: 1, hashAlgorithm: "sha256:path-content-executable:v1", entries: [])
    let document = "---\nname: import-demo\ndescription: Fixture source skill\nversion: '1.0'\nallowed-tools: [Read]\n---\n\n# Import demo\n\nUse scripts and assets.\n"
    var checkout: URL { paths.previewsRoot.appendingPathComponent(previewID.uuidString).appendingPathComponent("checkout") }
    var executionMarker: URL { root.appendingPathComponent("script-was-run") }

    init(path: String = "custom/import-demo") throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("source-import-\(UUID())")
        let repository = root.appendingPathComponent("repo")
        paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: repository)
        try FileManager.default.createDirectory(at: repository.appendingPathComponent("registry"), withIntermediateDirectories: true)
        try JSONEncoder().encode(emptyCatalog).write(to: repository.appendingPathComponent("registry/catalog.json"))
        let package = path == "." ? checkout : checkout.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: package.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: package.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try document.write(to: package.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try Data([0, 255, 1, 128]).write(to: package.appendingPathComponent("assets/data.bin"))
        try "#!/bin/sh\nprintf executed > '\(executionMarker.path)'\n".write(to: package.appendingPathComponent("scripts/run.sh"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: package.appendingPathComponent("scripts/run.sh").path)
        try "MIT fixture notice\n".write(to: checkout.appendingPathComponent("LICENSE"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: checkout.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "fake git data".write(to: checkout.appendingPathComponent(".git/config"), atomically: true, encoding: .utf8)
        try savePreview(path: path)
    }

    func service() throws -> SkillSetService { try SkillSetService(paths: paths) }
    func draft() throws -> SourceSkillImportDraft { try service().sourceSkillImportDraft(previewID: previewID, path: "custom/import-demo") }
    func cleanup() { try? FileManager.default.removeItem(at: root) }

    func savePreview(path: String = "custom/import-demo") throws {
        let actualPath = path.hasPrefix("..") ? "custom/import-demo" : path
        let analysis = try SkillAssetCopier.analyze(from: actualPath == "." ? checkout : checkout.appendingPathComponent(actualPath))
        let candidate = SourceSkillCandidate(id: "example/import-demo", path: path, slug: "import-demo", declaredName: "import-demo", description: "Fixture source skill", category: "other", state: .other, contentHash: analysis.contentHash, fileCount: analysis.files.count, bytes: analysis.bytes, issues: [])
        let record = SourcePreviewRecord(id: previewID, inputURL: "https://github.com/example/skills", canonicalURL: "https://github.com/example/skills", namespace: "example-skills", resolvedCommit: String(repeating: "a", count: 40), createdAt: Date(), workspacePath: root.appendingPathComponent("untrusted-path").path, licenseEvidence: "LICENSE", candidates: [candidate], excludedCounts: ["other": 1], warnings: [])
        try SourcePreviewStore(rootURL: paths.previewsRoot).save(record)
    }
}
