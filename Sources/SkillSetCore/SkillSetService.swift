import Foundation

public enum SkillSetServiceError: Error, LocalizedError, Equatable, Sendable {
    case repositoryNotFound
    case invalidStagingPath(String)
    case tooManySelections(Int)
    case unknownInstruction(String)
    case otherHarnessChanges

    public var code: String {
        switch self {
        case .repositoryNotFound: "REPOSITORY_NOT_FOUND"
        case .invalidStagingPath: "STAGING_INVALID"
        case .tooManySelections: "SELECTION_LIMIT_EXCEEDED"
        case .unknownInstruction: "INSTRUCTION_NOT_FOUND"
        case .otherHarnessChanges: "HARNESS_SCOPE_CONFLICT"
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
        case .otherHarnessChanges:
            return "本次变化也会修改另一个 AI 工具，当前计划未生成。请核对共用技能、规则和安装方式；若需共同更新，可通过 CLI 或 MCP 明确选择多个工具生成计划。"
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
    public let harnessSelections: [String: ProjectHarnessSelection]?

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
        skillObservations: [ProjectSkillObservation] = [],
        harnessSelections: [String: ProjectHarnessSelection]? = nil
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
        self.harnessSelections = harnessSelections
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
    public let globalConfiguration: GlobalConfigurationManager

    private let projectStore: ProjectStore
    private let draftStore: ProjectDraftStore
    private let planStore: DeploymentPlanStore
    private let executor: FileTransactionExecutor
    private let pluginLifecycle: PluginLifecycleManager
    /// 测试夹具可以显式提供技能源；正常运行只从本机技能库读取。
    private let injectedSkillSourceURLs: [String: URL]
    /// 与本次服务快照一起固定。重复搜索不再读索引，也不再折叠目录文本。
    private let skillSearchIndex: SkillSearchIndex
    private let libraryPackageURLs: [String: URL]

    public init(
        paths: SkillSetRuntimePaths = .detect(),
        projectStore: ProjectStore? = nil,
        draftStore: ProjectDraftStore? = nil,
        planStore: DeploymentPlanStore? = nil,
        executor: FileTransactionExecutor? = nil,
        pluginLifecycleManager: PluginLifecycleManager? = nil,
        globalLocations: GlobalConfigurationLocations? = nil,
        snapshot overrideSnapshot: AppSnapshot? = nil,
        skillSourceURLs: [String: URL]? = nil,
        library: LoadedSkillLibrary? = nil
    ) throws {
        try paths.migrateLegacyState()
        let configuration = GlobalConfigurationManager(paths: paths, locations: globalLocations)
        try Self.absorbLocalImports(paths: paths, home: configuration.locations.home)
        // 先搬旧库，库存里的内容才算"已知"，首次收编才不会把同一份技能再收一遍。
        try Self.migrateLibraryLocationIfNeeded(paths: paths, locations: configuration.locations)
        try Self.adoptInstalledSkillsIfNeeded(paths: paths, locations: configuration.locations)
        self.paths = paths
        self.globalConfiguration = configuration
        let repositorySnapshot = AppSnapshot.load(
            repositoryRoot: paths.repositoryRoot,
            includeBundledLibrary: Self.usesRepositoryLibrary
        )
        let base = overrideSnapshot ?? Self.defaultSnapshot(repositorySnapshot: repositorySnapshot)
        var automaticSources: [String: URL] = [:]
        if Self.usesRepositoryLibrary, let repositoryRoot = paths.repositoryRoot {
            automaticSources = Dictionary(uniqueKeysWithValues: repositorySnapshot.catalog.entries.map {
                ($0.id, repositoryRoot.appendingPathComponent($0.path))
            })
        }
        injectedSkillSourceURLs = automaticSources.merging(skillSourceURLs ?? [:]) { _, explicit in explicit }
        let loadedLibrary = try library ?? paths.makeLibraryStore().loadLibrary()
        let localCatalog = loadedLibrary.catalog(merging: base.catalog)
        libraryPackageURLs = loadedLibrary.packageURLs
        skillSearchIndex = SkillSearchIndex(entries: localCatalog.entries, sourceOrigins: loadedLibrary.origins)
        let localPresets = try PresetStore(rootURL: paths.applicationSupportRoot).list(merging: base.presets)
        snapshot = try base.replacingCatalog(localCatalog)
            .replacingPresets(localPresets)
            .replacingTemplates(TemplateStore(rootURL: paths.applicationSupportRoot).list(merging: base.templates))
        self.projectStore = projectStore ?? ProjectStore(rootURL: paths.applicationSupportRoot)
        self.draftStore = draftStore ?? ProjectDraftStore(rootURL: paths.applicationSupportRoot)
        self.planStore = planStore ?? DeploymentPlanStore(rootURL: paths.plansRoot)
        self.executor = executor ?? FileTransactionExecutor(
            operationsRoot: paths.operationsRoot, versionsRoot: paths.versionsRoot,
            libraryRoot: paths.libraryDirectoryURL, sourcesRoot: paths.sourcesRoot)
        self.pluginLifecycle = pluginLifecycleManager ?? PluginLifecycleManager(
            planStore: self.planStore,
            stagingRoot: paths.stagingRoot,
            operationsRoot: paths.operationsRoot
        )
    }

    /// 回归夹具显式设置该变量后使用仓库快照；正常启动只接受用户同步进本机技能库的内容。
    public static var usesRepositoryLibrary: Bool {
        ProcessInfo.processInfo.environment["SKILLSET_REPOSITORY_LIBRARY"] == "1"
    }

    /// 技能库曾放在通用目录 ~/.agents/skills。迁移到私有库存后，旧位置的软链继续保留，
    /// 通用目录里的技能对 Codex 等宿主仍然可见。
    private static func migrateLibraryLocationIfNeeded(
        paths: SkillSetRuntimePaths, locations: GlobalConfigurationLocations
    ) throws {
        try paths.makeLibraryStore().migrateLibraryEntries(
            from: locations.home.appendingPathComponent(".agents/skills", isDirectory: true),
            acceptedRoots: [paths.sourcesRoot, paths.previewsRoot, paths.versionsRoot],
            markerURL: paths.sourcesRoot.appendingPathComponent(".migrated-library-location")
        )
    }

    public static func defaultSnapshot(for paths: SkillSetRuntimePaths) -> AppSnapshot {
        defaultSnapshot(repositorySnapshot: AppSnapshot.load(
            repositoryRoot: paths.repositoryRoot,
            includeBundledLibrary: usesRepositoryLibrary
        ))
    }

    private static func defaultSnapshot(repositorySnapshot: AppSnapshot) -> AppSnapshot {
        // 仓库示例仅供显式启用的开发夹具；用户库从空内容开始。
        usesRepositoryLibrary ? repositorySnapshot : repositorySnapshot.withoutBundledSkills()
            .replacingPresets([]).replacingTemplates([])
    }

    public func libraryStore() -> SkillLibraryStore {
        paths.makeLibraryStore()
    }

    /// 本机技能库版本优先，测试注入的仓库快照只在库中没有同名条目时兜底。
    private func resolvedSkillSources() throws -> [String: URL] {
        libraryPackageURLs.merging(injectedSkillSourceURLs) { librarySource, _ in librarySource }
    }

    public func projects() throws -> [ProjectServiceSummary] {
        try projectStore.list().map { registration in
            let projectURL = URL(fileURLWithPath: registration.canonicalPath, isDirectory: true)
            let inspection = try ProjectInspector.inspect(
                projectURL: projectURL, catalog: snapshot.catalog, operationsRoot: executor.operationsRoot, versionsRoot: paths.versionsRoot,
                libraryRoot: paths.libraryDirectoryURL, sourcesRoot: paths.sourcesRoot
            )
            let draft = try draftStore.load(projectID: registration.id)
            let projectState = ProjectLockStore(projectRoot: projectURL, stateRoot: paths.applicationSupportRoot).inspect()
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
                skillObservations: inspection.skillObservations,
                harnessSelections: draft?.resolvedHarnessSelections ?? projectState.manifest?.resolvedHarnessSelections
            )
        }
    }

    public func skills(query: String, sourceID: String? = nil, includeBlocked: Bool = true) -> [SkillEntry] {
        let matched = skillSearchIndex.matching(query: query, sourceID: sourceID)
        guard !includeBlocked else { return matched }
        return matched.filter { !$0.isBlocked }
    }

    public func makePlan(
        projectID: UUID,
        skillIDs: [String],
        instructionIDs: [String],
        agents: [String]? = nil,
        ruleBlockID: String = "project-rules",
        installMethod: SkillInstallMethod = .symlink,
        harnessSelections: [String: ProjectHarnessSelection]? = nil,
        onlyChangingAgent: String? = nil
    ) throws -> StoredDeploymentPlan {
        let repositoryRoot = paths.applicationSupportRoot
        try FileManager.default.createDirectory(at: repositoryRoot, withIntermediateDirectories: true)
        let allSkillIDs = harnessSelections.map { Array(Set($0.values.flatMap(\.skillIDs))) } ?? skillIDs
        let allInstructionIDs = harnessSelections.map { Array(Set($0.values.flatMap(\.instructionIDs))) } ?? instructionIDs
        guard allSkillIDs.count <= 200 else {
            throw SkillSetServiceError.tooManySelections(allSkillIDs.count)
        }
        let knownInstructions = Set(snapshot.templates.map(\.id))
        if let unknown = allInstructionIDs.first(where: { !knownInstructions.contains($0) }) {
            throw SkillSetServiceError.unknownInstruction(unknown)
        }
        let project = try projectStore.project(id: projectID)
        let fragments = Dictionary(uniqueKeysWithValues: snapshot.templates.map { ($0.id, $0.body) })
        let resolvedAgents = agents ?? {
            let draft = try? draftStore.load(projectID: projectID)
            let manifest = try? ProjectLockStore(
                projectRoot: URL(fileURLWithPath: project.canonicalPath, isDirectory: true), stateRoot: paths.applicationSupportRoot
            ).loadManifest()
            let candidates = draft?.agents ?? manifest?.agents ?? project.agents
            return candidates.isEmpty ? ["codex"] : candidates
        }()
        var resolvedSelections = harnessSelections
        var targetAgents = resolvedAgents
        var scopedAgent = onlyChangingAgent
        // 旧 API 仍能编辑指定宿主；已有独立配置不能被一次共享请求悄悄抹平。
        if resolvedSelections == nil,
           let current = try ProjectLockStore(projectRoot: URL(fileURLWithPath: project.canonicalPath),
               stateRoot: paths.applicationSupportRoot).loadManifest() {
            // 旧共享清单也先按宿主展开，单宿主请求不能被解释为取消其他宿主。
            var independent = current.resolvedHarnessSelections
            for agent in resolvedAgents {
                independent[agent] = ProjectHarnessSelection(skillIDs: skillIDs, instructionIDs: instructionIDs)
            }
            resolvedSelections = independent
            targetAgents = independent.keys.sorted()
            if scopedAgent == nil, resolvedAgents.count == 1 { scopedAgent = resolvedAgents.first }
        }
        let finalSkills = resolvedSelections.map { Set($0.values.flatMap(\.skillIDs)) } ?? Set(skillIDs)
        guard finalSkills.count <= 200 else { throw SkillSetServiceError.tooManySelections(finalSkills.count) }
        let planner = DeploymentPlanner(
            catalog: snapshot.catalog,
            repositoryRoot: repositoryRoot,
            stagingRoot: paths.stagingRoot,
            operationsRoot: executor.operationsRoot,
            skillSourceURLs: try resolvedSkillSources(),
            versionsRoot: paths.versionsRoot,
            libraryRoot: paths.libraryDirectoryURL,
            sourcesRoot: paths.sourcesRoot
        )
        let plan = try planner.makePlan(
            projectPath: URL(fileURLWithPath: project.canonicalPath, isDirectory: true),
            request: DeploymentRequest(
                skillIDs: skillIDs.sorted(),
                instructionIDs: instructionIDs,
                agents: targetAgents,
                ruleBlockID: ruleBlockID,
                installMethod: installMethod,
                harnessSelections: resolvedSelections
            ),
            fragments: fragments
        )
        let staging = paths.stagingRoot.appendingPathComponent(plan.id.uuidString, isDirectory: true)
        if let scopedAgent, let target = AgentDeploymentAdapter.target(for: scopedAgent),
           plan.changes.contains(where: {
               $0.scope != "project-state" && $0.relativePath != target.instructionsFile
                   && !$0.relativePath.hasPrefix(target.skillsRoot + "/")
           }) {
            try FileManager.default.removeItem(at: staging)
            throw SkillSetServiceError.otherHarnessChanges
        }
        return try planStore.save(plan: plan, stagingPath: staging.path)
    }

    /// 只提交一个宿主的编辑；本机预览可包含关联更新，另一宿主仍沿用已部署选择。
    public func makeHarnessPlan(
        projectID: UUID, agent: String, selection: ProjectHarnessSelection?,
        installMethod: SkillInstallMethod = .symlink,
        allowRelatedHarnessUpdates: Bool = false
    ) throws -> StoredDeploymentPlan {
        guard AgentDeploymentAdapter.target(for: agent) != nil else { throw ProjectLockError.unsupportedAgent(agent) }
        let project = try projectStore.project(id: projectID)
        let current = try ProjectLockStore(projectRoot: URL(fileURLWithPath: project.canonicalPath),
            stateRoot: paths.applicationSupportRoot).loadManifest()
        var selections = current?.resolvedHarnessSelections ?? [:]
        selections[agent] = selection
        return try makePlan(projectID: projectID, skillIDs: [], instructionIDs: [],
            agents: selections.keys.sorted(), ruleBlockID: current?.ruleBlockID ?? "project-rules",
            installMethod: installMethod, harnessSelections: selections,
            onlyChangingAgent: allowRelatedHarnessUpdates ? nil : agent)
    }

    public func makeUserSkillPlan(
        skillIDs: [String], agents: [String], installMethod: SkillInstallMethod = .symlink,
        adoptExistingSkills: Bool = false,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> StoredDeploymentPlan {
        guard agents.count == 1, let agent = agents.first,
              let host = SkillConfigurationTarget(rawValue: agent) else { throw DeploymentError.invalidPlan }
        let manager = homeDirectory == FileManager.default.homeDirectoryForCurrentUser ? globalConfiguration :
            GlobalConfigurationManager(paths: paths, locations: GlobalConfigurationLocations(home: homeDirectory, stateRoot: paths.applicationSupportRoot))
        let inspection = try manager.inspect(host: host)
        let current = inspection.selection
        var sources = try resolvedSkillSources()
        var entries = snapshot.catalog.entries
        for id in current.skillIDs where !entries.contains(where: { $0.id == id }) {
            let slug = String(id.split(separator: "/").last ?? "")
            let target = manager.locations.skillsRoot(host).appendingPathComponent(slug)
            guard inspection.resources.contains(where: { $0.path == target.path && $0.managed && !$0.modified }) else {
                throw DeploymentError.managedSkillDrift(target.path)
            }
            let analysis = try SkillAssetCopier.analyze(from: target)
            entries.append(SkillEntry(id: id, slug: slug, declaredName: slug, description: "", declaredVersion: nil,
                metadataReview: "retained", sourceId: "retained", path: "retained/" + slug, contentHash: analysis.contentHash,
                fileCount: analysis.files.count, bytes: analysis.bytes, integrity: "snapshotted", issues: [], excludedPaths: []))
            sources[id] = target
        }
        if adoptExistingSkills {
            let origins = try libraryStore().sourceOrigins()
            for entry in entries where skillIDs.contains(entry.id) {
                let target = manager.locations.skillsRoot(host).appendingPathComponent(entry.slug)
                if inspection.resources.contains(where: { $0.path == target.path && !$0.managed }) {
                    let actual = try SkillAssetCopier.analyze(from: target).contentHash
                    guard actual == entry.contentHash || actual == origins[entry.id]?.contentHash else {
                        throw DeploymentError.unmanagedSkillConflict(target.path)
                    }
                }
            }
        }
        let selection = GlobalConfigurationDraft(skillIDs: Array(Set(current.skillIDs + skillIDs)).sorted(), instructionIDs: current.instructionIDs, installMethod: installMethod)
        let catalog = CatalogDocument(schemaVersion: 1, hashAlgorithm: snapshot.catalog.hashAlgorithm, entries: entries)
        return try manager.makeDeploymentPlan(host: host, selection: selection, catalog: catalog,
            sourceURLs: sources,
            fragments: Dictionary(uniqueKeysWithValues: snapshot.templates.map { ($0.id, $0.body) }),
            takeOverExisting: adoptExistingSkills, installMethod: installMethod)
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
        if record.plan.metadata?["mcpLibrarySelection"] == "1" {
            try validateMCPLibraryPlan(record.plan)
        }
        if planType == "global-configuration" {
            try globalConfiguration.validate(plan: record.plan)
            let calculated = DeploymentPlanner.calculateDigest(
                projectPath: record.plan.projectPath, changes: record.plan.changes, selectedSkills: [],
                metadata: record.plan.metadata, observations: record.plan.observations
            )
            guard calculated == record.plan.digest else { throw DeploymentPlanStoreError.digestMismatch }
        }
        if planType == "skill-deployment" {
            guard record.plan.ownershipReceipt != nil, record.plan.observations != nil,
                  record.plan.metadata?["projectStateStorage"] == "application-v1",
                  record.plan.changes.filter({ $0.scope != "project-state" }).allSatisfy({
                      ![ProjectLockStore.manifestFileName, ProjectLockStore.lockFileName].contains($0.relativePath)
                  }) else {
                // 升级前生成的计划没有归属与读取依赖，不能沿用旧审批绕过新保护。
                throw DeploymentPlanStoreError.invalidState("需要重新生成包含管理归属的计划")
            }
            let repositoryRoot = paths.applicationSupportRoot
            let stagedLock = staging.appendingPathComponent(ProjectLockStore.lockFileName)
            let projectLock = ProjectLockStore(
                projectRoot: URL(fileURLWithPath: record.plan.projectPath, isDirectory: true),
                stateRoot: paths.applicationSupportRoot
            ).lockURL
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

    public func makeGlobalPlan(host: SkillConfigurationTarget, selection: GlobalConfigurationDraft, takeOverExisting: Bool = false) throws -> StoredDeploymentPlan {
        try globalConfiguration.makeDeploymentPlan(host: host, selection: selection, catalog: snapshot.catalog,
            sourceURLs: libraryStore().sourceURLs(),
            fragments: Dictionary(uniqueKeysWithValues: snapshot.templates.map { ($0.id, $0.body) }),
            takeOverExisting: takeOverExisting, installMethod: selection.installMethod ?? .symlink)
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

    public func previewSource(urlString: String, ref: String? = nil, replacing replacedID: UUID? = nil) throws -> SourcePreviewRecord {
        let store = SourcePreviewStore(rootURL: paths.previewsRoot)
        if let replacedID { _ = try store.load(replacedID) }
        let record = try SourcePreviewService(previewsRoot: paths.previewsRoot).preview(urlString: urlString, ref: ref)
        do {
            if let replacedID {
                let oldRoot = paths.previewsRoot.appendingPathComponent(replacedID.uuidString).appendingPathComponent("checkout")
                let newRoot = paths.previewsRoot.appendingPathComponent(record.id.uuidString).appendingPathComponent("checkout")
                try libraryStore().retargetSourceLinks(from: oldRoot, to: newRoot, commit: record.resolvedCommit)
            }
            try synchronizeSourceLibrary(excluding: replacedID)
        }
        catch { try? store.remove(record.id); throw error }
        if let replacedID { try store.remove(replacedID) }
        return record
    }

    public func plan(_ id: UUID) throws -> StoredDeploymentPlan {
        try planStore.load(id)
    }

    public func projectState(projectID: UUID) throws -> ProjectStateSnapshot {
        let project = try projectStore.project(id: projectID)
        return ProjectLockStore(
            projectRoot: URL(fileURLWithPath: project.canonicalPath, isDirectory: true), stateRoot: paths.applicationSupportRoot
        ).inspect()
    }

    public func verifyProjectObjects(projectID: UUID?) throws -> ObjectStoreVerification {
        let repositoryRoot = paths.applicationSupportRoot
        try FileManager.default.createDirectory(at: repositoryRoot, withIntermediateDirectories: true)
        let lock: ProjectLockDocument
        if let projectID {
            let project = try projectStore.project(id: projectID)
            guard let loaded = try ProjectLockStore(
                projectRoot: URL(fileURLWithPath: project.canonicalPath, isDirectory: true), stateRoot: paths.applicationSupportRoot
            ).loadLock() else {
                throw ProjectLockError.corruptLock(ProjectLockStore.lockFileName)
            }
            lock = loaded
        } else {
            let locks = try projectStore.list().compactMap { registration in
                try ProjectLockStore(
                    projectRoot: URL(fileURLWithPath: registration.canonicalPath, isDirectory: true), stateRoot: paths.applicationSupportRoot
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
            applicationSupportRoot: paths.applicationSupportRoot,
            environment: ["CODEX_HOME": globalConfiguration.locations.codexRoot.path],
            homeDirectory: globalConfiguration.locations.home
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
            applicationSupportRoot: paths.applicationSupportRoot,
            environment: ["CODEX_HOME": globalConfiguration.locations.codexRoot.path],
            homeDirectory: globalConfiguration.locations.home
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
            ] + target.loadingWarnings,
            metadata: metadata
        )
        return try planStore.save(plan: plan, stagingPath: stage.path)
    }

    public func makeMCPLibraryPlan(host: MCPHost, projectID: UUID? = nil,
                                   overwritingNames: Set<String> = []) throws -> StoredDeploymentPlan {
        let library = MCPLibraryStore(rootURL: paths.applicationSupportRoot)
        let ids = try library.selectedIDs(host: host, projectID: projectID)
        let available = try library.entries()
        let entries = try ids.map { id in
            guard let entry = available.first(where: { $0.id == id }) else {
                throw MCPLibraryError.missingSelection
            }
            return entry
        }.sorted { $0.name < $1.name }
        let projectRoot = try projectID.map { URL(fileURLWithPath: try projectStore.project(id: $0).canonicalPath) }
        let manager = MCPConfigurationManager(projectRoot: projectRoot, applicationSupportRoot: paths.applicationSupportRoot,
            environment: ["CODEX_HOME": globalConfiguration.locations.codexRoot.path], homeDirectory: globalConfiguration.locations.home)
        let scope: MCPConfigurationScope = projectID == nil ? .user : .project
        guard let target = manager.targets().first(where: { $0.host == host && $0.scope == scope }) else {
            throw MCPConfigurationError.unsupportedTarget("\(host.rawValue)/\(scope.rawValue)")
        }
        let previous = try library.applied(configPath: target.configPath)
        guard !entries.isEmpty || previous != nil else { throw DeploymentError.noChanges }
        let externalNames = Set(entries.map(\.name)).intersection(overwritingNames)
        let edit = try manager.makeLibrarySelectionEdit(target: target, entries: entries, previous: previous,
            overwritingNames: externalNames)
        let allHashes = try manager.libraryNodeHashes(content: edit.content, target: target)
        let names = Set(entries.map(\.name))
        let applied = MCPLibraryAppliedSelection(configPath: target.configPath, entries: entries,
            nodeHashes: allHashes.filter { names.contains($0.key) })
        let appliedData = try library.encode(applied)
        let appliedURL = library.appliedURL(configPath: target.configPath)
        let oldApplied = FileManager.default.fileExists(atPath: appliedURL.path) ? try Data(contentsOf: appliedURL) : nil
        guard edit.action != "noop" || oldApplied != appliedData else { throw DeploymentError.noChanges }
        var root = URL(fileURLWithPath: target.rootPath).standardizedFileURL
        while !appliedURL.path.hasPrefix(root.path == "/" ? "/" : root.path + "/") { root.deleteLastPathComponent() }
        let planID = UUID()
        let stage = paths.stagingRoot.appendingPathComponent(planID.uuidString)
        let removed = (previous?.entries.map(\.name) ?? []).filter { !names.contains($0) }
        let overwriteNote = externalNames.isEmpty ? "" : "；覆盖外部 [\(externalNames.sorted().joined(separator: ", "))]"
        var changes: [PlannedChange] = []
        for (url, content, beforeHash, description) in [
            (URL(fileURLWithPath: target.configPath), edit.content, edit.beforeHash,
             "\(host.displayName) · \(scope.displayName)：保留或写入 [\(entries.map(\.name).joined(separator: ", "))]；移除 [\(removed.joined(separator: ", "))]\(overwriteNote)"),
            (appliedURL, appliedData, oldApplied.map(SkillAssetCopier.sha256), "记录本次 MCP 勾选及逐服务指纹")
        ] {
            let relative = String(url.path.dropFirst(root.path == "/" ? 1 : root.path.count + 1))
            let staged = stage.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: staged.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: staged, options: .atomic)
            changes.append(PlannedChange(action: beforeHash == nil ? "add" : "update", relativePath: relative,
                beforeHash: beforeHash, afterHash: SkillAssetCopier.sha256(content), unifiedDiff: description))
        }
        let encoder = JSONEncoder()
        let metadata = ["planType": "mcp-configuration", "mcpLibrarySelection": "1",
            "host": host.rawValue, "scope": scope.rawValue, "projectID": projectID?.uuidString ?? "",
            "configPath": target.configPath, "serverName": entries.map(\.name).joined(separator: ", "),
            "librarySelectedNames": String(decoding: try encoder.encode(entries.map(\.name)), as: UTF8.self),
            "libraryRemovedNames": String(decoding: try encoder.encode(removed), as: UTF8.self),
            "libraryOverwriteNames": String(decoding: try encoder.encode(externalNames.sorted()), as: UTF8.self)]
        let digest = DeploymentPlanner.calculateDigest(projectPath: root.path, changes: changes, selectedSkills: [], metadata: metadata)
        let plan = DeploymentPlan(id: planID, projectPath: root.path, createdAt: Date(), digest: digest,
            changes: changes, warnings: ["目标配置：\(target.configPath)",
                scope == .user ? "此操作影响当前用户在该 AI 工具中的全部项目。" : "只更新当前项目的 MCP 配置；全局连接仍可能生效。",
                "取消勾选只移除本配置库写入且未被修改的服务。",
                externalNames.isEmpty ? "未接管外部同名服务。" : "已明确确认接管外部同名服务：\(externalNames.sorted().joined(separator: "、"))。",
                "环境变量只写入 ${NAME} 引用，不读取或复制值。"] + target.loadingWarnings, metadata: metadata)
        return try planStore.save(plan: plan, stagingPath: stage.path)
    }

    private func validateMCPLibraryPlan(_ plan: DeploymentPlan) throws {
        guard let metadata = plan.metadata, let host = MCPHost(rawValue: metadata["host"] ?? "") else {
            throw DeploymentError.invalidPlan
        }
        let projectID = UUID(uuidString: metadata["projectID"] ?? "")
        let scope: MCPConfigurationScope = projectID == nil ? .user : .project
        let projectRoot = try projectID.map { URL(fileURLWithPath: try projectStore.project(id: $0).canonicalPath) }
        let manager = MCPConfigurationManager(projectRoot: projectRoot, applicationSupportRoot: paths.applicationSupportRoot,
            environment: ["CODEX_HOME": globalConfiguration.locations.codexRoot.path], homeDirectory: globalConfiguration.locations.home)
        guard let target = manager.targets().first(where: { $0.host == host && $0.scope == scope }),
              target.configPath == metadata["configPath"] else { throw DeploymentError.invalidPlan }
        let appliedURL = MCPLibraryStore(rootURL: paths.applicationSupportRoot).appliedURL(configPath: target.configPath)
        let allowed = Set([target.configPath, appliedURL.path])
        let actual = plan.changes.map { URL(fileURLWithPath: plan.projectPath).appendingPathComponent($0.relativePath).standardizedFileURL.path }
        guard actual.count == 2, Set(actual) == allowed,
              DeploymentPlanner.calculateDigest(projectPath: plan.projectPath, changes: plan.changes,
                selectedSkills: [], metadata: metadata) == plan.digest else { throw DeploymentError.invalidPlan }
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
