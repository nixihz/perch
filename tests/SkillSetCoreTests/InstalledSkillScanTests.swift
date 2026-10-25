import Foundation
import Testing
@testable import SkillSetCore

struct InstalledSkillScanTests {
    @Test func separateCollectionsShareOneFixedLocalImportSource() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? fm.removeItem(at: root) }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let home = root.appendingPathComponent("home")
        let locations = GlobalConfigurationLocations(home: home, stateRoot: paths.applicationSupportRoot)
        let external = root.appendingPathComponent("outside")
        for (name, body) in [("first", "one"), ("second", "two")] {
            let skill = external.appendingPathComponent(name)
            try fm.createDirectory(at: skill, withIntermediateDirectories: true)
            try Data("---\nname: \(name)\ndescription: test\n---\n\(body)".utf8)
                .write(to: skill.appendingPathComponent("SKILL.md"))
        }
        let service = try SkillSetService(paths: paths, globalLocations: locations)
        let first = try #require(service.scanInstalledSkills(additionalRoots: [external]).first { $0.path.hasSuffix("/first") })
        _ = try service.importInstalledSkills([first])
        let next = try #require(SkillSetService(paths: paths, globalLocations: locations)
            .scanInstalledSkills(additionalRoots: [external]).first { $0.path.hasSuffix("/second") && $0.canImport })
        try service.importInstalledSkills([next])
        #expect(!fm.fileExists(atPath: paths.applicationSupportRoot.appendingPathComponent("sources/local-imports").path))
        #expect(try service.sourcePreviews().isEmpty)
        let reloaded = try SkillSetService(paths: paths, globalLocations: locations)
        let stored = reloaded.skills(query: "")
        #expect(stored.count == 2)
        #expect(stored.allSatisfy { $0.sourceId == SkillLibraryStore.sourceID })
        let custom = paths.applicationSupportRoot.appendingPathComponent("sources/custom/first")
        #expect(try fm.destinationOfSymbolicLink(atPath: home.appendingPathComponent(".agents/skills/first").path) == custom.path)
    }

    @Test func legacyLocalImportDirectoriesMigrateAndDeduplicate() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? fm.removeItem(at: root) }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let home = root.appendingPathComponent("home")
        let locations = GlobalConfigurationLocations(home: home, stateRoot: paths.applicationSupportRoot)
        let sourceRoot = root.appendingPathComponent("source-packages")
        var packages: [(URL, String)] = []
        for (name, body) in [("first", "one"), ("second", "two")] {
            let skill = sourceRoot.appendingPathComponent(name)
            try fm.createDirectory(at: skill, withIntermediateDirectories: true)
            try Data("---\nname: \(name)\ndescription: test\n---\n\(body)".utf8)
                .write(to: skill.appendingPathComponent("SKILL.md"))
            packages.append((skill, try SkillAssetCopier.analyze(from: skill).contentHash))
        }
        let localImports = paths.applicationSupportRoot.appendingPathComponent("sources/local-imports")
        let legacyRoots = [localImports.appendingPathComponent("old-a"), localImports.appendingPathComponent("old-b")]
        for (index, legacy) in legacyRoots.enumerated() {
            let (package, hash) = packages[index]
            let destination = legacy.appendingPathComponent(hash).appendingPathComponent(package.lastPathComponent)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = try SkillAssetCopier.copy(from: package, to: destination)
            let observation = InstalledSkillObservation(path: package.path, resolvedPath: package.path, contentHash: hash,
                                                        managed: false, collected: false, issue: nil)
            let encoder = JSONEncoder()
            try encoder.encode([observation]).write(to: legacy.appendingPathComponent("installed-origins.json"))
            try Data("now".utf8).write(to: legacy.appendingPathComponent("scanned-at.txt"))
        }
        let service = try SkillSetService(paths: paths, globalLocations: locations)
        #expect(!fm.fileExists(atPath: localImports.path))
        #expect(try service.sourcePreviews().isEmpty)
        #expect(try service.consolidateInstalledSkillSources() == false)
        let reloaded = try SkillSetService(paths: paths, globalLocations: locations)
        let stored = reloaded.skills(query: "")
        #expect(stored.count == 2)
        #expect(stored.allSatisfy { $0.sourceId == SkillLibraryStore.sourceID })
        #expect(fm.fileExists(atPath: paths.applicationSupportRoot.appendingPathComponent("sources/custom/first/SKILL.md").path))
    }

    @Test func linkedRootPreservesInstallPathAndBadRootDoesNotAbortScan() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? fm.removeItem(at: root) }
        let real = root.appendingPathComponent("packages")
        let skill = real.appendingPathComponent("demo")
        try fm.createDirectory(at: skill, withIntermediateDirectories: true)
        try Data("---\nname: demo\ndescription: example\n---\nLinked root".utf8).write(to: skill.appendingPathComponent("SKILL.md"))
        let home = root.appendingPathComponent("home")
        try fm.createDirectory(at: home.appendingPathComponent(".agents/skills"), withIntermediateDirectories: true)
        let linked = root.appendingPathComponent("linked-skills")
        try fm.createSymbolicLink(at: linked, withDestinationURL: real)
        let badRoot = root.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: badRoot)
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let service = try SkillSetService(paths: paths, globalLocations: .init(home: home, stateRoot: paths.applicationSupportRoot))
        let scan = try service.scanInstalledSkills(additionalRoots: [badRoot, linked, real])
        let observed = try #require(scan.first { $0.path == linked.appendingPathComponent("demo").path })
        #expect(observed.resolvedPath == skill.path)
        #expect(observed.canImport)
        #expect(scan.first { $0.path == badRoot.path }?.issue != nil)
        #expect(scan.contains { $0.path == skill.path && $0.canImport })
        try service.importInstalledSkills([observed])
        #expect(fm.fileExists(atPath: paths.applicationSupportRoot.appendingPathComponent("sources/custom/demo/SKILL.md").path))
        #expect(try fm.destinationOfSymbolicLink(atPath: linked.path) == real.path)
        #expect(try service.scanInstalledSkills(additionalRoots: [linked]).first { $0.path == observed.path }?.collected == true)
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
        let importable = try service.scanInstalledSkills().filter(\.canImport)
        _ = try service.importInstalledSkills(importable)
        let stored = try SkillSetService(paths: paths, globalLocations: locations).skills(query: "demo")
        #expect(stored.count == 1)
        #expect(stored.first?.sourceId == SkillLibraryStore.sourceID)
        #expect(try String(contentsOf: paths.applicationSupportRoot.appendingPathComponent("sources/custom/demo/SKILL.md"), encoding: .utf8).contains("first"))
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
        let first = root.appendingPathComponent("loose/demo")
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
        let scan = try service.scanInstalledSkills(additionalRoots: [first.deletingLastPathComponent()])
        #expect(scan.filter(\.canImport).count == 2)
        #expect(scan.first { $0.path == broken.path }?.issue != nil)
        try service.importInstalledSkills(scan.filter(\.canImport))
        let reloaded = try SkillSetService(paths: paths, globalLocations: locations)
        #expect(reloaded.skills(query: "demo").count == 1)
        #expect(!FileManager.default.fileExists(atPath: paths.applicationSupportRoot.appendingPathComponent("sources/local-imports").path))
        #expect(try reloaded.scanInstalledSkills().filter(\.canImport).isEmpty)
        let origin = try #require(reloaded.libraryStore().sourceOrigins()["demo"])
        #expect(origin.url == first.path || origin.url == second.path)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: second.path) == first.path)
        #expect(try Data(contentsOf: first.appendingPathComponent("asset.bin")) == Data([0, 128, 255]))
        let collected = try reloaded.scanInstalledSkills(additionalRoots: [first.deletingLastPathComponent()]).first(where: { $0.path == first.path })!
        try reloaded.removeInstalledSkill(collected)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(try SkillSetService(paths: paths, globalLocations: locations).skills(query: "demo").count == 1)
        #expect(try reloaded.sourcePreviews().isEmpty)
        #expect(try reloaded.scanInstalledSkills().filter(\.canImport).isEmpty)
        #expect(try SkillSetService(paths: paths, globalLocations: locations).skills(query: "demo").count == 1)
    }

    @Test func externalSkillFileLinkUsesRealPackageAndKeepsWrapperInstallation() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? fm.removeItem(at: root) }
        let real = root.appendingPathComponent("gstack/open-gstack-browser")
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        try Data("---\nname: open-gstack-browser\ndescription: example\n---\nreal package".utf8)
            .write(to: real.appendingPathComponent("SKILL.md"))
        try Data("template".utf8).write(to: real.appendingPathComponent("SKILL.md.tmpl"))

        let home = root.appendingPathComponent("home")
        let wrapper = home.appendingPathComponent(".claude/skills/open-gstack-browser")
        try fm.createDirectory(at: wrapper, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: wrapper.appendingPathComponent("SKILL.md"),
                                  withDestinationURL: real.appendingPathComponent("SKILL.md"))

        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let locations = GlobalConfigurationLocations(home: home, stateRoot: paths.applicationSupportRoot)
        let service = try SkillSetService(paths: paths, globalLocations: locations)
        let observed = try #require(service.scanInstalledSkills().first { $0.path == wrapper.path })
        #expect(observed.resolvedPath == real.path)
        #expect(observed.canImport)

        try service.importInstalledSkills([observed])
        #expect(fm.fileExists(atPath: paths.applicationSupportRoot.appendingPathComponent("sources/custom/open-gstack-browser/SKILL.md").path))
        #expect(fm.fileExists(atPath: wrapper.path))
        #expect(try fm.destinationOfSymbolicLink(atPath: wrapper.appendingPathComponent("SKILL.md").path) ==
                real.appendingPathComponent("SKILL.md").path)

        let collected = try service.scanInstalledSkills().first { $0.path == wrapper.path }
        #expect(collected?.collected == true)
        if let collected { try service.removeInstalledSkill(collected) }
        #expect(!fm.fileExists(atPath: wrapper.path))
        #expect(fm.fileExists(atPath: real.appendingPathComponent("SKILL.md").path))
    }
}
