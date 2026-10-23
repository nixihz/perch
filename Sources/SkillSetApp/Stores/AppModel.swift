import Foundation
import Observation
import SkillSetCore

struct ProjectPlanNotice: Equatable {
    enum Tone: Equatable {
        case info
        case error
    }

    let message: String
    let tone: Tone
}

@MainActor
@Observable
final class AppModel {
    private(set) var snapshot: AppSnapshot
    private let baseSnapshot: AppSnapshot
    let runtimePaths: SkillSetRuntimePaths
    let mcpLibrary: MCPLibraryModel
    let globalConfiguration: GlobalConfigurationModel

    var section: NavigationItem = .projects {
        didSet {
            guard section == .mcp, oldValue != .mcp else { return }
            // 只沿用真实入口的编辑范围，不能让另一页遗留的项目选择覆盖全局工具。
            if oldValue == .projects, let project = selectedProject,
               let host = MCPHost(rawValue: project.editingAgent), let projectID = UUID(uuidString: project.id) {
                mcpLibrary.preferUsageTarget(host: host, projectID: projectID)
            } else {
                mcpLibrary.preferUsageTarget(host: globalConfiguration.host, projectID: nil)
            }
        }
    }
    var query = ""
    var selectedProjectID = "" {
        didSet {
            guard selectedProjectID != oldValue else { return }
            // 选择变化时立即撤下旧范围，不能等新页面的 task 开始后才清理。
            mcpRefreshID = UUID()
            isRefreshingMCPConfigurations = false
            mcpConfigInspections = []
            mcpServers = []
            selectedMCPID = ""
        }
    }
    var selectedSkillID: String? {
        didSet {
            guard selectedSkillID != oldValue else { return }
            skillDocumentRequest = UUID()
            isLoadingSkillDocument = false
            selectedSkillDocument = ""
            selectedSkillFiles = []
            libraryError = nil
            skillFilesError = nil
            closeSkillFile()
        }
    }
    var selectedMCPID = ""
    var selectedPluginID = ""
    var selectedSourceID = ""
    var skillInstallMethod: SkillInstallMethod = .symlink
    var selectedPreviewID: UUID?
    var selectedPresetID = ""
    var presetSelection: PresetSelectionRequest?
    var presetEditor: PresetEditorDraft?
    var presetError: String?
    var selectedTemplateID = ""
    var templateError: String?
    private(set) var templateLibraryError: String?
    var templateUseRequest: TemplateUseRequest?
    var templatePlanReady = false
    private var templatePlanID: UUID?
    private var templatePlanPaths: [String] = []
    private(set) var lastTemplateWritePaths: [String] = []
    var planError: String?
    private(set) var projectPlanNotices: [String: ProjectPlanNotice] = [:]
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
    var skillsShQuery = ""
    private(set) var skillsShResults: [SkillsShHit] = []
    private(set) var skillsShError: String?
    private(set) var isSearchingSkillsSh = false
    private(set) var installingSkillsShID: String?
    private(set) var isLoadingSkillDocument = false
    private var skillDocumentRequest = UUID()
    var selectedSkillDocument = ""
    var selectedSkillFiles: [SkillPackageFile] = []
    var skillFilesError: String?
    var selectedSkillFile: SkillPackageFile?
    var selectedSkillFilePreview: SkillFilePreview?
    var skillFilePreviewError: String?
    var hiddenSkillCount = 0
    var aiAccessError: LocalizedText?
    private(set) var mcpAccessInstallation: MCPAccessInstallation?
    private(set) var isRefreshingMCPConfigurations = false
    private(set) var isRefreshingAIAccess = false
    private var mcpRefreshID = UUID()
    private var mcpConfigurationsProjectID = ""
    private var pendingPlansRefreshID = UUID()
    private var aiAccessRefreshID = UUID()

    private let projectStore: ProjectStore
    private let draftStore: ProjectDraftStore
    private let planStore: DeploymentPlanStore
    private let executor: FileTransactionExecutor
    private let skillsShClient: SkillsShDirectoryClient
    private var service: SkillSetService?

    func report(_ message: LocalizedText) {
        actionMessage = message
    }

    func reportKey(_ key: String) {
        actionMessage = LocalizedText(stringLiteral: key)
    }

    init(
        snapshot: AppSnapshot? = nil,
        runtimePaths: SkillSetRuntimePaths = .detect(),
        globalLocations: GlobalConfigurationLocations? = nil,
        skillsShClient: SkillsShDirectoryClient = SkillsShDirectoryClient()
    ) {
        self.runtimePaths = runtimePaths
        self.skillsShClient = skillsShClient
        self.mcpLibrary = MCPLibraryModel(paths: runtimePaths, locations: globalLocations)
        self.globalConfiguration = GlobalConfigurationModel(paths: runtimePaths, locations: globalLocations)
        let base = snapshot ?? SkillSetService.defaultSnapshot(for: runtimePaths)
        self.baseSnapshot = base
        self.snapshot = base
        projectStore = ProjectStore(rootURL: runtimePaths.applicationSupportRoot)
        draftStore = ProjectDraftStore(rootURL: runtimePaths.applicationSupportRoot)
        planStore = DeploymentPlanStore(rootURL: runtimePaths.plansRoot)
        executor = FileTransactionExecutor(operationsRoot: runtimePaths.operationsRoot, versionsRoot: runtimePaths.versionsRoot)
        service = try? SkillSetService(paths: runtimePaths, globalLocations: globalLocations)
        selectedSkillID = self.snapshot.catalog.entries.first?.id

        do {
            try runtimePaths.migrateLegacyState()
            do { try service?.synchronizeSourceLibrary() }
            catch { sourceImportError = UserFacingText.error(error) }
            try reloadLibrary()
            let recovered = try executor.recoverPendingOperations()
            try reloadProjects(preferredID: nil)
            refreshMCPConfigurations()
            refreshPlugins()
            refreshSourcePreviews()
            if !recovered.isEmpty {
                report("已恢复 \(recovered.count) 个中断的写入操作")
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
        matchingSkills(snapshot.catalog.entries, query: query, sourceOrigins: sourceOrigins)
    }

    private var libraryStore: SkillLibraryStore { SkillLibraryStore(rootURL: runtimePaths.libraryRoot) }

    func loadSelectedSkillDocument() {
        skillDocumentRequest = UUID()
        isLoadingSkillDocument = false
        libraryError = nil
        skillFilesError = nil
        guard let skill = selectedSkill else { return }
        do { selectedSkillDocument = try libraryStore.document(for: skill, repositoryRoot: runtimePaths.repositoryRoot) }
        catch { libraryError = UserFacingText.error(error) }
        do {
            selectedSkillFiles = try libraryStore.attachedFiles(for: skill, repositoryRoot: runtimePaths.repositoryRoot)
            closeSkillFile()
        }
        catch { skillFilesError = UserFacingText.error(error) }
    }

    /// 文件读取和目录枚举不占用主线程；请求标识阻止旧技能覆盖新选择。
    func loadSelectedSkillDocumentInBackground() async {
        guard !Task.isCancelled else { return }
        let request = UUID()
        skillDocumentRequest = request
        guard let skill = selectedSkill else { isLoadingSkillDocument = false; return }
        isLoadingSkillDocument = true
        let paths = runtimePaths
        let result = await Task.detached(priority: .userInitiated) {
            let store = SkillLibraryStore(rootURL: paths.libraryRoot)
            let document = Result { try store.document(for: skill, repositoryRoot: paths.repositoryRoot) }
            let files = Result { try store.attachedFiles(for: skill, repositoryRoot: paths.repositoryRoot) }
            return (document, files)
        }.value
        guard skillDocumentRequest == request else { return }
        isLoadingSkillDocument = false
        guard !Task.isCancelled, selectedSkillID == skill.id else { return }
        libraryError = nil
        skillFilesError = nil
        do { selectedSkillDocument = try result.0.get() }
        catch { libraryError = UserFacingText.error(error) }
        do {
            selectedSkillFiles = try result.1.get()
            closeSkillFile()
        }
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
        do {
            snapshot = try snapshot.replacingPresets(presetStore.list(merging: baseSnapshot.presets))
            if !snapshot.presets.contains(where: { $0.id == selectedPresetID }) {
                selectedPresetID = snapshot.presets.first?.id ?? ""
            }
        }
        catch { presetError = "本机预设文件无法读取，请检查文件后重试。" }
        reloadTemplates()
        hiddenSkillCount = try libraryStore.hiddenCount()
        service = try SkillSetService(paths: runtimePaths, globalLocations: globalConfiguration.locations)
        updateQuery(query)
    }

    var selectedProject: ProjectRecord? {
        projects.first(where: { $0.id == selectedProjectID })
    }

    var canPrepareDeploymentPlan: Bool {
        selectedProject != nil && !isWorking
    }

    func projectPlanNotice(for projectID: String) -> ProjectPlanNotice? {
        projectPlanNotices[projectID]
    }

    private func setProjectPlanNotice(_ notice: ProjectPlanNotice?, for projectID: String) {
        if let notice {
            projectPlanNotices[projectID] = notice
        } else {
            projectPlanNotices.removeValue(forKey: projectID)
        }
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

    func reloadTemplates() {
        do {
            snapshot = snapshot.replacingTemplates(try templateStore.list(merging: baseSnapshot.templates))
            if !snapshot.templates.contains(where: { $0.id == selectedTemplateID }) {
                selectedTemplateID = snapshot.templates.first?.id ?? ""
            }
            templateLibraryError = nil
            templateError = nil
            service = try? SkillSetService(paths: runtimePaths, globalLocations: globalConfiguration.locations)
        } catch {
            snapshot = snapshot.replacingTemplates([])
            selectedTemplateID = ""
            templateLibraryError = "片段库读取失败，请检查 JSON 格式和版本后重新读取。原文件未被修改。"
        }
    }

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
            for index in projects.indices { projects[index].pendingChanges = pendingChangeCount(for: projects[index]) }
            service = try? SkillSetService(paths: runtimePaths, globalLocations: globalConfiguration.locations)
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
            service = try? SkillSetService(paths: runtimePaths, globalLocations: globalConfiguration.locations)
            report("片段已删除；已写入项目的规则保持不变。")
        } catch let error as TemplateStoreError {
            templateError = error.errorDescription
        } catch { templateError = UserFacingText.error(error) }
    }

    /// 选择窗口只读；明确加入草稿时才生成计划并持久化目标草稿。
    @discardableResult
    func prepareTemplateUse(templateID: String, target: TemplateUseTarget, preview: TemplateUsePreview) -> Bool {
        templateError = nil
        preparedPlan = nil
        planError = nil
        templatePlanReady = false
        do {
            let latest = try templateUsePreview(templateID: templateID, target: target)
            guard latest == preview else {
                templateError = "目标草稿或片段已改变，请重新选择目标以刷新预览。"
                return false
            }
            let fresh = try SkillSetService(paths: runtimePaths, globalLocations: globalConfiguration.locations)
            let plan: StoredDeploymentPlan
            switch target {
            case .project(let rawID):
                guard let id = UUID(uuidString: rawID), let draft = latest.projectDraft else { throw DeploymentError.invalidPlan }
                guard let agent = latest.agents.first else { throw DeploymentError.invalidPlan }
                plan = try fresh.makeHarnessPlan(projectID: id, agent: agent,
                    selection: draft.resolvedHarnessSelections[agent], installMethod: skillInstallMethod)
                _ = try draftStore.save(projectID: id, skillIDs: draft.skillIDs, instructionIDs: draft.instructionIDs,
                    agents: draft.agents, plugins: draft.plugins, mcpServers: draft.mcpServers, harnessSelections: draft.harnessSelections)
                try reloadProjects(preferredID: id)
            case .global(let host):
                guard let draft = latest.globalDraft else { throw DeploymentError.invalidPlan }
                plan = try fresh.makeGlobalPlan(host: host, selection: draft)
                try fresh.globalConfiguration.saveDraft(draft, host: host)
                globalConfiguration.selectHost(host)
            }
            service = fresh
            preparedPlan = plan
            templatePlanID = plan.id
            templatePlanPaths = latest.paths
            templatePlanReady = true
            templateUseRequest = nil
            report("片段已加入配置草稿；请核对变更并批准写入。")
            return true
        } catch {
            templateError = UserFacingText.error(error)
            return false
        }
    }

    func presentTemplatePlanIfReady() {
        guard templatePlanReady else { return }
        templatePlanReady = false
        planPresented = true
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
                catalog: snapshot.catalog, operationsRoot: runtimePaths.operationsRoot
            )
            if try draftStore.load(projectID: registration.id) == nil {
                let projectState = ProjectLockStore(
                    projectRoot: URL(fileURLWithPath: registration.canonicalPath, isDirectory: true), stateRoot: runtimePaths.applicationSupportRoot
                ).inspect()
                let manifest = projectState.manifest
                _ = try draftStore.save(
                    projectID: registration.id,
                    skillIDs: manifest?.skills ?? inspection?.observedSkillIDs ?? [],
                    instructionIDs: manifest?.instructions ?? [],
                    agents: manifest?.agents ?? (registration.agents.isEmpty ? ["codex"] : registration.agents),
                    harnessSelections: manifest?.harnessSelections
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
        guard let host = selectedProject.flatMap({ MCPHost(rawValue: $0.editingAgent) }) else { return false }
        return isDraftSelected(skill, host: host)
    }

    func isDraftSelected(_ skill: SkillEntry, host: MCPHost) -> Bool {
        selectedProject?.harnessSelections[host.rawValue]?.skillIDs.contains(skill.id) == true
    }

    func toggleSkill(_ skill: SkillEntry) {
        guard let host = selectedProject.flatMap({ MCPHost(rawValue: $0.editingAgent) }) else { return }
        setSkill(skill, enabled: !isDraftSelected(skill, host: host), host: host)
    }

    func setSkill(_ skill: SkillEntry, enabled: Bool, host: MCPHost) {
        guard let index = projects.firstIndex(where: { $0.id == selectedProjectID }) else { return }
        var proposed = projects[index]
        var selection = proposed.harnessSelections[host.rawValue] ?? ProjectHarnessSelection()
        guard selection.skillIDs.contains(skill.id) != enabled else { return }
        guard !enabled || !skill.isBlocked else {
            let message: LocalizedText = "\(skill.slug) 含阻塞问题，未加入草稿"
            setProjectPlanNotice(ProjectPlanNotice(message: host.displayName + " · " + L10n.tr(message), tone: .error), for: proposed.id)
            report(message)
            return
        }
        if enabled {
            let sameName = selection.skillIDs.contains { id in
                snapshot.catalog.entries.first(where: { $0.id == id })?.slug == skill.slug
            }
            if sameName {
                let message: LocalizedText = "\(skill.slug) 已有另一个来源，先移除同名条目"
                setProjectPlanNotice(ProjectPlanNotice(message: host.displayName + " · " + L10n.tr(message), tone: .error), for: proposed.id)
                report(message)
                return
            }
            selection.skillIDs.append(skill.id)
            selection.skillIDs.sort()
            proposed.agents.insert(host.displayName)
            proposed.adapter = proposed.agents.sorted().joined(separator: " · ")
        } else {
            selection.skillIDs.removeAll { $0 == skill.id }
        }
        proposed.harnessSelections[host.rawValue] = selection
        // 双宿主行内开关不能改变规则、插件和预览所在的编辑目标。
        proposed.selectEditingAgent(proposed.editingAgent)
        persistDraft(for: proposed)
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
        projects[index].updateEditingSelection()
        persistDraft(for: projects[index])
    }

    func selectProjectHost(_ host: AgentHost, projectID: String? = nil) {
        guard let index = projects.firstIndex(where: { $0.id == (projectID ?? selectedProjectID) }) else { return }
        let agent = host == .codex ? "codex" : "claude-code"
        if projects[index].editingAgent != agent {
            setProjectPlanNotice(nil, for: projects[index].id)
        }
        projects[index].selectEditingAgent(agent)
    }

    func toggleAgent(_ host: AgentHost) {
        guard let index = projects.firstIndex(where: { $0.id == selectedProjectID }) else { return }
        let agent = host == .codex ? "codex" : "claude-code"
        if projects[index].agents.contains(host.rawValue) {
            projects[index].agents.remove(host.rawValue)
            projects[index].harnessSelections.removeValue(forKey: agent)
        } else {
            projects[index].agents.insert(host.rawValue)
            projects[index].harnessSelections[agent] = ProjectHarnessSelection()
        }
        projects[index].selectEditingAgent(agent)
        projects[index].adapter = projects[index].agents.isEmpty ? "未选 AI 工具" : projects[index].agents.sorted().joined(separator: " · ")
        persistDraft(for: projects[index])
    }

    private var presetStore: PresetStore { PresetStore(rootURL: runtimePaths.applicationSupportRoot) }

    func removePreset(_ preset: PresetRecord) {
        presetError = nil
        do {
            snapshot = snapshot.replacingPresets(try presetStore.remove(id: preset.id))
            selectedPresetID = snapshot.presets.first?.id ?? ""
            service = try? SkillSetService(paths: runtimePaths, globalLocations: globalConfiguration.locations)
            report("预设已删除；已载入的项目草稿保持不变。")
        } catch let error as PresetStoreError {
            presetError = error.errorDescription
        } catch { presetError = UserFacingText.error(error) }
    }

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
                plugins: proposed.draftPlugins, mcpServers: proposed.draftMCPServers, harnessSelections: proposed.harnessSelections)
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
            // 预设技能与规则只替换当前宿主；插件与 MCP 已有各自明确的宿主范围。
            var proposed = projects[index]
            proposed.draftSkillIDs = Set(preset.skills)
            proposed.fragments = preset.instructionFragments
            proposed.updateEditingSelection()
            proposed.draftPlugins = preset.plugins
            proposed.draftMCPServers = preset.mcpServers
            _ = try draftStore.save(
                projectID: id, skillIDs: proposed.allDraftSkillIDs,
                instructionIDs: proposed.fragments, agents: canonicalAgentIDs(proposed.agents),
                plugins: proposed.draftPlugins, mcpServers: proposed.draftMCPServers,
                harnessSelections: proposed.harnessSelections
            )
            projects[index] = proposed
            projects[index].pendingChanges = pendingChangeCount(for: projects[index])
            setProjectPlanNotice(nil, for: targetID)
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

    func prepareUserSkillPlan(skillIDs: [String], agents: [String], method: SkillInstallMethod, adoptExisting: Bool) {
        do {
            guard let service else { throw SkillSetServiceError.repositoryNotFound }
            preparedPlan = try service.makeUserSkillPlan(skillIDs: skillIDs, agents: agents, installMethod: method, adoptExistingSkills: adoptExisting)
            planPresented = true
            report("已生成用户级技能计划；等待本机人工批准")
        } catch { libraryError = UserFacingText.error(error) }
    }

    func prepareDeploymentPlan() {
        guard let project = selectedProject, let id = UUID(uuidString: project.id) else {
            report("请先添加并选择一个项目")
            return
        }
        setProjectPlanNotice(nil, for: project.id)
        guard service != nil else {
            let message = L10n.tr("未找到技能库目录，无法生成部署计划")
            setProjectPlanNotice(ProjectPlanNotice(message: message, tone: .error), for: project.id)
            reportKey("未找到技能库目录，无法生成部署计划")
            return
        }
        let knownFragments = Set(snapshot.templates.map(\.id))
        guard Set(project.fragments).isSubset(of: knownFragments) else {
            let message = L10n.tr("草稿引用了已删除的 AGENTS 片段，请移除引用后再预览。")
            setProjectPlanNotice(ProjectPlanNotice(message: message, tone: .error), for: project.id)
            reportKey("草稿引用了已删除的 AGENTS 片段，请移除引用后再预览。")
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
                plugins: project.draftPlugins, mcpServers: project.draftMCPServers,
                harnessSelections: project.harnessSelections
            )
            guard let service else {
                report("服务未初始化，无法生成部署计划")
                return
            }
            preparedPlan = try service.makeHarnessPlan(
                projectID: id,
                agent: project.editingAgent,
                selection: project.harnessSelections[project.editingAgent],
                installMethod: skillInstallMethod
            )
            planPresented = true
            report("已生成变更计划；等待本机人工批准")
        } catch let error as DeploymentError where error == .noChanges {
            preparedPlan = nil
            planPresented = false
            let message = L10n.tr("草稿与项目现状一致，没有需要写入的变更。")
            setProjectPlanNotice(ProjectPlanNotice(message: message, tone: .info), for: project.id)
            reportKey("草稿与项目现状一致，没有需要写入的变更。")
        } catch {
            preparedPlan = nil
            planPresented = false
            setProjectPlanNotice(ProjectPlanNotice(message: UserFacingText.error(error), tone: .error), for: project.id)
            reportKey(UserFacingText.error(error))
        }
    }

    @discardableResult
    func approveAndApplyPreparedPlan() -> Bool {
        planError = nil
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
            if planType == "global-configuration" {
                if let raw = applied.plan.metadata?["globalHost"], let host = MCPHost(rawValue: raw), host != globalConfiguration.host {
                    globalConfiguration.selectHost(host)
                }
                globalConfiguration.didApply()
            }
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
            if applied.id == templatePlanID { lastTemplateWritePaths = templatePlanPaths }
            planPresented = false
            reportKey(UserFacingText.applyResult(result.message))
            return true
        } catch {
            planError = UserFacingText.error(error)
            reportKey(UserFacingText.error(error))
            return false
        }
    }

    func dismissPlan() {
        planError = nil
        preparedPlan = nil
        planPresented = false
    }

    func refreshPendingPlans() {
        pendingPlansRefreshID = UUID()
        do { pendingPlans = try PageSnapshotReader.pendingPlans(paths: runtimePaths) }
        catch { reportKey(UserFacingText.error(error)) }
    }

    func refreshPendingPlansInBackground() async {
        guard !Task.isCancelled else { return }
        let request = UUID()
        pendingPlansRefreshID = request
        let paths = runtimePaths
        let result = await Task.detached(priority: .userInitiated) {
            Result { try PageSnapshotReader.pendingPlans(paths: paths) }
        }.value
        guard pendingPlansRefreshID == request, !Task.isCancelled else { return }
        do { pendingPlans = try result.get() }
        catch { reportKey(UserFacingText.error(error)) }
    }

    func reviewPlan(_ record: StoredDeploymentPlan) {
        planError = nil
        preparedPlan = record
        planPresented = true
    }

    func pendingChangeCount(for project: ProjectRecord) -> Int {
        let current = try? ProjectLockStore(projectRoot: URL(fileURLWithPath: project.path),
            stateRoot: runtimePaths.applicationSupportRoot).loadManifest()
        let old = current?.resolvedHarnessSelections ?? [:]
        let hosts = Set(old.keys).union(project.harnessSelections.keys)
        let selectionDelta = hosts.reduce(0) { count, host in
            let before = old[host] ?? ProjectHarnessSelection()
            let after = project.harnessSelections[host] ?? ProjectHarnessSelection()
            return count + Set(before.skillIDs).symmetricDifference(after.skillIDs).count
                + Set(before.instructionIDs).symmetricDifference(after.instructionIDs).count
                + ((old[host] == nil) != (project.harnessSelections[host] == nil) ? 1 : 0)
        }
        let lockDelta = project.lockStatus == "valid" ? 0 : 1
        return selectionDelta + (ruleBlockMatches(project) ? 0 : 1) + lockDelta
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
        // 正文由技能页的可取消任务加载，跳转不重复遍历技能目录。
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

    func searchSkillsSh() async {
        let query = skillsShQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            skillsShResults = []
            skillsShError = nil
            return
        }
        guard !isSearchingSkillsSh else { return }
        isSearchingSkillsSh = true
        skillsShError = nil
        defer { isSearchingSkillsSh = false }
        do {
            let results = try await skillsShClient.search(query: query)
            guard skillsShQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
            skillsShResults = results
        } catch {
            guard skillsShQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
            skillsShResults = []
            skillsShError = UserFacingText.error(error)
        }
    }

    func installSkillsSh(_ hit: SkillsShHit) async -> SkillEntry? {
        guard !isWorking else { return nil }
        isWorking = true
        installingSkillsShID = hit.id
        skillsShError = nil
        defer {
            isWorking = false
            installingSkillsShID = nil
        }
        let paths = runtimePaths
        do {
            let entry = try await Task.detached(priority: .userInitiated) {
                try SkillSetService(paths: paths).installDirectorySkill(hit)
            }.value
            try reloadLibrary()
            report("已从 skills.sh 安装 \(entry.slug) 到技能库；尚未启用到项目")
            return entry
        } catch {
            skillsShError = UserFacingText.error(error)
            return nil
        }
    }

    func installedSkillsShEntry(for hit: SkillsShHit) -> SkillEntry? {
        let matches = installedSkillsShEntries(for: hit)
        return matches.count == 1 ? matches[0] : nil
    }

    private func installedSkillsShEntries(for hit: SkillsShHit) -> [SkillEntry] {
        guard let repositoryURL = hit.repositoryURL else { return [] }
        let skillID = SkillsShCandidateMatcher.normalizedIdentifier(hit.skillId)
        guard !skillID.isEmpty else { return [] }
        return snapshot.catalog.entries.filter { entry in
            guard let origin = sourceOrigins[entry.id], origin.url == repositoryURL else { return false }
            let pathLeaf = origin.path.split(separator: "/").last.map(String.init) ?? ""
            // 本机名称和标识可能由用户重新定义，不能据此把另一个目录条目视为已安装。
            // 旧证据没有原始名称时只按来源路径匹配，避免猜测并卸载错误的技能。
            return origin.declaredName.map { SkillsShCandidateMatcher.normalizedIdentifier($0) == skillID } == true
                || SkillsShCandidateMatcher.normalizedIdentifier(pathLeaf) == skillID
        }
    }

    @discardableResult
    func uninstallSkillsSh(_ hit: SkillsShHit) -> Bool {
        guard !isWorking else { return false }
        let matches = installedSkillsShEntries(for: hit)
        guard !matches.isEmpty else {
            skillsShError = L10n.tr("技能库中找不到这个技能，请重新搜索后再试。")
            return false
        }
        guard matches.count == 1 else {
            skillsShError = L10n.tr("技能库中有多个已安装技能匹配这个目录条目，请先在技能库中核对再卸载。")
            return false
        }
        skillsShError = nil
        let removed = removeSkills(matches)
        guard !removed.isEmpty, skillRemovalError == nil else {
            skillsShError = skillRemovalError ?? L10n.tr("未能从技能库卸载这个技能，请重新读取后重试。")
            return false
        }
        return true
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

    func scanInstalledSkills(additionalRoots: [URL]) throws -> [InstalledSkillObservation] {
        guard let service else { return [] }
        return try service.scanInstalledSkills(additionalRoots: additionalRoots)
    }

    var installedSkillImportError: String?

    func importInstalledSkills(_ selection: [InstalledSkillObservation]) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        let paths = runtimePaths
        let locations = globalConfiguration.locations
        installedSkillImportError = nil
        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try SkillSetService(paths: paths, globalLocations: locations).importInstalledSkills(selection)
            }.value
            try reloadLibrary()
            refreshSourcePreviews()
            report("已收录本机技能；原安装保持原样，可勾选技能后启用到 AI 工具")
            return true
        } catch {
            installedSkillImportError = UserFacingText.error(error)
            reportKey(UserFacingText.error(error))
            return false
        }
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
        let paths = runtimePaths
        let trimmedRef = ref?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let record = try await Task.detached(priority: .userInitiated) {
                try SkillSetService(paths: paths).previewSource(
                    urlString: trimmedURL,
                    ref: trimmedRef?.isEmpty == true ? nil : trimmedRef,
                    replacing: replacedID
                )
            }.value
            try reloadLibrary()
            sourcePreviews.removeAll { $0.id == record.id || $0.id == replacedID }
            sourcePreviews.insert(record, at: 0)
            selectedPreviewID = record.id
            report("已同步来源 \(record.resolvedCommit.prefix(12))；技能已可搜索，尚未启用")
            return true
        } catch {
            reportKey(UserFacingText.error(error))
            return false
        }
    }

    func removeSourcePreview(_ id: UUID) {
        guard !isWorking else { return }
        do {
            try service?.removeSource(id)
            try reloadLibrary()
            sourcePreviews.removeAll { $0.id == id }
            if selectedPreviewID == id { selectedPreviewID = sourcePreviews.first?.id }
            report("已移除来源及搜索条目；已部署的技能版本保留")
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

    func prepareMCPLibraryPlan(host: MCPHost, projectID: UUID?) {
        do {
            guard let service else { throw DeploymentError.invalidPlan }
            preparedPlan = try service.makeMCPLibraryPlan(host: host, projectID: projectID)
            mcpLibrary.error = nil
            planPresented = true
        } catch {
            preparedPlan = nil
            mcpLibrary.error = UserFacingText.error(error)
        }
    }

    func refreshMCPConfigurations() {
        mcpRefreshID = UUID()
        isRefreshingMCPConfigurations = false
        guard let service else { return }
        do { applyMCPConfigurations(try service.mcpConfigurations(projectID: UUID(uuidString: selectedProjectID))) }
        catch { reportKey(UserFacingText.error(error)) }
    }

    func refreshMCPConfigurationsInBackground() async {
        guard !Task.isCancelled, service != nil else { return }
        let request = UUID()
        mcpRefreshID = request
        isRefreshingMCPConfigurations = true
        let paths = runtimePaths, locations = globalConfiguration.locations, projectID = selectedProjectID
        if mcpConfigurationsProjectID != projectID { mcpConfigInspections = []; mcpServers = [] }
        let result = await Task.detached(priority: .userInitiated) {
            Result { try PageSnapshotReader.mcpConfigurations(paths: paths, locations: locations, projectID: projectID) }
        }.value
        guard mcpRefreshID == request else { return }
        isRefreshingMCPConfigurations = false
        guard !Task.isCancelled, selectedProjectID == projectID else { return }
        do { applyMCPConfigurations(try result.get()) }
        catch { reportKey(UserFacingText.error(error)) }
    }

    private func applyMCPConfigurations(_ inspections: [MCPConfigurationInspection]) {
        mcpConfigurationsProjectID = selectedProjectID
        mcpConfigInspections = inspections
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

    func mcpAccessInspection(host: MCPHost, scope: MCPConfigurationScope = .user) -> MCPConfigurationInspection? {
        guard mcpConfigurationsProjectID == selectedProjectID else { return nil }
        return mcpConfigInspections.first { $0.host == host && $0.scope == scope }
    }

    func refreshAIAccess() {
        aiAccessRefreshID = UUID()
        isRefreshingAIAccess = false
        mcpAccessInstallation = MCPAccessInstallation.detect(bundleURL: Bundle.main.bundleURL, repositoryRoot: runtimePaths.repositoryRoot)
        aiAccessError = nil
        refreshMCPConfigurations()
        refreshPendingPlans()
    }

    func refreshAIAccessInBackground() async {
        guard !Task.isCancelled else { return }
        let request = UUID()
        aiAccessRefreshID = request
        isRefreshingAIAccess = true
        aiAccessError = nil
        let bundleURL = Bundle.main.bundleURL, root = runtimePaths.repositoryRoot
        async let configuration: Void = refreshMCPConfigurationsInBackground()
        async let plans: Void = refreshPendingPlansInBackground()
        let installation = await Task.detached(priority: .userInitiated) {
            MCPAccessInstallation.detect(bundleURL: bundleURL, repositoryRoot: root)
        }.value
        _ = await (configuration, plans)
        guard aiAccessRefreshID == request else { return }
        isRefreshingAIAccess = false
        guard !Task.isCancelled else { return }
        mcpAccessInstallation = installation
    }

    @discardableResult
    func prepareAIAccess(host: MCPHost, scope: MCPConfigurationScope = .user) -> Bool {
        aiAccessRefreshID = UUID()
        isRefreshingAIAccess = false
        aiAccessError = nil
        // 预览前重新核对程序，页面缓存不能代替执行边界的验证。
        mcpAccessInstallation = MCPAccessInstallation.detect(bundleURL: Bundle.main.bundleURL, repositoryRoot: runtimePaths.repositoryRoot)
        guard let installation = mcpAccessInstallation else {
            preparedPlan = nil
            aiAccessError = "未找到完整的 MCP 程序。请重新构建或安装栖集，再重新检测。"
            return false
        }
        let success = makeMCPConfigPlan(installation.draft(host: host, scope: scope, paths: runtimePaths))
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
                    operationsRoot: runtimePaths.operationsRoot, versionsRoot: runtimePaths.versionsRoot
                )
                inspectionFailure = nil
            } catch {
                inspection = nil
                inspectionFailure = error
            }
            let projectState = ProjectLockStore(projectRoot: projectURL, stateRoot: runtimePaths.applicationSupportRoot).inspect()
            let manifest = projectState.manifest
            var draft = try draftStore.load(projectID: registration.id)
            if draft == nil {
                draft = try draftStore.save(
                    projectID: registration.id,
                    skillIDs: manifest?.skills ?? inspection?.observedSkillIDs ?? [],
                    instructionIDs: manifest?.instructions ?? [],
                    agents: manifest?.agents
                        ?? (registration.agents.isEmpty ? ["codex"] : registration.agents),
                    harnessSelections: manifest?.harnessSelections
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
                draftMCPServers: draft?.mcpServers ?? [],
                harnessSelections: draft?.resolvedHarnessSelections
            )
            let editingAgent = projects.first(where: { $0.id == record.id })?.editingAgent
                ?? (record.harnessSelections["codex"] != nil ? "codex" : record.harnessSelections.keys.sorted().first ?? "codex")
            record.selectEditingAgent(editingAgent)
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
                plugins: project.draftPlugins, mcpServers: project.draftMCPServers,
                harnessSelections: project.harnessSelections
            )
            if let index = projects.firstIndex(where: { $0.id == project.id }) {
                projects[index] = project
                projects[index].pendingChanges = pendingChangeCount(for: projects[index])
            }
            // 草稿已经改变，上一次预览结论不再对应当前内容。
            setProjectPlanNotice(nil, for: project.id)
            report("草稿已保存；尚未写入项目")
        } catch {
            let message = UserFacingText.error(error)
            setProjectPlanNotice(ProjectPlanNotice(message: message, tone: .error), for: project.id)
            reportKey(message)
        }
    }

    private func ruleBlockMatches(_ project: ProjectRecord) -> Bool {
        let targets = canonicalAgentIDs(project.agents).compactMap {
            AgentDeploymentAdapter.target(for: $0)
        }
        guard let inspection = try? ProjectInspector.inspect(
            projectURL: URL(fileURLWithPath: project.path, isDirectory: true),
            catalog: snapshot.catalog,
            operationsRoot: runtimePaths.operationsRoot,
            versionsRoot: runtimePaths.versionsRoot
        ) else {
            return false
        }
        return targets.allSatisfy { target in
            let expected = (project.harnessSelections[target.agent]?.instructionIDs ?? []).compactMap { id in
                snapshot.templates.first(where: { $0.id == id })?.body
            }.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
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
