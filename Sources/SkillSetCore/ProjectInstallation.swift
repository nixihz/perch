import Foundation

public enum ProjectInstallationError: Error, LocalizedError, SkillSetCodedError {
    case invalidTarget
    case unregisteredProject(String)
    case presetNotFound(String)
    case presetRequiresLocalPlan(String)
    case emptySelection

    public var code: String {
        switch self {
        case .invalidTarget: "INVALID_ARGUMENTS"
        case .unregisteredProject: "PROJECT_NOT_REGISTERED"
        case .presetNotFound: "PRESET_NOT_FOUND"
        case .presetRequiresLocalPlan: "PRESET_REQUIRES_LOCAL_PLAN"
        case .emptySelection: "SELECTION_REQUIRED"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidTarget:
            "请只提供 projectId 或项目绝对路径 projectPath；不使用 MCP 进程的工作目录推断当前项目。"
        case .unregisteredProject(let path):
            "项目尚未登记：\(path)。请在栖集添加该项目，或运行 skillset projects add <项目绝对路径>，再发起安装。"
        case .presetNotFound(let id):
            "找不到预设：\(id)。请先调用 presets_list。"
        case .presetRequiresLocalPlan(let id):
            "预设 \(id) 包含插件或 MCP 连接，请在栖集将完整预设用于项目并分别审阅组件计划；本次没有生成任何安装计划。"
        case .emptySelection:
            "请至少选择一个技能或包含技能、规则的预设。"
        }
    }
}

public extension SkillSetService {
    /// 每次查询读取本机预设，长运行的 MCP 也能看到 UI 保存的组合。
    func presets(query: String = "") throws -> [PresetRecord] {
        let records = try PresetStore(rootURL: paths.applicationSupportRoot).list(merging: snapshot.presets)
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? records : records.filter {
            [$0.id, $0.name, $0.description].joined(separator: " ").localizedCaseInsensitiveContains(query)
        }
    }

    /// 路径只用于匹配已登记项目，不能让 MCP 调用方自行扩展可写根目录。
    func installationProject(projectID: UUID? = nil, projectPath: String? = nil) throws -> ProjectRegistration {
        guard (projectID == nil) != (projectPath == nil) else { throw ProjectInstallationError.invalidTarget }
        let store = ProjectStore(rootURL: paths.applicationSupportRoot)
        if let projectID { return try store.project(id: projectID) }
        guard let projectPath, projectPath.hasPrefix("/") else { throw ProjectInstallationError.invalidTarget }
        let canonical = try store.canonicalProjectURL(URL(fileURLWithPath: projectPath, isDirectory: true))
        guard let project = try store.list().first(where: { $0.canonicalPath == canonical.path }) else {
            throw ProjectInstallationError.unregisteredProject(canonical.path)
        }
        return project
    }

    /// 安装追加到已落盘配置；尚未部署的 UI 草稿不能被安装操作意外启用。
    func makeInstallationPlan(
        projectID: UUID? = nil, projectPath: String? = nil,
        skillIDs: [String] = [], presetID: String? = nil, agents: [String]? = nil
    ) throws -> StoredDeploymentPlan {
        let project = try installationProject(projectID: projectID, projectPath: projectPath)
        let preset: PresetRecord?
        if let presetID {
            guard let found = try presets().first(where: { $0.id == presetID }) else {
                throw ProjectInstallationError.presetNotFound(presetID)
            }
            // 混合预设必须完整审阅，不能只装技能却报告整个预设安装成功。
            guard found.plugins.isEmpty && found.mcpServers.isEmpty else {
                throw ProjectInstallationError.presetRequiresLocalPlan(presetID)
            }
            preset = found
        } else { preset = nil }
        guard !skillIDs.isEmpty || (preset?.componentCount ?? 0) > 0 else {
            throw ProjectInstallationError.emptySelection
        }
        let current = try ProjectLockStore(projectRoot: URL(fileURLWithPath: project.canonicalPath), stateRoot: paths.applicationSupportRoot).loadManifest()
        let selectedAgents = agents ?? current?.agents ?? (project.agents.isEmpty ? ["codex"] : project.agents)
        // 保留已有宿主，安装不等同于取消其他宿主的配置。
        let targets = Array(Set((current?.agents ?? []) + selectedAgents)).sorted()
        return try makePlan(
            projectID: project.id,
            skillIDs: Array(Set((current?.skills ?? []) + skillIDs + (preset?.skills ?? []))).sorted(),
            instructionIDs: Array(Set((current?.instructions ?? []) + (preset?.instructionFragments ?? []))).sorted(),
            agents: targets, ruleBlockID: current?.ruleBlockID ?? "project-rules"
        )
    }
}
