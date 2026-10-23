import Foundation
import Testing
@testable import SkillSetCore

struct InstalledSkillScanTests {
    @Test func linkedRootPreservesInstallPathAndBadRootDoesNotAbortScan() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? fm.removeItem(at: root) }
        let real = root.appendingPathComponent("packages")
        let skill = real.appendingPathComponent("demo")
        try fm.createDirectory(at: skill, withIntermediateDirectories: true)
        try Data("---\nname: demo\ndescription: example\n---\nLinked root".utf8).write(to: skill.appendingPathComponent("SKILL.md"))
        let home = root.appendingPathComponent("home")
        let linked = home.appendingPathComponent(".agents/skills")
        try fm.createDirectory(at: linked.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: linked, withDestinationURL: real)
        let badRoot = root.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: badRoot)
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let service = try SkillSetService(paths: paths, globalLocations: .init(home: home, stateRoot: paths.applicationSupportRoot))
        let scan = try service.scanInstalledSkills(additionalRoots: [badRoot, real])
        let observed = try #require(scan.first { $0.path == linked.appendingPathComponent("demo").path })
        #expect(observed.resolvedPath == skill.path)
        #expect(observed.canImport)
        #expect(scan.first { $0.path == badRoot.path }?.issue != nil)
        #expect(scan.contains { $0.path == skill.path && $0.canImport })
        let imported = try service.importInstalledSkills([observed])
        #expect(imported.candidates.count == 1)
        #expect(try fm.destinationOfSymbolicLink(atPath: linked.path) == real.path)
        #expect(try service.scanInstalledSkills().first { $0.path == observed.path }?.collected == true)
    }

    @Test func sameNamesKeepDifferentContentsAndManagedLinksAreNotImported() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let root = temporary.resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let locations = GlobalConfigurationLocations(home: root, stateRoot: paths.applicationSupportRoot)
        for (folder, body) in [(".agents/skills/demo", "first"), (".claude/skills/demo", "second")] {
            let skill = root.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
            try Data("---\nname: demo\ndescription: example\n---\n\(body)".utf8).write(to: skill.appendingPathComponent("SKILL.md"))
        }
        let service = try SkillSetService(paths: paths, globalLocations: locations)
        let scan = try service.scanInstalledSkills()
        _ = try service.importInstalledSkills(scan)
        #expect(try SkillSetService(paths: paths, globalLocations: locations).skills(query: "demo").count == 2)
        let first = root.appendingPathComponent(".agents/skills/demo")
        let hash = try SkillAssetCopier.analyze(from: first).contentHash
        let version = try ManagedSkillLink.prepare(source: first, contentHash: hash, root: paths.versionsRoot)
        try FileManager.default.removeItem(at: first)
        try FileManager.default.createSymbolicLink(at: first, withDestinationURL: version)
        let managed = try #require(service.scanInstalledSkills().first { $0.path == first.path })
        #expect(managed.managed)
        #expect(!managed.canImport)
    }

    @Test func scanImportDeduplicatesAndPreservesInstallationsAndEvidence() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let root = temporary.resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let home = root.appendingPathComponent("home")
        let locations = GlobalConfigurationLocations(home: home, stateRoot: paths.applicationSupportRoot)
        let first = home.appendingPathComponent(".agents/skills/demo")
        let second = home.appendingPathComponent(".claude/skills/demo")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try Data("---\nname: demo\ndescription: imported skill\n---\n# Demo\n".utf8).write(to: first.appendingPathComponent("SKILL.md"))
        try Data([0, 128, 255]).write(to: first.appendingPathComponent("asset.bin"))
        try FileManager.default.createDirectory(at: second.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: second, withDestinationURL: first)
        let broken = second.deletingLastPathComponent().appendingPathComponent("broken")
        try FileManager.default.createSymbolicLink(atPath: broken.path, withDestinationPath: root.appendingPathComponent("missing").path)
        let service = try SkillSetService(paths: paths, globalLocations: locations)
        let direct = try service.scanInstalledSkills(additionalRoots: [first])
        #expect(direct.contains { $0.path == first.path && $0.canImport })
        let scan = try service.scanInstalledSkills()
        #expect(scan.filter(\.canImport).count == 2)
        #expect(scan.first { $0.path == broken.path }?.issue != nil)
        let record = try service.importInstalledSkills(scan.filter(\.canImport))
        let reloaded = try SkillSetService(paths: paths, globalLocations: locations)
        #expect(reloaded.skills(query: "demo").count == 1)
        #expect(record.candidates.count == 1)
        #expect(try reloaded.scanInstalledSkills().filter(\.canImport).isEmpty)
        let source = URL(fileURLWithPath: record.canonicalURL.replacingOccurrences(of: "file://", with: ""))
        let evidence = try JSONDecoder().decode([InstalledSkillObservation].self, from: Data(contentsOf: source.appendingPathComponent("installed-origins.json")))
        #expect(Set(evidence.map(\.path)) == Set([first.path, second.path]))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: second.path) == first.path)
        #expect(try Data(contentsOf: first.appendingPathComponent("asset.bin")) == Data([0, 128, 255]))
        try Data("changed".utf8).write(to: first.appendingPathComponent("asset.bin"))
        #expect(throws: SourceSkillImportError.self) { try service.importInstalledSkills(scan.filter(\.canImport)) }
        #expect(try reloaded.sourcePreviews().count == 1)
        try FileManager.default.removeItem(at: first)
        #expect(try SkillSetService(paths: paths, globalLocations: locations).skills(query: "demo").count == 1)
    }
}
