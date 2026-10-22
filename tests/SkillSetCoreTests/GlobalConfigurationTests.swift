import Foundation
import Testing
@testable import SkillSetCore

struct GlobalConfigurationTests {
    @Test(arguments: MCPHost.allCases, [SkillInstallMethod.copy, .symlink])
    func linkedSkillsRootSupportsInspectionDeploymentUndoAndBaselineRestore(host: MCPHost, method: SkillInstallMethod) throws {
        let f = try GlobalFixture(host: host)
        defer { f.cleanup() }
        let (alias, destination) = try f.linkSkillsRoot(relative: host == .codex)
        let originalLink = try FileManager.default.destinationOfSymbolicLink(atPath: alias.path)
        try f.write("已有技能", to: destination.appendingPathComponent("demo/SKILL.md"))
        try f.write("保留邻居", to: destination.appendingPathComponent("neighbor/SKILL.md"))
        let inspection = try f.manager.inspect(host: host)
        #expect(inspection.skillsPath == destination.path)
        #expect(inspection.resources.contains { $0.path == destination.appendingPathComponent("demo").path && !$0.managed })

        let pending = try f.plan(takeOver: true, method: method)
        #expect(pending.plan.changes.contains { URL(fileURLWithPath: pending.plan.projectPath).appendingPathComponent($0.relativePath).path == destination.appendingPathComponent("demo").path })
        #expect(try f.read(destination.appendingPathComponent("demo/SKILL.md")) == "已有技能")
        let first = try f.apply(pending)
        #expect(try f.read(alias.appendingPathComponent("demo/assets/data.txt")) == "完整附件")
        let isSkillLink = (try? FileManager.default.destinationOfSymbolicLink(atPath: f.skill.path)) != nil
        #expect(isSkillLink == (method == .symlink))
        #expect(try f.manager.inspect(host: host).resources.first { $0.path == f.skill.path }?.managed == true)
        _ = try f.revise()
        let second = try f.apply(f.plan(method: method))
        #expect(try f.read(f.skill.appendingPathComponent("SKILL.md")).contains("第二版"))
        _ = try f.apply(f.manager.makeUndoPlan(host: host, operationID: second.operationID))
        #expect(try f.read(f.skill.appendingPathComponent("SKILL.md")).contains("第一版"))
        _ = try f.apply(f.manager.makeRestorePlan(host: host, mode: .baseline))
        #expect(try f.read(alias.appendingPathComponent("demo/SKILL.md")) == "已有技能")
        #expect(try f.read(alias.appendingPathComponent("neighbor/SKILL.md")) == "保留邻居")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: alias.path) == originalLink)
        #expect(try !f.manager.inspect(host: host).hasManagement)
        #expect(try f.manager.history(host: host).contains { $0.id == first.operationID })
    }

    @Test(arguments: ["retarget-entry", "replace-real-directory", "remove-entry"])
    func changedSkillsRootRejectsOldPlanBeforeWritingEitherDirectory(change: String) throws {
        let f = try GlobalFixture()
        defer { f.cleanup() }
        let (alias, destination) = try f.linkSkillsRoot(relative: true)
        let other = f.root.appendingPathComponent("another skills")
        try f.write("原目录邻居", to: destination.appendingPathComponent("neighbor.txt"))
        try f.write("新目录邻居", to: other.appendingPathComponent("neighbor.txt"))
        let pending = try f.plan()
        let service = try f.service()
        _ = try service.approve(planID: pending.id, digest: pending.plan.digest)
        if change == "replace-real-directory" {
            try FileManager.default.moveItem(at: destination, to: f.root.appendingPathComponent("original skills"))
            try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: other)
        } else {
            try FileManager.default.removeItem(at: alias)
            if change == "retarget-entry" {
                try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: other)
            }
        }
        // 同一服务实例与重新启动后的服务都必须重新核验入口，不能只比较文件内容。
        for currentService in [service, try f.service()] {
            #expect(throws: FileTransactionError.staleFile(alias.path)) {
                try currentService.apply(planID: pending.id, digest: pending.plan.digest)
            }
        }
        let original = change == "replace-real-directory" ? f.root.appendingPathComponent("original skills") : destination
        #expect(try f.read(original.appendingPathComponent("neighbor.txt")) == "原目录邻居")
        #expect(try f.read(other.appendingPathComponent("neighbor.txt")) == "新目录邻居")
        #expect(!f.exists(original.appendingPathComponent("demo")))
        #expect(!f.exists(other.appendingPathComponent("demo")))
        #expect(!f.exists(f.rules))
        #expect(!f.exists(f.locations.stateURL(f.host)))
        #expect(!f.exists(f.paths.operationsRoot))
    }

    @Test(arguments: ["missing", "cycle", "file", "external-skill"])
    func unsupportedLinksStillBlockPlanningWithoutChangingResources(kind: String) throws {
        let f = try GlobalFixture()
        defer { f.cleanup() }
        let alias = f.locations.configuredSkillsRoot(f.host)
        try FileManager.default.createDirectory(at: alias.deletingLastPathComponent(), withIntermediateDirectories: true)
        let target = f.root.appendingPathComponent("link target")
        if kind == "file" { try f.write("不是目录", to: target) }
        if kind == "external-skill" {
            try f.write("外部技能", to: target.appendingPathComponent("SKILL.md"))
            try FileManager.default.createDirectory(at: alias, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: alias.appendingPathComponent("demo"), withDestinationURL: target)
        } else {
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: kind == "cycle" ? alias : target)
        }
        #expect(throws: (any Error).self) { try f.plan(takeOver: true) }
        #expect(!f.exists(f.rules))
        #expect(!f.exists(f.locations.stateURL(f.host)))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: kind == "external-skill" ? alias.appendingPathComponent("demo").path : alias.path)) != nil)
        if kind == "file" { #expect(try f.read(target) == "不是目录") }
        if kind == "external-skill" { #expect(try f.read(target.appendingPathComponent("SKILL.md")) == "外部技能") }
    }

    @Test
    func baselineRestorationKeepsOutsideEditsMadeBeforeAndAfterAnUpdate() throws {
        let f = try GlobalFixture()
        defer { f.cleanup() }
        let original = "用户前言\n<!-- skillset:begin id=global-rules schema=2 -->\n原始规则\n<!-- skillset:end id=global-rules -->\n用户结尾\n"
        try f.write(original, to: f.rules)
        _ = try f.apply(f.plan(takeOver: true))
        try f.write("更新前新增\n" + f.read(f.rules), to: f.rules)
        _ = try f.apply(f.plan(rule: "更新后的规则"))
        try f.write(f.read(f.rules) + "更新后新增\n", to: f.rules)
        _ = try f.apply(f.manager.makeRestorePlan(host: f.host, mode: .baseline))
        #expect(try f.read(f.rules) == "更新前新增\n" + original + "更新后新增\n")
    }

    @Test(arguments: MCPHost.allCases)
    func approvalGateCopiesWholePackageAndLeavesSourceAndNeighbors(host: MCPHost) throws {
        let f = try GlobalFixture(host: host)
        defer { f.cleanup() }
        try f.write("邻居", to: f.neighbor)
        let record = try f.plan()
        #expect(!f.exists(f.skill))
        #expect(!f.exists(f.rules))
        #expect(throws: DeploymentPlanStoreError.self) { try f.service().apply(planID: record.id, digest: record.plan.digest) }
        #expect(try f.read(f.neighbor) == "邻居")
        _ = try f.apply(record)
        #expect(try f.read(f.skill.appendingPathComponent("SKILL.md")).contains("第一版"))
        #expect(try f.read(f.skill.appendingPathComponent("assets/data.txt")) == "完整附件")
        #expect(try f.read(f.neighbor) == "邻居")
        #expect(try f.read(f.rules).contains("第一条规则"))
        #expect(try f.manager.inspect(host: host).resources.first { $0.path == f.skill.path }?.managed == true)
        #expect(try f.read(f.source.appendingPathComponent("SKILL.md")).contains("第一版"))
        #expect(!f.exists(f.home.appendingPathComponent("skillset.json")))
        #expect(!f.exists(f.home.appendingPathComponent("skillset.lock.json")))
        #expect(try ProjectStore(rootURL: f.paths.applicationSupportRoot).list().isEmpty)
    }

    @Test(arguments: MCPHost.allCases)
    func explicitTakeoverRetainsOriginalPackageAndPermissionsAcrossUpdates(host: MCPHost) throws {
        let f = try GlobalFixture(host: host)
        defer { f.cleanup() }
        try f.write("原来的技能", to: f.skill.appendingPathComponent("SKILL.md"))
        let executable = f.skill.appendingPathComponent("scripts/original.sh")
        try f.write("#!/bin/sh\nexit 0\n", to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try f.write("用户原始规则\n", to: f.rules)
        #expect(throws: DeploymentError.unmanagedSkillConflict(f.skill.path)) { try f.plan() }
        #expect(try f.read(f.skill.appendingPathComponent("SKILL.md")) == "原来的技能")
        _ = try f.apply(f.plan(takeOver: true))
        _ = try f.revise()
        _ = try f.apply(f.plan())
        _ = try f.apply(f.manager.makeRestorePlan(host: host, mode: .baseline))
        #expect(try f.read(f.skill.appendingPathComponent("SKILL.md")) == "原来的技能")
        #expect(try f.read(executable) == "#!/bin/sh\nexit 0\n")
        #expect(try FileManager.default.attributesOfItem(atPath: executable.path)[.posixPermissions] as? Int == 0o755)
        #expect(!f.exists(f.skill.appendingPathComponent("assets/data.txt")))
        #expect(try f.read(f.rules) == "用户原始规则\n")
        #expect(try !f.manager.inspect(host: host).hasManagement)
    }

    @Test
    func undoLatestThenEarlierDeploymentPreservesOutsideRuleEdits() throws {
        let f = try GlobalFixture()
        defer { f.cleanup() }
        let first = try f.apply(f.plan())
        _ = try f.revise()
        let second = try f.apply(f.plan(rule: "第二条规则"))
        #expect(throws: GlobalConfigurationError.self) { try f.manager.makeUndoPlan(host: f.host, operationID: first.operationID) }
        let edited = try f.read(f.rules) + "\n用户追加\n"
        try f.write(edited, to: f.rules)
        _ = try f.apply(f.manager.makeUndoPlan(host: f.host, operationID: second.operationID))
        #expect(try f.read(f.skill.appendingPathComponent("SKILL.md")).contains("第一版"))
        #expect(try f.read(f.rules).contains("第一条规则"))
        #expect(try f.read(f.rules).contains("用户追加"))
        _ = try f.apply(f.manager.makeUndoPlan(host: f.host, operationID: first.operationID))
        #expect(!f.exists(f.skill))
        #expect(try f.read(f.rules).contains("用户追加"))
        #expect(try !f.read(f.rules).contains("skillset:begin"))
        #expect(try f.manager.history(host: f.host).count == 4)
    }

    @Test(arguments: ["skill", "rule"])
    func laterUserEditsBlockRestoreWithoutChangingOtherFiles(kind: String) throws {
        let f = try GlobalFixture()
        defer { f.cleanup() }
        _ = try f.apply(f.plan())
        let target = kind == "skill" ? f.skill.appendingPathComponent("SKILL.md") : f.rules
        try f.write("用户新改动", to: target)
        let state = try Data(contentsOf: f.locations.stateURL(f.host))
        let originalRules = try Data(contentsOf: f.rules)
        #expect(throws: DeploymentError.self) { try f.manager.makeRestorePlan(host: f.host, mode: .baseline) }
        #expect(try Data(contentsOf: f.locations.stateURL(f.host)) == state)
        #expect(try Data(contentsOf: f.rules) == originalRules)
        #expect(try f.read(target) == "用户新改动")
    }

    @Test
    func stopManagementKeepsEditsAndUndoWillNotReadoptChangedFiles() throws {
        let f = try GlobalFixture()
        defer { f.cleanup() }
        _ = try f.apply(f.plan())
        try f.write("用户新改动", to: f.skill.appendingPathComponent("SKILL.md"))
        let rules = try f.read(f.rules)
        let stopped = try f.apply(f.manager.makeRestorePlan(host: f.host, mode: .keepFiles))
        #expect(try f.read(f.skill.appendingPathComponent("SKILL.md")) == "用户新改动")
        #expect(try f.read(f.rules) == rules)
        #expect(try !f.manager.inspect(host: f.host).hasManagement)
        #expect(throws: DeploymentError.self) { try f.manager.makeUndoPlan(host: f.host, operationID: stopped.operationID) }
    }

    @Test
    func matchingExternalContentIsNeverOwnedOrRemoved() throws {
        let f = try GlobalFixture()
        defer { f.cleanup() }
        _ = try SkillAssetCopier.copy(from: f.source, to: f.skill)
        _ = try f.apply(f.plan(instructions: false))
        let observations = try f.manager.inspect(host: f.host).resources
        let observed = try #require(observations.first(where: { $0.path == f.skill.path }), "\(observations.map { $0.path })")
        #expect(!observed.managed)
        _ = try f.apply(f.manager.makeRestorePlan(host: f.host, mode: .baseline))
        #expect(try f.read(f.skill.appendingPathComponent("SKILL.md")).contains("第一版"))
    }

    @Test(arguments: [false, true])
    func baselineRestoreDistinguishesAbsentFromEmptyRulesFile(wasEmptyFile: Bool) throws {
        let f = try GlobalFixture()
        defer { f.cleanup() }
        if wasEmptyFile { try f.write("", to: f.rules) }
        _ = try f.apply(f.plan())
        _ = try f.apply(f.manager.makeRestorePlan(host: f.host, mode: .baseline))
        #expect(f.exists(f.rules) == wasEmptyFile)
        if wasEmptyFile { #expect(try Data(contentsOf: f.rules).isEmpty) }
        #expect(!f.exists(f.skill))
    }

    @Test
    func missingOriginalBackupBlocksRestoreAndKeepsCurrentPackage() throws {
        let f = try GlobalFixture()
        defer { f.cleanup() }
        try f.write("原始技能", to: f.skill.appendingPathComponent("SKILL.md"))
        _ = try f.apply(f.plan(takeOver: true))
        try FileManager.default.removeItem(at: f.paths.applicationSupportRoot.appendingPathComponent("global-baselines"))
        #expect(throws: GlobalConfigurationError.self) { try f.manager.makeRestorePlan(host: f.host, mode: .baseline) }
        #expect(try f.read(f.skill.appendingPathComponent("SKILL.md")).contains("第一版"))
        #expect(try f.read(f.rules).contains("第一条规则"))
    }

    @Test(arguments: ["content", "parent-link"])
    func driftAfterPlanningRejectsApplyBeforeAnyOtherTargetWrites(kind: String) throws {
        let f = try GlobalFixture()
        defer { f.cleanup() }
        let pending = try f.plan()
        if kind == "content" { try f.write("后来新增的技能", to: f.skill.appendingPathComponent("SKILL.md")) }
        else {
            let outside = f.root.appendingPathComponent("outside")
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            let parent = f.locations.skillsRoot(f.host)
            try FileManager.default.createDirectory(at: parent.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: outside)
        }
        _ = try f.service().approve(planID: pending.id, digest: pending.plan.digest)
        #expect(throws: (any Error).self) { try f.service().apply(planID: pending.id, digest: pending.plan.digest) }
        #expect(!f.exists(f.rules))
        #expect(!f.exists(f.locations.stateURL(f.host)))
        if kind == "content" { #expect(try f.read(f.skill.appendingPathComponent("SKILL.md")) == "后来新增的技能") }
        else { #expect(try FileManager.default.contentsOfDirectory(atPath: f.root.appendingPathComponent("outside").path).isEmpty) }
    }

    @Test
    func stateWithoutCompletedLocalReceiptCannotAuthorizeRemoval() throws {
        let f = try GlobalFixture()
        defer { f.cleanup() }
        _ = try f.apply(f.plan())
        try FileManager.default.removeItem(at: f.paths.operationsRoot)
        #expect(throws: GlobalConfigurationError.self) { try f.manager.makeRestorePlan(host: f.host, mode: .baseline) }
        #expect(try f.read(f.skill.appendingPathComponent("SKILL.md")).contains("第一版"))
    }

    @Test
    func hostsAndDraftsRemainIndependentWithCustomHostDirectory() throws {
        let f = try GlobalFixture()
        defer { f.cleanup() }
        try f.manager.saveDraft(GlobalConfigurationDraft(skillIDs: [f.entry.id]), host: .codex)
        #expect(try f.manager.draft(host: .claudeCode).skillIDs.isEmpty)
        _ = try f.apply(f.plan())
        #expect(f.rules.path.contains("custom-codex"))
        #expect(!f.exists(f.locations.rulesURL(.claudeCode)))
        #expect(try !f.manager.inspect(host: .claudeCode).hasManagement)
        #expect(try f.manager.history(host: .claudeCode).isEmpty)
    }
}

private struct GlobalFixture {
    let root: URL
    let home: URL
    let paths: SkillSetRuntimePaths
    let locations: GlobalConfigurationLocations
    let host: MCPHost
    let entry: SkillEntry
    let source: URL
    var manager: GlobalConfigurationManager { GlobalConfigurationManager(paths: paths, locations: locations) }
    var skill: URL { locations.skillsRoot(host).appendingPathComponent("demo") }
    var rules: URL { locations.rulesURL(host) }
    var neighbor: URL { locations.skillsRoot(host).appendingPathComponent("neighbor/SKILL.md") }

    init(host: MCPHost = .codex) throws {
        self.host = host
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("global-tests-\(UUID())")
        home = root.appendingPathComponent("home")
        paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        locations = GlobalConfigurationLocations(home: home, stateRoot: paths.applicationSupportRoot,
            codexRoot: root.appendingPathComponent("custom-codex"))
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let library = SkillLibraryStore(rootURL: paths.libraryRoot)
        entry = try library.save(SkillEditorDraft(slug: "demo", document: "---\nname: demo\ndescription: 全局测试\n---\n第一版\n"), repositoryRoot: nil)
        source = try #require(library.sourceURLs()[entry.id])
        try FileManager.default.createDirectory(at: source.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try "完整附件".write(to: source.appendingPathComponent("assets/data.txt"), atomically: true, encoding: .utf8)
    }

    func service() throws -> SkillSetService { try SkillSetService(paths: paths, globalLocations: locations) }

    func plan(takeOver: Bool = false, instructions: Bool = true, rule: String = "第一条规则", method: SkillInstallMethod = .copy) throws -> StoredDeploymentPlan {
        // fixture 的资源包包含附件，按实际文件重新生成目录条目，验证不会只部署正文。
        let copy = try SkillAssetCopier.analyze(from: source)
        let entry = SkillEntry(id: entry.id, slug: entry.slug, declaredName: entry.declaredName,
            description: entry.description, declaredVersion: nil, metadataReview: "reviewed", sourceId: entry.sourceId,
            path: entry.path, contentHash: copy.contentHash, fileCount: copy.files.count, bytes: copy.bytes,
            integrity: "ok", issues: [], licenseReview: "pending", excludedPaths: [])
        return try manager.makeDeploymentPlan(host: host,
            selection: GlobalConfigurationDraft(skillIDs: [entry.id], instructionIDs: instructions ? ["rules"] : []),
            catalog: CatalogDocument(schemaVersion: 1, hashAlgorithm: "sha256:path-content-executable:v1", entries: [entry]),
            sourceURLs: [entry.id: source], fragments: ["rules": rule], takeOverExisting: takeOver, installMethod: method)
    }
    func linkSkillsRoot(relative: Bool) throws -> (alias: URL, destination: URL) {
        let alias = locations.configuredSkillsRoot(host)
        let destination = root.appendingPathComponent("shared skills")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: alias.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: alias.path,
            withDestinationPath: relative ? "../../shared skills" : destination.path)
        return (alias, destination)
    }
    @discardableResult func revise() throws -> String {
        try write("---\nname: demo\ndescription: 全局测试\n---\n第二版\n", to: source.appendingPathComponent("SKILL.md"))
        return "第二版"
    }
    func apply(_ record: StoredDeploymentPlan) throws -> ApplyServiceResult {
        let service = try service()
        _ = try service.approve(planID: record.id, digest: record.plan.digest)
        return try service.apply(planID: record.id, digest: record.plan.digest)
    }
    func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try value.write(to: url, atomically: true, encoding: .utf8)
    }
    func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
