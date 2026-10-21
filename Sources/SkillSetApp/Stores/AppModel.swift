import Foundation
import Observation
import SkillSetCore

@MainActor
@Observable
final class AppModel {
    let snapshot: AppSnapshot
    let runtimePaths: SkillSetRuntimePaths

    var section: NavigationItem = .projects
    var query = ""
    var selectedProjectID = ""
    var selectedSkillID: String?
    var selectedMCPID = ""
    var selectedPluginID = ""
    var selectedSourceID = "workspace"
    var selectedPreviewID: UUID?
    var selectedPresetID = "personal-base"
    var selectedTemplateID = "base-zh"
    var projects: [ProjectRecord] = []
    var projectIssues: [String: [String]] = [:]
    var mcpServers: [MCPServerRecord] = []
    var mcpConfigInspections: [MCPConfigurationInspection] = []
    var plugins: [PluginInventoryRecord] = []
    var pluginIssues: [String] = []
    var pluginScanRoots: [String] = []
    var planPresented = false
    var preparedPlan: StoredDeploymentPlan?
    var pendingPlans: [StoredDeploymentPlan] = []
    var sourcePreviews: [SourcePreviewRecord] = []
    private(set) var actionMessage: LocalizedText = "本机快照已载入"
    var lastAction: String { L10n.tr(actionMessage) }
    var history: [String] = []
    var isWorking = false

    private let projectStore: ProjectStore
    private let draftStore: ProjectDraftStore
    private let planStore: DeploymentPlanStore
    private let executor: FileTransactionExecutor
    private let service: SkillSetService?

    func report(_ message: LocalizedText) {
        actionMessage = message
    }

    func reportKey(_ key: String) {
        actionMessage = LocalizedText(stringLiteral: key)
    }

    init(
        snapshot: AppSnapshot? = nil,
        runtimePaths: SkillSetRuntimePaths = .detect()
    ) {
        self.runtimePaths = runtimePaths
        self.snapshot = snapshot ?? AppSnapshot.load(repositoryRoot: runtimePaths.repositoryRoot)
        projectStore = ProjectStore(rootURL: runtimePaths.applicationSupportRoot)
        draftStore = ProjectDraftStore(rootURL: runtimePaths.applicationSupportRoot)
        planStore = DeploymentPlanStore(rootURL: runtimePaths.plansRoot)
        executor = FileTransactionExecutor(operationsRoot: runtimePaths.operationsRoot)
        service = try? SkillSetService(paths: runtimePaths)
        selectedSkillID = self.snapshot.catalog.entries.first?.id

        do {
            let recovered = try executor.recoverPendingOperations()
            try reloadProjects(preferredID: nil)
            refreshMCPConfigurations()
            refreshPlugins()
            refreshSourcePreviews()
            if !recovered.isEmpty {
                report("已恢复 \(recovered.count) 个中断的写入操作")
            } else if runtimePaths.repositoryRoot == nil {
                report("未找到技能库目录；已登记项目仍可查看")
            } else if projects.isEmpty {
                report("尚未登记项目")
            } else {
                report("已载入 \(projects.count) 个本机项目")
            }
        } catch {
            reportKey(UserFacingText.error(error))
        }
    }

    var filteredSkills: [SkillEntry] {
        matchingSkills(snapshot.catalog.entries, query: query)
    }

    var selectedProject: ProjectRecord? {
        projects.first(where: { $0.id == selectedProjectID })
    }

    var selectedSkill: SkillEntry? {
        snapshot.catalog.entries.first(where: { $0.id == selectedSkillID })
    }

    var selectedMCP: MCPServerRecord? {
        mcpServers.first(where: { $0.id == selectedMCPID })
    }

    var selectedPlugin: PluginInventoryRecord? {
        plugins.first(where: { $0.id == selectedPluginID })
    }

    var selectedSource: SourceRecord? {
        snapshot.sources.sources.first(where: { $0.id == selectedSourceID })
    }

    var selectedSourcePreview: SourcePreviewRecord? {
        sourcePreviews.first(where: { $0.id == selectedPreviewID })
    }

    var selectedPreset: PresetRecord? {
        snapshot.presets.first(where: { $0.id == selectedPresetID })
    }

    var selectedTemplate: TemplateRecord? {
        snapshot.templates.first(where: { $0.id == selectedTemplateID })
    }

    var blockedCount: Int {
        snapshot.catalog.entries.filter(\.isBlocked).count
    }

    var repositoryLabel: String {
        runtimePaths.repositoryRoot?.path ?? L10n.tr("未找到")
    }

    var selectedProjectDraft: Set<String> {
        selectedProject?.draftSkillIDs ?? []
    }

    func updateQuery(_ value: String) {
        query = value
        if filteredSkills.contains(where: { $0.id == selectedSkillID }) {
            return
        }
        // 搜索条件改变后不能继续展示已被过滤掉的旧详情。
        selectedSkillID = filteredSkills.first?.id
    }

    @discardableResult
    func registerProject(_ url: URL, name: String? = nil) -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            let registration = try projectStore.register(path: url, name: name, agents: ["codex"])
            let inspection = try? ProjectInspector.inspect(
                projectURL: URL(fileURLWithPath: registration.canonicalPath, isDirectory: true),
                catalog: snapshot.catalog
            )
            if try draftStore.load(projectID: registration.id) == nil {
                let projectState = ProjectLockStore(
                    projectRoot: URL(fileURLWithPath: registration.canonicalPath, isDirectory: true)
                ).inspect()
                let manifest = projectState.manifest
                _ = try draftStore.save(
                    projectID: registration.id,
                    skillIDs: manifest?.skills ?? inspection?.observedSkillIDs ?? [],
                    instructionIDs: manifest?.instructions ?? [],
                    agents: manifest?.agents ?? (registration.agents.isEmpty ? ["codex"] : registration.agents)
                )
            }
            try reloadProjects(preferredID: registration.id)
            selectedProjectID = registration.id.uuidString
            report("已登记 \(registration.name)；未修改项目文件")
            return true
        } catch {
            reportKey(UserFacingText.error(error))
            return false
        }
    }

    @discardableResult
    func unregisterSelectedProject() -> Bool {
        guard let project = selectedProject, let id = UUID(uuidString: project.id) else { return false }
        do {
            try projectStore.unregister(id: id)
            try draftStore.remove(projectID: id)
            selectedProjectID = ""
            try reloadProjects(preferredID: nil)
            report("已移除本机登记；项目文件保持不变")
            return true
        } catch {
            reportKey(UserFacingText.error(error))
            return false
        }
    }

    func isDraftSelected(_ skill: SkillEntry) -> Bool {
        selectedProject?.draftSkillIDs.contains(skill.id) == true
    }

    func toggleSkill(_ skill: SkillEntry) {
        guard !skill.isBlocked else {
            report("\(skill.slug) 含阻塞问题，未加入草稿")
            return
        }
        guard let index = projects.firstIndex(where: { $0.id == selectedProjectID }) else { return }
        if projects[index].draftSkillIDs.contains(skill.id) {
            projects[index].draftSkillIDs.remove(skill.id)
        } else {
            let sameName = projects[index].draftSkillIDs.contains { id in
                snapshot.catalog.entries.first(where: { $0.id == id })?.slug == skill.slug
            }
            if sameName {
                report("\(skill.slug) 已有另一个来源，先移除同名条目")
                return
            }
            projects[index].draftSkillIDs.insert(skill.id)
        }
        persistDraft(for: projects[index])
    }

    func toggleInstruction(_ template: TemplateRecord) {
        guard let index = projects.firstIndex(where: { $0.id == selectedProjectID }) else { return }
        if projects[index].fragments.contains(template.id) {
            projects[index].fragments.removeAll { $0 == template.id }
        } else {
            projects[index].fragments.append(template.id)
            projects[index].fragments.sort()
        }
        persistDraft(for: projects[index])
    }

    func toggleAgent(_ host: AgentHost) {
        guard let index = projects.firstIndex(where: { $0.id == selectedProjectID }) else { return }
        if projects[index].agents.contains(host.rawValue) {
            projects[index].agents.remove(host.rawValue)
        } else {
            projects[index].agents.insert(host.rawValue)
        }
        persistDraft(for: projects[index])
    }

    func loadPreset(_ preset: PresetRecord, into projectID: String? = nil) {
        let targetID = projectID ?? selectedProjectID
        guard let index = projects.firstIndex(where: { $0.id == targetID }) else { return }
        let validIDs = Set(snapshot.catalog.entries.filter { !$0.isBlocked }.map(\.id))
        projects[index].draftSkillIDs = Set(preset.skills).intersection(validIDs)
        projects[index].fragments = preset.instructionFragments
        persistDraft(for: projects[index])
        selectedProjectID = targetID
        section = .projects
        report("已载入「\(LocalizedText(stringLiteral: preset.name))」草稿，尚未写入项目")
    }

    func prepareDeploymentPlan() {
        guard let project = selectedProject, let id = UUID(uuidString: project.id) else {
            report("先选择一个已登记项目")
            return
        }
        guard service != nil else {
            report("未找到技能库目录，无法生成部署计划")
            return
        }
        let knownFragments = Set(snapshot.templates.map(\.id))
        guard Set(project.fragments).isSubset(of: knownFragments) else {
            report("草稿包含未知指令片段，请重新选择预设或模板")
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try draftStore.save(
                projectID: id,
                skillIDs: project.draftSkillIDs,
                instructionIDs: project.fragments,
                agents: canonicalAgentIDs(project.agents)
            )
            guard let service else {
                report("服务未初始化，无法生成部署计划")
                return
            }
            preparedPlan = try service.makePlan(
                projectID: id,
                skillIDs: project.draftSkillIDs.sorted(),
                instructionIDs: project.fragments,
                agents: canonicalAgentIDs(project.agents),
                ruleBlockID: "project-rules"
            )
            planPresented = true
            report("已生成变更计划；等待本机人工批准")
        } catch {
            preparedPlan = nil
            planPresented = false
            reportKey(UserFacingText.error(error))
        }
    }

    @discardableResult
    func approveAndApplyPreparedPlan() -> Bool {
        guard let prepared = preparedPlan else {
            report("没有可执行的变更计划")
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let approved = try planStore.approve(id: prepared.id, digest: prepared.plan.digest)
            guard let service else {
                throw SkillSetServiceError.repositoryNotFound
            }
            let result = try service.apply(planID: approved.id, digest: approved.plan.digest)
            let applied = try planStore.load(approved.id)
            preparedPlan = applied
            let planType = applied.plan.metadata?["planType"] ?? "skill-deployment"
            let historyTitle: String
            if planType == "plugin-lifecycle" {
                let host = MCPHost(rawValue: applied.plan.metadata?["pluginHost"] ?? "")?.displayName ?? "未识别工具"
                let action = UserFacingText.changeAction(applied.plan.metadata?["pluginAction"] ?? "")
                let pluginID = applied.plan.metadata?["pluginID"] ?? "unknown"
                historyTitle = "\(host) · \(action) \(pluginID)"
            } else {
                historyTitle = URL(fileURLWithPath: applied.plan.projectPath).lastPathComponent
            }
            history.insert(
                "\(Date.formattedLocalShort()) · \(historyTitle) · \(result.changedPaths.count) 项目标",
                at: 0
            )
            history = Array(history.prefix(20))
            try reloadProjects(preferredID: UUID(uuidString: selectedProjectID))
            refreshMCPConfigurations()
            if planType == "plugin-lifecycle" {
                refreshPlugins()
            }
            planPresented = false
            reportKey(UserFacingText.applyResult(result.message))
            return true
        } catch {
            reportKey(UserFacingText.error(error))
            return false
        }
    }

    func dismissPlan() {
        preparedPlan = nil
        planPresented = false
    }

    func refreshPendingPlans() {
        do {
            pendingPlans = try planStore.list().filter { record in
                record.approvalState != .applied && !record.isExpired(at: Date())
            }
        } catch {
            reportKey(UserFacingText.error(error))
        }
    }

    func reviewPlan(_ record: StoredDeploymentPlan) {
        preparedPlan = record
        planPresented = true
    }

    func pendingChangeCount(for project: ProjectRecord) -> Int {
        let targetCount = max(project.agents.count, 1)
        let skillDelta = project.draftSkillIDs.symmetricDifference(project.appliedSkillIDs).count * targetCount
        let lockDelta = project.lockStatus == "valid" ? 0 : 1
        return skillDelta + (ruleBlockMatches(project) ? 0 : targetCount) + lockDelta
    }

    func refreshMCPStatus(_ server: MCPServerRecord) {
        selectedMCPID = server.id
        refreshMCPConfigurations()
        report("已重新读取 \(server.name) 的宿主配置；没有启动进程")
    }

    func mcpCommandPreview(_ server: MCPServerRecord) -> String {
        if let observed = mcpConfigInspections.flatMap(\.servers).first(where: { $0.id == server.id }) {
            return server.command + (observed.argumentCount == 0 ? "" : L10n.tr(" <\(observed.argumentCount) 个参数已收起>"))
        }
        return ([server.command] + server.args).joined(separator: " ")
    }

    func inspectPlugin(_ plugin: PluginInventoryRecord) {
        selectedPluginID = plugin.id
        report("已展开 \(plugin.name) 的组件清单")
    }

    func previewSource(urlString: String, ref: String? = nil) {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            report("请输入 GitHub 仓库根链接")
            return
        }
        guard !isWorking else { return }
        isWorking = true
        report("正在下载并扫描技能，不会运行仓库脚本")
        let previewsRoot = runtimePaths.previewsRoot
        let trimmedRef = ref?.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let record = try await Task.detached(priority: .userInitiated) {
                    try SourcePreviewService(previewsRoot: previewsRoot).preview(
                        urlString: trimmedURL,
                        ref: trimmedRef?.isEmpty == true ? nil : trimmedRef
                    )
                }.value
                sourcePreviews.removeAll { $0.id == record.id }
                sourcePreviews.insert(record, at: 0)
                selectedPreviewID = record.id
                report("已保存来源预览 \(record.resolvedCommit.prefix(12))；尚未收录或启用")
            } catch {
                reportKey(UserFacingText.error(error))
            }
            isWorking = false
        }
    }

    func refreshSourcePreviews() {
        do {
            sourcePreviews = try SourcePreviewStore(rootURL: runtimePaths.previewsRoot).list()
            if selectedPreviewID == nil {
                selectedPreviewID = sourcePreviews.first?.id
            }
        } catch {
            reportKey(UserFacingText.error(error))
        }
    }

    func refreshMCPConfigurations() {
        guard let service else { return }
        do {
            let projectID = UUID(uuidString: selectedProjectID)
            mcpConfigInspections = try service.mcpConfigurations(projectID: projectID)
            mcpServers = mcpConfigInspections.flatMap { inspection in
                inspection.servers.map { server in
                    MCPServerRecord(
                        id: server.id,
                        name: server.name,
                        host: server.host.displayName,
                        transport: server.transport,
                        scope: "\(server.scope.displayName) · \(server.configPath)",
                        command: server.command,
                        args: server.argumentCount == 0 ? [] : ["<\(server.argumentCount) 个参数已收起>"],
                        envKeys: server.envKeys,
                        state: server.managed ? "管理器受管" : "仅观察",
                        note: server.managed
                            ? "由栖集写入；修改仍要重新生成并通过本机审批。"
                            : "现有宿主配置仅观察；同名新增会阻塞，不会静默覆盖。"
                    )
                }
            }
            if !mcpServers.contains(where: { $0.id == selectedMCPID }) {
                selectedMCPID = mcpServers.first?.id ?? ""
            }
        } catch {
            reportKey(UserFacingText.error(error))
        }
    }

    func makeMCPConfigPlan(_ draft: MCPConfigurationDraft) -> Bool {
        guard let service else {
            report("服务未初始化，无法生成 MCP 配置计划")
            return false
        }
        let issues = draft.validationIssues()
        guard issues.isEmpty else {
            report(LocalizedText.joining(issues))
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            preparedPlan = try service.makeMCPConfigPlan(
                projectID: UUID(uuidString: selectedProjectID),
                draft: draft
            )
            planPresented = true
            report("已生成 MCP 配置计划；等待本机人工批准")
            return true
        } catch {
            preparedPlan = nil
            reportKey(UserFacingText.error(error))
            return false
        }
    }

    func refreshPlugins() {
        guard let service else { return }
        do {
            let snapshot = try service.plugins(projectID: UUID(uuidString: selectedProjectID))
            pluginIssues = snapshot.issues
            pluginScanRoots = snapshot.scannedRoots
            plugins = snapshot.records
            if !plugins.contains(where: { $0.id == selectedPluginID }) {
                selectedPluginID = plugins.first?.id ?? ""
            }
        } catch {
            reportKey(UserFacingText.error(error))
        }
    }

    func makePluginLifecyclePlan(
        _ plugin: PluginInventoryRecord,
        action: PluginLifecycleAction,
        acknowledgeExecutableComponents: Bool
    ) {
        guard let service else {
            report("服务未初始化，无法生成插件计划")
            return
        }
        let scope: PluginLifecycleScope
        if plugin.host == .codex {
            scope = .user
        } else if let value = plugin.scope.flatMap(PluginLifecycleScope.init(rawValue:)) {
            scope = value
        } else if let project = selectedProject,
                  plugin.manifestPath.hasPrefix(project.path + "/") {
            scope = .project
        } else {
            scope = .user
        }
        isWorking = true
        defer { isWorking = false }
        do {
            preparedPlan = try service.makePluginLifecyclePlan(
                projectID: scope == .user ? nil : UUID(uuidString: selectedProjectID),
                request: PluginLifecycleRequest(
                    host: plugin.host,
                    pluginID: plugin.pluginID,
                    action: action,
                    scope: scope,
                    expectedManifestDigest: plugin.manifestDigest,
                    keepData: true,
                    acknowledgeExecutableComponents: acknowledgeExecutableComponents
                )
            )
            planPresented = true
            report("已生成插件\(LocalizedText(stringLiteral: action.displayName))计划；等待本机人工批准")
        } catch {
            preparedPlan = nil
            reportKey(UserFacingText.error(error))
        }
    }

    private func reloadProjects(preferredID: UUID?) throws {
        let registrations = try projectStore.list()
        var records: [ProjectRecord] = []
        var issues: [String: [String]] = [:]
        for registration in registrations {
            let projectURL = URL(fileURLWithPath: registration.canonicalPath, isDirectory: true)
            let inspection: ProjectInspection?
            let inspectionFailure: Error?
            do {
                inspection = try ProjectInspector.inspect(
                    projectURL: projectURL,
                    catalog: snapshot.catalog
                )
                inspectionFailure = nil
            } catch {
                inspection = nil
                inspectionFailure = error
            }
            let projectState = ProjectLockStore(projectRoot: projectURL).inspect()
            let manifest = projectState.manifest
            var draft = try draftStore.load(projectID: registration.id)
            if draft == nil {
                draft = try draftStore.save(
                    projectID: registration.id,
                    skillIDs: manifest?.skills ?? inspection?.observedSkillIDs ?? [],
                    instructionIDs: manifest?.instructions ?? [],
                    agents: manifest?.agents
                        ?? (registration.agents.isEmpty ? ["codex"] : registration.agents)
                )
            }
            let agents = displayAgentNames(draft?.agents ?? registration.agents)
            var record = ProjectRecord(
                id: registration.id.uuidString,
                name: registration.name,
                path: registration.canonicalPath,
                adapter: agents.isEmpty ? "未选 AI 工具" : agents.sorted().joined(separator: " · "),
                inherited: inspectionFailure.map {
                    "项目观察失败：\(UserFacingText.error($0))"
                } ?? "已读取项目清单和所选 AI 工具的技能目录；未扫描全局或父目录。",
                draftSkillIDs: Set(draft?.skillIDs ?? []),
                appliedSkillIDs: Set(inspection?.observedSkillIDs ?? []),
                agents: Set(agents),
                fragments: draft?.instructionIDs ?? [],
                pendingChanges: 0,
                lockStatus: projectState.status
            )
            record.pendingChanges = pendingChangeCount(for: record)
            records.append(record)
            var projectIssues = inspection?.issues ?? []
            if inspectionFailure != nil {
                projectIssues.append("检查项目目录权限后重新选择项目。")
            }
            issues[record.id] = projectIssues
                + (inspection?.ambiguousSlugs.map { "\($0)：多个来源内容相同，请在草稿中明确选择来源。" } ?? [])
                + (inspection?.driftedSlugs.map { "\($0)：本机内容与技能库记录不一致，请检查文件改动。" } ?? [])
        }
        projects = records
        projectIssues = issues
        refreshPendingPlans()
        if let preferredID, records.contains(where: { $0.id == preferredID.uuidString }) {
            selectedProjectID = preferredID.uuidString
        } else if !records.contains(where: { $0.id == selectedProjectID }) {
            selectedProjectID = records.first?.id ?? ""
        }
    }

    private func persistDraft(for project: ProjectRecord) {
        guard let id = UUID(uuidString: project.id) else { return }
        do {
            _ = try draftStore.save(
                projectID: id,
                skillIDs: project.draftSkillIDs,
                instructionIDs: project.fragments,
                agents: canonicalAgentIDs(project.agents)
            )
            if let index = projects.firstIndex(where: { $0.id == project.id }) {
                projects[index].pendingChanges = pendingChangeCount(for: projects[index])
            }
            report("草稿已保存；尚未写入项目")
        } catch {
            reportKey(UserFacingText.error(error))
        }
    }

    private func ruleBlockMatches(_ project: ProjectRecord) -> Bool {
        let expected = project.fragments.compactMap { id in
            snapshot.templates.first(where: { $0.id == id })?.body
        }.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let targets = canonicalAgentIDs(project.agents).compactMap {
            AgentDeploymentAdapter.target(for: $0)
        }
        guard !targets.isEmpty,
              let inspection = try? ProjectInspector.inspect(
            projectURL: URL(fileURLWithPath: project.path, isDirectory: true),
            catalog: snapshot.catalog
        ) else {
            return false
        }
        return targets.allSatisfy { target in
            let observed = inspection.ruleBodies[target.instructionsFile]
            return expected.isEmpty ? observed == nil : observed == expected
        }
    }

    private func canonicalAgentIDs(_ agents: Set<String>) -> [String] {
        agents.map { value in
            switch value {
            case AgentHost.codex.rawValue: "codex"
            case AgentHost.claude.rawValue: "claude-code"
            default: value.lowercased().replacingOccurrences(of: " ", with: "-")
            }
        }.sorted()
    }

    private func displayAgentNames(_ agents: [String]) -> [String] {
        agents.map { value in
            switch value {
            case "codex": AgentHost.codex.rawValue
            case "claude-code": AgentHost.claude.rawValue
            default: value
            }
        }.sorted()
    }
}

private extension Date {
    static func formattedLocalShort() -> String {
        Date().formatted(date: .abbreviated, time: .shortened)
    }
}
