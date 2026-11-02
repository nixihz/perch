import Foundation
import Testing
@testable import SkillSetCore

struct ApplyRecoveryTests {
    @Test
    func applyLockRejectsConcurrentOwnerAndReleasesAfterOwnerEnds() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("apply-lock-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var owner: ApplyLockHandle? = try ApplyLock.acquire(rootURL: root, scope: "project")
        _ = withExtendedLifetime(owner) {
            #expect(throws: ApplyLockError.busy("project")) {
                try ApplyLock.acquire(rootURL: root, scope: "project")
            }
        }

        owner = nil
        let nextOwner = try ApplyLock.acquire(rootURL: root, scope: "project")
        withExtendedLifetime(nextOwner) {}
    }

    @Test
    func applyRejectsASecondProcessForTheSameProjectBeforeChangingPlanState() throws {
        let fixture = try ApplyRecoveryFixture()
        defer { fixture.cleanup() }
        let service = try fixture.makeService()
        let heldLock = try ApplyLock.acquire(
            rootURL: fixture.paths.applicationSupportRoot,
            scope: fixture.project.path
        )

        #expect(throws: ApplyLockError.busy(fixture.project.path)) {
            try service.apply(
                planID: fixture.plan.id,
                digest: fixture.plan.digest,
                idempotencyKey: "same-request"
            )
        }
        #expect(try fixture.planStore.load(fixture.plan.id).state == .approved)
        withExtendedLifetime(heldLock) {}
    }

    @Test
    func applyReplayWithSameIdempotencyKeyReturnsTheOriginalReceipt() throws {
        let fixture = try ApplyRecoveryFixture()
        defer { fixture.cleanup() }
        let service = try fixture.makeService()

        let first = try service.apply(
            planID: fixture.plan.id,
            digest: fixture.plan.digest,
            idempotencyKey: "same-request"
        )
        let replay = try service.apply(
            planID: fixture.plan.id,
            digest: fixture.plan.digest,
            idempotencyKey: "same-request"
        )

        #expect(replay == first)
        #expect(try Data(contentsOf: fixture.destination) == fixture.content)
        #expect(try fixture.planStore.load(fixture.plan.id).state == .applied)
        #expect(throws: DeploymentPlanStoreError.idempotencyKeyMismatch(fixture.plan.id.uuidString)) {
            try service.apply(
                planID: fixture.plan.id,
                digest: fixture.plan.digest,
                idempotencyKey: "different-request"
            )
        }
    }

    @Test
    func retryAfterTransactionJournalWasAppliedCompletesThePlanWithoutWritingAgain() throws {
        let fixture = try ApplyRecoveryFixture()
        defer { fixture.cleanup() }
        let operationID = UUID()
        try fixture.prepareInterruptedApply(
            operationID: operationID,
            journalState: .applied,
            stepState: "applied",
            writeDestination: true,
            idempotencyKey: "same-request"
        )

        let result = try fixture.makeService().apply(
            planID: fixture.plan.id,
            digest: fixture.plan.digest,
            idempotencyKey: "same-request"
        )
        let stored = try fixture.planStore.load(fixture.plan.id)

        #expect(result.operationID == operationID)
        #expect(stored.state == .applied)
        #expect(stored.applyReceipt?.operationID == operationID)
        #expect(try Data(contentsOf: fixture.destination) == fixture.content)
    }

    @Test
    func interruptedTransactionRollsBackBeforeRetryingWithTheSameIdempotencyKey() throws {
        let fixture = try ApplyRecoveryFixture()
        defer { fixture.cleanup() }
        let interruptedOperationID = UUID()
        try fixture.prepareInterruptedApply(
            operationID: interruptedOperationID,
            journalState: .applying,
            stepState: "applied",
            writeDestination: true,
            idempotencyKey: "same-request"
        )

        let result = try fixture.makeService().apply(
            planID: fixture.plan.id,
            digest: fixture.plan.digest,
            idempotencyKey: "same-request"
        )
        let oldJournal = try FileTransactionExecutor(
            operationsRoot: fixture.paths.operationsRoot
        ).loadJournal(interruptedOperationID)
        let stored = try fixture.planStore.load(fixture.plan.id)
        let newJournal = try FileTransactionExecutor(
            operationsRoot: fixture.paths.operationsRoot
        ).loadJournal(result.operationID)

        #expect(result.operationID != interruptedOperationID)
        #expect(oldJournal.state == .rolledBack)
        #expect(newJournal.state == .applied)
        #expect(stored.state == .applied)
        #expect(try Data(contentsOf: fixture.destination) == fixture.content)
    }
}

private struct ApplyRecoveryFixture {
    let root: URL
    let paths: SkillSetRuntimePaths
    let project: URL
    let plan: DeploymentPlan
    let content: Data
    let destination: URL
    let planStore: DeploymentPlanStore

    init() throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory
            .appendingPathComponent("apply-recovery-\(UUID().uuidString)", isDirectory: true)
        let applicationSupportRoot = root.appendingPathComponent("support", isDirectory: true)
        project = root.appendingPathComponent("project", isDirectory: true)
        paths = SkillSetRuntimePaths(applicationSupportRoot: applicationSupportRoot, repositoryRoot: nil)
        content = Data("managed content\n".utf8)
        destination = project.appendingPathComponent("managed.txt")
        let contentHash = SkillAssetCopier.sha256(content)
        let planID = UUID()
        plan = DeploymentPlan(
            id: planID,
            projectPath: project.path,
            createdAt: Date(),
            digest: SkillAssetCopier.sha256(Data("apply-recovery-plan".utf8)),
            changes: [
                PlannedChange(
                    action: "add",
                    relativePath: "managed.txt",
                    beforeHash: nil,
                    afterHash: contentHash,
                    unifiedDiff: ""
                )
            ],
            warnings: [],
            metadata: ["planType": "test"]
        )
        planStore = DeploymentPlanStore(rootURL: paths.plansRoot)

        try fileManager.createDirectory(at: project, withIntermediateDirectories: true)
        let staging = paths.stagingRoot.appendingPathComponent(planID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        try content.write(to: staging.appendingPathComponent("managed.txt"))
        _ = try planStore.save(plan: plan, stagingPath: staging.path)
        _ = try planStore.approve(id: plan.id, digest: plan.digest)
    }

    func makeService() throws -> SkillSetService {
        try SkillSetService(
            paths: paths,
            planStore: planStore,
            globalLocations: GlobalConfigurationLocations(
                home: root.appendingPathComponent("home", isDirectory: true),
                stateRoot: paths.applicationSupportRoot
            )
        )
    }

    func prepareInterruptedApply(
        operationID: UUID,
        journalState: OperationState,
        stepState: String,
        writeDestination: Bool,
        idempotencyKey: String
    ) throws {
        _ = try planStore.beginApply(
            id: plan.id,
            digest: plan.digest,
            operationID: operationID,
            idempotencyKey: idempotencyKey
        )
        if writeDestination {
            try content.write(to: destination)
        }
        let journal = FileTransactionJournal(
            operationID: operationID,
            projectPath: project.path,
            planID: plan.id,
            planDigest: plan.digest,
            createdAt: Date(),
            state: journalState,
            steps: [
                FileTransactionStep(
                    relativePath: "managed.txt",
                    action: "add",
                    beforeHash: nil,
                    afterHash: SkillAssetCopier.sha256(content),
                    state: stepState
                )
            ],
            metadata: plan.metadata
        )
        let journalURL = paths.operationsRoot
            .appendingPathComponent(operationID.uuidString, isDirectory: true)
            .appendingPathComponent("journal.json")
        try FileManager.default.createDirectory(
            at: journalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(journal).write(to: journalURL, options: .atomic)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
