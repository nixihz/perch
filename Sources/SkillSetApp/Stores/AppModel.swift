import Foundation
import Observation
import SkillSetCore

@MainActor
@Observable
final class AppModel {
    private(set) var snapshot: AppSnapshot
    private let baseSnapshot: AppSnapshot
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
    var presetSelection: PresetSelectionRequest?
    var presetEditor: PresetEditorDraft?
    var presetError: String?
    var selectedTemplateID = "base-zh"
    var templateError: String?
    var projects: [ProjectRecord] = []
    var projectIssues: [String: [String]] = [:]
    var projectSkillObservations: [String: [ProjectSkillObservation]] = [:]
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
    var libraryError: String?
    private(set) var skillRemovalError: String?
    var sourceImportError: String?
    var sourceOrigins: [String: SourceSkillOrigin] = [:]
    var selectedSkillDocument = ""
    var selectedSkillFiles: [SkillPackageFile] = []
    var skillFilesError: String?
    var selectedSkillFile: SkillPackageFile?
    var selectedSkillFilePreview: SkillFilePreview?
    var skillFilePreviewError: String?
    var hiddenSkillCount = 0
    var aiAccessError: LocalizedText?

    private let projectStore: ProjectStore
    private let draftStore: ProjectDraftStore
    private let planStore: DeploymentPlanStore
    private let executor: FileTransactionExecutor
    private var service: SkillSetService?

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
        let base = snapshot ?? AppSnapshot.load(repositoryRoot: runtimePaths.repositoryRoot)
        self.baseSnapshot = base
        self.snapshot = base
        projectStore = ProjectStore(rootURL: runtimePaths.applicationSupportRoot)
        draftStore = ProjectDraftStore(rootURL: runtimePaths.applicationSupportRoot)
        planStore = DeploymentPlanStore(rootURL: runtimePaths.plansRoot)
        executor = FileTransactionExecutor(operationsRoot: runtimePaths.operationsRoot)
        service = try? SkillSetService(paths: runtimePaths)
        selectedSkillID = self.snapshot.catalog.entries.first?.id

        do {
            try reloadLibrary()
            let recovered = try executor.recoverPendingOperations()
            try reloadProjects(preferredID: nil)
            refreshMCPConfigurations()
            refreshPlugins()
            refreshSourcePreviews()
            if !recovered.isEmpty {
                report("已恢复 \(recovered.count) 个中断的写入操作")
            } else if runtimePaths.repositoryRoot == nil {
                report("未找到技能库目录；已添加项目仍可查看")
            } else if projects.isEmpty {
                report("尚未添加项目")
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

    private var libraryStore: SkillLibraryStore { SkillLibraryStore(rootURL: runtimePaths.libraryRoot) }

    func loadSelectedSkillDocument() {
        libraryError = nil
        selectedSkillDocument = ""
        selectedSkillFiles = []
        skillFilesError = nil
        closeSkillFile()
        guard let skill = selectedSkill else { return }
        do { selectedSkillDocument = try libraryStore.document(for: skill, repositoryRoot: runtimePaths.repositoryRoot) }
        catch { libraryError = UserFacingText.error(error) }
        do { selectedSkillFiles = try libraryStore.attachedFiles(for: skill, repositoryRoot: runtimePaths.repositoryRoot) }
        catch { skillFilesError = UserFacingText.error(error) }
    }

    func openSkillFile(_ file: SkillPackageFile) {
        closeSkillFile()
        guard let skill = selectedSkill, selectedSkillFiles.contains(file) else { return }
        selectedSkillFile = file
        do { selectedSkillFilePreview = try libraryStore.previewAttachedFile(file.path, for: skill, repositoryRoot: runtimePaths.repositoryRoot) }
        catch { skillFilePreviewError = UserFacingText.error(error) }
    }

    func closeSkillFile() {
        selectedSkillFile = nil
        selectedSkillFilePreview = nil
        skillFilePreviewError = nil
    }

    func selectedSkillFileURL() -> URL? {
        guard let skill = selectedSkill, let file = selectedSkillFile else { return nil }
        do { return try libraryStore.attachedFileURL(file.path, for: skill, repositoryRoot: runtimePaths.repositoryRoot) }
        catch { skillFilePreviewError = UserFacingText.error(error); return nil }
    }

    func editorDraft(for skill: SkillEntry) -> SkillEditorDraft? {
        libraryError = nil
        do {
            return SkillEditorDraft(
                slug: skill.slug,
                document: try libraryStore.document(for: skill, repositoryRoot: runtimePaths.repositoryRoot),
                original: skill
            )
        } catch {
            libraryError = UserFacingText.error(error)
            return nil
        }
    }

    @discardableResult
    func saveSkill(_ draft: SkillEditorDraft) -> Bool {
        libraryError = nil
        do {
            let entry = try libraryStore.save(draft, repositoryRoot: runtimePaths.repositoryRoot)
            try reloadLibrary()
            query = ""
            selectedSkillID = entry.id
            loadSelectedSkillDocument()
            report("已保存技能 \(entry.slug)；项目更新仍需生成计划")
            return true
        } catch {
            libraryError = UserFacingText.error(error)
            return false
        }
    }

    func removeSkill(_ skill: SkillEntry) {
        removeSkills([skill])
    }

    @discardableResult
    func removeSkills(_ skills: [SkillEntry]) -> Set<String> {
        libraryError = nil
        skillRemovalError = nil
        var removed: Set<String> = []
        for skill in skills where !removed.contains(skill.id) {
            do {
                try libraryStore.remove(skill)
                removed.insert(skill.id)
            } catch {
                // 首次失败后停止，保留未完成项供用户核对和重试。
                skillRemovalError = UserFacingText.error(error)
                break
            }
        }
        do {
            try reloadLibrary()
            if !filteredSkills.contains(where: { $0.id == selectedSkillID }) {
                selectedSkillID = filteredSkills.first?.id
            }
            loadSelectedSkillDocument()
            if !removed.isEmpty {
                report("已从技能库移除 \(removed.count) 个技能；已部署的项目文件保持不变")
            }
        } catch { skillRemovalError = UserFacingText.error(error) }
        return removed
    }

    func restoreHiddenSkills() {
        libraryError = nil
        do {
            try libraryStore.restoreHidden()
            try reloadLibrary()
            updateQuery(query)
            report("已恢复隐藏的来源条目")
        } catch { libraryError = UserFacingText.error(error) }
    }

    private func reloadLibrary() throws {
        snapshot = try baseSnapshot.replacingCatalog(libraryStore.catalog(merging: baseSnapshot.catalog))
        sourceOrigins = try libraryStore.sourceOrigins()
        do { snapshot = try snapshot.replacingPresets(presetStore.list(merging: baseSnapshot.presets)) }
        catch { presetError = "本机预设文件无法读取，请检查文件后重试。" }
        do {
            snapshot = try snapshot.replacingTemplates(templateStore.list(merging: baseSnapshot.templates))
            if !snapshot.templates.contains(where: { $0.id == selectedTemplateID }) {
                selectedTemplateID = snapshot.templates.first?.id ?? ""
            }
            templateError = nil
        } catch {
            snapshot = snapshot.replacingTemplates([])
            templateError = "本机片段库无法读取，请检查数据文件后重试。"
        }
        hiddenSkillCount = try libraryStore.hiddenCount()
        service = try SkillSetService(paths: runtimePaths)
        updateQuery(query)
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

    private var templateStore: TemplateStore { TemplateStore(rootURL: runtimePaths.applicationSupportRoot) }

    func matchingTemplates(_ query: String) -> [TemplateRecord] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return snapshot.templates.filter { template in
            term.isEmpty || [UserFacingText.templateTitle(template), UserFacingText.templatePurpose(template), template.body]
                .contains { $0.localizedStandardContains(term) }
        }
    }

    @discardableResult
    func saveTemplate(_ draft: TemplateEditorDraft) -> Bool {
        templateError = nil
        do {
            snapshot = try snapshot.replacingTemplates(templateStore.save(draft.record, initial: baseSnapshot.templates))
            selectedTemplateID = draft.id
            service = try? SkillSetService(paths: runtimePaths)
            report("片段已保存；项目更新仍需预览和批准。")
            return true
        } catch let error as TemplateStoreError {
            templateError = error.errorDescription
        } catch { templateError = UserFacingText.error(error) }
        return false
    }

    func removeTemplate(_ template: TemplateRecord) {
        templateError = nil
        do {
            snapshot = try snapshot.replacingTemplates(templateStore.remove(id: template.id, initial: baseSnapshot.templates))
            selectedTemplateID = snapshot.templates.first?.id ?? ""
            service = try? SkillSetService(paths: runtimePaths)
            report("片段已删除；已写入项目的规则保持不变。")
        } catch let error as TemplateStoreError {
            templateError = error.errorDescription
        } catch { templateError = UserFacingText.error(error) }
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
            report("已添加 \(registration.name)；未修改项目文件")
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
            report("已从列表移除项目；项目文件保持不变")
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
        toggleInstructionID(template.id)
    }

    func toggleInstructionID(_ id: String) {
        guard let index = projects.firstIndex(where: { $0.id == selectedProjectID }) else { return }
        if projects[index].fragments.contains(id) {
            projects[index].fragments.removeAll { $0 == id }
        } else {
            guard snapshot.templates.contains(where: { $0.id == id }) else { return }
            projects[index].fragments.append(id)
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

    private var presetStore: PresetStore { PresetStore(rootURL: runtimePaths.applicationSupportRoot) }

    func beginNewPreset() {
        presetError = nil
        refreshPlugins()
        presetEditor = PresetEditorDraft()
    }

    func beginEditingPreset(_ preset: PresetRecord, copy: Bool = false) {
        presetError = nil
        refreshPlugins()
        presetEditor = PresetEditorDraft(preset: preset, copy: copy)
    }

    @discardableResult
    func savePreset(_ draft: PresetEditorDraft) -> Bool {
        presetError = nil
        let preset = draft.record
        let validation = PresetDraftPreview(preset: preset, project: selectedProject ?? ProjectRecord.demo[0], snapshot: snapshot)
        guard validation.unavailableSkillIDs.isEmpty && validation.unavailableInstructionIDs.isEmpty && validation.conflictingSkillIDs.isEmpty else {
            presetError = "预设包含不可用或同名冲突的技能、规则，请核对后重试"
            return false
        }
        do {
            let presets = try presetStore.save(preset, initial: baseSnapshot.presets)
            snapshot = snapshot.replacingPresets(presets)
            selectedPresetID = preset.id
            report("预设已保存；可随时用于项目草稿。")
            return true
        } catch let error as PresetStoreError {
            presetError = error.errorDescription
            return false
        } catch {
            presetError = UserFacingText.error(error)
            return false
        }
    }

    func presetPlugins(for projectID: String) -> [PluginInventoryRecord] {
        guard let service else { return plugins }
        return (try? service.plugins(projectID: UUID(uuidString: projectID)).records) ?? []
    }

    func preparePresetPlugin(_ reference: PresetPluginReference, acknowledge: Bool) {
        guard let service else { report("服务未初始化，无法生成插件计划"); return }
        preparedPlan = nil
        do {
            guard let plugin = presetPlugins(for: selectedProjectID).first(where: {
                $0.host == reference.host && $0.pluginID == reference.pluginID && $0.manifestDigest == reference.manifestDigest
            }) else { report("插件版本不可用，请重新扫描并更新预设。"); return }
            preparedPlan = try service.makePluginLifecyclePlan(
                projectID: reference.scope == .user ? nil : UUID(uuidString: selectedProjectID),
                request: PluginLifecycleRequest(host: reference.host, pluginID: reference.pluginID,
                    action: plugin.installed && plugin.scope == reference.scope.rawValue ? .enable : .install, scope: reference.scope,
                    expectedManifestDigest: reference.manifestDigest, keepData: true,
                    acknowledgeExecutableComponents: acknowledge)
            )
            planPresented = true
        } catch { reportKey(UserFacingText.error(error)) }
    }

    func removePresetComponent(pluginID: String? = nil, mcpID: String? = nil) {
        guard let index = projects.firstIndex(where: { $0.id == selectedProjectID }),
              let id = UUID(uuidString: selectedProjectID) else { return }
        var proposed = projects[index]
        if let pluginID { proposed.draftPlugins.removeAll { $0.id == pluginID } }
        if let mcpID { proposed.draftMCPServers.removeAll { $0.presetID == mcpID } }
        do {
            _ = try draftStore.save(projectID: id, skillIDs: proposed.draftSkillIDs,
                instructionIDs: proposed.fragments, agents: canonicalAgentIDs(proposed.agents),
                plugins: proposed.draftPlugins, mcpServers: proposed.draftMCPServers)
            projects[index] = proposed
            report("草稿已保存；尚未写入项目")
        } catch { reportKey(UserFacingText.error(error)) }
    }

    @discardableResult
    func loadPreset(_ preset: PresetRecord, into projectID: String? = nil) -> Bool {
        let targetID = projectID ?? selectedProjectID
        guard let index = projects.firstIndex(where: { $0.id == targetID }),
              let id = UUID(uuidString: targetID) else {
            report("请先添加并选择一个项目")
            return false
        }
        let preview = PresetDraftPreview(preset: preset, project: projects[index], snapshot: snapshot, availablePlugins: presetPlugins(for: targetID))
        guard preview.canLoad else {
            if let issue = preview.componentIssues.first { reportKey(issue) }
            else { report("预设包含不可用或同名冲突的技能、规则，请核对后重试") }
            return false
        }
        do {
            // 先持久化再更新界面，保存失败时保留原草稿和目标选择。
            let draft = try draftStore.save(
                projectID: id,
                skillIDs: preset.skills,
                instructionIDs: preset.instructionFragments,
                agents: canonicalAgentIDs(projects[index].agents),
                plugins: preset.plugins, mcpServers: preset.mcpServers
            )
            projects[index].draftSkillIDs = Set(draft.skillIDs)
            projects[index].fragments = draft.instructionIDs
            projects[index].draftPlugins = draft.plugins
            projects[index].draftMCPServers = draft.mcpServers
            projects[index].pendingChanges = pendingChangeCount(for: projects[index])
            selectedProjectID = targetID
            selectedPresetID = preset.id
            section = .projects
            if preset.status == "local" { report("已载入「\(preset.name)」草稿，尚未写入项目") }
            else { report("已载入「\(LocalizedText(stringLiteral: preset.name))」草稿，尚未写入项目") }
            return true
        } catch {
            reportKey(UserFacingText.error(error))
            return false
        }
    }

    func prepareDeploymentPlan() {
        guard let project = selectedProject, let id = UUID(uuidString: project.id) else {
            report("请先添加并选择一个项目")
            return
        }
        guard service != nil else {
            report("未找到技能库目录，无法生成部署计划")
            return
        }
        let knownFragments = Set(snapshot.templates.map(\.id))
        guard Set(project.fragments).isSubset(of: knownFragments) else {
            report("草稿中有找不到的AGENTS 片段，请重新选择预设或AGENTS 片段")
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try draftStore.save(
                projectID: id,
                skillIDs: project.draftSkillIDs,
                instructionIDs: project.fragments,
                agents: canonicalAgentIDs(project.agents),
                plugins: project.draftPlugins, mcpServers: project.draftMCPServers
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
            report("没有可用的计划，请先预览变更")
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
        report("已重新读取 \(server.name) 的 AI 工具配置；没有启动服务")
    }

    func importedSkillID(preview: SourcePreviewRecord, candidate: SourceSkillCandidate) -> String? {
        snapshot.catalog.entries.first { entry in
            guard let origin = sourceOrigins[entry.id] else { return false }
            return origin.url == preview.canonicalURL && origin.commit == preview.resolvedCommit
                && origin.path == candidate.path && origin.contentHash == candidate.contentHash
        }?.id
    }

    func showLibrarySkill(_ id: String) {
        query = ""
        selectedSkillID = id
        loadSelectedSkillDocument()
        section = .skills
    }

    func prepareSourceSkillImport(previewID: UUID, path: String) async -> SourceSkillImportDraft? {
        guard !isWorking else { return nil }
        isWorking = true
        sourceImportError = nil
        defer { isWorking = false }
        let paths = runtimePaths
        do {
            return try await Task.detached(priority: .userInitiated) {
                try SkillSetService(paths: paths).sourceSkillImportDraft(previewID: previewID, path: path)
            }.value
        } catch { sourceImportError = UserFacingText.error(error); return nil }
    }

    func importSourceSkill(_ draft: SourceSkillImportDraft) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        sourceImportError = nil
        defer { isWorking = false }
        let paths = runtimePaths
        do {
            let entry = try await Task.detached(priority: .userInitiated) {
                try SkillSetService(paths: paths).importSourceSkill(draft)
            }.value
            try reloadLibrary()
            query = ""
            selectedSkillID = entry.id
            report("已加入技能库 \(entry.slug)；可到项目页选择并预览变更")
            return true
        } catch { sourceImportError = UserFacingText.error(error); return false }
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

    func previewSource(urlString: String, ref: String? = nil, replacing replacedID: UUID? = nil) async -> Bool {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            report("请输入 GitHub 仓库根链接")
            return false
        }
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        report("正在下载并扫描技能，不会运行仓库脚本")
        let previewsRoot = runtimePaths.previewsRoot
        let trimmedRef = ref?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let record = try await Task.detached(priority: .userInitiated) {
                try SourcePreviewService(previewsRoot: previewsRoot).preview(
                    urlString: trimmedURL,
                    ref: trimmedRef?.isEmpty == true ? nil : trimmedRef,
                    replacing: replacedID
                )
            }.value
            sourcePreviews.removeAll { $0.id == record.id || $0.id == replacedID }
            sourcePreviews.insert(record, at: 0)
            selectedPreviewID = record.id
            report("已保存来源预览 \(record.resolvedCommit.prefix(12))；尚未收录或启用")
            return true
        } catch {
            reportKey(UserFacingText.error(error))
            return false
        }
    }

    func removeSourcePreview(_ id: UUID) {
        guard !isWorking else { return }
        do {
            try SourcePreviewStore(rootURL: runtimePaths.previewsRoot).remove(id)
            sourcePreviews.removeAll { $0.id == id }
            if selectedPreviewID == id { selectedPreviewID = sourcePreviews.first?.id }
            report("已删除隔离预览；技能库和项目未改变")
        } catch {
            reportKey(UserFacingText.error(error))
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
                            : "已有配置；可编辑或删除，批准计划后生效。"
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

    func makeMCPConfigPlan(_ draft: MCPConfigurationDraft, existingServer: MCPObservedServer? = nil,
                           remove: Bool = false, replaceArguments: Bool = false) -> Bool {
        guard let service else {
            report("服务未初始化，无法生成 MCP 配置计划")
            return false
        }
        let issues = draft.validationIssues()
        guard remove || issues.isEmpty else {
            report(LocalizedText.joining(issues))
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            preparedPlan = try service.makeMCPConfigPlan(
                projectID: UUID(uuidString: selectedProjectID),
                draft: draft, existingServer: existingServer, remove: remove,
                replaceArguments: replaceArguments
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

    var selectedMCPObservation: MCPObservedServer? {
        mcpConfigInspections.flatMap(\.servers).first { $0.id == selectedMCPID }
    }

    func removeMCPServer(_ server: MCPObservedServer) {
        let draft = MCPConfigurationDraft(name: server.name, host: server.host, scope: server.scope,
            transport: server.transport, commandOrURL: server.command)
        _ = makeMCPConfigPlan(draft, existingServer: server, remove: true)
    }

    var mcpAccessInstallation: MCPAccessInstallation? {
        MCPAccessInstallation.detect(bundleURL: Bundle.main.bundleURL, repositoryRoot: runtimePaths.repositoryRoot)
    }

    func mcpAccessInspection(host: MCPHost) -> MCPConfigurationInspection? {
        mcpConfigInspections.first { $0.host == host && $0.scope == .user }
    }

    func refreshAIAccess() {
        aiAccessError = nil
        refreshMCPConfigurations()
        refreshPendingPlans()
    }

    @discardableResult
    func prepareAIAccess(host: MCPHost) -> Bool {
        aiAccessError = nil
        guard let installation = mcpAccessInstallation else {
            aiAccessError = "未找到完整的 MCP 程序。请重新构建或安装栖集，再重新检测。"
            return false
        }
        let success = makeMCPConfigPlan(installation.draft(host: host, paths: runtimePaths))
        if !success { aiAccessError = actionMessage }
        return success
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
        var skillObservations: [String: [ProjectSkillObservation]] = [:]
        for registration in registrations {
            let projectURL = URL(fileURLWithPath: registration.canonicalPath, isDirectory: true)
            let inspection: ProjectInspection?
            let inspectionFailure: Error?
            do {
                inspection = try ProjectInspector.inspect(
                    projectURL: projectURL,
                    catalog: snapshot.catalog,
                    operationsRoot: runtimePaths.operationsRoot
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
                lockStatus: projectState.status,
                draftPlugins: draft?.plugins ?? [],
                draftMCPServers: draft?.mcpServers ?? []
            )
            record.pendingChanges = pendingChangeCount(for: record)
            records.append(record)
            skillObservations[record.id] = inspection?.skillObservations ?? []
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
        projectSkillObservations = skillObservations
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
                agents: canonicalAgentIDs(project.agents),
                plugins: project.draftPlugins, mcpServers: project.draftMCPServers
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
