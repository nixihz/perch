import Foundation
import Testing
@testable import SkillSetCore

struct PluginSourceLibraryTests {
    @Test func scanAndImportPreserveFullPackageAndInstallationsWithoutRunningHooks() throws {
        try fixture { root, home, plugin, library in
            let marker = root.appendingPathComponent("hook-ran")
            let hook = plugin.appendingPathComponent("hooks/run.sh")
            try Data("#!/bin/sh\ntouch '\(marker.path)'\n".utf8).write(to: hook)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
            let before = try SkillAssetCopier.analyze(from: plugin).contentHash
            let records = PluginInventoryManager(projectRoot: nil, homeDirectory: home).inspect().records
            let candidate = try #require(library.scan(records: records + records).first)
            #expect(candidate.records.count == 1)
            #expect(candidate.records[0].installed)
            #expect(candidate.canImport)
            #expect(try library.sources().isEmpty)
            let saved = try library.importCandidate(candidate)
            let copied = library.rootURL.appendingPathComponent(saved.id.uuidString).appendingPathComponent("checkout")
            #expect(try Data(contentsOf: copied.appendingPathComponent("hooks/run.sh")) == Data(contentsOf: hook))
            #expect(try SkillAssetCopier.analyze(from: copied).contentHash == before)
            #expect(try SkillAssetCopier.analyze(from: plugin).contentHash == before)
            #expect(!FileManager.default.fileExists(atPath: marker.path))
            #expect(try library.evidence(saved.id)?.installations.first?.pluginID == "demo@fixture")
            #expect(try library.inventory(saved.id).records.allSatisfy { !$0.installed })
            #expect(try library.scan(records: records).first?.collected == true)
            #expect(throws: PluginSourceError.alreadyCollected) { try library.importCandidate(candidate) }
            // 原安装移除后，收录包仍可独立读取。
            try FileManager.default.removeItem(at: plugin)
            #expect(try library.inventory(saved.id).records.first?.name == "demo")
            try library.remove(saved.id)
            #expect(try library.sources().isEmpty)
            #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude/plugins/installed_plugins.json").path))
        }
    }

    @Test func changedHookAfterScanIsRejectedEvenWhenManifestIsUnchanged() throws {
        try fixture { _, home, plugin, library in
            let records = PluginInventoryManager(projectRoot: nil, homeDirectory: home).inspect().records
            let candidate = try #require(library.scan(records: records).first)
            try Data("changed executable content".utf8).write(to: plugin.appendingPathComponent("hooks/run.sh"))
            #expect(throws: PluginSourceError.changed) { try library.importCandidate(candidate) }
            #expect(try library.sources().isEmpty)
            #expect(try library.scan(records: records).first?.contentHash != candidate.contentHash)
        }
    }

    @Test func outsideLinkBlocksImportAndSourceInventoryDoesNotFollowLinkedContainers() throws {
        try fixture { root, home, plugin, library in
            let outside = root.appendingPathComponent("outside")
            try Data("private".utf8).write(to: outside)
            try FileManager.default.createSymbolicLink(at: plugin.appendingPathComponent("outside"), withDestinationURL: outside)
            let records = PluginInventoryManager(projectRoot: nil, homeDirectory: home).inspect().records
            let candidate = try #require(library.scan(records: records).first)
            #expect(!candidate.canImport)
            #expect(candidate.issue != nil)
            #expect(throws: PluginSourceError.changed) { try library.importCandidate(candidate) }
            let source = root.appendingPathComponent("source")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("linked"), withDestinationURL: plugin)
            #expect(try PluginInventoryManager(projectRoot: nil, homeDirectory: home).inspectSource(at: source).records.isEmpty)
        }
    }

    @Test func sameContentMergesLocationsAndChangedContentCanBeCollectedSeparately() throws {
        try fixture { _, home, plugin, library in
            let second = home.appendingPathComponent(".claude/plugins/cache/fixture/demo/2")
            try FileManager.default.copyItem(at: plugin, to: second)
            let records = PluginInventoryManager(projectRoot: nil, homeDirectory: home).inspect().records
            let candidates = try library.scan(records: records)
            #expect(candidates.count == 1)
            #expect(candidates[0].records.count == 2)
            let saved = try library.importCandidate(candidates[0])
            #expect(try library.evidence(saved.id)?.installations.count == 2)
            try Data("new package revision".utf8).write(to: second.appendingPathComponent("hooks/run.sh"))
            let rescanned = try library.scan(records: PluginInventoryManager(projectRoot: nil, homeDirectory: home).inspect().records)
            #expect(rescanned.count == 2)
            #expect(rescanned.filter(\.canImport).count == 1)
            #expect(rescanned.filter(\.collected).count == 1)
        }
    }

    @Test func failedSourceEditKeepsPreviousSnapshot() throws {
        try fixture { root, _, plugin, library in
            let original = try library.save(address: plugin.path)
            #expect(try library.inventory(original.id).records.first?.name == "demo")
            #expect(throws: (any Error).self) { try library.save(address: root.appendingPathComponent("missing").path, replacing: original.id) }
            #expect(try library.sources().map(\.id) == [original.id])
            #expect(try library.inventory(original.id).records.first?.components.contains("hooks") == true)
        }
    }

    @Test func localSourceRevisionIncludesHooksWithoutAnySkills() throws {
        try fixture { _, _, plugin, library in
            let original = try library.save(address: plugin.path)
            try Data("updated hook".utf8).write(to: plugin.appendingPathComponent("hooks/run.sh"))
            let updated = try library.save(address: plugin.path, replacing: original.id)
            #expect(original.resolvedCommit != updated.resolvedCommit)
            #expect(try library.sources().map(\.id) == [updated.id])
            #expect(try library.inventory(updated.id).records.first?.name == "demo")
        }
    }

    private func fixture(_ body: (URL, URL, URL, PluginSourceLibrary) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let plugin = home.appendingPathComponent(".claude/plugins/cache/fixture/demo/1")
        try FileManager.default.createDirectory(at: plugin.appendingPathComponent(".claude-plugin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: plugin.appendingPathComponent("hooks"), withIntermediateDirectories: true)
        try Data(#"{"name":"demo","version":"1.0","hooks":{}}"#.utf8).write(to: plugin.appendingPathComponent(".claude-plugin/plugin.json"))
        try Data("original hook".utf8).write(to: plugin.appendingPathComponent("hooks/run.sh"))
        let index: [String: Any] = ["plugins": ["demo@fixture": [["installPath": plugin.path, "scope": "user", "enabled": true, "gitCommitSha": "fixed-revision"]]]]
        try JSONSerialization.data(withJSONObject: index).write(to: home.appendingPathComponent(".claude/plugins/installed_plugins.json"))
        try body(root, home, plugin, PluginSourceLibrary(stateRoot: root.appendingPathComponent("state")))
    }
}
