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
    var relatedPath: String? = nil
}

private struct ImportedOriginKey: Hashable {
    let url: String
    let commit: String
    let path: String
    let contentHash: String
}

private struct SourceDetailKey: Equatable {
    let id: UUID
    let createdAt: Date
    let commit: String
    let candidateCount: Int
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
                mcpLibrary.preferUsageTarget(host: globalConfiguration.host.mcpHost ?? .codex, projectID: nil)
            }
        }
    }
    var query = ""
    @ObservationIgnored private var skillSearchIndex = SkillSearchIndex(entries: [])
    @ObservationIgnored private var filteredSkillQuery: String?
    @ObservationIgnored private var filteredSkillCache: [SkillEntry] = []
    @ObservationIgnored private(set) var skillLibraryIndex = SkillLibraryIndex(entries: [])
    @ObservationIgnored private(set) var skillSourceLabels: [String: String] = [:]
    @ObservationIgnored private var importedSkillIDs: [ImportedOriginKey: String] = [:]
    @ObservationIgnored private var sourceListTitles: [UUID: String] = [:]
    @ObservationIgnored private var sourceDetailKey: SourceDetailKey?
    @ObservationIgnored private var cachedSourceFolders: [(String, Int)] = []
    @ObservationIgnored private var cachedSourceCandidates: [SourceSkillCandidate] = []
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
    var presetDrafts: [String: PresetEditorDraft] = [:]
    var presetSelection: PresetSelectionRequest?
    var presetEditor: PresetEditorDraft?
    var presetError: LocalizedText?
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
    private(set) var skillInvocationPolicies: [String: SkillInvocationPolicy] = [:]
    private(set) var isUpdatingSkillMetadata = false
    var skillMetadataError: String?
    private(set) var skillMetadataSaveMessage: String?
    var projectSaveMessage: String?
    var sourceImportError: String?
    var sourceOrigins: [String: SourceSkillOrigin] = [:]
    /// 技能实体的真实存放位置。自建和复制导入在 sources/custom，跟随来源的指向来源检出目录。
    private(set) var skillStorageURLs: [String: URL] = [:]
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
    @ObservationIgnored private var libraryGeneration: SkillLibraryGeneration?
    @ObservationIgnored private var libraryReloadID = UUID()
    @ObservationIgnored private var isCheckingLibrary = false
    @ObservationIgnored private var libraryRefreshError: String?

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
        executor = FileTransactionExecutor(
            operationsRoot: runtimePaths.operationsRoot, versionsRoot: runtimePaths.versionsRoot,
            libraryRoot: runtimePaths.libraryDirectoryURL, sourcesRoot: runtimePaths.sourcesRoot)
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
            refreshSkillIndexes()
            reportKey(UserFacingText.error(error))
        }
    }

    var filteredSkills: [SkillEntry] {
        if filteredSkillQuery == query { return filteredSkillCache }
        let matched = skillSearchIndex.matching(query: query)
        filteredSkillQuery = query
        filteredSkillCache = matched
        return matched
    }

    /// 目录或来源变化后重建折叠文本和重名索引。搜索框连续读取命中缓存。
    private func refreshSkillIndexes() {
        skillSearchIndex = SkillSearchIndex(entries: snapshot.catalog.entries, sourceOrigins: sourceOrigins)
        skillLibraryIndex = SkillLibraryIndex(entries: snapshot.catalog.entries)
        skillSourceLabels = Dictionary(grouping: snapshot.catalog.entries, by: skillSourceKey).mapValues { entries in
            skillSourceTitle(entries[0])
        }
        filteredSkillQuery = nil
        var imported: [ImportedOriginKey: String] = [:]
        imported.reserveCapacity(sourceOrigins.count)
        for entry in snapshot.catalog.entries {
            guard let origin = sourceOrigins[entry.id] else { continue }
            let key = ImportedOriginKey(url: origin.url, commit: origin.commit, path: origin.path, contentHash: origin.contentHash)
            if imported[key] == nil { imported[key] = entry.id }
        }
        importedSkillIDs = imported
    }

    func skillSourceTitle(_ skill: SkillEntry) -> String {
        SkillSourceLabel.title(
            sourceID: skill.sourceId,
            origin: sourceOrigins[skill.id]?.url,
            registeredTitle: snapshot.sources.sources.first { $0.id == skill.sourceId }?.title
        )
    }

    func skillSourceKey(_ skill: SkillEntry) -> String {
        SkillSourceLabel.filterKey(sourceID: skill.sourceId, origin: sourceOrigins[skill.id]?.url)
    }

    func skills(from sourceKey: String) -> [SkillEntry] {
        guard !sourceKey.isEmpty else { return filteredSkills }
        return filteredSkills.filter { skillSourceKey($0) == sourceKey }
    }

    func skillDisplayTitle(_ skillID: String) -> String {
        if let entry = snapshot.catalog.entries.first(where: { $0.id == skillID }) {
            return entry.declaredName
        }
        return PresetDraftPreview.referenceName(skillID)
    }

    func pluginDisplayTitle(_ pluginID: String?) -> String {
        guard let pluginID, !pluginID.isEmpty else { return L10n.tr("未知") }
        if let name = plugins.first(where: { $0.pluginID == pluginID })?.name, !name.isEmpty {
            return name
        }
        return pluginID.split(separator: "@").first.map(String.init) ?? pluginID
    }

    private var libraryStore: SkillLibraryStore {
        runtimePaths.makeLibraryStore()
    }

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
            let store = paths.makeLibraryStore()
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

    /// 与窗口任务同生共灭；即使用户停留在其他页面，也要让配置列表使用最新技能库。
    func observeLibraryChanges(interval: Duration = .seconds(2)) async {
        while !Task.isCancelled {
            await refreshLibraryIfChanged()
            do { try await Task.sleep(for: interval) }
            catch { return }
        }
    }

    func refreshLibraryIfChanged() async {
        guard !Task.isCancelled, !isCheckingLibrary, !isWorking else { return }
        isCheckingLibrary = true
        defer { isCheckingLibrary = false }
        let paths = runtimePaths
        let previous = libraryGeneration
        let request = libraryReloadID
        do {
            let result = try await Task.detached(priority: .utility) {
                let before = SkillLibraryGeneration.capture(paths: paths)
                if before.isComplete, before == previous { return nil as (LoadedSkillLibrary, SkillLibraryGeneration)? }
                let loaded = try paths.makeLibraryStore().loadLibrary()
                let after = SkillLibraryGeneration.capture(paths: paths)
                // 读取期间还有写入时留到下一轮，不能把旧内容记作最新文件身份。
                guard before == after else { return nil }
                return (loaded, after)
            }.value
            // 本机保存或删除优先于较早开始的后台读取；取消窗口任务后不再发布。
            guard !Task.isCancelled, !isWorking, request == libraryReloadID, let (loaded, generation) = result else { return }
            let selected = selectedSkill
            try reloadLibrary(loaded: loaded)
            libraryGeneration = generation
            if libraryError == libraryRefreshError { libraryError = nil }
            libraryRefreshError = nil
            if !snapshot.catalog.entries.contains(where: { $0.id == selectedSkillID }) {
                selectedSkillID = filteredSkills.first?.id
            }
            if selected != selectedSkill {
                closeSkillFile()
                await loadSelectedSkillDocumentInBackground()
            }
        } catch {
            guard !Task.isCancelled, request == libraryReloadID else { return }
            libraryRefreshError = UserFacingText.error(error)
            libraryError = libraryRefreshError
        }
    }

    private func reloadLibrary(loaded: LoadedSkillLibrary? = nil) throws {
        libraryReloadID = UUID()
        libraryGeneration = nil
        let loaded = try loaded ?? libraryStore.loadLibrary()
        snapshot = baseSnapshot.replacingCatalog(loaded.catalog(merging: baseSnapshot.catalog))
        sourceOrigins = loaded.origins
        skillStorageURLs = loaded.packageURLs
        do {
            snapshot = try snapshot.replacingPresets(presetStore.list(merging: baseSnapshot.presets))
            if !snapshot.presets.contains(where: { $0.id == selectedPresetID }) {
                selectedPresetID = snapshot.presets.first?.id ?? ""
            }
        }
        catch { presetError = "本机预设文件无法读取，请检查文件后重试。" }
        globalConfiguration.setAvailableReferences(
            skillIDs: Set(snapshot.catalog.entries.map(\.id)),
            instructionIDs: Set(snapshot.templates.map(\.id))
        )
        reloadTemplates(updateService: false)
        refreshSkillIndexes()
        refreshSkillInvocationPolicies()
        service = try SkillSetService(paths: runtimePaths, globalLocations: globalConfiguration.locations, library: loaded)
        updateQuery(query)
    }

    func invocationPolicy(for skill: SkillEntry) -> SkillInvocationPolicy {
        skillInvocationPolicies[skill.id] ?? SkillInvocationPolicy()
    }

    @discardableResult
    func setInvocationPolicy(_ skill: SkillEntry, target: SkillInvocationTarget, manualOnly: Bool) -> Bool {
        guard !isUpdatingSkillMetadata else { return false }
        isUpdatingSkillMetadata = true
        skillMetadataError = nil
        skillMetadataSaveMessage = nil
        defer { isUpdatingSkillMetadata = false }
        do {
            let updated = try libraryStore.setInvocationPolicy(
                skill, target: target, manualOnly: manualOnly, repositoryRoot: runtimePaths.repositoryRoot
            )
            try reloadLibrary()
            selectedSkillID = updated.id
            loadSelectedSkillDocument()
            let targetName = target == .codex ? "Codex" : "Claude Code"
            skillMetadataSaveMessage = L10n.tr("已更新：\(targetName) · \(skill.slug) 的调用元信息")
            return true
        } catch {
            skillMetadataError = UserFacingText.error(error)
            return false
        }
    }

    var selectedProject: ProjectRecord? {
        projects.first(where: { $0.id == selectedProjectID })
    }

    private func refreshSkillInvocationPolicies() {
        var policies: [String: SkillInvocationPolicy] = [:]
        for skill in snapshot.catalog.entries {
            if let policy = try? libraryStore.invocationPolicy(for: skill, repositoryRoot: runtimePaths.repositoryRoot) {
                policies[skill.id] = policy
            }
        }
        skillInvocationPolicies = policies
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

    func reloadTemplates(updateService: Bool = true) {
        do {
            snapshot = snapshot.replacingTemplates(try templateStore.list(merging: baseSnapshot.templates))
            if !snapshot.templates.contains(where: { $0.id == selectedTemplateID }) {
                selectedTemplateID = snapshot.templates.first?.id ?? ""
            }
            templateLibraryError = nil
            templateError = nil
            if updateService {
                service = try? SkillSetService(paths: runtimePaths, globalLocations: globalConfiguration.locations)
            }
            globalConfiguration.setAvailableReferences(
                skillIDs: Set(snapshot.catalog.entries.map(\.id)),
                instructionIDs: Set(snapshot.templates.map(\.id))
            )
        } catch {
            snapshot = snapshot.replacingTemplates([])
            selectedTemplateID = ""
            templateLibraryError = "片段库无法读取，请在 Finder 中打开数据文件，检查格式后点击「重新读取」。"
            // 片段库读取失败时清空悬空草稿引用，保持项目和全局页面可继续操作。
            globalConfiguration.setAvailableReferences(
                skillIDs: Set(snapshot.catalog.entries.map(\.id)), instructionIDs: []
            )
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
        let previousBody = snapshot.templates.first(where: { $0.id == draft.id })?.body
        do {
            snapshot = try snapshot.replacingTemplates(templateStore.save(draft.record, initial: baseSnapshot.templates))
            selectedTemplateID = draft.id
            for index in projects.indices { projects[index].pendingChanges = pendingChangeCount(for: projects[index]) }
            service = try? SkillSetService(paths: runtimePaths, globalLocations: globalConfiguration.locations)
            let affectsConfiguration = previousBody != nil
                && previousBody != draft.body
                && ((try? templateReferences(draft.id).contains { $0.target != nil }) ?? true)
            if affectsConfiguration {
                invalidatePreparedRulePlan()
            }
            report("片段已保存；项目更新仍需预览和批准。")
            return true
        } catch let error as TemplateStoreError {
            templateError = error.errorDescription
        } catch { templateError = UserFacingText.error(error) }
        return false
    }

    func removeTemplate(_ template: TemplateRecord) {
        templateError = nil
        let affectsConfiguration = (try? templateReferences(template.id).contains { $0.target != nil }) ?? true
        do {
            snapshot = try snapshot.replacingTemplates(templateStore.remove(id: template.id, initial: baseSnapshot.templates))
            selectedTemplateID = snapshot.templates.first?.id ?? ""
            for index in projects.indices { projects[index].pendingChanges = pendingChangeCount(for: projects[index]) }
            service = try? SkillSetService(paths: runtimePaths, globalLocations: globalConfiguration.locations)
            if affectsConfiguration { invalidatePreparedRulePlan() }
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
                    selection: draft.resolvedHarnessSelections[agent], installMethod: skillInstallMethod,
                    allowRelatedHarnessUpdates: true)
                _ = try draftStore.save(projectID: id, skillIDs: draft.skillIDs, instructionIDs: draft.instructionIDs,
                    agents: draft.agents, plugins: draft.plugins, mcpServers: draft.mcpServers, harnessSelections: draft.harnessSelections)
                try reloadProjects(preferredID: id)
            case .global(let host):
                guard let draft = latest.globalDraft else { throw DeploymentError.invalidPlan }
                plan = try fresh.makeGlobalPlan(host: SkillConfigurationTarget(host), selection: draft)
                try fresh.globalConfiguration.saveDraft(draft, host: SkillConfigurationTarget(host))
                globalConfiguration.selectHost(SkillConfigurationTarget(host))
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

    /// 片段正文变化后，当前打开的规则计划已不再对应片段库快照。
    /// 计划记录本身保持不可变；这里只撤下 UI 中尚未执行的计划，避免继续执行旧正文。
    private func invalidatePreparedRulePlan() {
        guard let preparedPlan,
              preparedPlan.approvalState != .applied,
              preparedPlan.plan.changes.contains(where: { change in
                  change.relativePath == "AGENTS.md" || change.relativePath == "CLAUDE.md"
              }) else { return }
        self.preparedPlan = nil
        planPresented = false
        planError = "片段内容已变化，之前的规则计划已失效，请重新预览。"
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
            let message: LocalizedText = "\(skill.slug) 未通过文件检查，请到技能库查看原因。"
            setProjectPlanNotice(ProjectPlanNotice(message: host.displayName + " · " + L10n.tr(message), tone: .error), for: proposed.id)
            report(message)
            return
        }
        if enabled {
            let sameName = selection.skillIDs.contains { id in
                snapshot.catalog.entries.first(where: { $0.id == id })?.slug == skill.slug
            }
            if sameName {
                let message: LocalizedText = "\(skill.slug) 已选了另一个来源，请先取消同名技能。"
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

    func removeUnavailableSkill(_ id: String, host: MCPHost) {
        guard !snapshot.catalog.entries.contains(where: { $0.id == id }),
              var project = selectedProject,
              var selection = project.harnessSelections[host.rawValue] else { return }
        selection.skillIDs.removeAll { $0 == id }
        project.harnessSelections[host.rawValue] = selection
        project.selectEditingAgent(project.editingAgent)
        persistDraft(for: project)
    }

    func toggleInstructionID(_ id: String) {
        guard let project = selectedProject, let host = MCPHost(rawValue: project.editingAgent) else { return }
        setInstruction(id, enabled: !project.fragments.contains(id), host: host)
    }

    func setInstruction(_ id: String, enabled: Bool, host: MCPHost) {
        guard let index = projects.firstIndex(where: { $0.id == selectedProjectID }) else { return }
        var proposed = projects[index]
        var selection = proposed.harnessSelections[host.rawValue] ?? ProjectHarnessSelection()
        guard selection.instructionIDs.contains(id) != enabled else { return }
        if enabled {
            guard snapshot.templates.contains(where: { $0.id == id }) else { return }
            selection.instructionIDs.append(id)
            selection.instructionIDs.sort()
            proposed.agents.insert(host.displayName)
            proposed.adapter = proposed.agents.sorted().joined(separator: " · ")
        } else {
            selection.instructionIDs.removeAll { $0 == id }
        }
        proposed.harnessSelections[host.rawValue] = selection
        proposed.selectEditingAgent(proposed.editingAgent)
        persistDraft(for: proposed)
    }

    @discardableResult
    func saveProjectSkill(_ skill: SkillEntry, enabled: Bool, host: MCPHost) async -> Bool {
        guard !enabled || !skill.isBlocked else {
            let message: LocalizedText = "\(skill.slug) 未通过文件检查，请到技能库查看原因。"
            if let project = selectedProject {
                setProjectPlanNotice(ProjectPlanNotice(message: host.displayName + " · " + L10n.tr(message), tone: .error), for: project.id)
            }
            report(message)
            return false
        }
        if enabled, let project = selectedProject,
           let selected = project.harnessSelections[host.rawValue]?.skillIDs,
           snapshot.catalog.entries.contains(where: { $0.id != skill.id && $0.slug == skill.slug && selected.contains($0.id) }) {
            let message: LocalizedText = "\(skill.slug) 已选了另一个来源，请先取消同名技能。"
            setProjectPlanNotice(ProjectPlanNotice(message: host.displayName + " · " + L10n.tr(message), tone: .error), for: project.id)
            report(message)
            return false
        }
        return await saveProjectSkill(skill.id, name: skill.slug, enabled: enabled, host: host)
    }

    @discardableResult
    func saveProjectSkill(_ id: String, name: String, enabled: Bool, host: MCPHost) async -> Bool {
        guard let project = selectedProject, let projectUUID = UUID(uuidString: project.id), !isWorking else { return false }
        let previousSelection = project.harnessSelections[host.rawValue] ?? ProjectHarnessSelection()
        var updatedSelection = previousSelection
        updatedSelection.skillIDs.removeAll { $0 == id }
        if enabled { updatedSelection.skillIDs.append(id); updatedSelection.skillIDs.sort() }
        var proposed = project
        proposed.harnessSelections[host.rawValue] = updatedSelection
        proposed.selectEditingAgent(proposed.editingAgent)
        persistDraft(for: proposed)
        isWorking = true
        projectSaveMessage = nil
        defer { isWorking = false }
        do {
            guard let service else { throw SkillSetServiceError.repositoryNotFound }
            let plan: StoredDeploymentPlan?
            do {
                plan = try service.makeHarnessPlan(projectID: projectUUID, agent: host.rawValue, selection: updatedSelection,
                                                   installMethod: skillInstallMethod, allowRelatedHarnessUpdates: true)
            } catch let error as DeploymentError where error == .noChanges {
                plan = nil
            }
            if let plan {
                let approved = try planStore.approve(id: plan.id, digest: plan.plan.digest)
                _ = try service.apply(planID: approved.id, digest: approved.plan.digest)
            }
            try reloadProjects(preferredID: projectUUID)
            setProjectPlanNotice(nil, for: project.id)
            projectSaveMessage = L10n.tr("已保存：\(host.displayName) · \(name)")
            report("已保存：\(host.displayName) · \(name)")
            return true
        } catch {
            var restored = project
            restored.harnessSelections[host.rawValue] = previousSelection
            restored.selectEditingAgent(restored.editingAgent)
            persistDraft(for: restored)
            var notice = ProjectPlanNotice(message: UserFacingText.error(error), tone: .error)
            if case let DeploymentError.symlinkDetected(path) = error {
                notice.relatedPath = path
                let projectRoot = URL(fileURLWithPath: project.path)
                if path == projectRoot.appendingPathComponent(".claude/skills").path,
                   URL(fileURLWithPath: path).resolvingSymlinksInPath().path
                    == projectRoot.appendingPathComponent(".agents/skills").resolvingSymlinksInPath().path {
                    notice = ProjectPlanNotice(message: "Claude Code 和 Codex 共用技能文件夹，暂时无法分别保存。请改用独立文件夹。",
                        tone: .error, relatedPath: path)
                }
            }
            setProjectPlanNotice(notice, for: project.id)
            reportKey(UserFacingText.error(error))
            return false
        }
    }

    @discardableResult
    func saveProjectInstruction(_ template: TemplateRecord, enabled: Bool, host: MCPHost) async -> Bool {
        await saveProjectInstruction(template.id, title: UserFacingText.templateTitle(template), enabled: enabled, host: host)
    }

    @discardableResult
    func saveProjectInstruction(_ id: String, title: String, enabled: Bool, host: MCPHost) async -> Bool {
        guard let project = selectedProject, let projectUUID = UUID(uuidString: project.id), !isWorking else { return false }
        let previousSelection = project.harnessSelections[host.rawValue] ?? ProjectHarnessSelection()
        var updatedSelection = previousSelection
        updatedSelection.instructionIDs.removeAll { $0 == id }
        if enabled { updatedSelection.instructionIDs.append(id); updatedSelection.instructionIDs.sort() }
        var proposed = project
        proposed.harnessSelections[host.rawValue] = updatedSelection
        proposed.selectEditingAgent(proposed.editingAgent)
        persistDraft(for: proposed)
        isWorking = true
        projectSaveMessage = nil
        defer { isWorking = false }
        do {
            guard let service else { throw SkillSetServiceError.repositoryNotFound }
            let plan: StoredDeploymentPlan?
            do {
                plan = try service.makeHarnessPlan(projectID: projectUUID, agent: host.rawValue, selection: updatedSelection,
                                                   installMethod: skillInstallMethod, allowRelatedHarnessUpdates: true)
            } catch let error as DeploymentError where error == .noChanges {
                plan = nil
            }
            if let plan {
                let approved = try planStore.approve(id: plan.id, digest: plan.plan.digest)
                _ = try service.apply(planID: approved.id, digest: approved.plan.digest)
            }
            try reloadProjects(preferredID: projectUUID)
            setProjectPlanNotice(nil, for: project.id)
            projectSaveMessage = L10n.tr("已保存：\(host.displayName) · \(title)")
            report("已保存：\(host.displayName) · \(title)")
            return true
        } catch {
            var restored = project
            restored.harnessSelections[host.rawValue] = previousSelection
            restored.selectEditingAgent(restored.editingAgent)
            persistDraft(for: restored)
            let notice = ProjectPlanNotice(message: UserFacingText.error(error), tone: .error)
            setProjectPlanNotice(notice, for: project.id)
            reportKey(UserFacingText.error(error))
            return false
        }
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
            presetDrafts[preset.id] = nil
            selectedPresetID = snapshot.presets.first?.id ?? ""
            service = try? SkillSetService(paths: runtimePaths, globalLocations: globalConfiguration.locations)
            report("预设已删除；已载入的项目草稿保持不变。")
        } catch let error as PresetStoreError {
            presetError = error.errorDescription.map { LocalizedText(stringLiteral: $0) }
        } catch { presetError = LocalizedText(stringLiteral: UserFacingText.error(error)) }
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
        let reasons = validation.blockingReasons(origins: sourceOrigins)
        guard reasons.isEmpty else {
            presetError = LocalizedText.joining(reasons)
            return false
        }
        do {
            let presets = try presetStore.save(preset, initial: baseSnapshot.presets)
            snapshot = snapshot.replacingPresets(presets)
            selectedPresetID = preset.id
            presetDrafts[preset.id] = nil
            report("预设已保存；可随时用于项目草稿。")
            return true
        } catch let error as PresetStoreError {
            presetError = error.errorDescription.map { LocalizedText(stringLiteral: $0) }
            return false
        } catch {
            presetError = LocalizedText(stringLiteral: UserFacingText.error(error))
            return false
        }
    }

    func presetPlugins(for projectID: String) -> [PluginInventoryRecord] {
        guard let service else { return plugins }
        return (try? service.plugins(projectID: UUID(uuidString: projectID)).records) ?? []
    }

    func preparePresetPlugin(_ reference: PresetPluginReference, acknowledge: Bool) {
        guard let service else { report("应用尚未准备好，请重新打开栖集后再预览插件变更。"); return }
        preparedPlan = nil
        do {
            guard let plugin = presetPlugins(for: selectedProjectID).first(where: {
                $0.host == reference.host && $0.pluginID == reference.pluginID && $0.manifestDigest == reference.manifestDigest
            }) else { report("插件「\(reference.name)」的这个版本不可用，请重新扫描并更新预设。"); return }
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
        applyPresets([preset], into: projectID)
    }

    /// 把预设并入项目草稿。多个预设可以同时生效，重叠内容只保留一份。
    @discardableResult
    func applyPresets(_ presets: [PresetRecord], into projectID: String? = nil) -> Bool {
        updateProjectPresets(presets, into: projectID, mode: .merge)
    }

    /// 以选中集合为准更新项目草稿：未选中的预设按差集取消。
    @discardableResult
    func selectPresets(_ presets: [PresetRecord], into projectID: String? = nil) -> Bool {
        updateProjectPresets(presets, into: projectID, mode: .select)
    }

    /// 取消单个预设。只回收它独占的内容，其他预设和手动选择保持不变。
    @discardableResult
    func cancelPreset(_ presetID: String, into projectID: String? = nil) -> Bool {
        let targetID = projectID ?? selectedProjectID
        guard let index = projects.firstIndex(where: { $0.id == targetID }),
              let id = UUID(uuidString: targetID) else {
            report("请先添加并选择一个项目")
            return false
        }
        let project = projects[index]
        let host = project.editingAgent
        let state = presetDraftState(for: project)
        guard state.applications.contains(where: { $0.presetID == presetID && $0.host == host }) else {
            report("这个预设没有用于当前项目")
            return false
        }
        let merged = PresetDraftMerge.removing(presetIDs: [presetID], host: host, from: state)
        return savePresetState(merged, project: project, projectID: id,
                               message: "已取消这个预设；其他预设和手动选择的内容保持不变")
    }

    private func updateProjectPresets(_ presets: [PresetRecord], into projectID: String?, mode: PresetDraftPreview.Mode) -> Bool {
        let targetID = projectID ?? selectedProjectID
        guard let index = projects.firstIndex(where: { $0.id == targetID }),
              let id = UUID(uuidString: targetID) else {
            report("请先添加并选择一个项目")
            return false
        }
        let project = projects[index]
        let preview = PresetDraftPreview(presets: presets, project: project, snapshot: snapshot,
                                         availablePlugins: presetPlugins(for: targetID), mode: mode)
        let reasons = preview.blockingReasons(origins: sourceOrigins)
        guard reasons.isEmpty else {
            report(LocalizedText.joining(reasons))
            return false
        }
        return savePresetState(preview.mergedState, project: project, projectID: id,
                               message: presetLoadMessage(presets))
    }

    private func presetLoadMessage(_ presets: [PresetRecord]) -> String {
        let names = presets.map { $0.status == "local" ? $0.name : L10n.text($0.name) }
        if names.count == 1, let name = names.first { return "已载入「\(name)」草稿，尚未写入项目" }
        return "已载入 \(names.count) 个预设的草稿，尚未写入项目"
    }

    private func presetDraftState(for project: ProjectRecord) -> PresetDraftState {
        PresetDraftState(selections: project.harnessSelections, plugins: project.draftPlugins,
                         mcpServers: project.draftMCPServers, applications: project.presetApplications)
    }

    /// 写入合并后的草稿状态，并刷新项目摘要。
    private func savePresetState(_ state: PresetDraftState, project: ProjectRecord, projectID: UUID, message: String) -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return false }
        var proposed = project
        proposed.harnessSelections = state.selections
        proposed.draftPlugins = state.plugins
        proposed.draftMCPServers = state.mcpServers
        proposed.presetApplications = state.applications
        // 技能与片段按当前宿主保存，切换宿主不能改写另一个工具的选择。
        proposed.selectEditingAgent(proposed.editingAgent)
        proposed.updateEditingSelection()
        do {
            _ = try draftStore.save(
                projectID: projectID, skillIDs: proposed.allDraftSkillIDs,
                instructionIDs: proposed.fragments, agents: canonicalAgentIDs(proposed.agents),
                plugins: proposed.draftPlugins, mcpServers: proposed.draftMCPServers,
                presetApplications: proposed.presetApplications,
                harnessSelections: proposed.harnessSelections
            )
            projects[index] = proposed
            projects[index].pendingChanges = pendingChangeCount(for: projects[index])
            setProjectPlanNotice(nil, for: project.id)
            selectedProjectID = project.id
            section = .projects
            reportKey(message)
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
            report("技能安装计划已生成，请审阅并批准。")
        } catch { libraryError = UserFacingText.error(error) }
    }

    func prepareDeploymentPlan(host: MCPHost? = nil) {
        guard let project = selectedProject, let id = UUID(uuidString: project.id) else {
            report("请先添加并选择一个项目")
            return
        }
        setProjectPlanNotice(nil, for: project.id)
        guard service != nil else {
            let message = L10n.tr("找不到技能库目录，请检查技能库位置后重新打开栖集。")
            setProjectPlanNotice(ProjectPlanNotice(message: message, tone: .error), for: project.id)
            reportKey("找不到技能库目录，请检查技能库位置后重新打开栖集。")
            return
        }
        let agent = host?.rawValue ?? project.editingAgent
        let knownFragments = Set(snapshot.templates.map(\.id))
        guard Set(project.harnessSelections[agent]?.instructionIDs ?? []).isSubset(of: knownFragments) else {
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
                report("应用尚未准备好，请重新打开栖集后再预览变更。")
                return
            }
            preparedPlan = try service.makeHarnessPlan(
                projectID: id,
                agent: agent,
                selection: project.harnessSelections[agent],
                installMethod: skillInstallMethod,
                allowRelatedHarnessUpdates: true
            )
            planPresented = true
            report("变更计划已生成，请审阅后保存。")
        } catch let error as DeploymentError where error == .noChanges {
            preparedPlan = nil
            planPresented = false
            let message = L10n.tr("草稿与项目现状一致，没有需要写入的变更。")
            setProjectPlanNotice(ProjectPlanNotice(message: message, tone: .info), for: project.id)
            reportKey("草稿与项目现状一致，没有需要写入的变更。")
        } catch {
            preparedPlan = nil
            planPresented = false
            var notice = ProjectPlanNotice(message: UserFacingText.error(error), tone: .error)
            if case let DeploymentError.symlinkDetected(path) = error {
                notice.relatedPath = path
                let projectRoot = URL(fileURLWithPath: project.path)
                if path == projectRoot.appendingPathComponent(".claude/skills").path,
                   URL(fileURLWithPath: path).resolvingSymlinksInPath().path
                    == projectRoot.appendingPathComponent(".agents/skills").resolvingSymlinksInPath().path {
                    notice = ProjectPlanNotice(message: "Claude Code 和 Codex 共用技能文件夹，暂时无法分别保存。请改用独立文件夹。",
                        tone: .error, relatedPath: path)
                }
            }
            setProjectPlanNotice(notice, for: project.id)
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
                if let raw = applied.plan.metadata?["globalHost"], let host = SkillConfigurationTarget(rawValue: raw), host != globalConfiguration.host {
                    globalConfiguration.selectHost(host)
                }
                globalConfiguration.didApply()
            }
            let historyTitle: String
            if planType == "plugin-lifecycle" {
                let host = MCPHost(rawValue: applied.plan.metadata?["pluginHost"] ?? "")?.displayName ?? "未识别工具"
                let action = UserFacingText.changeAction(applied.plan.metadata?["pluginAction"] ?? "")
                let pluginName = pluginDisplayTitle(applied.plan.metadata?["pluginID"])
                historyTitle = "\(host) · \(action) \(pluginName)"
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
        importedSkillIDs[ImportedOriginKey(
            url: preview.canonicalURL, commit: preview.resolvedCommit,
            path: candidate.path, contentHash: candidate.contentHash
        )]
    }

    func sourceListTitle(_ preview: SourcePreviewRecord) -> String {
        if let title = sourceListTitles[preview.id] { return title }
        let title = SkillSourceLabel.repository(preview.canonicalURL)
        sourceListTitles[preview.id] = title
        return title
    }

    func sourceFolders(for preview: SourcePreviewRecord) -> [(String, Int)] {
        prepareSourceDetail(preview)
        return cachedSourceFolders
    }

    func sourceCandidates(for preview: SourcePreviewRecord) -> [SourceSkillCandidate] {
        prepareSourceDetail(preview)
        return cachedSourceCandidates
    }

    /// 文件夹分组和路径排序只跟当前预览绑定，避免详情每次刷新都重排整份候选列表。
    private func prepareSourceDetail(_ preview: SourcePreviewRecord) {
        let key = SourceDetailKey(id: preview.id, createdAt: preview.createdAt, commit: preview.resolvedCommit, candidateCount: preview.candidates.count)
        guard sourceDetailKey != key else { return }
        var counts: [String: Int] = [:]
        for candidate in preview.candidates {
            let folder = (candidate.path as NSString).deletingLastPathComponent
            let name = folder.isEmpty ? "." : folder
            counts[name, default: 0] += 1
        }
        cachedSourceFolders = counts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        cachedSourceCandidates = preview.candidates.sorted { $0.path < $1.path }
        sourceDetailKey = key
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

    /// 批量加入技能库。整批占用一次 isWorking；单项失败不影响同批其他项。
    func importSourceSkills(
        previewID: UUID,
        items: [SourceSkillBatchItem],
        mode: SkillInstallMethod,
        category: String
    ) async -> [SourceSkillBatchItemResult]? {
        guard !isWorking, !items.isEmpty else { return nil }
        isWorking = true
        sourceImportError = nil
        defer { isWorking = false }
        let paths = runtimePaths
        let request = SourceSkillBatchRequest(previewID: previewID, items: items, mode: mode, category: category)
        do {
            let results = try await Task.detached(priority: .userInitiated) { () -> [SourceSkillBatchItemResult] in
                let service = try SkillSetService(paths: paths)
                return service.importSourceSkills(request)
            }.value
            try reloadLibrary()
            let imported = results.filter { if case .imported = $0.status { return true } else { return false } }.count
            let remaining = results.count - imported
            if remaining > 0 {
                report("已加入技能库 \(imported) 个技能，\(remaining) 个未加入；可到项目页选择并预览变更")
            } else {
                report("已加入技能库 \(imported) 个技能；可到项目页选择并预览变更")
            }
            return results
        } catch {
            sourceImportError = UserFacingText.error(error)
            return nil
        }
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
            report("已将 \(entry.slug) 加入技能库，请到项目中选择并预览变更。")
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
            skillsShError = L10n.tr("技能库中有多个技能匹配这项结果，请到技能库核对后再移除。")
            return false
        }
        skillsShError = nil
        let removed = removeSkills(matches)
        guard !removed.isEmpty, skillRemovalError == nil else {
            skillsShError = skillRemovalError ?? L10n.tr("未能从技能库移除这个技能，请重新读取后再试。")
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
    var installedSkillRemovalError: String?

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
            report("已加入技能库；可在扫描列表中删除原安装，再由栖集统一配置。")
            return true
        } catch {
            installedSkillImportError = UserFacingText.error(error)
            reportKey(UserFacingText.error(error))
            return false
        }
    }

    func removeInstalledSkill(_ item: InstalledSkillObservation) async -> Bool {
        guard !isWorking, item.contentHash != nil else { return false }
        isWorking = true
        defer { isWorking = false }
        installedSkillRemovalError = nil
        let paths = runtimePaths
        let locations = globalConfiguration.locations
        do {
            try await Task.detached(priority: .userInitiated) {
                try SkillSetService(paths: paths, globalLocations: locations)
                    .removeInstalledSkill(item)
            }.value
            try reloadLibrary()
            refreshSourcePreviews()
            report("已删除原安装；技能库收录副本保留")
            return true
        } catch {
            installedSkillRemovalError = UserFacingText.error(error)
            reportKey(UserFacingText.error(error))
            return false
        }
    }

    func removeInstalledSkills(_ items: [InstalledSkillObservation]) async -> Bool {
        guard !isWorking, !items.isEmpty else { return false }
        isWorking = true
        defer { isWorking = false }
        installedSkillRemovalError = nil
        let paths = runtimePaths
        let locations = globalConfiguration.locations
        do {
            try await Task.detached(priority: .userInitiated) {
                try SkillSetService(paths: paths, globalLocations: locations)
                    .removeInstalledSkills(items)
            }.value
            try reloadLibrary()
            refreshSourcePreviews()
            report("已批量删除 \(items.count) 个原安装；技能库收录副本保留")
            return true
        } catch {
            installedSkillRemovalError = UserFacingText.error(error)
            reportKey(UserFacingText.error(error))
            return false
        }
    }

    func previewSource(urlString: String, ref: String? = nil, replacing replacedID: UUID? = nil) async -> Bool {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            report("请填写仓库链接或本地目录。")
            return false
        }
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        report("正在读取来源并扫描技能，不会运行脚本。")
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
            applySourcePreviews(try SourcePreviewStore(rootURL: runtimePaths.previewsRoot).list())
        } catch {
            reportKey(UserFacingText.error(error))
        }
    }

    /// 页面打开时在后台重读预览文件。内容没变就不替换数组，避免主线程比对整份候选列表。
    func reloadSourcePreviews() async {
        let root = runtimePaths.previewsRoot
        let records = await Task.detached(priority: .userInitiated) {
            try? SourcePreviewStore(rootURL: root).list()
        }.value
        guard let records else { return }
        applySourcePreviews(records)
    }

    private func applySourcePreviews(_ records: [SourcePreviewRecord]) {
        if sourcePreviewListMatches(sourcePreviews, records) { return }
        sourcePreviews = records
        sourceDetailKey = nil
        sourceListTitles.removeAll(keepingCapacity: true)
        if selectedPreviewID == nil {
            selectedPreviewID = records.first?.id
        }
    }

    private func sourcePreviewListMatches(_ current: [SourcePreviewRecord], _ records: [SourcePreviewRecord]) -> Bool {
        guard current.count == records.count else { return false }
        for (left, right) in zip(current, records) {
            if left.id != right.id || left.createdAt != right.createdAt || left.resolvedCommit != right.resolvedCommit
                || left.candidates.count != right.candidates.count {
                return false
            }
        }
        return true
    }

    func prepareMCPLibraryPlan(host: MCPHost, projectID: UUID?) {
        do {
            guard let service else { throw DeploymentError.invalidPlan }
            preparedPlan = try service.makeMCPLibraryPlan(
                host: host,
                projectID: projectID,
                overwritingNames: mcpLibrary.takeApprovedOverwriteNames(host: host, projectID: projectID)
            )
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
            report("应用尚未准备好，请重新打开栖集后再预览 MCP 变更。")
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
            report("MCP 配置计划已生成，请审阅并批准。")
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
            report("应用尚未准备好，请重新打开栖集后再预览插件变更。")
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
                    operationsRoot: runtimePaths.operationsRoot, versionsRoot: runtimePaths.versionsRoot,
                    libraryRoot: runtimePaths.libraryDirectoryURL, sourcesRoot: runtimePaths.sourcesRoot
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
            if let loaded = draft {
                let availableSkills = Set(snapshot.catalog.entries.map(\.id))
                let availableInstructions = Set(snapshot.templates.map(\.id))
                let repairedSelections = loaded.harnessSelections?.mapValues {
                    ProjectHarnessSelection(
                        skillIDs: $0.skillIDs.filter(availableSkills.contains),
                        instructionIDs: $0.instructionIDs.filter(availableInstructions.contains)
                    )
                }
                let repairedSkills = loaded.skillIDs.filter(availableSkills.contains)
                let repairedInstructions = loaded.instructionIDs.filter(availableInstructions.contains)
                if repairedSkills != loaded.skillIDs || repairedInstructions != loaded.instructionIDs
                    || repairedSelections != loaded.harnessSelections {
                    // 删除技能库条目或片段后，自动清理项目草稿中的悬空引用；已部署文件不动。
                    draft = try draftStore.save(
                        projectID: registration.id,
                        skillIDs: repairedSkills,
                        instructionIDs: repairedInstructions,
                        agents: loaded.agents,
                        plugins: loaded.plugins,
                        mcpServers: loaded.mcpServers,
                        harnessSelections: repairedSelections
                    )
                }
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
                presetApplications: draft?.presetApplications ?? [],
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
                presetApplications: project.presetApplications,
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
            versionsRoot: runtimePaths.versionsRoot,
            libraryRoot: runtimePaths.libraryDirectoryURL,
            sourcesRoot: runtimePaths.sourcesRoot
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
