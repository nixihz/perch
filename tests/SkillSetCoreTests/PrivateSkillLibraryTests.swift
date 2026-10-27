import Foundation
import Testing
@testable import SkillSetCore

/// 技能库是栖集私有库存。通用目录只当安装目标，旧库内容一次性搬进库存。
struct PrivateSkillLibraryTests {
    @Test func libraryRootIsPrivateAndSharedDirectoryIsCollectedOnlyDuringInitialization() throws {
        let fixture = try InventoryFixture()
        defer { fixture.cleanup() }
        #expect(fixture.paths.libraryDirectoryURL.standardizedFileURL.path
            == fixture.paths.applicationSupportRoot.appendingPathComponent("skills/library").standardizedFileURL.path)
        #expect(fixture.paths.makeLibraryStore().libraryURL == fixture.paths.libraryDirectoryURL)

        // 首次收录复制技能；共享安装目录不能变成会随库存编辑变化的实体库。
        let shared = fixture.home.appendingPathComponent(".agents/skills/demo")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        try Data("---\nname: demo\ndescription: 通用目录\n---\n通用".utf8)
            .write(to: shared.appendingPathComponent("SKILL.md"))
        let original = try Data(contentsOf: shared.appendingPathComponent("SKILL.md"))
        let service = try fixture.service()
        #expect(service.skills(query: "demo").count == 1)
        let custom = fixture.paths.sourcesRoot.appendingPathComponent("custom/demo/SKILL.md")
        try Data("库存内编辑".utf8).write(to: custom)
        #expect(try Data(contentsOf: shared.appendingPathComponent("SKILL.md")) == original)
        let later = shared.deletingLastPathComponent().appendingPathComponent("later")
        try FileManager.default.createDirectory(at: later, withIntermediateDirectories: true)
        try Data("---\nname: later\ndescription: 稍后添加\n---\n正文".utf8).write(to: later.appendingPathComponent("SKILL.md"))
        #expect(try fixture.service().skills(query: "later").isEmpty)
    }

    @Test func legacyLinksMoveIntoInventoryAndOldDirectoryKeepsItsLinks() throws {
        let fixture = try InventoryFixture()
        defer { fixture.cleanup() }
        let checkout = fixture.paths.previewsRoot.appendingPathComponent("source/checkout/followed")
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        try Data("---\nname: followed\ndescription: 跟随来源\n---\n来源".utf8)
            .write(to: checkout.appendingPathComponent("SKILL.md"))
        let legacy = fixture.home.appendingPathComponent(".agents/skills")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: legacy.appendingPathComponent("followed"), withDestinationURL: checkout)

        let service = try fixture.service()
        #expect(service.skills(query: "followed").map(\.id) == ["followed"])
        // 库存里的软链指向同一份内容，旧位置的软链原样保留。
        let inventoryEntry = fixture.paths.libraryDirectoryURL.appendingPathComponent("followed")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: inventoryEntry.path) == checkout.path)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: legacy.appendingPathComponent("followed").path) == checkout.path)
    }

    @Test func customSkillStaysInCatalogWithoutInventoryLink() throws {
        let fixture = try InventoryFixture()
        defer { fixture.cleanup() }
        let custom = fixture.paths.sourcesRoot.appendingPathComponent("custom/solo")
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        try Data("---\nname: solo\ndescription: 自建技能\n---\n自建".utf8)
            .write(to: custom.appendingPathComponent("SKILL.md"))
        _ = try fixture.service()
        let inventoryEntry = fixture.paths.libraryDirectoryURL.appendingPathComponent("solo")
        #expect(FileManager.default.fileExists(atPath: inventoryEntry.path))

        // 库存软链没了，自建技能的实体仍然算库里的一条。
        try FileManager.default.removeItem(at: inventoryEntry)
        #expect(try fixture.service().skills(query: "solo").map(\.id) == ["solo"])
    }

    @Test func removedSkillIsNotCollectedFromTheLegacyDirectoryAgain() throws {
        let fixture = try InventoryFixture()
        defer { fixture.cleanup() }
        let checkout = fixture.paths.previewsRoot.appendingPathComponent("source/checkout/followed")
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        try Data("---\nname: followed\ndescription: 跟随来源\n---\n来源".utf8)
            .write(to: checkout.appendingPathComponent("SKILL.md"))
        let legacy = fixture.home.appendingPathComponent(".agents/skills")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: legacy.appendingPathComponent("followed"), withDestinationURL: checkout)
        _ = try fixture.service()

        try FileManager.default.removeItem(at: fixture.paths.libraryDirectoryURL.appendingPathComponent("followed"))
        #expect(try fixture.service().skills(query: "followed").isEmpty)
    }

    @Test func unreadableLegacyLibraryDoesNotMarkMigrationComplete() throws {
        let fixture = try InventoryFixture()
        defer { fixture.cleanup() }
        let legacy = fixture.home.appendingPathComponent(".agents/skills")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: legacy.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: legacy.path) }
        let marker = fixture.paths.sourcesRoot.appendingPathComponent(".migrated-library-location")

        #expect(throws: (any Error).self) { try fixture.service() }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func hostInstallTargetInsideInventoryIsRejected() throws {
        let fixture = try InventoryFixture()
        defer { fixture.cleanup() }
        let store = fixture.paths.makeLibraryStore()
        let entry = try store.save(
            SkillEditorDraft(slug: "demo", document: "---\nname: demo\ndescription: 库存内安装\n---\n正文\n"),
            repositoryRoot: nil
        )
        let source = try #require(store.sourceURLs()[entry.id])
        // 把宿主的技能目录指到库存里，安装计划必须拒绝，不能覆盖库存内容。
        let locations = GlobalConfigurationLocations(
            home: fixture.home, stateRoot: fixture.paths.applicationSupportRoot,
            codexRoot: fixture.paths.libraryDirectoryURL
        )
        let manager = GlobalConfigurationManager(paths: fixture.paths, locations: locations)
        #expect(throws: DeploymentError.self) {
            try manager.makeDeploymentPlan(
                host: .codex,
                selection: GlobalConfigurationDraft(skillIDs: [entry.id], instructionIDs: []),
                catalog: CatalogDocument(schemaVersion: 1, hashAlgorithm: "sha256:path-content-executable:v1", entries: [entry]),
                sourceURLs: [entry.id: source], fragments: [:], takeOverExisting: false, installMethod: .symlink
            )
        }
    }
}

private struct InventoryFixture {
    let root: URL
    let home: URL
    let paths: SkillSetRuntimePaths

    init() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("inventory-\(UUID())")
        home = root.appendingPathComponent("home")
        paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }

    func service() throws -> SkillSetService {
        try SkillSetService(
            paths: paths,
            globalLocations: GlobalConfigurationLocations(home: home, stateRoot: paths.applicationSupportRoot)
        )
    }
}
