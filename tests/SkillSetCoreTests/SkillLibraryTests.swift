import Foundation
import Testing
@testable import SkillSetCore

struct SkillLibraryTests {
    @Test func savesNewVersionsSurvivesRestartAndRemovesWithoutErasingHistory() throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanup() }
        let original = try fixture.store.save(fixture.draft(), repositoryRoot: nil)
        let restarted = SkillLibraryStore(libraryURL: fixture.store.libraryURL, sourcesURL: fixture.store.sourcesURL, categoriesURL: fixture.store.categoriesURL)
        #expect(try restarted.catalog(merging: fixture.emptyCatalog).entries.map(\.id) == ["demo"])
        #expect(try restarted.document(for: original, repositoryRoot: nil).contains("第一版"))

        let updated = try restarted.save(fixture.draft(body: "第二版", original: original), repositoryRoot: nil)
        #expect(updated.contentHash != original.contentHash)
        #expect(updated.path == original.path)
        #expect(updated.declaredVersion == "1.0")
        #expect(updated.description == "用于验证保存和检索")
        #expect(try restarted.document(for: updated, repositoryRoot: nil).contains("第二版"))
        #expect(try restarted.catalog(merging: fixture.emptyCatalog).entries.count == 1)
        #expect(try matchingSkills(restarted.catalog(merging: fixture.emptyCatalog).entries, query: "验证").map(\.id) == [updated.id])
        try restarted.remove(updated)
        #expect(!FileManager.default.fileExists(atPath: restarted.customURL.appendingPathComponent(updated.slug).path))
        #expect(try restarted.catalog(merging: fixture.emptyCatalog).entries.isEmpty)
        #expect(throws: (any Error).self) { try restarted.document(for: updated, repositoryRoot: nil) }
    }

    @Test func ownedLibraryDirectoryMovesIntoCustom() throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanup() }
        let fm = FileManager.default
        let libraryEntry = fixture.store.libraryURL.appendingPathComponent("local-demo")
        try fm.createDirectory(at: libraryEntry, withIntermediateDirectories: true)
        try Data("---\nname: local-demo\ndescription: imported\n---\nbody\n".utf8)
            .write(to: libraryEntry.appendingPathComponent("SKILL.md"))
        let loaded = try fixture.store.loadLibrary()
        let custom = fixture.store.customURL.appendingPathComponent("local-demo")
        #expect(fm.fileExists(atPath: custom.appendingPathComponent("SKILL.md").path))
        #expect(try fm.destinationOfSymbolicLink(atPath: libraryEntry.path) == custom.path)
        #expect(loaded.records.first { $0.entry.slug == "local-demo" }?.entry.sourceId == SkillLibraryStore.sourceID)
    }

    @Test func removingLinkedSkillDropsLibraryEntryAndKeepsSource() throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanup() }
        let fm = FileManager.default
        let source = fixture.root.appendingPathComponent("checkout/demo")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        let document = "---\nname: demo\ndescription: 来源技能\n---\n\n# Demo\n"
        try document.write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let analysis = try SkillAssetCopier.analyze(from: source)
        let origin = SourceSkillOrigin(
            url: "https://github.com/example/skills", commit: String(repeating: "a", count: 40),
            path: "demo", contentHash: analysis.contentHash, licenseEvidence: "", licenseHashes: [:], declaredName: "demo"
        )
        var draft = SourceSkillImportDraft(
            previewID: UUID(), origin: origin, document: document, files: [], slug: "demo"
        )
        draft.mode = .symlink
        let entry = try fixture.store.importSource(draft, source: source, licenses: [:])
        try fixture.store.remove(entry)
        #expect(try fixture.store.catalog(merging: fixture.emptyCatalog).entries.isEmpty)
        #expect(!fm.fileExists(atPath: fixture.store.libraryURL.appendingPathComponent("demo").path))
        #expect(try String(contentsOf: source.appendingPathComponent("SKILL.md"), encoding: .utf8) == document)
    }

    @Test func forksPreserveAssetsPermissionsAndUnknownFrontmatterWithoutTouchingSource() throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanup() }
        let source = try fixture.makeRepositorySkill()
        let before = try Data(contentsOf: fixture.repository.appendingPathComponent("skills/demo/SKILL.md"))
        let copy = try fixture.store.save(fixture.draft(body: "修改副本", original: source), repositoryRoot: fixture.repository)
        #expect(copy.id == "demo")
        #expect(copy.fileCount == 2)
        #expect(copy.licenseReview == "required")
        #expect(try Data(contentsOf: fixture.repository.appendingPathComponent("skills/demo/SKILL.md")) == before)
        let copyURL = try #require(fixture.store.sourceURLs()[copy.id])
        let files = try SkillAssetCopier.analyze(from: copyURL).fileManifest
        #expect(files.contains { $0.path == "scripts/run.sh" && $0.executable })
        #expect(try fixture.store.document(for: copy, repositoryRoot: nil).contains("allowed-tools: [Read]"))
        let again = try fixture.store.save(fixture.draft(body: "再编辑", original: copy), repositoryRoot: nil)
        #expect(again.fileCount == 2)
    }

    @Test func duplicateInvalidDocumentsAndStaleEditorsCannotReplaceCurrentVersion() throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanup() }
        let original = try fixture.store.save(fixture.draft(), repositoryRoot: nil)
        #expect(throws: SkillLibraryError.duplicate) { try fixture.store.save(fixture.draft(), repositoryRoot: nil) }
        var traversal = fixture.draft(); traversal.slug = "../../escape"
        #expect(throws: SkillLibraryError.invalidSlug) { try fixture.store.save(traversal, repositoryRoot: nil) }
        var malformed = fixture.draft(slug: "invalid"); malformed.document = "---\nname: missing-description\n---\nbody"
        #expect(throws: SkillLibraryError.invalidDocument) { try fixture.store.save(malformed, repositoryRoot: nil) }
        let current = try fixture.store.save(fixture.draft(body: "当前版本", original: original), repositoryRoot: nil)
        #expect(throws: SkillLibraryError.stale) { try fixture.store.save(fixture.draft(body: "过期编辑", original: original), repositoryRoot: nil) }
        #expect(throws: SkillLibraryError.stale) { try fixture.store.remove(original) }
        #expect(try fixture.store.document(for: current, repositoryRoot: nil).contains("当前版本"))
        #expect(try fixture.store.catalog(merging: fixture.emptyCatalog).entries.map(\.contentHash) == [current.contentHash])
    }

    @Test func externalEditsAndSymlinkReplacementAreRejectedWithoutWritingOutsideLibrary() throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanup() }
        let entry = try fixture.store.save(fixture.draft(), repositoryRoot: nil)
        let source = try #require(fixture.store.sourceURLs()[entry.id])
        try "外部修改".write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        #expect(throws: SkillLibraryError.stale) { try fixture.store.save(fixture.draft(original: entry), repositoryRoot: nil) }
        let custom = fixture.store.customURL
        try FileManager.default.removeItem(at: custom)
        let outside = fixture.root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: custom, withDestinationURL: outside)
        #expect(throws: SkillLibraryError.unsafePath) { try fixture.store.save(fixture.draft(slug: "escaped"), repositoryRoot: nil) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test func hidingAndRestoringSnapshotEntriesNeverMutatesRepository() throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanup() }
        let entry = try fixture.makeRepositorySkill()
        let base = CatalogDocument(schemaVersion: 1, hashAlgorithm: "sha256:path-content-executable:v1", entries: [entry])
        try fixture.store.remove(entry)
        #expect(try fixture.store.catalog(merging: base).entries.isEmpty)
        #expect(try fixture.store.hiddenCount() == 1)
        #expect(try SkillAssetCopier.analyze(from: fixture.repository.appendingPathComponent(entry.path)).contentHash == entry.contentHash)
        try fixture.store.restoreHidden()
        #expect(try fixture.store.catalog(merging: base).entries.map(\.id) == [entry.id])
    }

    @Test func corruptIndexCannotBeSilentlyOverwritten() throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanup() }
        _ = try fixture.store.save(fixture.draft(), repositoryRoot: nil)
        let url = fixture.store.categoriesURL
        let broken = Data("not-json".utf8)
        try broken.write(to: url)
        #expect(throws: SkillLibraryError.corrupt) { try fixture.store.save(fixture.draft(slug: "next"), repositoryRoot: nil) }
        #expect(try Data(contentsOf: url) == broken)
    }

    @Test func personalSkillsDeployThroughExistingApprovalAndObjectStore() throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanup() }
        let entry = try fixture.store.save(fixture.draft(), repositoryRoot: nil)
        let project = fixture.root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let registration = try ProjectStore(rootURL: fixture.paths.applicationSupportRoot).register(path: project)
        let service = try SkillSetService(
            paths: fixture.paths,
            globalLocations: .init(home: fixture.root.appendingPathComponent("home"), stateRoot: fixture.paths.applicationSupportRoot)
        )
        #expect(service.skills(query: "验证").map(\.id) == [entry.id])
        let record = try service.makePlan(projectID: registration.id, skillIDs: [entry.id], instructionIDs: [])
        #expect(throws: DeploymentPlanStoreError.self) { try service.apply(planID: record.id, digest: record.plan.digest) }
        _ = try service.approve(planID: record.id, digest: record.plan.digest)
        _ = try service.apply(planID: record.id, digest: record.plan.digest)
        let installed = project.appendingPathComponent(".agents/skills/demo/SKILL.md")
        #expect(try String(contentsOf: installed, encoding: .utf8).contains("第一版"))
        let lock = try #require(try ProjectLockStore(projectRoot: project, stateRoot: fixture.paths.applicationSupportRoot).loadLock())
        #expect(lock.skills.first?.contentHash == entry.contentHash)
        #expect(try SkillObjectStore(repositoryRoot: fixture.paths.applicationSupportRoot).verify(lock: lock).checkedObjects > 0)
        try fixture.store.remove(entry)
        #expect(throws: (any Error).self) { try String(contentsOf: installed, encoding: .utf8) }
    }
}

private struct LibraryFixture {
    let root: URL
    let repository: URL
    let paths: SkillSetRuntimePaths
    let store: SkillLibraryStore
    let emptyCatalog = CatalogDocument(schemaVersion: 1, hashAlgorithm: "sha256:path-content-executable:v1", entries: [])

    init() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("library-tests-\(UUID())")
        repository = root.appendingPathComponent("repo")
        paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: repository)
        store = paths.makeLibraryStore(home: root.appendingPathComponent("home"))
        try FileManager.default.createDirectory(at: repository.appendingPathComponent("registry"), withIntermediateDirectories: true)
        try JSONEncoder().encode(emptyCatalog).write(to: repository.appendingPathComponent("registry/catalog.json"))
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }

    func draft(slug: String = "demo", body: String = "第一版", original: SkillEntry? = nil) -> SkillEditorDraft {
        SkillEditorDraft(slug: slug, document: "---\nname: demo\ndescription: >-\n  用于验证保存和检索\nversion: '1.0'\nallowed-tools: [Read]\n---\n\n# Demo\n\n\(body)\n", original: original)
    }

    func makeRepositorySkill() throws -> SkillEntry {
        let source = repository.appendingPathComponent("skills/demo")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try draft().document.write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "#!/bin/sh\nexit 0\n".write(to: source.appendingPathComponent("scripts/run.sh"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.appendingPathComponent("scripts/run.sh").path)
        let analysis = try SkillAssetCopier.analyze(from: source)
        return SkillEntry(id: "workspace/demo", slug: "demo", declaredName: "demo", description: "原始来源", declaredVersion: nil,
                          metadataReview: "not-schema-validated", sourceId: "workspace", path: "skills/demo", contentHash: analysis.contentHash,
                          fileCount: 2, bytes: analysis.bytes, integrity: "snapshotted", issues: [], licenseReview: "required", excludedPaths: [])
    }
}
