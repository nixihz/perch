import Foundation

public struct CatalogDocument: Codable, Sendable {
    public let schemaVersion: Int
    public let hashAlgorithm: String
    public let entries: [SkillEntry]
}

public struct CatalogIssue: Codable, Hashable, Sendable {
    public let path: String?
    public let reason: String?
    public let message: String?

    public init(path: String? = nil, reason: String? = nil, message: String? = nil) {
        self.path = path
        self.reason = reason
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            path = nil
            reason = nil
            message = value
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }

    public var summary: String {
        if let message { return message }
        if let path, let reason { return "\(path)：\(reason)" }
        return reason ?? path ?? "未说明的问题"
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case reason
        case message
    }
}

public struct SkillEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let slug: String
    public let declaredName: String
    public let description: String
    public let declaredVersion: String?
    public let metadataReview: String
    public let sourceId: String
    public let path: String
    public let contentHash: String
    public let fileCount: Int
    public let bytes: Int
    public let integrity: String
    public let issues: [CatalogIssue]
    public let licenseReview: String
    public let excludedPaths: [String]

    public var shortHash: String {
        String(contentHash.prefix(10))
    }

    public var isBlocked: Bool {
        integrity == "blocked"
    }
}

public struct SourceDocument: Codable, Sendable {
    public let schemaVersion: Int
    public let capturedOn: String
    public let sources: [SourceRecord]
    public let researchOnly: [ResearchSource]
}

public struct SourceRecord: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: String
    public let title: String
    public let path: String?
    public let origin: String
    public let importedFrom: String?
    public let sourceCommit: String?
    public let sourceDirty: Bool?
    public let snapshotPath: String?
    public let report: String?
    public let licenseReview: String
    public let trust: String
}

public struct ResearchSource: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let url: String
    public let commit: String
    public let imported: Bool
    public let note: String
}

public struct PresetRecord: Codable, Identifiable, Hashable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let name: String
    public let description: String
    public let revision: Int
    public let skills: [String]
    public let instructionFragments: [String]
    public let plugins: [PresetPluginReference]
    public let mcpServers: [MCPConfigurationDraft]
    public let mergePolicy: String
    public let status: String

    public var componentCount: Int { skills.count + instructionFragments.count + plugins.count + mcpServers.count }

    public init(id: String = UUID().uuidString, name: String, description: String = "", revision: Int = 1,
                skills: [String] = [], instructionFragments: [String] = [],
                plugins: [PresetPluginReference] = [], mcpServers: [MCPConfigurationDraft] = [],
                status: String = "local") {
        schemaVersion = 2
        self.id = id
        self.name = name
        self.description = description
        self.revision = revision
        self.skills = skills
        self.instructionFragments = instructionFragments
        self.plugins = plugins
        self.mcpServers = mcpServers
        mergePolicy = "explicit-selection"
        self.status = status
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        revision = try c.decode(Int.self, forKey: .revision)
        skills = try c.decode([String].self, forKey: .skills)
        instructionFragments = try c.decode([String].self, forKey: .instructionFragments)
        plugins = try c.decodeIfPresent([PresetPluginReference].self, forKey: .plugins) ?? []
        mcpServers = try c.decodeIfPresent([MCPConfigurationDraft].self, forKey: .mcpServers) ?? []
        mergePolicy = try c.decode(String.self, forKey: .mergePolicy)
        status = try c.decode(String.self, forKey: .status)
    }
}

public struct TemplateRecord: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let purpose: String
    public let isLocal: Bool

    public init(id: String = UUID().uuidString.lowercased(), title: String, body: String, purpose: String = "", isLocal: Bool = false) {
        self.id = id
        self.title = title
        self.body = body
        self.purpose = purpose
        self.isLocal = isLocal
    }
}

public struct MattSnapshot: Codable, Sendable {
    public let url: String
    public let commit: String
    public let version: String
    public let license: String
    public let capturedOn: String
    public let network: Bool
    public let candidates: [MattCandidate]
    public let excluded: MattExcluded
}

public struct MattCandidate: Codable, Identifiable, Hashable, Sendable {
    public let name: String
    public let category: String
    public let path: String

    public var id: String { path }
}

public struct MattExcluded: Codable, Hashable, Sendable {
    public let misc: Int
    public let inProgress: Int
    public let deprecated: Int

    enum CodingKeys: String, CodingKey {
        case misc
        case inProgress = "in-progress"
        case deprecated
    }
}

public struct MCPServerRecord: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let host: String
    public let transport: String
    public let scope: String
    public let command: String
    public let args: [String]
    public let envKeys: [String]
    public let state: String
    public let note: String

    public init(id: String, name: String, host: String, transport: String, scope: String, command: String, args: [String], envKeys: [String], state: String, note: String) {
        self.id = id
        self.name = name
        self.host = host
        self.transport = transport
        self.scope = scope
        self.command = command
        self.args = args
        self.envKeys = envKeys
        self.state = state
        self.note = note
    }

    public static let demo: [MCPServerRecord] = [
        MCPServerRecord(
            id: "skillset-local",
            name: "Skill Set",
            host: "本应用",
            transport: "stdio",
            scope: "应用内",
            command: "skillset",
            args: ["mcp", "serve", "--transport", "stdio"],
            envKeys: [],
            state: "设计中",
            note: "未来提供项目、skills、plan 与审计查询；写入仍需可信 UI 批准。"
        ),
        MCPServerRecord(
            id: "filesystem-demo",
            name: "Filesystem（示例）",
            host: "Claude Code",
            transport: "stdio",
            scope: "项目",
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/project"],
            envKeys: [],
            state: "未安装",
            note: "演示数据，不扫描也不启动本机进程。路径需要用户逐项确认。"
        ),
        MCPServerRecord(
            id: "remote-demo",
            name: "Research API（示例）",
            host: "Codex",
            transport: "streamable-http",
            scope: "用户",
            command: "",
            args: [],
            envKeys: ["MCP_BEARER_TOKEN"],
            state: "仅记录",
            note: "首版不替用户登录远端 HTTP MCP；只保存变量名和风险提示。"
        )
    ]
}

public struct PluginRecord: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let host: String
    public let source: String
    public let revision: String
    public let version: String
    public let components: [String]
    public let dependencySummary: String
    public let risk: String
    public let state: String

    public init(
        id: String,
        name: String,
        host: String,
        source: String,
        revision: String,
        version: String,
        components: [String],
        dependencySummary: String,
        risk: String,
        state: String
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.source = source
        self.revision = revision
        self.version = version
        self.components = components
        self.dependencySummary = dependencySummary
        self.risk = risk
        self.state = state
    }

    public static let demo: [PluginRecord] = [
        PluginRecord(
            id: "claude-ui-toolkit",
            name: "UI Toolkit（示例）",
            host: "Claude Code",
            source: "本地 fixture",
            revision: "无真实 revision",
            version: "0.1.0-demo",
            components: ["skills", "hooks", "MCP"],
            dependencySummary: "无依赖（演示）",
            risk: "含 hook",
            state: "未安装"
        ),
        PluginRecord(
            id: "codex-marketplace-demo",
            name: "Codex Marketplace（示例）",
            host: "Codex",
            source: "marketplace fixture",
            revision: "未知",
            version: "未知",
            components: ["skills"],
            dependencySummary: "Codex manifest schema 待核验",
            risk: "宿主能力未知",
            state: "仅记录"
        ),
        PluginRecord(
            id: "mcp-bundle-demo",
            name: "Research Bundle（示例）",
            host: "Claude Code",
            source: "archive fixture",
            revision: "未锁定",
            version: "0.3.0-demo",
            components: ["MCP", "commands"],
            dependencySummary: "1 个范围依赖（演示）",
            risk: "命令来源需人工审核",
            state: "阻塞"
        )
    ]
}

public struct ProjectRecord: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public var adapter: String
    public let inherited: String
    public var draftSkillIDs: Set<String>
    public var appliedSkillIDs: Set<String>
    public var agents: Set<String>
    public var fragments: [String]
    public var editingAgent: String
    public var harnessSelections: [String: ProjectHarnessSelection]
    public var draftPlugins: [PresetPluginReference]
    public var draftMCPServers: [MCPConfigurationDraft]
    public var pendingChanges: Int
    public var lockStatus: String

    public init(
        id: String,
        name: String,
        path: String,
        adapter: String,
        inherited: String,
        draftSkillIDs: Set<String>,
        appliedSkillIDs: Set<String>,
        agents: Set<String>,
        fragments: [String],
        pendingChanges: Int,
        lockStatus: String = "absent",
        draftPlugins: [PresetPluginReference] = [],
        draftMCPServers: [MCPConfigurationDraft] = [],
        editingAgent: String = "codex",
        harnessSelections: [String: ProjectHarnessSelection]? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.adapter = adapter
        self.inherited = inherited
        self.draftSkillIDs = draftSkillIDs
        self.appliedSkillIDs = appliedSkillIDs
        self.agents = agents
        self.fragments = fragments
        self.editingAgent = editingAgent
        self.harnessSelections = harnessSelections ?? Dictionary(uniqueKeysWithValues: agents.map {
            let key = $0 == "Codex" ? "codex" : ($0 == "Claude Code" ? "claude-code" : $0)
            return (key, ProjectHarnessSelection(skillIDs: Array(draftSkillIDs), instructionIDs: fragments))
        })
        self.draftPlugins = draftPlugins
        self.draftMCPServers = draftMCPServers
        self.pendingChanges = pendingChanges
        self.lockStatus = lockStatus
    }

    public var editingAgentName: String { editingAgent == "claude-code" ? "Claude Code" : "Codex" }

    public var allDraftSkillIDs: Set<String> { Set(harnessSelections.values.flatMap(\.skillIDs)) }

    public mutating func selectEditingAgent(_ agent: String) {
        editingAgent = agent
        let selection = harnessSelections[agent] ?? ProjectHarnessSelection()
        draftSkillIDs = Set(selection.skillIDs)
        fragments = selection.instructionIDs
    }

    public mutating func updateEditingSelection() {
        harnessSelections[editingAgent] = ProjectHarnessSelection(skillIDs: Array(draftSkillIDs), instructionIDs: fragments)
        agents.insert(editingAgentName)
        adapter = agents.sorted().joined(separator: " · ")
    }

    public static let demo: [ProjectRecord] = [
        ProjectRecord(
            id: "skill-set",
            name: "skill-set",
            path: "/opt/case/iamx/skill-set",
            adapter: "Codex",
            inherited: "~/.agents/skills · 11 条全局入口",
            draftSkillIDs: [
                "workspace/brian-working-style",
                "workspace/project-guide",
                "workspace/stc"
            ],
            appliedSkillIDs: [
                "workspace/brian-working-style",
                "workspace/project-guide"
            ],
            agents: ["Codex", "Claude Code"],
            fragments: ["base-zh", "engineering"],
            pendingChanges: 2,
            lockStatus: "absent"
        ),
        ProjectRecord(
            id: "ai-trading-bot",
            name: "ai-trading-bot",
            path: "/opt/case/brian/ai-trading-bot",
            adapter: "Codex",
            inherited: "无已知项目覆盖",
            draftSkillIDs: ["local-brian/ai-trading-bot"],
            appliedSkillIDs: ["local-brian/ai-trading-bot"],
            agents: ["Codex"],
            fragments: ["base-zh"],
            pendingChanges: 0,
            lockStatus: "valid"
        ),
        ProjectRecord(
            id: "commerce",
            name: "commerce",
            path: "/opt/case/brian/commerce",
            adapter: "Claude Code",
            inherited: "父目录 CLAUDE.md · 待观察",
            draftSkillIDs: ["workspace/stc", "workspace/project-guide"],
            appliedSkillIDs: ["workspace/stc"],
            agents: ["Claude Code"],
            fragments: ["base-zh", "engineering"],
            pendingChanges: 1,
            lockStatus: "stale"
        )
    ]
}

public struct AppSnapshot: Sendable {
    public let catalog: CatalogDocument
    public let sources: SourceDocument
    public let presets: [PresetRecord]
    public let templates: [TemplateRecord]
    public let matt: MattSnapshot

    public static func load(repositoryRoot: URL? = nil) -> AppSnapshot {
        let decoder = JSONDecoder()
        let catalog = decodeRepository(
            repositoryRoot?.appendingPathComponent("registry/catalog.json"),
            as: CatalogDocument.self,
            decoder: decoder
        ) ?? decode("catalog.json", as: CatalogDocument.self, decoder: decoder)
        let sources = decodeRepository(
            repositoryRoot?.appendingPathComponent("registry/sources.json"),
            as: SourceDocument.self,
            decoder: decoder
        ) ?? decode("sources.json", as: SourceDocument.self, decoder: decoder)
        let matt = decode("matt.json", as: MattSnapshot.self, decoder: decoder)
        let presets = ["personal-base", "frontend-workbench", "research-first"].compactMap {
            decodeRepository(
                repositoryRoot?.appendingPathComponent("presets/\($0).json"),
                as: PresetRecord.self,
                decoder: decoder
            ) ?? decode("\($0).json", as: PresetRecord.self, decoder: decoder)
        }
        let templateData: [(String, String, String)] = [
            ("base-zh", "中文协作", "把协作约定写入项目的规则文件。"),
            ("engineering", "工程质量", "把验证、边界和测试约束固定下来。"),
            ("ui-craft", "界面交付", "提醒 UI 任务先看 DESIGN.md 并保留证据。")
        ]
        let templates: [TemplateRecord] = templateData.compactMap { item in
            let (id, title, purpose) = item
            let repositoryText = repositoryRoot.flatMap {
                try? String(contentsOf: $0.appendingPathComponent("templates/agents/\(id).md"), encoding: .utf8)
            }
            guard let body = repositoryText ?? resourceText("\(id).md") else { return nil }
            return TemplateRecord(id: id, title: title, body: body, purpose: purpose)
        }
        return AppSnapshot(
            catalog: catalog ?? CatalogDocument(schemaVersion: 1, hashAlgorithm: "", entries: []),
            sources: sources ?? SourceDocument(schemaVersion: 1, capturedOn: "", sources: [], researchOnly: []),
            presets: presets,
            templates: templates,
            matt: matt ?? MattSnapshot(url: "", commit: "", version: "", license: "", capturedOn: "", network: false, candidates: [], excluded: MattExcluded(misc: 0, inProgress: 0, deprecated: 0))
        )
    }

    public func withoutBundledSkills() -> AppSnapshot {
        AppSnapshot(
            catalog: CatalogDocument(schemaVersion: 1, hashAlgorithm: "sha256:path-content-executable:v1", entries: []),
            sources: SourceDocument(schemaVersion: 1, capturedOn: "", sources: [], researchOnly: []),
            presets: presets, templates: templates, matt: matt
        )
    }

    public func replacingPresets(_ presets: [PresetRecord]) -> AppSnapshot {
        AppSnapshot(catalog: catalog, sources: sources, presets: presets, templates: templates, matt: matt)
    }

    public func replacingTemplates(_ templates: [TemplateRecord]) -> AppSnapshot {
        AppSnapshot(catalog: catalog, sources: sources, presets: presets, templates: templates, matt: matt)
    }

    public func replacingCatalog(_ catalog: CatalogDocument) -> AppSnapshot {
        AppSnapshot(catalog: catalog, sources: sources, presets: presets, templates: templates, matt: matt)
    }

    private static func decode<T: Decodable>(_ name: String, as type: T.Type, decoder: JSONDecoder) -> T? {
        guard let data = resourceURL(name).flatMap({ try? Data(contentsOf: $0) }) else {
            return nil
        }
        return try? decoder.decode(type, from: data)
    }

    private static func decodeRepository<T: Decodable>(_ url: URL?, as type: T.Type, decoder: JSONDecoder) -> T? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private static func resourceText(_ name: String) -> String? {
        guard let url = resourceURL(name) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static func resourceURL(_ name: String) -> URL? {
        let path = name as NSString
        return Bundle.module.url(
            forResource: path.deletingPathExtension,
            withExtension: path.pathExtension.isEmpty ? nil : path.pathExtension
        )
    }
}

public struct MCPConfigDraft: Hashable, Sendable {
    public var name: String
    public var transport: String
    public var command: String
    public var args: [String]
    public var envKeys: [String]
    public var scope: String

    public init(name: String = "", transport: String = "stdio", command: String = "", args: [String] = [], envKeys: [String] = [], scope: String = "项目") {
        self.name = name
        self.transport = transport
        self.command = command
        self.args = args
        self.envKeys = envKeys
        self.scope = scope
    }

    public func validationIssues() -> [String] {
        var issues: [String] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("服务器名称不能为空。")
        }
        if transport == "stdio" && command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("stdio 服务器需要 command。")
        }
        if transport != "stdio" && command.isEmpty && args.isEmpty {
            issues.append("HTTP 配置需要 URL 或宿主可识别的连接参数。")
        }
        if envKeys.contains(where: { $0.contains("=") || $0.contains(" ") }) {
            issues.append("环境变量只能保存名称，不能包含值或空格。")
        }
        if command.contains("://") || args.contains(where: { $0.contains("://") && $0.contains("://") && $0.contains("@") }) {
            issues.append("配置中疑似包含带凭据的 URL，管理器不会接收。")
        }
        return issues
    }
}

public func matchingSkills(_ entries: [SkillEntry], query: String, sourceID: String? = nil, sourceOrigins: [String: SourceSkillOrigin] = [:]) -> [SkillEntry] {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    return entries.filter { entry in
        let searchable = "\(entry.id) \(entry.slug) \(entry.path) \(entry.description) \(entry.declaredName) \(sourceOrigins[entry.id]?.url ?? "") \(sourceOrigins[entry.id]?.path ?? "")".localizedLowercase
        return (sourceID == nil || entry.sourceId == sourceID) && (normalized.isEmpty || searchable.contains(normalized))
    }
}
