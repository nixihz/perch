import Foundation
import Testing
@testable import SkillSetCore

struct ProjectIntegrationTests {
    @Test
    func deploymentKeepsManagementRecordsOutsideProjectAndPreservesUnrelatedJSON() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let userFile = fixture.project.appendingPathComponent("skillset.json")
        let userContent = Data("用户自己的文件，不是安装清单".utf8)
        try userContent.write(to: userFile)
        let result = try apply(fixture.makePlan(), in: fixture)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: fixture.project.path)) == ["skillset.json", ".agents", "AGENTS.md"])
        #expect(try Data(contentsOf: userFile) == userContent)
        #expect(try fixture.stateStore.loadManifest()?.skills == ["workspace/demo"])
        #expect(try fixture.stateStore.loadLock()?.skills.first?.files.count == 2)
        #expect(throws: DeploymentError.noChanges) { try fixture.makePlan() }
        _ = try FileTransactionExecutor(operationsRoot: fixture.operations).rollback(operationID: result.operationID)
        #expect(try Data(contentsOf: userFile) == userContent)
        #expect(try fixture.stateStore.loadManifest() == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent("skillset.lock.json").path))
    }

    @Test
    func stateDirectorySymlinkReplacementRejectsApplyBeforeWritingProject() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let plan = try fixture.makePlan()
        let outside = fixture.root.appendingPathComponent("outside")
        let stateDirectory = fixture.stateStore.directoryURL
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stateDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: stateDirectory, withDestinationURL: outside)
        #expect(throws: FileTransactionError.self) { try apply(plan, in: fixture) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.project.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test
    func oldDeploymentPlanCannotWriteManagementFilesBackIntoProject() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let current = try fixture.makePlan()
        let legacy = DeploymentPlan(
            id: current.id, projectPath: current.projectPath, createdAt: current.createdAt,
            digest: current.digest,
            changes: current.changes.map { PlannedChange(action: $0.action, relativePath: $0.relativePath,
                beforeHash: $0.beforeHash, afterHash: $0.afterHash, unifiedDiff: $0.unifiedDiff) },
            warnings: current.warnings, metadata: ["planType": "skill-deployment"],
            ownershipReceipt: current.ownershipReceipt, observations: current.observations
        )
        #expect(throws: DeploymentError.invalidPlan) { try apply(legacy, in: fixture) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.project.path).isEmpty)
    }

    @Test
    func legacyInstallationWithLocalReceiptMovesFutureManagementIntoApplicationState() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        _ = try apply(fixture.makePlan(), in: fixture)
        let manifestData = try Data(contentsOf: fixture.stateStore.manifestURL)
        let lockData = try Data(contentsOf: fixture.stateStore.lockURL)
        try manifestData.write(to: fixture.project.appendingPathComponent("skillset.json"))
        try lockData.write(to: fixture.project.appendingPathComponent("skillset.lock.json"))
        try FileManager.default.removeItem(at: fixture.stateStore.directoryURL)
        let migration = try fixture.makePlan(skillIDs: [])
        #expect(migration.changes.contains { $0.relativePath == ".agents/skills/demo" && $0.action == "remove" })
        #expect(migration.changes.filter { $0.relativePath.hasPrefix("skillset.") }.allSatisfy { $0.scope == "project-state" })
        _ = try apply(migration, in: fixture)
        #expect(try fixture.stateStore.loadManifest()?.skills.isEmpty == true)
        #expect(!FileManager.default.fileExists(atPath: skillURL(fixture).path))
        #expect(try Data(contentsOf: fixture.project.appendingPathComponent("skillset.json")) == manifestData)
        #expect(try Data(contentsOf: fixture.project.appendingPathComponent("skillset.lock.json")) == lockData)
    }

    @Test
    func deselectingOwnedSkillRemovesItAndRollbackRestoresFilesAndLock() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        _ = try apply(fixture.makePlan(), in: fixture)
        let lockURL = fixture.stateStore.lockURL
        let originalLock = try Data(contentsOf: lockURL)
        let plan = try fixture.makePlan(skillIDs: [])
        #expect(plan.changes.contains { $0.relativePath == ".agents/skills/demo" && $0.action == "remove" })
        #expect(FileManager.default.fileExists(atPath: skillURL(fixture).path))
        let removed = try apply(plan, in: fixture)
        #expect(!FileManager.default.fileExists(atPath: skillURL(fixture).path))
        #expect(try fixture.stateStore.loadLock()?.skills.isEmpty == true)
        _ = try FileTransactionExecutor(operationsRoot: fixture.operations).rollback(operationID: removed.operationID)
        #expect(try String(contentsOf: skillURL(fixture).appendingPathComponent("SKILL.md"), encoding: .utf8) == "# Demo\n")
        let permissions = try FileManager.default.attributesOfItem(atPath: skillURL(fixture).appendingPathComponent("scripts/run.sh").path)
        #expect(((permissions[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o111 != 0)
        #expect(try Data(contentsOf: lockURL) == originalLock)
        // 撤销删除后，原操作记录仍能证明归属。
        #expect(try fixture.makePlan(skillIDs: []).changes.contains { $0.action == "remove" })
    }

    @Test
    func matchingExistingSkillNeverBecomesOwnedAcrossRepeatedPlans() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        _ = try SkillAssetCopier.copy(from: fixture.repository.appendingPathComponent("skills/demo"), to: skillURL(fixture))
        let first = try fixture.makePlan()
        #expect(!first.changes.contains { $0.relativePath == ".agents/skills/demo" })
        #expect(first.warnings.contains { $0.contains("保留原归属") })
        _ = try apply(first, in: fixture)
        _ = try apply(fixture.makePlan(instructionIDs: []), in: fixture)
        let cancelled = try fixture.makePlan(skillIDs: [], instructionIDs: [])
        #expect(!cancelled.changes.contains { $0.relativePath == ".agents/skills/demo" })
        _ = try apply(cancelled, in: fixture)
        #expect(try String(contentsOf: skillURL(fixture).appendingPathComponent("SKILL.md"), encoding: .utf8) == "# Demo\n")
    }

    @Test
    func copiedProjectLockWithoutLocalReceiptDoesNotAuthorizeDeletion() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        _ = try apply(fixture.makePlan(), in: fixture)
        try FileManager.default.removeItem(at: fixture.operations)
        let cancelled = try fixture.makePlan(skillIDs: [])
        #expect(!cancelled.changes.contains { $0.action == "remove" })
        _ = try apply(cancelled, in: fixture)
        #expect(FileManager.default.fileExists(atPath: skillURL(fixture).appendingPathComponent("SKILL.md").path))
    }

    @Test(arguments: [true, false])
    func userEditsBlockManagedUpdateAndRemoval(deselect: Bool) throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        _ = try apply(fixture.makePlan(), in: fixture)
        let lockURL = fixture.stateStore.lockURL
        let oldLock = try Data(contentsOf: lockURL)
        try "用户自己的版本\n".write(to: skillURL(fixture).appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        #expect(throws: DeploymentError.managedSkillDrift(".agents/skills/demo")) {
            try fixture.makePlan(skillIDs: deselect ? [] : ["workspace/demo"])
        }
        #expect(try Data(contentsOf: lockURL) == oldLock)
        #expect(try String(contentsOf: skillURL(fixture).appendingPathComponent("SKILL.md"), encoding: .utf8) == "用户自己的版本\n")
    }

    @Test
    func managedRevisionUpdateCanBeUndone() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        _ = try apply(fixture.makePlan(), in: fixture)
        let source = fixture.repository.appendingPathComponent("skills/demo")
        try "# Demo v2\n".write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let revised = try revisedCatalog(fixture, source: source)
        let update = try fixture.makePlan(catalogOverride: revised)
        #expect(update.changes.contains { $0.relativePath == ".agents/skills/demo" && $0.action == "update" })
        let result = try apply(update, in: fixture)
        #expect(try String(contentsOf: skillURL(fixture).appendingPathComponent("SKILL.md"), encoding: .utf8) == "# Demo v2\n")
        _ = try FileTransactionExecutor(operationsRoot: fixture.operations).rollback(operationID: result.operationID)
        #expect(try String(contentsOf: skillURL(fixture).appendingPathComponent("SKILL.md"), encoding: .utf8) == "# Demo\n")
    }

    @Test
    func removingOneHostKeepsTheOtherHostsSkillAndExternalNeighbors() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        _ = try apply(fixture.makePlan(agents: ["codex", "claude-code"]), in: fixture)
        let neighbor = fixture.project.appendingPathComponent(".agents/skills/personal/SKILL.md")
        try FileManager.default.createDirectory(at: neighbor.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "个人技能".write(to: neighbor, atomically: true, encoding: .utf8)
        _ = try apply(fixture.makePlan(agents: ["claude-code"]), in: fixture)
        #expect(!FileManager.default.fileExists(atPath: skillURL(fixture).path))
        #expect(FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent(".claude/skills/demo/SKILL.md").path))
        #expect(try String(contentsOf: neighbor, encoding: .utf8) == "个人技能")
        #expect(!(try String(contentsOf: fixture.project.appendingPathComponent("AGENTS.md"), encoding: .utf8)).contains("skillset:begin"))
        #expect(try String(contentsOf: fixture.project.appendingPathComponent("CLAUDE.md"), encoding: .utf8).contains("只做受管内容"))
    }

    @Test(arguments: ["selected", "removed", "lock"])
    func changedReadDependenciesRejectApplyBeforeAnyWrites(target: String) throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        _ = try apply(fixture.makePlan(), in: fixture)
        let plan = try fixture.makePlan(skillIDs: target == "selected" ? ["workspace/demo"] : [], instructionIDs: [])
        let changed = target == "lock" ? fixture.stateStore.lockURL : fixture.project.appendingPathComponent(".agents/skills/demo/SKILL.md")
        try "外部变更".write(to: changed, atomically: true, encoding: .utf8)
        let rules = try Data(contentsOf: fixture.project.appendingPathComponent("AGENTS.md"))
        #expect(throws: FileTransactionError.self) { try apply(plan, in: fixture) }
        #expect(try Data(contentsOf: fixture.project.appendingPathComponent("AGENTS.md")) == rules)
        #expect(try String(contentsOf: changed, encoding: .utf8) == "外部变更")
    }

    @Test
    func rollbackConflictIsPreflightedWithoutPartiallyRevertingLock() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let result = try apply(fixture.makePlan(), in: fixture)
        let lockURL = fixture.stateStore.lockURL
        let lock = try Data(contentsOf: lockURL)
        try "新编辑".write(to: skillURL(fixture).appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        #expect(throws: FileTransactionError.rollbackConflict(".agents/skills/demo")) {
            try FileTransactionExecutor(operationsRoot: fixture.operations).rollback(operationID: result.operationID)
        }
        #expect(try Data(contentsOf: lockURL) == lock)
        #expect(try fixture.stateStore.loadManifest()?.skills == ["workspace/demo"])
    }

    @Test
    func rollbackRemovalDoesNotOverwriteANewDirectory() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        _ = try apply(fixture.makePlan(), in: fixture)
        let result = try apply(fixture.makePlan(skillIDs: []), in: fixture)
        try FileManager.default.createDirectory(at: skillURL(fixture), withIntermediateDirectories: true)
        try "新目录".write(to: skillURL(fixture).appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        #expect(throws: FileTransactionError.rollbackConflict(".agents/skills/demo")) {
            try FileTransactionExecutor(operationsRoot: fixture.operations).rollback(operationID: result.operationID)
        }
        #expect(try String(contentsOf: skillURL(fixture).appendingPathComponent("SKILL.md"), encoding: .utf8) == "新目录")
    }

    @Test(arguments: [false, true])
    func danglingAndLiveSymlinksArePreserved(isLive: Bool) throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let outside = fixture.root.appendingPathComponent("outside")
        if isLive { try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true) }
        let target = skillURL(fixture)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
        #expect(throws: DeploymentError.symlinkDetected(target.path)) { try fixture.makePlan() }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: target.path) == outside.path)
        #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("SKILL.md").path))
    }

    @Test
    func originallyEmptyRulesFileRemainsAnEmptyFileAfterRollback() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let rules = fixture.project.appendingPathComponent("AGENTS.md")
        try Data().write(to: rules)
        let result = try apply(fixture.makePlan(), in: fixture)
        _ = try FileTransactionExecutor(operationsRoot: fixture.operations).rollback(operationID: result.operationID)
        #expect(FileManager.default.fileExists(atPath: rules.path))
        #expect(try Data(contentsOf: rules).isEmpty)
    }

    @Test
    func corruptOrOrphanedLockCannotBeSilentlyReplaced() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let lock = fixture.stateStore.lockURL
        try FileManager.default.createDirectory(at: lock.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "broken".write(to: lock, atomically: true, encoding: .utf8)
        #expect(throws: ProjectLockError.corruptLock(lock.path)) { try fixture.makePlan() }
        #expect(try String(contentsOf: lock, encoding: .utf8) == "broken")
        #expect(!FileManager.default.fileExists(atPath: skillURL(fixture).path))
    }

    @Test
    func interruptedRemovalCanRecoverFromItsDurableJournal() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        _ = try apply(fixture.makePlan(), in: fixture)
        let result = try apply(fixture.makePlan(skillIDs: []), in: fixture)
        let executor = FileTransactionExecutor(operationsRoot: fixture.operations)
        var journal = try executor.loadJournal(result.operationID)
        // 模拟已移走技能、尚未继续写锁的中断状态，恢复器必须从 displaced 还原。
        for index in journal.steps.indices {
            if journal.steps[index].action == "remove" {
                let backup = fixture.operations.appendingPathComponent("\(result.operationID.uuidString)/backup/\(journal.steps[index].relativePath)")
                let displaced = URL(fileURLWithPath: try #require(journal.steps[index].displacedPath))
                try FileManager.default.copyItem(at: backup, to: displaced)
                journal.steps[index].state = "old-moved"
            }
        }
        journal.state = "applying"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(journal).write(to: result.journalURL)
        #expect(try executor.recoverPendingOperations() == [result.operationID])
        #expect(try String(contentsOf: skillURL(fixture).appendingPathComponent("SKILL.md"), encoding: .utf8) == "# Demo\n")
        #expect(try executor.loadJournal(result.operationID).state == "rolled-back")
        #expect(try executor.recoverPendingOperations().isEmpty)
    }

    @Test(arguments: [false, true])
    func interruptedRollbackResumesFromItsRestorePaths(alreadyRestored: Bool) throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let rules = fixture.project.appendingPathComponent("AGENTS.md")
        try "接入前的规则\n".write(to: rules, atomically: true, encoding: .utf8)
        let result = try apply(fixture.makePlan(), in: fixture)
        let executor = FileTransactionExecutor(operationsRoot: fixture.operations)
        var journal = try executor.loadJournal(result.operationID)
        let index = try #require(journal.steps.firstIndex { $0.relativePath == "AGENTS.md" })
        let restore = fixture.project.appendingPathComponent(".skillset-interrupted-restore")
        let discarded = fixture.project.appendingPathComponent(".skillset-interrupted-discarded")
        try FileManager.default.moveItem(at: rules, to: discarded)
        let backup = fixture.operations.appendingPathComponent("\(result.operationID.uuidString)/backup/AGENTS.md")
        try FileManager.default.copyItem(at: backup, to: alreadyRestored ? rules : restore)
        journal.steps[index].state = "restoring"
        journal.steps[index].restorePath = restore.path
        journal.steps[index].discardedPath = discarded.path
        journal.state = "rolling-back"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(journal).write(to: result.journalURL)
        #expect(try executor.recoverPendingOperations() == [result.operationID])
        #expect(try String(contentsOf: rules, encoding: .utf8) == "接入前的规则\n")
        #expect(!FileManager.default.fileExists(atPath: restore.path))
        #expect(!FileManager.default.fileExists(atPath: discarded.path))
        #expect(!FileManager.default.fileExists(atPath: skillURL(fixture).path))
        #expect(try executor.recoverPendingOperations().isEmpty)
    }

    @Test(arguments: [false, true])
    func interruptedNewFileRenameDoesNotLeaveAnUntrackedFile(beforeRename: Bool) throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let staged = fixture.staging.appendingPathComponent("new-file.txt")
        try "本次新增文件".write(to: staged, atomically: true, encoding: .utf8)
        let change = PlannedChange(
            action: "add", relativePath: "new-file.txt", beforeHash: nil,
            afterHash: try SkillAssetCopier.sha256(fileAt: staged), unifiedDiff: "新增文件"
        )
        let plan = DeploymentPlan(
            projectPath: fixture.project.path, createdAt: Date(),
            digest: DeploymentPlanner.calculateDigest(projectPath: fixture.project.path, changes: [change], selectedSkills: []),
            changes: [change], warnings: []
        )
        let executor = FileTransactionExecutor(operationsRoot: fixture.operations)
        let result = try executor.apply(plan: plan, from: fixture.staging)
        var journal = try executor.loadJournal(result.operationID)
        let target = fixture.project.appendingPathComponent("new-file.txt")
        let temporary = URL(fileURLWithPath: try #require(journal.steps[0].temporaryPath))
        if beforeRename { try FileManager.default.moveItem(at: target, to: temporary) }
        journal.steps[0].state = "staged"
        journal.state = "applying"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(journal).write(to: result.journalURL)
        #expect(try executor.recoverPendingOperations() == [result.operationID])
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
        #expect(try executor.loadJournal(result.operationID).state == "rolled-back")
    }

    @Test
    func inspectionFindsBothHostsWithoutWritingOrClaimingExistingSkills() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let claude = fixture.project.appendingPathComponent(".claude/skills/demo")
        _ = try SkillAssetCopier.copy(from: fixture.repository.appendingPathComponent("skills/demo"), to: claude)
        let result = try ProjectInspector.inspect(projectURL: fixture.project, catalog: fixture.catalog, operationsRoot: fixture.operations)
        #expect(result.observedSkillIDs == ["workspace/demo"])
        let observation = try #require(result.skillObservations.first)
        #expect(observation.relativePath == ".claude/skills/demo")
        #expect(observation.ownership == "existing")
        #expect(!FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent("skillset.json").path))
        _ = try apply(fixture.makePlan(), in: fixture)
        let managed = try ProjectInspector.inspect(projectURL: fixture.project, catalog: fixture.catalog, operationsRoot: fixture.operations)
        #expect(managed.skillObservations.first { $0.agent == "codex" }?.ownership == "managed")
        #expect(managed.skillObservations.first { $0.agent == "claude-code" }?.ownership == "existing")
    }

    @Test
    func repeatedNoChangePlanDoesNotRewriteTheLock() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        _ = try apply(fixture.makePlan(), in: fixture)
        let lockURL = fixture.stateStore.lockURL
        let contents = try Data(contentsOf: lockURL)
        #expect(throws: DeploymentError.noChanges) { try fixture.makePlan() }
        #expect(try Data(contentsOf: lockURL) == contents)
    }

    @Test
    func previouslyApprovedLegacyPlanMustBeRegenerated() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let current = try fixture.makePlan()
        let legacy = DeploymentPlan(
            id: current.id, projectPath: current.projectPath, createdAt: current.createdAt,
            digest: current.digest, changes: current.changes, warnings: current.warnings,
            metadata: current.metadata
        )
        let store = DeploymentPlanStore(rootURL: fixture.root.appendingPathComponent("plans"))
        _ = try store.save(plan: legacy, stagingPath: fixture.staging.appendingPathComponent(current.id.uuidString).path)
        _ = try store.approve(id: current.id, digest: current.digest)
        let service = try SkillSetService(paths: SkillSetRuntimePaths(applicationSupportRoot: fixture.root, repositoryRoot: fixture.repository))
        #expect(throws: DeploymentPlanStoreError.self) { try service.apply(planID: current.id, digest: current.digest) }
        #expect(!FileManager.default.fileExists(atPath: skillURL(fixture).path))
        #expect(!FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent("skillset.json").path))
    }

    @Test
    func oldMatchingExternalReceiptCannotHideALaterManagedInstallation() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        _ = try SkillAssetCopier.copy(from: fixture.repository.appendingPathComponent("skills/demo"), to: skillURL(fixture))
        _ = try apply(fixture.makePlan(), in: fixture)
        _ = try apply(fixture.makePlan(skillIDs: []), in: fixture)
        try FileManager.default.removeItem(at: skillURL(fixture))
        _ = try apply(fixture.makePlan(), in: fixture)
        let cancelled = try fixture.makePlan(skillIDs: [])
        #expect(cancelled.changes.contains { $0.relativePath == ".agents/skills/demo" && $0.action == "remove" })
        _ = try apply(cancelled, in: fixture)
        #expect(!FileManager.default.fileExists(atPath: skillURL(fixture).path))
    }

    @Test
    func removingManagedRulesPreservesLaterEditsOutsideTheBlock() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let rules = fixture.project.appendingPathComponent("AGENTS.md")
        try "原有规则\n".write(to: rules, atomically: true, encoding: .utf8)
        _ = try apply(fixture.makePlan(), in: fixture)
        let deployed = try String(contentsOf: rules, encoding: .utf8)
        try (deployed + "\n用户后加的规则\n").write(to: rules, atomically: true, encoding: .utf8)
        _ = try apply(fixture.makePlan(instructionIDs: []), in: fixture)
        #expect(try String(contentsOf: rules, encoding: .utf8) == "原有规则\n用户后加的规则\n")
    }

    @Test
    func userEditsInsideManagedRuleBlockBlockDeselectingIt() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        _ = try apply(fixture.makePlan(), in: fixture)
        let rules = fixture.project.appendingPathComponent("AGENTS.md")
        let text = try String(contentsOf: rules, encoding: .utf8).replacingOccurrences(of: "只做受管内容", with: "用户修改规则")
        try text.write(to: rules, atomically: true, encoding: .utf8)
        #expect(throws: DeploymentError.managedRuleDrift("AGENTS.md")) {
            try fixture.makePlan(instructionIDs: [])
        }
        #expect(try String(contentsOf: rules, encoding: .utf8) == text)
    }

    @Test
    func matchingForeignRuleMarkerDoesNotGrantOwnership() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let rules = fixture.project.appendingPathComponent("AGENTS.md")
        let original = try ManagedBlocks.upsert(original: "项目原文\n", id: "project-rules", body: "只做受管内容").content
        try original.write(to: rules, atomically: true, encoding: .utf8)
        _ = try apply(fixture.makePlan(), in: fixture)
        _ = try apply(fixture.makePlan(instructionIDs: []), in: fixture)
        #expect(try String(contentsOf: rules, encoding: .utf8) == original)
    }

    @Test
    func differentForeignRuleMarkerBlocksReplacement() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let rules = fixture.project.appendingPathComponent("AGENTS.md")
        let original = try ManagedBlocks.upsert(original: "项目原文\n", id: "project-rules", body: "外部规则").content
        try original.write(to: rules, atomically: true, encoding: .utf8)
        #expect(throws: DeploymentError.unmanagedRuleConflict("AGENTS.md")) { try fixture.makePlan() }
        #expect(try String(contentsOf: rules, encoding: .utf8) == original)
        #expect(!FileManager.default.fileExists(atPath: skillURL(fixture).path))
    }

    private func apply(_ plan: DeploymentPlan, in fixture: DeploymentFixture) throws -> TransactionResult {
        try FileTransactionExecutor(operationsRoot: fixture.operations).apply(
            plan: plan, from: fixture.staging.appendingPathComponent(plan.id.uuidString)
        )
    }

    private func skillURL(_ fixture: DeploymentFixture) -> URL {
        fixture.project.appendingPathComponent(".agents/skills/demo")
    }

    private func revisedCatalog(_ fixture: DeploymentFixture, source: URL) throws -> CatalogDocument {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture.catalog)) as? [String: Any])
        var entries = try #require(json["entries"] as? [[String: Any]])
        entries[0]["contentHash"] = try SkillAssetCopier.analyze(from: source).contentHash
        json["entries"] = entries
        return try JSONDecoder().decode(CatalogDocument.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
