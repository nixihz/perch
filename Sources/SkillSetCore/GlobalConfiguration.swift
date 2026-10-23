import Foundation

public struct GlobalConfigurationLocations: Sendable {
    public let home: URL
    public let codexRoot: URL
    public let claudeRoot: URL
    public let stateRoot: URL

    public init(home: URL, stateRoot: URL, codexRoot: URL? = nil, claudeRoot: URL? = nil) {
        self.home = home.resolvingSymlinksInPath().standardizedFileURL
        self.stateRoot = stateRoot.resolvingSymlinksInPath().standardizedFileURL
        self.codexRoot = (codexRoot ?? self.home.appendingPathComponent(".codex")).resolvingSymlinksInPath().standardizedFileURL
        self.claudeRoot = (claudeRoot ?? self.home.appendingPathComponent(".claude")).resolvingSymlinksInPath().standardizedFileURL
    }

    public static func detect(stateRoot: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
        Self(home: environment["SKILLSET_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser, stateRoot: stateRoot,
             codexRoot: environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) },
             claudeRoot: environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) })
    }

    public func skillsRoot(_ host: MCPHost) -> URL {
        configuredSkillsRoot(host).resolvingSymlinksInPath().standardizedFileURL
    }

    func configuredSkillsRoot(_ host: MCPHost) -> URL {
        host == .codex ? home.appendingPathComponent(".agents/skills") : claudeRoot.appendingPathComponent("skills")
    }

    public func rulesURL(_ host: MCPHost) -> URL {
        (host == .codex ? codexRoot : claudeRoot).appendingPathComponent(host == .codex ? "AGENTS.md" : "CLAUDE.md")
    }

    func stateURL(_ host: MCPHost) -> URL { stateRoot.appendingPathComponent("global/\(host.rawValue).json") }
    func draftURL(_ host: MCPHost) -> URL { stateRoot.appendingPathComponent("global/\(host.rawValue)-draft.json") }

    // 事务根只用于相对路径与 journal；服务还会按宿主精确校验目标白名单。
    func transactionRoot(_ host: MCPHost) -> URL {
        let urls = [skillsRoot(host), rulesURL(host), stateURL(host)]
        var root = urls[0].deletingLastPathComponent()
        while !urls.allSatisfy({ $0.path.hasPrefix(root.path == "/" ? "/" : root.path + "/") }) {
            root.deleteLastPathComponent()
        }
        return root
    }
}

public enum GlobalVerificationReason: String, Sendable {
    case invalidDraft = "全局草稿格式无效或缺少必需字段"
    case invalidState = "全局管理记录格式无效或缺少必需字段"
    case unsupportedSchema = "全局管理记录的数据版本不受支持"
    case hostMismatch = "管理记录中的 AI 工具与当前工具不一致"
    case skillsPathMismatch = "管理记录中的技能目录与当前目录不一致"
    case rulesPathMismatch = "管理记录中的规则文件路径与当前路径不一致"
    case unmanagedPath = "管理记录包含当前工具管理范围以外的路径"
    case missingReceipt = "找不到与当前管理记录内容指纹匹配的已完成操作凭证"
    case invalidRulesEncoding = "规则内容不是有效的 UTF-8 文本"
    case missingStateStep = "撤销操作的日志缺少全局管理记录变更步骤"
    case invalidBackup = "操作备份中的全局管理记录格式无效"
    case invalidRuleMarkers = "规则内容的起止标记无法配对"
}

public enum GlobalConfigurationError: Error, LocalizedError, SkillSetCodedError {
    case corruptState
    case verificationFailed(GlobalVerificationReason, path: String)
    case baselineMissing
    case staleOperation

    public var code: String {
        switch self {
        case .corruptState, .verificationFailed: "GLOBAL_STATE_CORRUPT"
        case .baselineMissing: "GLOBAL_BASELINE_MISSING"
        case .staleOperation: "GLOBAL_OPERATION_STALE"
        }
    }
    public var errorDescription: String? {
        switch self {
        case .corruptState: "全局管理记录损坏或缺少本机操作凭证，请先检查操作历史。"
        case let .verificationFailed(reason, path):
            "全局配置核验失败：\(reason.rawValue)。\(path.isEmpty ? "" : "\n文件：\(path)")\n已停止当前操作，请核对上述内容后重试。"
        case .baselineMissing: "原始备份缺失或已改变，已停止还原。"
        case .staleOperation: "已有后续全局变更，请先撤销后续操作。"
        }
    }
}

public struct GlobalConfigurationDraft: Codable, Hashable, Sendable {
    public var skillIDs: [String]
    public var instructionIDs: [String]
    public var installMethod: SkillInstallMethod?
    public init(skillIDs: [String] = [], instructionIDs: [String] = [], installMethod: SkillInstallMethod? = nil) {
        self.skillIDs = skillIDs
        self.instructionIDs = instructionIDs
        self.installMethod = installMethod
    }
}

struct GlobalManagedResource: Codable, Hashable {
    let hash: String
    let baselineID: UUID?
    let baselineHash: String?
    let originalRules: Data?
    let writtenRules: Data?
}

struct GlobalConfigurationState: Codable {
    var schemaVersion = 1
    var revision = UUID()
    let host: MCPHost
    let skillsPath: String
    let rulesPath: String
    var selection: GlobalConfigurationDraft
    var managed: [String: GlobalManagedResource]
}

public struct GlobalResourceObservation: Identifiable, Sendable {
    public let path: String
    public let managed: Bool
    public let modified: Bool
    public let symbolicLink: Bool
    public var id: String { path }
}

public struct GlobalConfigurationInspection: Sendable {
    public let host: MCPHost
    public let skillsPath: String
    public let rulesPath: String
    public let resources: [GlobalResourceObservation]
    public let selection: GlobalConfigurationDraft
    public let hasManagement: Bool
}

public enum GlobalRestoreMode: String, Sendable {
    case baseline
    case keepFiles
}

public struct GlobalOperationRecord: Identifiable, Sendable {
    public let journal: FileTransactionJournal
    public let action: String
    public let canUndo: Bool
    public var id: UUID { journal.operationID }
}

/// 用户作用域独立保存期望、归属和接管基线，不将 HOME 注册为项目。
public struct GlobalConfigurationManager {
    public let locations: GlobalConfigurationLocations
    let paths: SkillSetRuntimePaths
    let fileManager = FileManager.default
    static let blockID = "global-rules"

    public init(paths: SkillSetRuntimePaths, locations: GlobalConfigurationLocations? = nil) {
        self.paths = paths
        self.locations = locations ?? .detect(stateRoot: paths.applicationSupportRoot)
    }

    /// 引用盘点只需已落盘选择，避免为每个片段重复核验全部全局技能包。
    public func appliedSelection(host: MCPHost) throws -> GlobalConfigurationDraft {
        try loadState(host)?.selection ?? GlobalConfigurationDraft()
    }

    public func inspect(host: MCPHost) throws -> GlobalConfigurationInspection {
        try validateSkillsRoot(host)
        let state = try loadState(host)
        let root = locations.transactionRoot(host)
        let skillsRoot = locations.skillsRoot(host)
        try check(skillsRoot, root: root)
        var resources: [GlobalResourceObservation] = []
        if fileManager.fileExists(atPath: skillsRoot.path) {
            for child in try fileManager.contentsOfDirectory(at: skillsRoot, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) {
                let url = skillsRoot.appendingPathComponent(child.lastPathComponent)
                let link = isLink(url)
                let record = state?.managed[url.path]
                let actual = record == nil ? nil : try hash(url)
                resources.append(GlobalResourceObservation(path: url.path, managed: record != nil,
                    modified: record.map { $0.hash != actual } ?? false, symbolicLink: link))
            }
        }
        // 用户手工删除的受管包仍需显示，以便解释后续计划为何冲突。
        for (path, _) in state?.managed ?? [:] where path != locations.rulesURL(host).path && !resources.contains(where: { $0.path == path }) {
            resources.append(GlobalResourceObservation(path: path, managed: true, modified: true, symbolicLink: false))
        }
        let rules = locations.rulesURL(host)
        try check(rules, root: root)
        if let data = try dataIfPresent(rules) {
            let body = try ruleBody(data, path: rules.path)
            let record = state?.managed[rules.path]
            resources.append(GlobalResourceObservation(path: rules.path, managed: record != nil,
                modified: record.map { $0.hash != body.map { SkillAssetCopier.sha256(Data($0.utf8)) } } ?? false,
                symbolicLink: false))
        } else if state?.managed[rules.path] != nil {
            resources.append(GlobalResourceObservation(path: rules.path, managed: true, modified: true, symbolicLink: false))
        }
        return GlobalConfigurationInspection(host: host, skillsPath: skillsRoot.path, rulesPath: rules.path,
            resources: resources, selection: state?.selection ?? GlobalConfigurationDraft(),
            hasManagement: !(state?.managed.isEmpty ?? true) || !(state?.selection.skillIDs.isEmpty ?? true) || !(state?.selection.instructionIDs.isEmpty ?? true))
    }

    public func draft(host: MCPHost) throws -> GlobalConfigurationDraft {
        let url = locations.draftURL(host)
        try check(url, root: locations.transactionRoot(host))
        guard let data = try dataIfPresent(url) else { return try loadState(host)?.selection ?? GlobalConfigurationDraft() }
        do { return try JSONDecoder().decode(GlobalConfigurationDraft.self, from: data) }
        catch { throw GlobalConfigurationError.verificationFailed(.invalidDraft, path: url.path) }
    }

    public func saveDraft(_ draft: GlobalConfigurationDraft, host: MCPHost) throws {
        let url = locations.draftURL(host)
        try check(url, root: locations.transactionRoot(host))
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(draft).write(to: url, options: .atomic)
    }

    public func history(host: MCPHost) throws -> [GlobalOperationRecord] {
        let currentHash = try hash(locations.stateURL(host))
        let statePath = relative(locations.stateURL(host), root: locations.transactionRoot(host))
        return try journals(host).sorted { $0.createdAt > $1.createdAt }.map { journal in
            GlobalOperationRecord(journal: journal, action: journal.metadata?["globalAction"] ?? "deploy",
                canUndo: journal.state == "applied" && journal.steps.contains { $0.relativePath == statePath && $0.afterHash == currentHash })
        }
    }

    func loadState(_ host: MCPHost) throws -> GlobalConfigurationState? {
        let url = locations.stateURL(host)
        try check(url, root: locations.transactionRoot(host))
        let history = try journals(host)
        if history.contains(where: { ["applying", "failed", "rolling-back"].contains($0.state) }) {
            throw FileTransactionError.journalCorrupt(paths.operationsRoot.path)
        }
        guard let data = try dataIfPresent(url) else { return nil }
        let state: GlobalConfigurationState
        do { state = try JSONDecoder().decode(GlobalConfigurationState.self, from: data) }
        catch { throw GlobalConfigurationError.verificationFailed(.invalidState, path: url.path) }
        let statePath = relative(url, root: locations.transactionRoot(host))
        // 分别报告失败条件，避免把路径变化与缺少凭证都显示成数据损坏。
        func require(_ condition: Bool, _ reason: GlobalVerificationReason) throws {
            guard condition else { throw GlobalConfigurationError.verificationFailed(reason, path: url.path) }
        }
        try require(state.schemaVersion == 1, .unsupportedSchema)
        try require(state.host == host, .hostMismatch)
        try require(state.skillsPath == locations.skillsRoot(host).path, .skillsPathMismatch)
        try require(state.rulesPath == locations.rulesURL(host).path, .rulesPathMismatch)
        try require(state.managed.keys.allSatisfy({ allowedResource(URL(fileURLWithPath: $0), host: host) }), .unmanagedPath)
        try require(history.contains(where: { $0.state == "applied" && $0.steps.contains {
            $0.relativePath == statePath && $0.afterHash == SkillAssetCopier.sha256(data)
        } }), .missingReceipt)
        return state
    }

    func journals(_ host: MCPHost) throws -> [FileTransactionJournal] {
        guard fileManager.fileExists(atPath: paths.operationsRoot.path) else { return [] }
        let executor = FileTransactionExecutor(operationsRoot: paths.operationsRoot)
        return try fileManager.contentsOfDirectory(at: paths.operationsRoot, includingPropertiesForKeys: nil).compactMap { url in
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            // 插件 journal 使用另一文件格式；全局文件 journal 损坏时拒绝静默跳过。
            guard fileManager.fileExists(atPath: url.appendingPathComponent("journal.json").path) else { return nil }
            let journal = try executor.loadJournal(id)
            return journal.metadata?["globalHost"] == host.rawValue
                && journal.projectPath == locations.transactionRoot(host).path ? journal : nil
        }
    }

    func allowedResource(_ url: URL, host: MCPHost) -> Bool {
        url.path == locations.rulesURL(host).path
            || (url.deletingLastPathComponent().path == locations.skillsRoot(host).path
                && url.lastPathComponent.range(of: #"^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$"#, options: .regularExpression) != nil)
    }

    /// 全局事务根可能包含宿主自定义目录；执行前仍只接受这两类资源和本机状态文件。
    public func validate(plan: DeploymentPlan) throws {
        guard let raw = plan.metadata?["globalHost"], let host = MCPHost(rawValue: raw) else {
            throw DeploymentError.invalidPlan
        }
        // 只解析宿主技能根目录；批准后入口改指其他目录时，旧计划不能继续写入。
        let skillsRoot = locations.skillsRoot(host)
        if let expected = plan.metadata?["globalSkillsRoot"] {
            guard expected == skillsRoot.path else {
                throw FileTransactionError.staleFile(locations.configuredSkillsRoot(host).path)
            }
        } else if skillsRoot.path != locations.configuredSkillsRoot(host).path {
            throw FileTransactionError.staleFile(locations.configuredSkillsRoot(host).path)
        }
        try validateSkillsRoot(host)
        guard plan.projectPath == locations.transactionRoot(host).path else { throw DeploymentError.invalidPlan }
        let root = locations.transactionRoot(host)
        guard root.resolvingSymlinksInPath().standardizedFileURL.path == root.path else {
            throw DeploymentError.symlinkDetected(root.path)
        }
        for path in plan.changes.map(\.relativePath) + (plan.observations ?? []).map(\.relativePath) {
            let url = root.appendingPathComponent(path).standardizedFileURL
            guard relative(url, root: root) == path,
                  url == locations.stateURL(host) || allowedResource(url, host: host) else {
                throw DeploymentError.pathOutsideRoot(path)
            }
            try check(url, root: root)
        }
    }

    func validateSkillsRoot(_ host: MCPHost) throws {
        let configured = locations.configuredSkillsRoot(host)
        let resolved = locations.skillsRoot(host)
        var directory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: resolved.path, isDirectory: &directory)
        // 普通目录允许首次创建；软链必须指向现有目录，断链和循环不能成为写入入口。
        guard (!exists || directory.boolValue),
              exists || (configured.path == resolved.path && !isLink(configured)) else {
            throw DeploymentError.pathOutsideRoot(configured.path)
        }
        try check(resolved, root: locations.transactionRoot(host))
    }

    func hash(_ url: URL) throws -> String? {
        if let hash = try ManagedSkillLink.hash(url, versionsRoot: paths.versionsRoot) { return hash }
        // 只在已配置的目录边界内检查，不能把 macOS 的 /var 系统别名误判为用户置换。
        let roots = [locations.home, locations.stateRoot, locations.codexRoot, locations.claudeRoot,
                     locations.skillsRoot(.codex), locations.skillsRoot(.claudeCode)]
        guard let root = roots.first(where: { url.path.hasPrefix($0.path + "/") }) else {
            throw DeploymentError.pathOutsideRoot(url.path)
        }
        try check(url, root: root)
        var directory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &directory) else { return nil }
        guard directory.boolValue else { return try SkillAssetCopier.sha256(fileAt: url) }
        for path in try fileManager.subpathsOfDirectory(atPath: url.path) where isLink(url.appendingPathComponent(path)) {
            throw DeploymentError.symlinkDetected(path)
        }
        return try SkillAssetCopier.analyze(from: url).contentHash
    }

    func check(_ url: URL, root: URL) throws {
        guard url.standardizedFileURL.path == url.path, url.path != root.path,
              root.path == "/" || url.path.hasPrefix(root.path + "/") else { throw DeploymentError.pathOutsideRoot(url.path) }
        var cursor = url
        while cursor.path != root.path {
            if isLink(cursor) {
                guard cursor == url, try ManagedSkillLink.hash(cursor, versionsRoot: paths.versionsRoot) != nil else {
                    throw DeploymentError.symlinkDetected(cursor.path)
                }
            }
            cursor.deleteLastPathComponent()
        }
    }

    func isLink(_ url: URL) -> Bool { (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil }
    func dataIfPresent(_ url: URL) throws -> Data? {
        fileManager.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    }
    func relative(_ url: URL, root: URL) -> String { String(url.path.dropFirst(root.path == "/" ? 1 : root.path.count + 1)) }
    func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    func ruleBody(_ data: Data, path: String = "") throws -> String? {
        guard let text = String(data: data, encoding: .utf8) else { throw GlobalConfigurationError.verificationFailed(.invalidRulesEncoding, path: path) }
        return try GlobalRuleEditing.body(in: text, path: path)
    }
}
