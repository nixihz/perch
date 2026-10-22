import Foundation

public enum SkillSetServiceError: Error, LocalizedError, Equatable, Sendable {
    case repositoryNotFound
    case invalidStagingPath(String)
    case tooManySelections(Int)
    case unknownInstruction(String)

    public var code: String {
        switch self {
        case .repositoryNotFound: "REPOSITORY_NOT_FOUND"
        case .invalidStagingPath: "STAGING_INVALID"
        case .tooManySelections: "SELECTION_LIMIT_EXCEEDED"
        case .unknownInstruction: "INSTRUCTION_NOT_FOUND"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .repositoryNotFound:
            return "未找到包含 registry/catalog.json 的 skill 库根目录。"
        case let .invalidStagingPath(path):
            return "计划 staging 路径不在允许目录内：\(path)"
        case let .tooManySelections(count):
            return "一次最多选择 200 个 Skill，当前为 \(count) 个。"
        case let .unknownInstruction(id):
            return "找不到指令片段：\(id)"
        }
    }
}

public struct ProjectServiceSummary: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let path: String
    public let agents: [String]
    public let desiredSkillIDs: [String]
    public let observedSkillIDs: [String]
    public let instructionIDs: [String]
    public let lockStatus: String
    public let issues: [String]
    public let skillObservations: [ProjectSkillObservation]

    public init(
        id: UUID,
        name: String,
        path: String,
        agents: [String],
        desiredSkillIDs: [String],
        observedSkillIDs: [String],
        instructionIDs: [String],
        lockStatus: String,
        issues: [String],
        skillObservations: [ProjectSkillObservation] = []
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.agents = agents
        self.desiredSkillIDs = desiredSkillIDs
        self.observedSkillIDs = observedSkillIDs
        self.instructionIDs = instructionIDs
        self.lockStatus = lockStatus
        self.issues = issues
        self.skillObservations = skillObservations
    }
}

public struct ApplyServiceResult: Codable, Hashable, Sendable {
    public let operationID: UUID
    public let planID: UUID
    public let planDigest: String
    public let changedPaths: [String]
    public let journalPath: String
    public let message: String?

    public init(
        operationID: UUID,
        planID: UUID,
        planDigest: String,
        changedPaths: [String],
        journalPath: String,
        message: String? = nil
    ) {
        self.operationID = operationID
        self.planID = planID
        self.planDigest = planDigest
        self.changedPaths = changedPaths
        self.journalPath = journalPath
        self.message = message
    }
}

/// App、CLI 和 MCP 共用的本机服务边界；所有实际写入都经过计划审批和同一事务执行器。
public struct SkillSetService {
    public let paths: SkillSetRuntimePaths
    public let snapshot: AppSnapshot

    private let projectStore: ProjectStore
    private let draftStore: ProjectDraftStore
    private let planStore: DeploymentPlanStore
    private let executor: FileTransactionExecutor
    private let pluginLifecycle: PluginLifecycleManager

    public init(
        paths: SkillSetRuntimePaths = .detect(),
        projectStore: ProjectStore? = nil,
        draftStore: ProjectDraftStore? = nil,
        planStore: DeploymentPlanStore? = nil,
        executor: FileTransactionExecutor? = nil,
        pluginLifecycleManager: PluginLifecycleManager? = nil
    ) throws {
        self.paths = paths
        let base = AppSnapshot.load(repositoryRoot: paths.repositoryRoot)
        snapshot = try base.replacingCatalog(SkillLibraryStore(rootURL: paths.libraryRoot).catalog(merging: base.catalog))
            .replacingTemplates(TemplateStore(rootURL: paths.applicationSupportRoot).list(merging: base.templates))
        self.projectStore = projectStore ?? ProjectStore(rootURL: paths.applicationSupportRoot)
        self.draftStore = draftStore ?? ProjectDraftStore(rootURL: paths.applicationSupportRoot)
        self.planStore = planStore ?? DeploymentPlanStore(rootURL: paths.plansRoot)
        self.executor = executor ?? FileTransactionExecutor(operationsRoot: paths.operationsRoot)
        self.pluginLifecycle = pluginLifecycleManager ?? PluginLifecycleManager(
            planStore: self.planStore,
            stagingRoot: paths.stagingRoot,
            operationsRoot: paths.operationsRoot
        )
    }

    public func projects() throws -> [ProjectServiceSummary] {
        try projectStore.list().map { registration in
            let projectURL = URL(fileURLWithPath: registration.canonicalPath, isDirectory: true)
            let inspection = try ProjectInspector.inspect(
                projectURL: projectURL, catalog: snapshot.catalog, operationsRoot: executor.operationsRoot
            )
            let draft = try draftStore.load(projectID: registration.id)
            let projectState = ProjectLockStore(projectRoot: projectURL).inspect()
            return ProjectServiceSummary(
                id: registration.id,
                name: registration.name,
                path: registration.canonicalPath,
                agents: draft?.agents ?? projectState.manifest?.agents ?? registration.agents,
                desiredSkillIDs: draft?.skillIDs ?? projectState.manifest?.skills ?? inspection.observedSkillIDs,
                observedSkillIDs: inspection.observedSkillIDs,
                instructionIDs: draft?.instructionIDs ?? projectState.manifest?.instructions ?? [],
                lockStatus: projectState.status,
                issues: projectState.issues + inspection.issues
                    + inspection.ambiguousSlugs.map { "\($0)：来源不唯一。" }
                    + inspection.driftedSlugs.map { "\($0)：内容漂移。" },
                skillObservations: inspection.skillObservations
            )
        }
    }

    public func skills(query: String, sourceID: String? = nil, includeBlocked: Bool = true) -> [SkillEntry] {
        matchingSkills(snapshot.catalog.entries, query: query, sourceID: sourceID)
            .filter { includeBlocked || !$0.isBlocked }
    }

    public func makePlan(
        projectID: UUID,
        skillIDs: [String],
        instructionIDs: [String],
        agents: [String]? = nil,
        ruleBlockID: String = "project-rules"
    ) throws -> StoredDeploymentPlan {
        guard let repositoryRoot = paths.repositoryRoot else {
            throw SkillSetServiceError.repositoryNotFound
        }
        guard skillIDs.count <= 200 else {
            throw SkillSetServiceError.tooManySelections(skillIDs.count)
        }
        let knownInstructions = Set(snapshot.templates.map(\.id))
        if let unknown = instructionIDs.first(where: { !knownInstructions.contains($0) }) {
            throw SkillSetServiceError.unknownInstruction(unknown)
        }
        let project = try projectStore.project(id: projectID)
        let fragments = Dictionary(uniqueKeysWithValues: snapshot.templates.map { ($0.id, $0.body) })
        let resolvedAgents = agents ?? {
            let draft = try? draftStore.load(projectID: projectID)
            let manifest = try? ProjectLockStore(
                projectRoot: URL(fileURLWithPath: project.canonicalPath, isDirectory: true)
            ).loadManifest()
            let candidates = draft?.agents ?? manifest?.agents ?? project.agents
            return candidates.isEmpty ? ["codex"] : candidates
        }()
        let planner = DeploymentPlanner(
            catalog: snapshot.catalog,
            repositoryRoot: repositoryRoot,
            stagingRoot: paths.stagingRoot,
            operationsRoot: executor.operationsRoot,
            skillSourceURLs: try SkillLibraryStore(rootURL: paths.libraryRoot).sourceURLs()
        )
        let plan = try planner.makePlan(
            projectPath: URL(fileURLWithPath: project.canonicalPath, isDirectory: true),
            request: DeploymentRequest(
                skillIDs: skillIDs.sorted(),
                instructionIDs: instructionIDs,
                agents: resolvedAgents,
                ruleBlockID: ruleBlockID
            ),
            fragments: fragments
        )
        let staging = paths.stagingRoot.appendingPathComponent(plan.id.uuidString, isDirectory: true)
        return try planStore.save(plan: plan, stagingPath: staging.path)
    }

    @discardableResult
    public func approve(planID: UUID, digest: String) throws -> StoredDeploymentPlan {
        try planStore.approve(id: planID, digest: digest)
    }

    public func apply(planID: UUID, digest: String) throws -> ApplyServiceResult {
        let record = try planStore.requireApprovedForApply(id: planID, digest: digest)
        let planType = record.plan.metadata?["planType"] ?? "skill-deployment"
        if planType == "plugin-lifecycle" {
            let execution = try pluginLifecycle.execute(record)
            if execution.planConsumed {
                _ = try planStore.markApplied(
                    id: planID,
                    digest: digest,
                    operationID: execution.operationID
                )
            }
            if !execution.succeeded {
                if execution.state.contains("uncertain") {
                    throw PluginLifecycleError.executionUncertain(
                        execution.operationID,
                        execution.message
                    )
                }
                throw PluginLifecycleError.executionFailed(
                    execution.operationID,
                    execution.state,
                    execution.message
                )
            }
            return ApplyServiceResult(
                operationID: execution.operationID,
                planID: planID,
                planDigest: digest,
                changedPaths: [
                    "\(record.plan.metadata?["pluginHost"] ?? "plugin"):"
                        + "\(record.plan.metadata?["pluginID"] ?? "unknown")"
                ],
                journalPath: execution.journalPath,
                message: execution.message
            )
        }
        let staging = URL(fileURLWithPath: record.stagingPath, isDirectory: true).standardizedFileURL
        guard isInside(staging, root: paths.stagingRoot.standardizedFileURL) else {
            throw SkillSetServiceError.invalidStagingPath(staging.path)
        }
        if planType == "skill-deployment" {
            guard record.plan.ownershipReceipt != nil, record.plan.observations != nil else {
                // 升级前生成的计划没有归属与读取依赖，不能沿用旧审批绕过新保护。
                throw DeploymentPlanStoreError.invalidState("需要重新生成包含管理归属的计划")
            }
            guard let repositoryRoot = paths.repositoryRoot else {
                throw SkillSetServiceError.repositoryNotFound
            }
            let stagedLock = staging.appendingPathComponent(ProjectLockStore.lockFileName)
            let projectLock = URL(fileURLWithPath: record.plan.projectPath, isDirectory: true)
                .appendingPathComponent(ProjectLockStore.lockFileName)
            let lockURL = fileManagerExists(at: stagedLock) ? stagedLock : projectLock
            guard fileManagerExists(at: lockURL) else {
                throw ProjectLockError.corruptLock(lockURL.path)
            }
            let lock: ProjectLockDocument
            do {
                lock = try JSONDecoder().decode(ProjectLockDocument.self, from: Data(contentsOf: lockURL))
            } catch {
                throw ProjectLockError.corruptLock(lockURL.path)
            }
            _ = try SkillObjectStore(repositoryRoot: repositoryRoot).verify(lock: lock)
        }
        let result = try executor.apply(plan: record.plan, from: staging)
        do {
            if planType == "mcp-configuration" {
                try MCPConfigurationManager(
                    projectRoot: nil,
                    applicationSupportRoot: paths.applicationSupportRoot
                ).recordApplied(plan: record.plan)
            }
            _ = try planStore.markApplied(id: planID, digest: digest, operationID: result.operationID)
        } catch {
            if planType == "mcp-configuration" {
                _ = try? executor.rollback(operationID: result.operationID)
            }
            throw error
        }
        return ApplyServiceResult(
            operationID: result.operationID,
            planID: planID,
            planDigest: digest,
            changedPaths: result.changedPaths,
            journalPath: result.journalURL.path
        )
    }

    public func operation(_ operationID: UUID) throws -> FileTransactionJournal {
        try executor.loadJournal(operationID)
    }

    public func operationInspection(_ operationID: UUID) throws -> OperationInspection {
        do {
            let journal = try executor.loadJournal(operationID)
            return OperationInspection(
                operationID: journal.operationID,
                kind: .fileTransaction,
                state: journal.state,
                projectPath: journal.projectPath,
                planID: journal.planID,
                planDigest: journal.planDigest,
                createdAt: journal.createdAt,
                steps: journal.steps
            )
        } catch let fileError {
            if (fileError as? SkillSetCodedError)?.code != "OPERATION_NOT_FOUND" {
                throw fileError
            }
            do {
                let operation = try pluginLifecycle.loadOperation(operationID)
                return OperationInspection(
                    operationID: operation.operationID,
                    kind: .pluginLifecycle,
                    state: operation.state,
                    projectPath: operation.workingDirectory,
                    planID: operation.planID,
                    planDigest: operation.planDigest,
                    createdAt: operation.createdAt,
                    steps: [],
                    plugin: operation
                )
            } catch let pluginError {
                if let error = pluginError as? PluginLifecycleError,
                   case .operationNotFound = error {
                    throw fileError
                }
                throw pluginError
            }
        }
    }

    public func rollback(operationID: UUID) throws -> [String] {
        do {
            let plugin = try pluginLifecycle.loadOperation(operationID)
            throw PluginLifecycleError.rollbackUnsupported(
                plugin.pluginID,
                plugin.action.displayName
            )
        } catch let error as PluginLifecycleError {
            if case .operationNotFound = error {
                // 继续尝试文件事务 journal。
            } else {
                throw error
            }
        }
        return try executor.rollback(operationID: operationID)
    }

    public func pendingPlans() throws -> [StoredDeploymentPlan] {
        try planStore.list().filter { record in
            record.approvalState != .applied && !record.isExpired(at: Date())
        }
    }

    public func sourcePreviews() throws -> [SourcePreviewRecord] {
        try SourcePreviewStore(rootURL: paths.previewsRoot).list()
    }

    public func sourcePreview(id: UUID) throws -> SourcePreviewRecord {
        try SourcePreviewStore(rootURL: paths.previewsRoot).load(id)
    }

    public func previewSource(urlString: String, ref: String? = nil) throws -> SourcePreviewRecord {
        try SourcePreviewService(previewsRoot: paths.previewsRoot)
            .preview(urlString: urlString, ref: ref)
    }

    public func plan(_ id: UUID) throws -> StoredDeploymentPlan {
        try planStore.load(id)
    }

    public func projectState(projectID: UUID) throws -> ProjectStateSnapshot {
        let project = try projectStore.project(id: projectID)
        return ProjectLockStore(
            projectRoot: URL(fileURLWithPath: project.canonicalPath, isDirectory: true)
        ).inspect()
    }

    public func verifyProjectObjects(projectID: UUID?) throws -> ObjectStoreVerification {
        guard let repositoryRoot = paths.repositoryRoot else {
            throw SkillSetServiceError.repositoryNotFound
        }
        let lock: ProjectLockDocument
        if let projectID {
            let project = try projectStore.project(id: projectID)
            guard let loaded = try ProjectLockStore(
                projectRoot: URL(fileURLWithPath: project.canonicalPath, isDirectory: true)
            ).loadLock() else {
                throw ProjectLockError.corruptLock(ProjectLockStore.lockFileName)
            }
            lock = loaded
        } else {
            let locks = try projectStore.list().compactMap { registration in
                try ProjectLockStore(
                    projectRoot: URL(fileURLWithPath: registration.canonicalPath, isDirectory: true)
                ).loadLock()
            }
            guard !locks.isEmpty else {
                return ObjectStoreVerification(checkedObjects: 0, checkedBytes: 0)
            }
            lock = ProjectLockDocument(
                manifestDigest: "merged",
                targets: [],
                skills: locks.flatMap(\.skills),
                instructions: locks.flatMap(\.instructions)
            )
        }
        return try SkillObjectStore(repositoryRoot: repositoryRoot).verify(lock: lock)
    }

    public func mcpConfigurations(projectID: UUID? = nil) throws -> [MCPConfigurationInspection] {
        let projectRoot: URL?
        if let projectID {
            projectRoot = URL(
                fileURLWithPath: try projectStore.project(id: projectID).canonicalPath,
                isDirectory: true
            )
        } else {
            projectRoot = nil
        }
        return MCPConfigurationManager(
            projectRoot: projectRoot,
            applicationSupportRoot: paths.applicationSupportRoot
        ).inspectAll()
    }

    public func makeMCPConfigPlan(
        projectID: UUID?,
        draft: MCPConfigurationDraft,
        existingServer: MCPObservedServer? = nil,
        remove: Bool = false,
        replaceArguments: Bool = false
    ) throws -> StoredDeploymentPlan {
        let projectRoot: URL?
        if let projectID {
            projectRoot = URL(
                fileURLWithPath: try projectStore.project(id: projectID).canonicalPath,
                isDirectory: true
            )
        } else {
            projectRoot = nil
        }
        let manager = MCPConfigurationManager(
            projectRoot: projectRoot,
            applicationSupportRoot: paths.applicationSupportRoot
        )
        guard let target = manager.targets().first(where: {
            $0.host == draft.host && $0.scope == draft.scope
        }) else {
            throw MCPConfigurationError.unsupportedTarget(
                "\(draft.host.rawValue)/\(draft.scope.rawValue)"
            )
        }
        let edit: MCPConfigEditResult
        if let existingServer {
            edit = try manager.makeExistingEdit(target: target, server: existingServer,
                draft: remove ? nil : draft, replaceArguments: replaceArguments)
        } else {
            guard !remove else { throw MCPConfigurationError.configConflict(draft.name) }
            edit = try manager.makeEdit(target: target, draft: draft)
        }
        guard edit.action != "noop" else {
            throw DeploymentError.noChanges
        }
        let planID = UUID()
        let stage = paths.stagingRoot.appendingPathComponent(planID.uuidString, isDirectory: true)
        if FileManager.default.fileExists(atPath: stage.path) {
            try FileManager.default.removeItem(at: stage)
        }
        let staged = stage.appendingPathComponent(target.relativePath)
        try FileManager.default.createDirectory(
            at: staged.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try edit.content.write(to: staged, options: .atomic)
        let change = PlannedChange(
            action: edit.action,
            relativePath: target.relativePath,
            beforeHash: edit.beforeHash,
            afterHash: edit.afterHash,
            unifiedDiff: "\(edit.action == "add" ? "新增" : (remove ? "删除" : "更新")) \(target.host.displayName) \(target.scope.displayName) MCP Server \(edit.serverName)"
        )
        let metadata = [
            "planType": "mcp-configuration",
            "mcpAction": remove ? "remove" : "upsert",
            "host": target.host.rawValue,
            "scope": target.scope.rawValue,
            "serverName": edit.serverName,
            "configPath": target.configPath,
            "projectID": projectID?.uuidString ?? ""
        ]
        let digest = DeploymentPlanner.calculateDigest(
            projectPath: target.rootPath,
            changes: [change],
            selectedSkills: ["mcp:\(target.host.rawValue):\(target.scope.rawValue):\(edit.serverName)"],
            metadata: metadata
        )
        let plan = DeploymentPlan(
            id: planID,
            projectPath: target.rootPath,
            createdAt: Date(),
            digest: digest,
            changes: [change],
            warnings: [
                "目标配置：\(target.configPath)",
                "环境变量只写入 ${NAME} 引用，不读取或复制值。",
                target.host == .claudeCode
                    ? "Claude JSON 会保留未知键，但对象键顺序会归一化。"
                    : "Codex TOML 只修改选中的服务，其他配置保留。"
            ],
            metadata: metadata
        )
        return try planStore.save(plan: plan, stagingPath: stage.path)
    }

    public func plugins(projectID: UUID? = nil) throws -> PluginInventorySnapshot {
        let projectRoot: URL?
        if let projectID {
            projectRoot = URL(
                fileURLWithPath: try projectStore.project(id: projectID).canonicalPath,
                isDirectory: true
            )
        } else {
            projectRoot = nil
        }
        return PluginInventoryManager(projectRoot: projectRoot).inspect()
    }

    public func makePluginLifecyclePlan(
        projectID: UUID?,
        request: PluginLifecycleRequest
    ) throws -> StoredDeploymentPlan {
        let projectRoot: URL?
        if let projectID {
            projectRoot = URL(
                fileURLWithPath: try projectStore.project(id: projectID).canonicalPath,
                isDirectory: true
            )
        } else {
            projectRoot = nil
        }
        return try pluginLifecycle.makePlan(request: request, projectRoot: projectRoot)
    }

    public func pluginOperation(_ operationID: UUID) throws -> PluginLifecycleOperation {
        try pluginLifecycle.loadOperation(operationID)
    }

    public func recoverPendingOperations() throws -> [UUID] {
        try executor.recoverPendingOperations()
            + pluginLifecycle.recoverInterruptedOperations()
    }

    private func isInside(_ candidate: URL, root: URL) -> Bool {
        candidate.path == root.path || candidate.path.hasPrefix(root.path + "/")
    }

    private func fileManagerExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
