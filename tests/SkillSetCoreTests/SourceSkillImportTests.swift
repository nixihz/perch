import Foundation
import Testing
@testable import SkillSetCore

struct SourceSkillImportTests {
    @Test func importsCompletePackageAndLicensesSurvivesPreviewDeletionAndDeploysWithApproval() throws {
        let fixture = try SourceImportFixture()
        defer { fixture.cleanup() }
        var draft = try fixture.draft()
        draft.mode = .copy
        let entry = try fixture.service().importSourceSkill(draft)
        let store = fixture.paths.makeLibraryStore()
        let package = try #require(store.sourceURLs()[entry.id])
        #expect(try Data(contentsOf: package.appendingPathComponent("assets/data.bin")) == Data([0, 255, 1, 128]))
        #expect(try String(contentsOf: package.appendingPathComponent("_source_licenses/LICENSE"), encoding: .utf8) == "MIT fixture notice\n")
        #expect(try FileManager.default.attributesOfItem(atPath: package.appendingPathComponent("scripts/run.sh").path)[.posixPermissions] as? Int == 0o755)
        #expect(!FileManager.default.fileExists(atPath: fixture.executionMarker.path))

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
        #expect(!plan.plan.warnings.contains { $0.contains("许可") })
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
        let store = fixture.paths.makeLibraryStore()
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
        let categories = fixture.paths.applicationSupportRoot.appendingPathComponent("skill-categories.json")
        try FileManager.default.createDirectory(at: categories.deletingLastPathComponent(), withIntermediateDirectories: true)
        let broken = Data("not-json".utf8)
        try broken.write(to: categories)
        #expect(throws: SkillLibraryError.corrupt) { try fixture.service().importSourceSkill(draft) }
        #expect(try Data(contentsOf: categories) == broken)
        try FileManager.default.removeItem(at: categories)
        try "---\nname: missing-description\n---\nbody".write(to: fixture.checkout.appendingPathComponent("custom/import-demo/SKILL.md"), atomically: true, encoding: .utf8)
        try fixture.savePreview()
        let invalid = try fixture.draft()
        #expect(throws: SkillLibraryError.invalidDocument) { try fixture.service().importSourceSkill(invalid) }
        let libraryEntry = fixture.paths.libraryDirectoryURL.appendingPathComponent("import-demo")
        #expect(!FileManager.default.fileExists(atPath: libraryEntry.path))
    }

    @Test func rootSkillImportsWithoutGitMetadataAndNeverTrustsWorkspacePath() throws {
        let fixture = try SourceImportFixture(path: ".")
        defer { fixture.cleanup() }
        var draft = try fixture.service().sourceSkillImportDraft(previewID: fixture.previewID, path: ".")
        draft.mode = .copy
        let entry = try fixture.service().importSourceSkill(draft)
        let store = fixture.paths.makeLibraryStore()
        let package = try #require(store.sourceURLs()[entry.id])
        #expect(!FileManager.default.fileExists(atPath: package.appendingPathComponent(".git").path))
        #expect(try String(contentsOf: package.appendingPathComponent("SKILL.md"), encoding: .utf8) == fixture.document)
        #expect(try String(contentsOf: package.appendingPathComponent("LICENSE"), encoding: .utf8) == "MIT fixture notice\n")
        #expect(try store.sourceOrigins()[entry.id]?.path == ".")
    }

    @Test func batchImportAddsEverySkillAndKeepsSourceEvidenceInOneMetadataWrite() throws {
        let fixture = try BatchImportFixture()
        defer { fixture.cleanup() }
        let results = try fixture.service().importSourceSkills(fixture.request(category: "review"))
        #expect(results.count == 3)
        #expect(results.allSatisfy { if case .imported = $0.status { return true } else { return false } })

        let store = fixture.paths.makeLibraryStore()
        let origins = try store.sourceOrigins()
        #expect(Set(origins.keys) == ["alpha", "beta", "gamma"])
        #expect(origins["alpha"]?.path == "skills/alpha")
        #expect(origins["gamma"]?.commit == String(repeating: "a", count: 40))
        #expect(try store.catalog(merging: fixture.emptyCatalog).entries.map(\.id).sorted() == ["alpha", "beta", "gamma"])

        // 软链指向来源检出目录，来源更新后仍指向同一份内容。
        let link = fixture.libraryRoot.appendingPathComponent("alpha")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
            .contains(fixture.checkout.lastPathComponent))

        let meta = try JSONDecoder().decode(SkillLibraryMeta.self, from: Data(contentsOf: fixture.paths.applicationSupportRoot.appendingPathComponent("skill-categories.json")))
        #expect(meta.categories == ["alpha": "review", "beta": "review", "gamma": "review"])
        #expect(meta.origins.count == 3)
    }

    @Test func batchImportCopiesCompletePackagesWithLicensesAndWithoutGitMetadata() throws {
        let fixture = try BatchImportFixture()
        defer { fixture.cleanup() }
        let results = try fixture.service().importSourceSkills(fixture.request(mode: .copy))
        #expect(results.count == 3)

        let store = fixture.paths.makeLibraryStore()
        let package = try #require(store.sourceURLs()["alpha"])
        #expect(package.lastPathComponent == "alpha")
        #expect(try Data(contentsOf: package.appendingPathComponent("assets/data.bin")) == Data([0, 255, 1, 128]))
        #expect(try String(contentsOf: package.appendingPathComponent("_source_licenses/LICENSE"), encoding: .utf8) == "MIT fixture notice\n")
        #expect(!FileManager.default.fileExists(atPath: package.appendingPathComponent(".git").path))
        // 复制后与来源无关：删除预览缓存后技能仍在库里。
        try SourcePreviewStore(rootURL: fixture.paths.previewsRoot).remove(fixture.previewID)
        #expect(try fixture.service().skills(query: "alpha").map(\.id) == ["alpha"])
    }

    @Test func batchImportKeepsOtherSkillsWhenOneChangesAndNeverOverwritesAnOccupiedID() throws {
        let fixture = try BatchImportFixture()
        defer { fixture.cleanup() }
        let single = try fixture.service().sourceSkillImportDraft(previewID: fixture.previewID, path: "skills/beta")
        _ = try fixture.service().importSourceSkill(single)
        try Data("changed".utf8).write(to: fixture.checkout.appendingPathComponent("skills/gamma/assets/data.bin"))

        let results = try fixture.service().importSourceSkills(fixture.request())
        #expect(results.count == 3)
        #expect(statusCode(results[0]) == nil, "alpha 应加入成功")
        #expect(statusCode(results[1]) == SkillLibraryError.duplicate.code, "beta 标识已被占用，应跳过")
        #expect(statusCode(results[2]) == SourceSkillImportError.changed.code, "gamma 内容已变，应失败")

        let store = fixture.paths.makeLibraryStore()
        let entries = try store.catalog(merging: fixture.emptyCatalog).entries
        #expect(entries.map(\.id).sorted() == ["alpha", "beta"])
        // 已被占用的标识保持原内容，不被覆盖。
        #expect(try store.document(for: entries.first { $0.id == "beta" }!, repositoryRoot: nil).contains("name: beta"))
    }

    @Test func batchCopyDoesNotReplaceAnExistingSourceLink() throws {
        let fixture = try BatchImportFixture()
        defer { fixture.cleanup() }
        let service = try fixture.service()
        let draft = try service.sourceSkillImportDraft(previewID: fixture.previewID, path: "skills/beta")
        _ = try service.importSourceSkill(draft)
        let link = fixture.libraryRoot.appendingPathComponent("beta")
        let target = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)

        let results = service.importSourceSkills(fixture.request(mode: .copy))
        #expect(statusCode(results[1]) == SkillLibraryError.duplicate.code)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target)
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.sourcesRoot.appendingPathComponent("custom/beta").path))
        #expect(statusCode(results[0]) == nil)
        #expect(statusCode(results[2]) == nil)
    }

    @Test func batchLinkDoesNotShadowACustomSkillWithoutAnInventoryLink() throws {
        let fixture = try BatchImportFixture()
        defer { fixture.cleanup() }
        let service = try fixture.service()
        let store = fixture.paths.makeLibraryStore()
        let original = try store.save(SkillEditorDraft(slug: "alpha", document:
            "---\nname: alpha\ndescription: 本机原稿\n---\n保留本机内容\n"), repositoryRoot: nil)
        try FileManager.default.removeItem(at: fixture.libraryRoot.appendingPathComponent("alpha"))

        let results = service.importSourceSkills(fixture.request())
        #expect(statusCode(results[0]) == SkillLibraryError.duplicate.code)
        let retained = try #require(fixture.service().skills(query: "alpha").first)
        #expect(retained.contentHash == original.contentHash)
        #expect(try store.document(for: retained, repositoryRoot: nil).contains("保留本机内容"))
        #expect(!FileManager.default.fileExists(atPath: fixture.libraryRoot.appendingPathComponent("alpha").path))
    }

    @Test func batchImportPreservesCorruptMetadataAndWritesNoPackages() throws {
        let fixture = try BatchImportFixture()
        defer { fixture.cleanup() }
        let service = try fixture.service()
        let metadata = fixture.paths.applicationSupportRoot.appendingPathComponent("skill-categories.json")
        let broken = Data("invalid-json".utf8)
        try broken.write(to: metadata)

        let results = service.importSourceSkills(fixture.request())
        #expect(results.allSatisfy { statusCode($0) == SkillLibraryError.corrupt.code })
        #expect(try Data(contentsOf: metadata) == broken)
        #expect(!FileManager.default.fileExists(atPath: fixture.libraryRoot.appendingPathComponent("alpha").path))
    }

    @Test func batchImportRejectsInvalidDocumentsBeforeCopying() throws {
        let fixture = try BatchImportFixture()
        defer { fixture.cleanup() }
        try Data("---\nname: alpha\n---\n缺少描述\n".utf8)
            .write(to: fixture.checkout.appendingPathComponent("skills/alpha/SKILL.md"))
        try fixture.savePreview()
        let results = try fixture.service().importSourceSkills(fixture.request(mode: .copy))
        #expect(statusCode(results[0]) == SkillLibraryError.invalidDocument.code)
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.sourcesRoot.appendingPathComponent("custom/alpha").path))
        #expect(statusCode(results[1]) == nil)
        #expect(statusCode(results[2]) == nil)
    }

    @Test func batchCopyCleansUpWhenSourceChangesAfterValidation() throws {
        let fixture = try BatchImportFixture()
        defer { fixture.cleanup() }
        let service = try fixture.service()
        let draft = try service.sourceSkillImportDraft(previewID: fixture.previewID, path: "skills/alpha")
        let source = fixture.checkout.appendingPathComponent("skills/alpha")
        let analysis = try SkillAssetCopier.analyze(from: source)
        try Data("changed-after-validation".utf8).write(to: source.appendingPathComponent("assets/data.bin"))
        let package = SourceSkillBatchPackage(path: "skills/alpha", slug: "alpha", source: source,
            licenses: [:], origin: draft.origin, analysis: analysis)

        let results = fixture.paths.makeLibraryStore().importSourceBatch([package], mode: .copy, category: "")
        #expect(statusCode(results[0]) == SourceSkillImportError.changed.code)
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.sourcesRoot.appendingPathComponent("custom/alpha").path))
        #expect(try fixture.service().skills(query: "alpha").isEmpty)
    }

    @Test func batchImportUsesTheSameIdentifierRulesAsSingleImport() {
        #expect(SourceSkillSlug.normalized("Animate Expo!") == "animate-expo")
        #expect(SourceSkillSlug.normalized("---") == "imported-skill")
        #expect(SourceSkillSlug.unique("animate", existing: ["animate"]) == "animate-2")
        #expect(SourceSkillSlug.unique("animate", existing: ["animate", "animate-2"]) == "animate-3")
        #expect(SourceSkillSlug.unique("animate", existing: []) == "animate")
        #expect(SourceSkillSlug.normalized(String(repeating: "a", count: 100)).count == 80)
    }
}

/// 批量结果里的失败与跳过只带错误码；成功没有错误码。
private func statusCode(_ result: SourceSkillBatchItemResult) -> String? {
    switch result.status {
    case .imported: nil
    case .skipped(let code): code
    case .failed(let code): code
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

    func service() throws -> SkillSetService {
        try SkillSetService(paths: paths, globalLocations: .init(home: root.appendingPathComponent("home"), stateRoot: paths.applicationSupportRoot))
    }
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

/// 批量导入用的来源：同一个预览里有三个技能。
private struct BatchImportFixture {
    let root: URL
    let paths: SkillSetRuntimePaths
    let previewID = UUID()
    let emptyCatalog = CatalogDocument(schemaVersion: 1, hashAlgorithm: "sha256:path-content-executable:v1", entries: [])
    let names = ["alpha", "beta", "gamma"]
    var checkout: URL { paths.previewsRoot.appendingPathComponent(previewID.uuidString).appendingPathComponent("checkout") }
    var libraryRoot: URL { paths.libraryDirectoryURL }

    init() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("source-batch-\(UUID())")
        let repository = root.appendingPathComponent("repo")
        paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: repository)
        try FileManager.default.createDirectory(at: repository.appendingPathComponent("registry"), withIntermediateDirectories: true)
        try JSONEncoder().encode(emptyCatalog).write(to: repository.appendingPathComponent("registry/catalog.json"))
        for name in names {
            let package = checkout.appendingPathComponent("skills").appendingPathComponent(name)
            try FileManager.default.createDirectory(at: package.appendingPathComponent("assets"), withIntermediateDirectories: true)
            let document = "---\nname: \(name)\ndescription: Fixture batch skill \(name)\n---\n\n# \(name)\n"
            try document.write(to: package.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            try Data([0, 255, 1, 128]).write(to: package.appendingPathComponent("assets/data.bin"))
        }
        try "MIT fixture notice\n".write(to: checkout.appendingPathComponent("LICENSE"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: checkout.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "fake git data".write(to: checkout.appendingPathComponent(".git/config"), atomically: true, encoding: .utf8)
        try savePreview()
    }

    func service() throws -> SkillSetService {
        try SkillSetService(paths: paths, globalLocations: .init(home: root.appendingPathComponent("home"), stateRoot: paths.applicationSupportRoot))
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }

    func request(slugs: [String]? = nil, mode: SkillInstallMethod = .symlink, category: String = "") -> SourceSkillBatchRequest {
        SourceSkillBatchRequest(
            previewID: previewID,
            items: names.enumerated().map { index, name in
                SourceSkillBatchItem(path: "skills/\(name)", slug: slugs?[index] ?? name)
            },
            mode: mode,
            category: category
        )
    }

    func savePreview() throws {
        var candidates: [SourceSkillCandidate] = []
        for name in names {
            let package = checkout.appendingPathComponent("skills").appendingPathComponent(name)
            let analysis = try SkillAssetCopier.analyze(from: package)
            candidates.append(SourceSkillCandidate(
                id: "example/\(name)", path: "skills/\(name)", slug: name, declaredName: name,
                description: "Fixture batch skill \(name)", category: "other", state: .other,
                contentHash: analysis.contentHash, fileCount: analysis.fileManifest.count,
                bytes: analysis.bytes, issues: []
            ))
        }
        let record = SourcePreviewRecord(
            id: previewID, inputURL: "https://github.com/example/skills",
            canonicalURL: "https://github.com/example/skills", namespace: "example-skills",
            resolvedCommit: String(repeating: "a", count: 40), createdAt: Date(),
            workspacePath: root.appendingPathComponent("untrusted-path").path, licenseEvidence: "LICENSE",
            candidates: candidates, excludedCounts: [:], warnings: []
        )
        try SourcePreviewStore(rootURL: paths.previewsRoot).save(record)
    }
}
