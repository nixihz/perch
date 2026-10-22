import Foundation
import SkillSetCore

enum BDDWorldError: Error, LocalizedError {
    case repositoryNotFound
    case missingProject
    case missingSelection
    case missingPlan
    case missingSourceFixture
    case missingPreview
    case missingMCPConfiguration
    case missingInventorySnapshot
    case missingProjectSnapshot
    case missingActionError
    case missingPluginFixture
    case missingNativeUI
    case permissionFixtureReadable(String)
    case gitCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .repositoryNotFound:
            return "找不到包含 registry/catalog.json 的仓库根目录。"
        case .missingProject:
            return "当前场景尚未登记项目。"
        case .missingSelection:
            return "当前场景尚未选择 Skill 或目标 agent。"
        case .missingPlan:
            return "当前场景尚未生成部署计划。"
        case .missingSourceFixture:
            return "当前场景尚未准备本地 Git 来源。"
        case .missingPreview:
            return "当前场景尚未生成来源预览。"
        case .missingMCPConfiguration:
            return "当前场景尚未生成 MCP 配置。"
        case .missingInventorySnapshot:
            return "当前场景尚未记录库存快照。"
        case .missingProjectSnapshot:
            return "当前场景尚未记录项目快照。"
        case .missingActionError:
            return "当前场景没有可核对的失败结果。"
        case .missingPluginFixture:
            return "当前场景尚未准备 Plugin 生命周期 fixture。"
        case .missingNativeUI:
            return "当前场景尚未启动原生界面。"
        case let .permissionFixtureReadable(path):
            return "权限失败 fixture 仍可读取：\(path)"
        case let .gitCommandFailed(message):
            return "Git fixture 命令失败：\(message)"
        }
    }
}

private struct TreeFingerprint: Equatable {
    let digest: String
}

/// 每个 BDD 场景独占一套临时项目与应用数据，避免测试触碰真实宿主配置。
@MainActor
final class BDDWorld {
    let repositoryRoot: URL
    let temporaryRoot: URL
    let applicationSupportRoot: URL

    private let fileManager: FileManager
    private(set) var service: SkillSetService?
    private(set) var projectURL: URL?
    private(set) var projectID: UUID?
    private(set) var selectedSkillID: String?
    private(set) var selectedAgent: String?
    private(set) var currentPlan: StoredDeploymentPlan?
    private(set) var currentPreview: SourcePreviewRecord?
    private(set) var nativeUI: NativeUIHarness?
    private(set) var firstSourceCommit: String?
    private(set) var secondSourceCommit: String?
    private(set) var lastError: Error?

    private var previewService: SourcePreviewService?
    private var sourceRemotePath: String?
    private var sourceWorktreeURL: URL?
    private var pluginHomeURL: URL?
    private var pluginHostInvocationLogURL: URL?
    private var inventorySnapshot: TreeFingerprint?
    private var projectSnapshot: TreeFingerprint?
    private var uiPlanDigestBeforeCancel: String?
    private var nativeUIPreparesRiskyPlugin = false
    private var restrictedProjectPaths: [URL] = []

    init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        repositoryRoot = try Self.locateRepositoryRoot()
        temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("skillset-bdd-\(UUID().uuidString)", isDirectory: true)
        applicationSupportRoot = temporaryRoot.appendingPathComponent("state", isDirectory: true)
        try fileManager.createDirectory(at: applicationSupportRoot, withIntermediateDirectories: true)
        // 应用不再内置技能；BDD 夹具直接以仓库目录作为库存，模拟已同步的来源内容。
        let repositorySnapshot = AppSnapshot.load(repositoryRoot: repositoryRoot)
        let repositorySkillSources = Dictionary(uniqueKeysWithValues: repositorySnapshot.catalog.entries.map {
            ($0.id, repositoryRoot.appendingPathComponent($0.path))
        })
        service = try SkillSetService(
            paths: SkillSetRuntimePaths(
                applicationSupportRoot: applicationSupportRoot,
                repositoryRoot: repositoryRoot
            ),
            snapshot: repositorySnapshot,
            skillSourceURLs: repositorySkillSources
        )
    }

    func registerProject(named name: String) throws {
        let projectRoot = temporaryRoot.appendingPathComponent("projects/\(name)", isDirectory: true)
        try fileManager.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let registration = try ProjectStore(rootURL: applicationSupportRoot).register(
            path: projectRoot,
            name: name
        )
        projectURL = projectRoot
        projectID = registration.id
    }

    func selectSkill(_ id: String) {
        selectedSkillID = id
    }

    func selectAgent(_ agent: String) {
        selectedAgent = agent
    }

    func prepareNativeUIPluginFixture() {
        nativeUIPreparesRiskyPlugin = true
    }

    func restrictProjectSkillsDirectory() throws {
        guard let projectURL else { throw BDDWorldError.missingProject }
        let skills = projectURL.appendingPathComponent(".agents/skills", isDirectory: true)
        try fileManager.createDirectory(at: skills, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: skills.path)
        restrictedProjectPaths.append(skills)
        do {
            _ = try fileManager.contentsOfDirectory(atPath: skills.path)
        } catch {
            return
        }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: skills.path)
        restrictedProjectPaths.removeAll { $0 == skills }
        throw BDDWorldError.permissionFixtureReadable(skills.path)
    }

    func makePlan() throws {
        guard let projectID, let selectedSkillID, let selectedAgent, let service else {
            throw BDDWorldError.missingSelection
        }
        currentPlan = try service.makePlan(
            projectID: projectID,
            skillIDs: [selectedSkillID],
            instructionIDs: ["base-zh"],
            agents: [selectedAgent]
        )
        lastError = nil
    }

    func attemptMakePlan() {
        do {
            try makePlan()
        } catch {
            lastError = error
        }
    }

    func approvePlan() throws {
        guard let plan = currentPlan, let service else {
            throw BDDWorldError.missingPlan
        }
        currentPlan = try service.approve(planID: plan.id, digest: plan.plan.digest)
        lastError = nil
    }

    func applyPlan() throws {
        guard let plan = currentPlan, let service else {
            throw BDDWorldError.missingPlan
        }
        _ = try service.apply(planID: plan.id, digest: plan.plan.digest)
        let planStore = DeploymentPlanStore(rootURL: service.paths.plansRoot)
        currentPlan = try planStore.load(plan.id)
        lastError = nil
    }

    func attemptApplyPlan() {
        do {
            try applyPlan()
        } catch {
            lastError = error
        }
    }

    func makeMCPConfigPlan(
        name: String,
        host: MCPHost = .claudeCode,
        scope: MCPConfigurationScope = .project,
        transport: String = "stdio",
        commandOrURL: String,
        args: [String] = [],
        envKeys: [String] = []
    ) throws {
        guard let projectID, let service else {
            throw BDDWorldError.missingProject
        }
        currentPlan = try service.makeMCPConfigPlan(
            projectID: projectID,
            draft: MCPConfigurationDraft(
                name: name,
                host: host,
                scope: scope,
                transport: transport,
                commandOrURL: commandOrURL,
                args: args,
                envKeys: envKeys
            )
        )
        lastError = nil
    }

    func attemptMakeMCPConfigPlan(
        name: String,
        host: MCPHost = .claudeCode,
        scope: MCPConfigurationScope = .project,
        transport: String = "stdio",
        commandOrURL: String,
        args: [String] = [],
        envKeys: [String] = []
    ) {
        do {
            try makeMCPConfigPlan(
                name: name,
                host: host,
                scope: scope,
                transport: transport,
                commandOrURL: commandOrURL,
                args: args,
                envKeys: envKeys
            )
        } catch {
            lastError = error
        }
    }

    func mcpConfigPlanCount() throws -> Int {
        guard let service else {
            throw BDDWorldError.missingProject
        }
        return try DeploymentPlanStore(rootURL: service.paths.plansRoot)
            .list()
            .filter { $0.plan.metadata?["planType"] == "mcp-configuration" }
            .count
    }

    func writeClaudeMCPConfigurationWithUnknownFields() throws {
        guard let projectURL else {
            throw BDDWorldError.missingProject
        }
        let object: [String: Any] = [
            "theme": "keep-me",
            "futureFeature": [
                "mode": "preserve"
            ],
            "mcpServers": [
                "existing": [
                    "type": "stdio",
                    "command": "existing-server",
                    "manualOwner": "keep-me",
                    "metadata": [
                        "owner": "manual"
                    ]
                ]
            ]
        ]
        var data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        try data.write(to: projectURL.appendingPathComponent(".mcp.json"), options: .atomic)
    }

    func mcpServerExists(_ name: String) throws -> Bool {
        let servers = try projectMCPJSONObject()["mcpServers"] as? [String: Any]
        return servers?[name] != nil
    }

    func mcpEnvironmentReference(server name: String, key: String) throws -> String? {
        let servers = try projectMCPJSONObject()["mcpServers"] as? [String: Any]
        let server = servers?[name] as? [String: Any]
        let environment = server?["env"] as? [String: Any]
        return environment?[key] as? String
    }

    func mcpConfigurationPreservesUnknownFields() throws -> Bool {
        let object = try projectMCPJSONObject()
        guard object["theme"] as? String == "keep-me",
              let future = object["futureFeature"] as? [String: Any],
              future["mode"] as? String == "preserve",
              let servers = object["mcpServers"] as? [String: Any],
              let existing = servers["existing"] as? [String: Any],
              existing["command"] as? String == "existing-server",
              existing["manualOwner"] as? String == "keep-me",
              let metadata = existing["metadata"] as? [String: Any],
              metadata["owner"] as? String == "manual" else {
            return false
        }
        return true
    }

    func createCachedRiskyClaudePlugin() throws {
        try preparePluginLifecycleFixture()
        guard let home = pluginHomeURL else {
            throw BDDWorldError.missingPluginFixture
        }
        let cache = home.appendingPathComponent(
            ".claude/plugins/cache/demo/risky/1.0.0",
            isDirectory: true
        )
        let manifestDirectory = cache.appendingPathComponent(".claude-plugin", isDirectory: true)
        try fileManager.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: cache.appendingPathComponent("hooks", isDirectory: true),
            withIntermediateDirectories: true
        )
        try writePluginManifest(
            at: manifestDirectory.appendingPathComponent("plugin.json"),
            object: [
                "name": "risky",
                "version": "1.0.0",
                "hooks": "./hooks/hooks.json"
            ]
        )
        try installPluginLifecycleService()
    }

    func createInstalledClaudePlugin(enabled: Bool) throws {
        try preparePluginLifecycleFixture()
        guard let home = pluginHomeURL else {
            throw BDDWorldError.missingPluginFixture
        }
        let cache = home.appendingPathComponent(
            ".claude/plugins/cache/demo/sample/1.2.0",
            isDirectory: true
        )
        let manifestDirectory = cache.appendingPathComponent(".claude-plugin", isDirectory: true)
        try fileManager.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        try writePluginManifest(
            at: manifestDirectory.appendingPathComponent("plugin.json"),
            object: [
                "name": "sample",
                "version": "1.2.0"
            ]
        )
        try writeClaudePluginInstallation(
            home: home,
            installPath: cache,
            enabled: enabled
        )
        try installPluginLifecycleService()
    }

    func makePluginLifecyclePlan(pluginID: String, action: String) throws {
        guard let service else {
            throw BDDWorldError.missingProject
        }
        guard let lifecycleAction = PluginLifecycleAction.allCases.first(
            where: { $0.displayName == action }
        ) else {
            throw PluginLifecycleError.actionUnsupported(action)
        }
        currentPlan = try service.makePluginLifecyclePlan(
            projectID: nil,
            request: PluginLifecycleRequest(
                host: .claudeCode,
                pluginID: pluginID,
                action: lifecycleAction,
                scope: .user
            )
        )
        lastError = nil
    }

    func attemptMakePluginLifecyclePlan(pluginID: String, action: String) {
        do {
            try makePluginLifecyclePlan(pluginID: pluginID, action: action)
        } catch {
            lastError = error
        }
    }

    func changeInstalledPluginEnabledState(_ enabled: Bool) throws {
        guard let home = pluginHomeURL else {
            throw BDDWorldError.missingPluginFixture
        }
        let cache = home.appendingPathComponent(
            ".claude/plugins/cache/demo/sample/1.2.0",
            isDirectory: true
        )
        try writeClaudePluginInstallation(
            home: home,
            installPath: cache,
            enabled: enabled
        )
    }

    func pluginLifecyclePlanCount() throws -> Int {
        guard let service else {
            throw BDDWorldError.missingProject
        }
        return try DeploymentPlanStore(rootURL: service.paths.plansRoot)
            .list()
            .filter { $0.plan.metadata?["planType"] == "plugin-lifecycle" }
            .count
    }

    func pluginOperationCount() throws -> Int {
        guard let service else {
            throw BDDWorldError.missingProject
        }
        let root = service.paths.operationsRoot
        guard fileManager.fileExists(atPath: root.path) else { return 0 }
        return try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter {
            UUID(uuidString: $0.lastPathComponent) != nil
                && fileManager.fileExists(
                    atPath: $0.appendingPathComponent("plugin-operation.json").path
                )
        }.count
    }

    func pluginHostInvocationCount() throws -> Int {
        guard let logURL = pluginHostInvocationLogURL else {
            throw BDDWorldError.missingPluginFixture
        }
        guard fileManager.fileExists(atPath: logURL.path) else { return 0 }
        return try String(contentsOf: logURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .count
    }

    func captureInventorySnapshot() throws {
        let registry = try fingerprint(repositoryRoot.appendingPathComponent("registry"))
        let vendor = try fingerprint(repositoryRoot.appendingPathComponent("vendor"))
        inventorySnapshot = TreeFingerprint(
            digest: SkillAssetCopier.sha256(Data("\(registry.digest)|\(vendor.digest)".utf8))
        )
    }

    func inventoryUnchanged() throws -> Bool {
        guard let inventorySnapshot else { throw BDDWorldError.missingInventorySnapshot }
        let registry = try fingerprint(repositoryRoot.appendingPathComponent("registry"))
        let vendor = try fingerprint(repositoryRoot.appendingPathComponent("vendor"))
        let current = TreeFingerprint(
            digest: SkillAssetCopier.sha256(Data("\(registry.digest)|\(vendor.digest)".utf8))
        )
        return current == inventorySnapshot
    }

    func catalogContains(_ skillID: String) -> Bool {
        AppSnapshot.load(repositoryRoot: repositoryRoot).catalog.entries.contains { $0.id == skillID }
    }

    func captureProjectSnapshot() throws {
        guard let projectURL else { throw BDDWorldError.missingProject }
        projectSnapshot = try fingerprint(projectURL)
    }

    func projectDirectoryUnchanged() throws -> Bool {
        guard let projectURL, let projectSnapshot else {
            throw BDDWorldError.missingProjectSnapshot
        }
        return try fingerprint(projectURL) == projectSnapshot
    }

    func launchNativeUI() throws {
        let instructions = selectedSkillID == nil ? [] : ["base-zh"]
        nativeUI = try NativeUIHarness(
            repositoryRoot: repositoryRoot,
            temporaryRoot: temporaryRoot,
            projectURL: projectURL,
            projectName: projectURL?.lastPathComponent,
            skillIDs: selectedSkillID.map { [$0] } ?? [],
            instructionIDs: instructions,
            agents: [selectedAgent ?? "codex"],
            prepareRiskyPluginFixture: nativeUIPreparesRiskyPlugin
        )
    }

    func previewNativeUIPlan() throws {
        guard let nativeUI else { throw BDDWorldError.missingNativeUI }
        try nativeUI.previewDeploymentPlan()
        currentPlan = try nativeUI.waitForSinglePlan()
        uiPlanDigestBeforeCancel = currentPlan?.plan.digest
        lastError = nil
    }

    func cancelNativeUIPlan() throws {
        guard let nativeUI else { throw BDDWorldError.missingNativeUI }
        try nativeUI.pressEscapeToCancelPlan()
        currentPlan = try nativeUI.planRecords().first
        lastError = nil
    }

    func nativeUIPlanCount() throws -> Int {
        guard let nativeUI else { throw BDDWorldError.missingNativeUI }
        return try nativeUI.planRecords().count
    }

    func nativeUIPlanDigestUnchanged() throws -> Bool {
        guard let nativeUI, let uiPlanDigestBeforeCancel else {
            throw BDDWorldError.missingNativeUI
        }
        return try nativeUI.planRecords().first?.plan.digest == uiPlanDigestBeforeCancel
    }

    func nativeUIPlanCount(type: String? = nil) throws -> Int {
        guard let nativeUI else { throw BDDWorldError.missingNativeUI }
        return try nativeUI.planRecords(type: type).count
    }

    func nativeUIPluginHostInvocationCount() throws -> Int {
        guard let nativeUI else { throw BDDWorldError.missingNativeUI }
        return try nativeUI.pluginHostInvocationCount()
    }

    func generateNativeUIPluginPlan() throws {
        guard let nativeUI else { throw BDDWorldError.missingNativeUI }
        try nativeUI.pressButton("生成安装计划")
        currentPlan = try nativeUI.waitForSinglePlan(type: "plugin-lifecycle")
    }

    func requestNativeUIPlanApproval() throws {
        guard let nativeUI else { throw BDDWorldError.missingNativeUI }
        try nativeUI.pressButton("批准并写入项目")
        try nativeUI.waitForConfirmationAlert()
    }

    func returnToNativeUIReview() throws {
        guard let nativeUI else { throw BDDWorldError.missingNativeUI }
        try nativeUI.pressEscapeToDismissConfirmation()
    }

    func configureMissingRemote() {
        let missing = temporaryRoot.appendingPathComponent("remote/missing.git").path
        installPreviewService(remotePath: missing, virtualURL: "https://github.com/bdd-owner/missing")
    }

    func createLocalSourceFixture() throws {
        let remote = temporaryRoot.appendingPathComponent("remote/skills.git", isDirectory: true)
        let worktree = temporaryRoot.appendingPathComponent("source-work", isDirectory: true)
        try fileManager.createDirectory(
            at: remote.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: worktree, withIntermediateDirectories: true)

        _ = try runGit(["init", "--bare", remote.path])
        _ = try runGit(["init", "-b", "main", worktree.path])
        _ = try runGit(["-C", worktree.path, "config", "user.name", "Skill Set BDD"])
        _ = try runGit(["-C", worktree.path, "config", "user.email", "bdd@example.test"])

        let skillDirectory = worktree.appendingPathComponent("skills/engineering/alpha", isDirectory: true)
        try fileManager.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try writeSourceSkill(
            at: skillDirectory.appendingPathComponent("SKILL.md"),
            description: "Alpha 第一版"
        )
        try Data("MIT License\n".utf8).write(
            to: worktree.appendingPathComponent("LICENSE"),
            options: .atomic
        )
        _ = try runGit(["-C", worktree.path, "add", "."])
        _ = try runGit(["-C", worktree.path, "commit", "-m", "第一版候选"])
        firstSourceCommit = try runGit(["-C", worktree.path, "rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try runGit(["-C", worktree.path, "tag", "v1"])

        try writeSourceSkill(
            at: skillDirectory.appendingPathComponent("SKILL.md"),
            description: "Alpha 第二版"
        )
        _ = try runGit(["-C", worktree.path, "add", "."])
        _ = try runGit(["-C", worktree.path, "commit", "-m", "第二版候选"])
        secondSourceCommit = try runGit(["-C", worktree.path, "rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        _ = try runGit(["-C", worktree.path, "remote", "add", "origin", remote.path])
        _ = try runGit(["-C", worktree.path, "push", "origin", "main", "--tags"])
        _ = try runGit(["-C", remote.path, "symbolic-ref", "HEAD", "refs/heads/main"])

        sourceRemotePath = remote.path
        sourceWorktreeURL = worktree
        installPreviewService(
            remotePath: remote.path,
            virtualURL: "https://github.com/bdd-owner/skills"
        )
    }

    func moveSourceTagToSecondCommit() throws {
        guard let sourceWorktreeURL, let secondSourceCommit else {
            throw BDDWorldError.missingSourceFixture
        }
        _ = try runGit(["-C", sourceWorktreeURL.path, "tag", "-f", "v1", secondSourceCommit])
        _ = try runGit(["-C", sourceWorktreeURL.path, "push", "--force", "origin", "v1"])
    }

    func preview(urlString: String, ref: String? = nil) throws {
        guard let previewService else { throw BDDWorldError.missingSourceFixture }
        currentPreview = try previewService.preview(urlString: urlString, ref: ref)
        lastError = nil
    }

    func attemptPreview(urlString: String, ref: String? = nil) {
        do {
            try preview(urlString: urlString, ref: ref)
        } catch {
            lastError = error
        }
    }

    func savedPreviewCount() throws -> Int {
        try SourcePreviewStore(rootURL: applicationSupportRoot.appendingPathComponent("cache/sources"))
            .list()
            .count
    }

    func previewDirectoryCount() throws -> Int {
        let root = applicationSupportRoot.appendingPathComponent("cache/sources", isDirectory: true)
        guard fileManager.fileExists(atPath: root.path) else { return 0 }
        return try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { UUID(uuidString: $0.lastPathComponent) != nil }.count
    }

    func previewCandidateCount() throws -> Int {
        guard let currentPreview else { throw BDDWorldError.missingPreview }
        return currentPreview.candidates.count
    }

    func previewResolvedCommit() throws -> String {
        guard let currentPreview else { throw BDDWorldError.missingPreview }
        return currentPreview.resolvedCommit
    }

    func savedPreviewResolvedCommit() throws -> String {
        try reloadedPreview().resolvedCommit
    }

    func previewWorkspaceContent(_ relativePath: String) throws -> String {
        guard let currentPreview else { throw BDDWorldError.missingPreview }
        return try String(
            contentsOf: URL(fileURLWithPath: currentPreview.workspacePath, isDirectory: true)
                .appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    func savedPreviewWorkspaceContent(_ relativePath: String) throws -> String {
        let preview = try reloadedPreview()
        return try String(
            contentsOf: URL(fileURLWithPath: preview.workspacePath, isDirectory: true)
                .appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    func previewWorkspaceIsIsolated() throws -> Bool {
        guard let currentPreview else { throw BDDWorldError.missingPreview }
        let workspace = URL(fileURLWithPath: currentPreview.workspacePath, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let root = applicationSupportRoot.appendingPathComponent("cache/sources", isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        return workspace.path.hasPrefix(root.path + "/")
            && !workspace.path.hasPrefix(repositoryRoot.path + "/")
    }

    func writeProjectFile(_ relativePath: String, content: String) throws {
        guard let projectURL else { throw BDDWorldError.missingProject }
        let target = projectURL.appendingPathComponent(relativePath)
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: target, options: .atomic)
    }

    func projectPathExists(_ relativePath: String) throws -> Bool {
        guard let projectURL else { throw BDDWorldError.missingProject }
        return fileManager.fileExists(atPath: projectURL.appendingPathComponent(relativePath).path)
    }

    func projectFileContent(_ relativePath: String) throws -> String {
        guard let projectURL else { throw BDDWorldError.missingProject }
        return try String(
            contentsOf: projectURL.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    func projectLockStatus() throws -> String {
        guard let projectURL else { throw BDDWorldError.missingProject }
        return ProjectLockStore(projectRoot: projectURL, stateRoot: applicationSupportRoot).inspect().status
    }

    func planStatusLabel() throws -> String {
        guard let currentPlan else { throw BDDWorldError.missingPlan }
        switch currentPlan.approvalState {
        case .pending:
            return "待批准"
        case .approved:
            return "已批准"
        case .applied:
            return "已应用"
        }
    }

    func actionErrorCode() throws -> String {
        guard let lastError else { throw BDDWorldError.missingActionError }
        switch lastError {
        case let error as DeploymentPlanStoreError:
            return error.code
        case let error as DeploymentError:
            return error.code
        case let error as FileTransactionError:
            return error.code
        case let error as SkillSetServiceError:
            return error.code
        case let error as SourcePreviewError:
            return error.code
        case let error as MCPConfigurationError:
            return error.code
        case let error as PluginLifecycleError:
            return error.code
        default:
            return String(describing: type(of: lastError))
        }
    }

    func actionErrorMessage() throws -> String {
        guard let lastError else { throw BDDWorldError.missingActionError }
        return lastError.localizedDescription
    }

    func cleanup() {
        nativeUI?.stop()
        nativeUI = nil
        for path in restrictedProjectPaths {
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
        }
        try? fileManager.removeItem(at: temporaryRoot)
    }

    private static func locateRepositoryRoot() throws -> URL {
        if let configured = ProcessInfo.processInfo.environment["SKILLSET_REPOSITORY_ROOT"],
           !configured.isEmpty {
            let url = URL(fileURLWithPath: configured, isDirectory: true)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            if FileManager.default.fileExists(
                atPath: url.appendingPathComponent("registry/catalog.json").path
            ) {
                return url
            }
        }

        var cursor = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: cursor.appendingPathComponent("registry/catalog.json").path
            ) {
                return cursor.resolvingSymlinksInPath().standardizedFileURL
            }
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path {
                break
            }
            cursor = parent
        }
        throw BDDWorldError.repositoryNotFound
    }

    private func installPreviewService(remotePath: String, virtualURL: String) {
        let baseURL = URL(fileURLWithPath: remotePath).absoluteString
        previewService = SourcePreviewService(
            previewsRoot: applicationSupportRoot.appendingPathComponent("cache/sources", isDirectory: true),
            gitEnvironment: [
                "GIT_CONFIG_COUNT": "1",
                "GIT_CONFIG_KEY_0": "url.\(baseURL).insteadOf",
                "GIT_CONFIG_VALUE_0": "\(virtualURL).git"
            ]
        )
    }

    private func reloadedPreview() throws -> SourcePreviewRecord {
        guard let currentPreview else { throw BDDWorldError.missingPreview }
        return try SourcePreviewStore(
            rootURL: applicationSupportRoot.appendingPathComponent("cache/sources", isDirectory: true)
        ).load(currentPreview.id)
    }

    private func preparePluginLifecycleFixture() throws {
        let home = temporaryRoot.appendingPathComponent("plugin-home", isDirectory: true)
        let executable = temporaryRoot.appendingPathComponent("plugin-host.sh")
        let log = temporaryRoot.appendingPathComponent("plugin-host-invocations.log")
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        let quotedLog = log.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$*" >> '\(quotedLog)'
        exit 0
        """
        try Data(script.utf8).write(to: executable, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try? fileManager.removeItem(at: log)
        pluginHomeURL = home
        pluginHostInvocationLogURL = log
    }

    private func installPluginLifecycleService() throws {
        guard let currentService = service,
              let home = pluginHomeURL,
              pluginHostInvocationLogURL != nil else {
            throw BDDWorldError.missingPluginFixture
        }
        let executable = temporaryRoot.appendingPathComponent("plugin-host.sh")
        let planStore = DeploymentPlanStore(rootURL: currentService.paths.plansRoot)
        let manager = PluginLifecycleManager(
            planStore: planStore,
            stagingRoot: currentService.paths.stagingRoot,
            operationsRoot: currentService.paths.operationsRoot,
            homeDirectory: home,
            executableOverrides: [.claudeCode: executable],
            environment: ProcessInfo.processInfo.environment
        )
        service = try SkillSetService(
            paths: currentService.paths,
            planStore: planStore,
            pluginLifecycleManager: manager
        )
    }

    private func writePluginManifest(at url: URL, object: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            .write(to: url, options: .atomic)
    }

    private func writeClaudePluginInstallation(
        home: URL,
        installPath: URL,
        enabled: Bool
    ) throws {
        let index: [String: Any] = [
            "version": 2,
            "plugins": [
                "sample@demo": [[
                    "scope": "user",
                    "installPath": installPath.path,
                    "version": "1.2.0",
                    "gitCommitSha": String(repeating: "b", count: 40)
                ]]
            ]
        ]
        let indexURL = home.appendingPathComponent(".claude/plugins/installed_plugins.json")
        try fileManager.createDirectory(
            at: indexURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: index, options: [.sortedKeys])
            .write(to: indexURL, options: .atomic)
        let settingsURL = home.appendingPathComponent(".claude/settings.json")
        try fileManager.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(
            withJSONObject: ["enabledPlugins": ["sample@demo": enabled]],
            options: [.sortedKeys]
        ).write(to: settingsURL, options: .atomic)
    }

    private func projectMCPJSONObject() throws -> [String: Any] {
        guard let projectURL else {
            throw BDDWorldError.missingProject
        }
        let url = projectURL.appendingPathComponent(".mcp.json")
        guard fileManager.fileExists(atPath: url.path) else {
            throw BDDWorldError.missingMCPConfiguration
        }
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard let dictionary = object as? [String: Any] else {
            throw BDDWorldError.missingMCPConfiguration
        }
        return dictionary
    }

    private func writeSourceSkill(at url: URL, description: String) throws {
        let text = """
        ---
        name: alpha
        description: \(description)
        ---
        # Alpha
        \(description)
        """
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    private func runGit(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw BDDWorldError.gitCommandFailed(
                "\(arguments.joined(separator: " "))：\(output.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
        return output
    }

    private func fingerprint(_ root: URL) throws -> TreeFingerprint {
        let standardizedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        guard fileManager.fileExists(atPath: standardizedRoot.path) else {
            return TreeFingerprint(digest: "")
        }
        guard let enumerator = fileManager.enumerator(
            at: standardizedRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else {
            throw BDDWorldError.missingInventorySnapshot
        }
        let prefix = standardizedRoot.path + "/"
        var lines: [String] = []
        for case let url as URL in enumerator {
            let relative = String(url.path.dropFirst(min(prefix.count, url.path.count)))
            let values = try url.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            if values.isSymbolicLink == true {
                let target = try fileManager.destinationOfSymbolicLink(atPath: url.path)
                lines.append("L|\(relative)|\(target)")
                if values.isDirectory == true {
                    enumerator.skipDescendants()
                }
            } else if values.isRegularFile == true {
                lines.append("F|\(relative)|\(try SkillAssetCopier.sha256(fileAt: url))")
            } else if values.isDirectory == true {
                lines.append("D|\(relative)")
            }
        }
        lines.sort()
        return TreeFingerprint(
            digest: SkillAssetCopier.sha256(Data(lines.joined(separator: "\n").utf8))
        )
    }
}
