import Foundation

public enum MCPHost: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case claudeCode = "claude-code"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        }
    }
}

public enum MCPConfigurationScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case project
    case user

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .project: "项目"
        case .user: "用户"
        }
    }
}

public enum MCPConfigurationError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedTarget(String)
    case invalidDraft(String)
    case configConflict(String)
    case configCorrupt(String)
    case rootMissing(String)
    case unsafePath(String)
    case notOwned(String)

    public var code: String {
        switch self {
        case .unsupportedTarget: "MCP_CONFIG_TARGET_UNSUPPORTED"
        case .invalidDraft: "MCP_CONFIG_DRAFT_INVALID"
        case .configConflict: "MCP_CONFIG_CONFLICT"
        case .configCorrupt: "MCP_CONFIG_CORRUPT"
        case .rootMissing: "MCP_CONFIG_ROOT_MISSING"
        case .unsafePath: "PATH_OUTSIDE_ROOT"
        case .notOwned: "MCP_CONFIG_NOT_OWNED"
        }
    }

    public var errorDescription: String? {
        switch self {
        case let .unsupportedTarget(target):
            return "不支持的 MCP 配置目标：\(target)"
        case let .invalidDraft(reason):
            return "MCP 配置草稿无效：\(reason)"
        case let .configConflict(name):
            return "已有同名 MCP Server 且不属于管理器，拒绝覆盖：\(name)"
        case let .configCorrupt(path):
            return "MCP 配置无法安全解析：\(path)"
        case let .rootMissing(path):
            return "MCP 配置根目录不存在：\(path)"
        case let .unsafePath(path):
            return "MCP 配置路径不安全：\(path)"
        case let .notOwned(name):
            return "MCP Server 不由当前管理器拥有，不能修改：\(name)"
        }
    }
}

public struct MCPConfigurationTarget: Codable, Hashable, Sendable {
    public let host: MCPHost
    public let scope: MCPConfigurationScope
    public let rootPath: String
    public let relativePath: String

    public init(host: MCPHost, scope: MCPConfigurationScope, rootPath: String, relativePath: String) {
        self.host = host
        self.scope = scope
        self.rootPath = rootPath
        self.relativePath = relativePath
    }

    public var configPath: String {
        URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent(relativePath)
            .standardizedFileURL.path
    }
}

public struct MCPConfigurationDraft: Codable, Hashable, Sendable {
    public var name: String
    public var host: MCPHost
    public var scope: MCPConfigurationScope
    public var transport: String
    public var commandOrURL: String
    public var args: [String]
    public var envKeys: [String]

    public init(
        name: String = "",
        host: MCPHost = .codex,
        scope: MCPConfigurationScope = .project,
        transport: String = "stdio",
        commandOrURL: String = "",
        args: [String] = [],
        envKeys: [String] = []
    ) {
        self.name = name
        self.host = host
        self.scope = scope
        self.transport = transport
        self.commandOrURL = commandOrURL
        self.args = args
        self.envKeys = envKeys
    }

    public func normalized() -> MCPConfigurationDraft {
        MCPConfigurationDraft(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            host: host,
            scope: scope,
            transport: transport,
            commandOrURL: commandOrURL.trimmingCharacters(in: .whitespacesAndNewlines),
            args: args.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            envKeys: Array(Set(envKeys.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty })).sorted()
        )
    }

    public func validationIssues() -> [String] {
        var issues: [String] = []
        let value = normalized()
        if value.name.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"#, options: .regularExpression) == nil {
            issues.append("名称只能包含字母、数字、点、下划线或连字符。")
        }
        if !["stdio", "streamable-http"].contains(value.transport) {
            issues.append("请选择 stdio 或 streamable-http 连接方式。")
        }
        if value.commandOrURL.isEmpty {
            issues.append(value.transport == "stdio" ? "请填写启动命令。" : "请填写服务地址。")
        }
        if value.transport == "stdio" && value.commandOrURL.contains("://") {
            issues.append("请填写本机启动命令，而不是网址。")
        }
        if value.transport == "streamable-http" {
            guard let url = URL(string: value.commandOrURL),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.host != nil else {
                issues.append("请填写以 http:// 或 https:// 开头的服务地址。")
                return issues
            }
            if url.user != nil || url.password != nil {
                issues.append("请移除服务地址中的用户名和密码。")
            }
        }
        for arg in value.args where arg.contains("\n") || arg.contains("\0") {
            issues.append("启动参数中有换行或空字符，请删除后重试。")
            break
        }
        for key in value.envKeys where key.range(
            of: #"^[A-Za-z_][A-Za-z0-9_]{0,127}$"#,
            options: .regularExpression
        ) == nil {
            // 输入可能误含密钥值；拒绝原因不能回显，否则错误日志会成为新的泄露点。
            issues.append("请只填环境变量名称，不要填密钥值；名称使用字母、数字和下划线，且不能以数字开头。")
            break
        }
        return Array(Set(issues)).sorted()
    }
}

public struct MCPObservedServer: Codable, Identifiable, Hashable, Sendable {
    public let host: MCPHost
    public let scope: MCPConfigurationScope
    public let name: String
    public let transport: String
    public let command: String
    public let argumentCount: Int
    public let envKeys: [String]
    public let configPath: String
    public let managed: Bool

    public var id: String {
        "\(host.rawValue):\(scope.rawValue):\(name):\(configPath)"
    }

    public init(
        host: MCPHost,
        scope: MCPConfigurationScope,
        name: String,
        transport: String,
        command: String,
        argumentCount: Int,
        envKeys: [String],
        configPath: String,
        managed: Bool
    ) {
        self.host = host
        self.scope = scope
        self.name = name
        self.transport = transport
        self.command = command
        self.argumentCount = argumentCount
        self.envKeys = envKeys.sorted()
        self.configPath = configPath
        self.managed = managed
    }
}

public struct MCPConfigurationInspection: Codable, Identifiable, Hashable, Sendable {
    public let host: MCPHost
    public let scope: MCPConfigurationScope
    public let configPath: String
    public let exists: Bool
    public let servers: [MCPObservedServer]
    public let issues: [String]

    public var id: String { "\(host.rawValue):\(scope.rawValue):\(configPath)" }

    public init(
        host: MCPHost,
        scope: MCPConfigurationScope,
        configPath: String,
        exists: Bool,
        servers: [MCPObservedServer],
        issues: [String]
    ) {
        self.host = host
        self.scope = scope
        self.configPath = configPath
        self.exists = exists
        self.servers = servers
        self.issues = issues
    }
}

public struct MCPConfigEditResult: Hashable, Sendable {
    public let target: MCPConfigurationTarget
    public let serverName: String
    public let content: Data
    public let beforeHash: String?
    public let afterHash: String
    public let action: String

    public init(
        target: MCPConfigurationTarget,
        serverName: String,
        content: Data,
        beforeHash: String?,
        afterHash: String,
        action: String
    ) {
        self.target = target
        self.serverName = serverName
        self.content = content
        self.beforeHash = beforeHash
        self.afterHash = afterHash
        self.action = action
    }
}

public struct ManagedMCPServerRecord: Codable, Hashable, Sendable {
    public let configPath: String
    public let serverName: String
    public let contentHash: String
    public let updatedAt: Date
}

private struct ManagedMCPServerDocument: Codable {
    let schemaVersion: Int
    var servers: [ManagedMCPServerRecord]
}

public struct ManagedMCPRegistry {
    public let rootURL: URL
    private let fileManager: FileManager
    private let clock: () -> Date

    public init(
        rootURL: URL,
        fileManager: FileManager = .default,
        clock: @escaping () -> Date = Date.init
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.clock = clock
    }

    public var documentURL: URL {
        rootURL.appendingPathComponent("managed-mcp.json")
    }

    public func isManaged(configPath: String, serverName: String) -> Bool {
        (try? load().servers.contains {
            canonicalPath($0.configPath) == canonicalPath(configPath) && $0.serverName == serverName
        }) ?? false
    }

    public func record(configPath: String, serverName: String, contentHash: String) throws {
        var document = try load()
        let record = ManagedMCPServerRecord(
            configPath: canonicalPath(configPath),
            serverName: serverName,
            contentHash: contentHash,
            updatedAt: clock()
        )
        document.servers.removeAll {
            canonicalPath($0.configPath) == record.configPath && $0.serverName == serverName
        }
        document.servers.append(record)
        document.servers.sort {
            ($0.configPath, $0.serverName) < ($1.configPath, $1.serverName)
        }
        try write(document)
    }

    public func forget(configPath: String, serverName: String) throws {
        var document = try load()
        document.servers.removeAll {
            canonicalPath($0.configPath) == canonicalPath(configPath) && $0.serverName == serverName
        }
        try write(document)
    }

    public func recordSelection(configPath: String, names: [String], removed: [String], contentHash: String) throws {
        var document = try load()
        let path = canonicalPath(configPath)
        document.servers.removeAll { canonicalPath($0.configPath) == path && (names + removed).contains($0.serverName) }
        document.servers += names.map { ManagedMCPServerRecord(configPath: path, serverName: $0, contentHash: contentHash, updatedAt: clock()) }
        try write(document)
    }

    private func load() throws -> ManagedMCPServerDocument {
        guard fileManager.fileExists(atPath: documentURL.path) else {
            return ManagedMCPServerDocument(schemaVersion: 1, servers: [])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ManagedMCPServerDocument.self, from: Data(contentsOf: documentURL))
    }

    private func write(_ document: ManagedMCPServerDocument) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(document)
        data.append(0x0A)
        try data.write(to: documentURL, options: .atomic)
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

public struct MCPConfigurationManager {
    public let projectRoot: URL?
    public let environment: [String: String]
    public let homeDirectory: URL

    private let fileManager: FileManager
    private let registry: ManagedMCPRegistry

    public init(
        projectRoot: URL?,
        applicationSupportRoot: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.projectRoot = projectRoot?.resolvingSymlinksInPath().standardizedFileURL
        self.environment = environment
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.fileManager = fileManager
        self.registry = ManagedMCPRegistry(
            rootURL: applicationSupportRoot,
            fileManager: fileManager
        )
    }

    public func targets() -> [MCPConfigurationTarget] {
        let codexRoot: URL
        if let configured = environment["CODEX_HOME"], !configured.isEmpty {
            codexRoot = URL(fileURLWithPath: configured, isDirectory: true)
        } else {
            codexRoot = homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        }
        var targets = [
            MCPConfigurationTarget(
                host: .codex,
                scope: .user,
                rootPath: codexRoot.standardizedFileURL.path,
                relativePath: "config.toml"
            ),
            MCPConfigurationTarget(
                host: .claudeCode,
                scope: .user,
                rootPath: homeDirectory.path,
                relativePath: ".claude.json"
            )
        ]
        if let projectRoot {
            targets.append(MCPConfigurationTarget(
                host: .claudeCode,
                scope: .project,
                rootPath: projectRoot.path,
                relativePath: ".mcp.json"
            ))
        }
        return targets
    }

    public func inspectAll() -> [MCPConfigurationInspection] {
        targets().map(inspect)
    }

    public func inspect(_ target: MCPConfigurationTarget) -> MCPConfigurationInspection {
        let url = URL(fileURLWithPath: target.configPath)
        guard fileManager.fileExists(atPath: url.path) else {
            return MCPConfigurationInspection(
                host: target.host,
                scope: target.scope,
                configPath: target.configPath,
                exists: false,
                servers: [],
                issues: []
            )
        }
        do {
            let data = try Data(contentsOf: url)
            let servers: [MCPObservedServer]
            switch target.host {
            case .codex:
                servers = try parseCodex(
                    String(decoding: data, as: UTF8.self),
                    target: target
                )
            case .claudeCode:
                servers = try parseClaudeJSON(data, target: target)
            }
            return MCPConfigurationInspection(
                host: target.host,
                scope: target.scope,
                configPath: target.configPath,
                exists: true,
                servers: servers,
                issues: servers
                    .filter { !$0.managed && target.scope == .user }
                    .map { "\($0.name)：现有用户级配置；编辑或删除须预览并批准。" }
            )
        } catch {
            return MCPConfigurationInspection(
                host: target.host,
                scope: target.scope,
                configPath: target.configPath,
                exists: true,
                servers: [],
                issues: [error.localizedDescription]
            )
        }
    }

    public func makeEdit(
        target: MCPConfigurationTarget,
        draft rawDraft: MCPConfigurationDraft
    ) throws -> MCPConfigEditResult {
        let draft = rawDraft.normalized()
        let issues = draft.validationIssues()
        guard issues.isEmpty else {
            throw MCPConfigurationError.invalidDraft(issues.joined(separator: "；"))
        }
        guard draft.host == target.host, draft.scope == target.scope else {
            throw MCPConfigurationError.unsupportedTarget("\(draft.host.rawValue)/\(draft.scope.rawValue)")
        }
        let root = URL(fileURLWithPath: target.rootPath, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw MCPConfigurationError.rootMissing(root.path)
        }
        let configURL = root.appendingPathComponent(target.relativePath)
        try ensureInside(configURL, root: root)
        if fileManager.fileExists(atPath: configURL.path),
           (try? fileManager.destinationOfSymbolicLink(atPath: configURL.path)) != nil {
            throw MCPConfigurationError.unsafePath(configURL.path)
        }
        let before = fileManager.fileExists(atPath: configURL.path)
            ? try Data(contentsOf: configURL, options: .mappedIfSafe)
            : nil

        let content: Data
        switch target.host {
        case .codex:
            content = try updateCodex(
                existing: before.map { String(decoding: $0, as: UTF8.self) } ?? "",
                draft: draft,
                target: target
            )
        case .claudeCode:
            let managed = before != nil && registry.isManaged(
                configPath: target.configPath,
                serverName: draft.name
            )
            content = try updateClaudeJSON(existing: before, draft: draft, target: target, managed: managed)
        }
        let beforeHash = before.map(SkillAssetCopier.sha256)
        let afterHash = SkillAssetCopier.sha256(content)
        return MCPConfigEditResult(
            target: target,
            serverName: draft.name,
            content: content,
            beforeHash: beforeHash,
            afterHash: afterHash,
            action: before == nil ? "add" : (beforeHash == afterHash ? "noop" : "update")
        )
    }

    /// 只修改用户选中的连接字段，保留凭据、未知字段和其他服务。
    public func makeExistingEdit(
        target: MCPConfigurationTarget, server: MCPObservedServer,
        draft: MCPConfigurationDraft?, replaceArguments: Bool = false
    ) throws -> MCPConfigEditResult {
        guard server.configPath == target.configPath, server.host == target.host,
              server.scope == target.scope,
              inspect(target).servers.contains(where: { $0 == server }) else {
            throw MCPConfigurationError.configConflict(server.name)
        }
        if let draft {
            guard draft.name == server.name, draft.host == server.host,
                  draft.scope == server.scope, draft.validationIssues().isEmpty else {
                throw MCPConfigurationError.invalidDraft("请检查连接信息；编辑时不能更换名称、工具或范围。")
            }
        }
        let url = URL(fileURLWithPath: target.configPath)
        try ensureInside(url, root: URL(fileURLWithPath: target.rootPath))
        guard (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) == nil else {
            throw MCPConfigurationError.unsafePath(url.path)
        }
        let before = try Data(contentsOf: url)
        let content: Data
        switch target.host {
        case .claudeCode:
            guard var object = try JSONSerialization.jsonObject(with: before) as? [String: Any],
                  var servers = object["mcpServers"] as? [String: Any],
                  var node = servers[server.name] as? [String: Any] else {
                throw MCPConfigurationError.configCorrupt(target.configPath)
            }
            if let draft {
                guard draft.transport == server.transport else {
                    throw MCPConfigurationError.invalidDraft("请保留原连接方式；切换方式请删除后重新添加。")
                }
                if draft.commandOrURL != server.command || !server.command.hasPrefix("<") {
                    node[draft.transport == "stdio" ? "command" : "url"] = draft.commandOrURL
                }
                if replaceArguments { node["args"] = draft.args }
                servers[server.name] = node
            } else {
                servers.removeValue(forKey: server.name)
            }
            object["mcpServers"] = servers
            content = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) + Data("\n".utf8)
        case .codex:
            var lines = String(decoding: before, as: UTF8.self).components(separatedBy: "\n")
            guard let start = lines.firstIndex(where: { codexServerName(fromHeader: $0) == server.name }) else {
                throw MCPConfigurationError.configConflict(server.name)
            }
            let blocks = try codexManagedBlocks(in: lines)
            let block = blocks.first { $0.name == server.name }
            let tableKey = server.name.contains(".") ? tomlString(server.name) : server.name
            let next = lines.indices.first { index in
                index > start && (
                    lines[index].hasPrefix("# skillset:begin mcp ") ||
                    (lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("[") &&
                     !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("[mcp_servers.\(tableKey)."))
                )
            } ?? lines.count
            if let draft {
                guard draft.transport == server.transport else {
                    throw MCPConfigurationError.invalidDraft("请保留原连接方式；切换方式请删除后重新添加。")
                }
                let rootEnd = ((start + 1)..<next).first {
                    lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("[") ||
                    lines[$0].hasPrefix("# skillset:end")
                } ?? next
                let field = draft.transport == "stdio" ? "command" : "url"
                let connectionPatch: [(String, String)] = draft.commandOrURL == server.command && server.command.hasPrefix("<")
                    ? [] : [(field, tomlString(draft.commandOrURL))]
                let patch = connectionPatch +
                    (replaceArguments ? [("args", "[" + draft.args.map(tomlString).joined(separator: ", ") + "]")] : [])
                // 字段逐项替换；缺失字段插入服务表开头。
                for (key, value) in patch {
                    if let index = ((start + 1)..<rootEnd).first(where: {
                        lines[$0].range(of: "^\\s*" + key + "\\s*=", options: .regularExpression) != nil
                    }) {
                        // 多行数组无法逐行安全替换，拒绝而不损坏原配置。
                        if key == "args", !lines[index].contains("]") {
                            throw MCPConfigurationError.invalidDraft("多行参数请在原配置中修改，或保留现有参数。")
                        }
                        lines[index] = "\(key) = \(value)"
                    } else { lines.insert("\(key) = \(value)", at: start + 1) }
                }
            } else {
                let lower = block?.begin ?? start
                let upper = block.map { $0.end + 1 } ?? next
                lines.removeSubrange(lower..<upper)
            }
            content = Data(lines.joined(separator: "\n").utf8)
        }
        return MCPConfigEditResult(
            target: target, serverName: server.name, content: content,
            beforeHash: SkillAssetCopier.sha256(before), afterHash: SkillAssetCopier.sha256(content),
            action: content == before ? "noop" : "update"
        )
    }

    /// 扫描只提取可复用连接字段；env/header 的值不会进入候选或本机库。
    public func libraryScanCandidates() -> [MCPLibraryScanCandidate] {
        targets().flatMap { target -> [MCPLibraryScanCandidate] in
            let inspection = inspect(target)
            if inspection.servers.isEmpty && !inspection.issues.isEmpty {
                return [MCPLibraryScanCandidate(id: target.configPath, name: target.host.displayName,
                    source: target.configPath, entry: nil, issue: "配置无法安全解析，请检查原文件。")]
            }
            guard inspection.exists else { return [] }
            return inspection.servers.map { server in
                do {
                    let url = URL(fileURLWithPath: target.configPath)
                    try ensureInside(url, root: URL(fileURLWithPath: target.rootPath))
                    guard (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) == nil else {
                        throw MCPConfigurationError.unsafePath(url.path)
                    }
                    let data = try Data(contentsOf: url)
                    var args: [String] = []
                    var keys = server.envKeys
                    if target.host == .claudeCode {
                        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                        let node = (object?["mcpServers"] as? [String: [String: Any]])?[server.name]
                        if let value = node?["args"] {
                            guard let parsed = value as? [String] else { throw MCPConfigurationError.invalidDraft("") }
                            args = parsed
                        }
                    } else {
                        let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
                        guard let start = lines.firstIndex(where: { codexServerName(fromHeader: $0) == server.name }) else {
                            throw MCPConfigurationError.invalidDraft("")
                        }
                        let end = lines.indices.first { $0 > start && lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.count
                        let body = Array(lines[(start + 1)..<end])
                        if let argStart = body.firstIndex(where: { $0.range(of: #"^\s*args\s*="#, options: .regularExpression) != nil }) {
                            let raw = body[argStart...].joined(separator: "\n")
                            args = try MCPTOMLArguments.parse(String(raw.dropFirst(raw.firstIndex(of: "=")!.utf16Offset(in: raw) + 1)))
                        }
                        // env 子表只读取键名，不保留值。
                        let serverEnd = lines.indices.first { $0 > start && codexServerName(fromHeader: lines[$0]) != nil } ?? lines.count
                        let tableKey = server.name.contains(".") ? tomlString(server.name) : server.name
                        let envStart = ((start + 1)..<serverEnd).first {
                            lines[$0].trimmingCharacters(in: .whitespaces) == "[mcp_servers.\(tableKey).env]"
                        }
                        if let envStart {
                            for line in lines[(envStart + 1)...].prefix(while: { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("[") }) {
                                if let equal = line.firstIndex(of: "=") {
                                    let key = line[..<equal].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                                    if key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil { keys.append(key) }
                                }
                            }
                        }
                    }
                    let entry = MCPLibraryEntry(name: server.name, transport: server.transport,
                        commandOrURL: server.command, args: args, envKeys: Array(Set(keys)).sorted())
                    guard !MCPConnectionSafety.containsCredential([server.command] + args),
                          !server.command.hasPrefix("<"),
                          entry.draft(host: target.host, scope: target.scope).validationIssues().isEmpty else {
                        throw MCPConfigurationError.invalidDraft("")
                    }
                    return MCPLibraryScanCandidate(id: server.id, name: server.name,
                        source: "\(target.host.displayName) · \(target.scope.displayName) · \(target.configPath)", entry: entry, issue: nil)
                } catch {
                    return MCPLibraryScanCandidate(id: server.id, name: server.name, source: target.configPath,
                        entry: nil, issue: "连接包含敏感信息或不支持的参数格式，请手动添加并改用环境变量引用。")
                }
            }
        }
    }

    /// 对整组勾选生成一次配置变更；仅替换本配置库先前写入且没有漂移的节点。
    public func makeLibrarySelectionEdit(target: MCPConfigurationTarget, entries: [MCPLibraryEntry],
                                         previous: MCPLibraryAppliedSelection?) throws -> MCPConfigEditResult {
        let root = URL(fileURLWithPath: target.rootPath)
        let url = URL(fileURLWithPath: target.configPath)
        try ensureInside(url, root: root)
        guard fileManager.fileExists(atPath: root.path),
              (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) == nil else {
            throw MCPConfigurationError.unsafePath(url.path)
        }
        let before = fileManager.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        var content = before ?? Data()
        let hashes = try libraryNodeHashes(content: content, target: target)
        for (name, expected) in previous?.nodeHashes ?? [:] {
            guard hashes[name] == expected else {
                throw MCPLibraryError.modifiedConnection
            }
        }
        let oldNames = Set(previous?.nodeHashes.keys.map { $0 } ?? [])
        let newNames = entries.map(\.name)
        guard Set(newNames).count == newNames.count else {
            throw MCPConfigurationError.invalidDraft("选择中存在同名服务。")
        }
        for entry in entries {
            let draft = entry.draft(host: target.host, scope: target.scope)
            guard draft.validationIssues().isEmpty else {
                throw MCPConfigurationError.invalidDraft(draft.validationIssues().joined(separator: "；"))
            }
            if hashes[entry.name] != nil && !oldNames.contains(entry.name) {
                throw MCPConfigurationError.configConflict(entry.name)
            }
        }
        switch target.host {
        case .claudeCode:
            var object = content.isEmpty ? [:] : try JSONSerialization.jsonObject(with: content) as? [String: Any] ?? [:]
            var servers = object["mcpServers"] as? [String: Any] ?? [:]
            for name in oldNames { servers.removeValue(forKey: name) }
            object["mcpServers"] = servers
            content = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            for entry in entries.sorted(by: { $0.name < $1.name }) {
                content = try updateClaudeJSON(existing: content, draft: entry.draft(host: target.host, scope: target.scope),
                                              target: target, managed: false)
            }
            if entries.isEmpty {
                content = try JSONSerialization.data(withJSONObject: object,
                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) + Data("\n".utf8)
            }
        case .codex:
            var lines = String(decoding: content, as: UTF8.self).components(separatedBy: "\n")
            for block in try codexManagedBlocks(in: lines).reversed() where oldNames.contains(block.name) && !Set(newNames).contains(block.name) {
                lines.removeSubrange(block.begin...block.end)
            }
            content = Data(lines.joined(separator: "\n").utf8)
            for entry in entries.sorted(by: { $0.name < $1.name }) {
                content = try updateCodex(existing: String(decoding: content, as: UTF8.self),
                    draft: entry.draft(host: target.host, scope: target.scope), target: target)
            }
        }
        return MCPConfigEditResult(target: target, serverName: newNames.joined(separator: ", "), content: content,
            beforeHash: before.map(SkillAssetCopier.sha256), afterHash: SkillAssetCopier.sha256(content),
            action: before == nil ? "add" : (before == content ? "noop" : "update"))
    }

    public func libraryNodeHashes(content: Data, target: MCPConfigurationTarget) throws -> [String: String] {
        if content.isEmpty { return [:] }
        switch target.host {
        case .claudeCode:
            guard let object = try JSONSerialization.jsonObject(with: content) as? [String: Any],
                  object["mcpServers"] == nil || object["mcpServers"] is [String: Any] else {
                throw MCPConfigurationError.configCorrupt(target.configPath)
            }
            return try (object["mcpServers"] as? [String: Any] ?? [:]).mapValues {
                SkillAssetCopier.sha256(try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .fragmentsAllowed]))
            }
        case .codex:
            let lines = String(decoding: content, as: UTF8.self).components(separatedBy: "\n")
            var hashes: [String: String] = [:]
            for name in lines.compactMap(codexServerName(fromHeader:)) {
                guard hashes[name] == nil else { throw MCPConfigurationError.configCorrupt(target.configPath) }
                hashes[name] = "external"
            }
            for block in try codexManagedBlocks(in: lines) {
                hashes[block.name] = SkillAssetCopier.sha256(Data(lines[block.begin...block.end].joined(separator: "\n").utf8))
            }
            return hashes
        }
    }

    public func recordApplied(plan: DeploymentPlan) throws {
        guard plan.metadata?["planType"] == "mcp-configuration",
              let configPath = plan.metadata?["configPath"],
              let serverName = plan.metadata?["serverName"],
              let change = plan.changes.first,
              let afterHash = change.afterHash else {
            return
        }
        if let selected = plan.metadata?["librarySelectedNames"],
           let removed = plan.metadata?["libraryRemovedNames"] {
            let names = try JSONDecoder().decode([String].self, from: Data(selected.utf8))
            let removals = try JSONDecoder().decode([String].self, from: Data(removed.utf8))
            try registry.recordSelection(configPath: configPath, names: names, removed: removals, contentHash: afterHash)
            return
        }
        if plan.metadata?["mcpAction"] == "remove" {
            try registry.forget(configPath: configPath, serverName: serverName)
            return
        }
        try registry.record(
            configPath: configPath,
            serverName: serverName,
            contentHash: afterHash
        )
    }

    private func parseClaudeJSON(
        _ data: Data,
        target: MCPConfigurationTarget
    ) throws -> [MCPObservedServer] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPConfigurationError.configCorrupt(target.configPath)
        }
        let servers = object["mcpServers"] as? [String: Any] ?? [:]
        return servers.map { name, raw in
            let server = raw as? [String: Any] ?? [:]
            let type = server["type"] as? String ?? "stdio"
            let transport = type == "http" || type == "sse" ? "streamable-http" : "stdio"
            let command = redactedCommand(
                (server["command"] as? String) ?? (server["url"] as? String) ?? ""
            )
            let args = server["args"] as? [Any] ?? []
            let env = server["env"] as? [String: Any] ?? [:]
            return MCPObservedServer(
                host: target.host,
                scope: target.scope,
                name: name,
                transport: transport,
                command: command,
                argumentCount: args.count,
                envKeys: Array(env.keys),
                configPath: target.configPath,
                managed: registry.isManaged(configPath: target.configPath, serverName: name)
            )
        }.sorted { $0.name < $1.name }
    }

    private func parseCodex(
        _ text: String,
        target: MCPConfigurationTarget
    ) throws -> [MCPObservedServer] {
        let lines = text.components(separatedBy: "\n")
        let managedNames = try managedCodexServerNames(in: lines)
        let headers = lines.enumerated().compactMap { index, line -> (name: String, index: Int)? in
            guard let name = codexServerName(fromHeader: line) else { return nil }
            return (name, index)
        }
        var servers: [MCPObservedServer] = []
        for (offset, header) in headers.enumerated() {
            let end = offset + 1 < headers.count ? headers[offset + 1].index : lines.count
            // 子表及后续普通配置表不属于服务的连接字段。
            let body = lines[(header.index + 1)..<end].prefix { line in
                !line.trimmingCharacters(in: .whitespaces).hasPrefix("[")
            }
            let command = body.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("command =") })
                .flatMap { tomlQuotedValue($0) }
                ?? body.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("url =") })
                    .flatMap { tomlQuotedValue($0) }
                ?? ""
            // Codex 自带运行组件不属于用户管理的连接；空连接也可能是 env 子表。
            guard !command.isEmpty,
                  !["computer-use", "node_repl"].contains(header.name) else { continue }
            let argsCount = body.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("args =") })
                .map(countTOMLArrayItems) ?? 0
            let envKeys = body.compactMap { tomlInlineEnvKeys($0) }.flatMap { $0 }
            let bearer = body.first(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("bearer_token_env_var =")
            }).flatMap { tomlQuotedValue($0) }
            var keys = Set(envKeys)
            if let bearer { keys.insert(bearer) }
            servers.append(MCPObservedServer(
                host: target.host,
                scope: target.scope,
                name: header.name,
                transport: body.contains(where: {
                    $0.trimmingCharacters(in: .whitespaces).hasPrefix("url =")
                }) ? "streamable-http" : "stdio",
                command: redactedCommand(command),
                argumentCount: argsCount,
                envKeys: Array(keys),
                configPath: target.configPath,
                managed: managedNames.contains(header.name)
            ))
        }
        return servers.sorted { $0.name < $1.name }
    }

    private func updateClaudeJSON(
        existing: Data?,
        draft: MCPConfigurationDraft,
        target: MCPConfigurationTarget,
        managed: Bool
    ) throws -> Data {
        var object: [String: Any] = [:]
        if let existing {
            guard let decoded = try JSONSerialization.jsonObject(with: existing) as? [String: Any] else {
                throw MCPConfigurationError.configCorrupt(target.configPath)
            }
            object = decoded
        }
        if let existingServers = object["mcpServers"], !(existingServers is [String: Any]) {
            throw MCPConfigurationError.configCorrupt(target.configPath)
        }
        var servers = object["mcpServers"] as? [String: Any] ?? [:]
        if servers[draft.name] != nil && !managed {
            throw MCPConfigurationError.configConflict(draft.name)
        }
        var server: [String: Any] = [:]
        if draft.transport == "stdio" {
            server["type"] = "stdio"
            server["command"] = draft.commandOrURL
            if !draft.args.isEmpty { server["args"] = draft.args }
        } else {
            server["type"] = "http"
            server["url"] = draft.commandOrURL
        }
        if !draft.envKeys.isEmpty {
            server["env"] = Dictionary(uniqueKeysWithValues: draft.envKeys.map { ($0, "${\($0)}") })
        }
        servers[draft.name] = server
        object["mcpServers"] = servers
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return data + Data("\n".utf8)
    }

    private func updateCodex(
        existing: String,
        draft: MCPConfigurationDraft,
        target: MCPConfigurationTarget
    ) throws -> Data {
        let lines = existing.components(separatedBy: "\n")
        let blocks = try codexManagedBlocks(in: lines)
        let unownedHeaders = Set(lines.compactMap(codexServerName(fromHeader:)))
            .subtracting(blocks.map(\.name))
        if unownedHeaders.contains(draft.name), blocks.first(where: { $0.name == draft.name }) == nil {
            throw MCPConfigurationError.configConflict(draft.name)
        }

        let block = renderCodexServer(draft)
        var updated = lines
        if let range = blocks.first(where: { $0.name == draft.name }) {
            updated.replaceSubrange(range.begin...range.end, with: block)
        } else {
            while updated.last?.isEmpty == true {
                updated.removeLast()
            }
            if !updated.isEmpty {
                updated.append("")
            }
            updated.append(contentsOf: block)
        }
        let text = updated.joined(separator: "\n")
        return Data((text.hasSuffix("\n") ? text : text + "\n").utf8)
    }

    private func renderCodexServer(_ draft: MCPConfigurationDraft) -> [String] {
        var lines = [
            "# skillset:begin mcp name=\(draft.name) schema=1",
            "[mcp_servers.\(draft.name.contains(".") ? tomlString(draft.name) : draft.name)]"
        ]
        if draft.transport == "stdio" {
            lines.append("command = \(tomlString(draft.commandOrURL))")
            if !draft.args.isEmpty {
                lines.append("args = [\(draft.args.map(tomlString).joined(separator: ", "))]")
            }
        } else {
            lines.append("url = \(tomlString(draft.commandOrURL))")
            if let key = draft.envKeys.first {
                lines.append("bearer_token_env_var = \(tomlString(key))")
            }
        }
        if !draft.envKeys.isEmpty {
            let pairs = draft.envKeys.map { "\($0) = \(tomlString("${\($0)}"))" }
            lines.append("env = { \(pairs.joined(separator: ", ")) }")
        }
        lines.append("# skillset:end mcp name=\(draft.name)")
        return lines
    }

    private struct CodexBlock {
        let name: String
        let begin: Int
        let end: Int
    }

    private func codexManagedBlocks(in lines: [String]) throws -> [CodexBlock] {
        var blocks: [CodexBlock] = []
        var active: (name: String, begin: Int)?
        var seen: Set<String> = []
        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let name = codexManagedMarker(line, prefix: "# skillset:begin mcp name=") {
                guard active == nil, !seen.contains(name) else {
                    throw MCPConfigurationError.configCorrupt("Codex MCP 受管块重复或嵌套：\(name)")
                }
                active = (name, index)
            } else if let name = codexManagedMarker(line, prefix: "# skillset:end mcp name=") {
                guard let current = active, current.name == name else {
                    throw MCPConfigurationError.configCorrupt("Codex MCP 受管块结束标记无效：\(name)")
                }
                blocks.append(CodexBlock(name: name, begin: current.begin, end: index))
                seen.insert(name)
                active = nil
            }
        }
        if let active {
            throw MCPConfigurationError.configCorrupt("Codex MCP 受管块缺少结束标记：\(active.name)")
        }
        return blocks
    }

    private func managedCodexServerNames(in lines: [String]) throws -> Set<String> {
        Set(try codexManagedBlocks(in: lines).map(\.name))
    }

    private func codexManagedMarker(_ line: String, prefix: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        let remainder = line.dropFirst(prefix.count)
        return remainder.split(separator: " ").first.map(String.init)
    }

    private func codexServerName(fromHeader rawLine: String) -> String? {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        // 未加引号的点表示子表，不能作为服务名称的一部分。
        let pattern = #"^\[mcp_servers\.(?:([A-Za-z0-9][A-Za-z0-9_-]{0,63})|"([A-Za-z0-9][A-Za-z0-9._-]{0,63})")\]\s*(?:#.*)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }
        for index in 1...2 {
            if let range = Range(match.range(at: index), in: line) { return String(line[range]) }
        }
        return nil
    }

    private func tomlQuotedValue(_ line: String) -> String? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let raw = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        guard raw.first == "\"", raw.last == "\"", raw.count >= 2 else { return nil }
        let inner = String(raw.dropFirst().dropLast())
        return inner
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private func countTOMLArrayItems(_ line: String) -> Int {
        guard let start = line.firstIndex(of: "["), let end = line.lastIndex(of: "]"), start < end else {
            return 0
        }
        let body = line[line.index(after: start)..<end].trimmingCharacters(in: .whitespaces)
        return body.isEmpty ? 0 : body.split(separator: ",").count
    }

    private func tomlInlineEnvKeys(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("env ="), let open = trimmed.firstIndex(of: "{"),
              let close = trimmed.lastIndex(of: "}"), open < close else {
            return nil
        }
        let body = trimmed[trimmed.index(after: open)..<close]
        return body.split(separator: ",").compactMap { pair in
            pair.split(separator: "=", maxSplits: 1).first.map {
                $0.trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
    }

    private func tomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    private func redactedCommand(_ command: String) -> String {
        let lowered = command.lowercased()
        if lowered.contains("token=") || lowered.contains("secret=") || lowered.contains("password=") {
            return "<已隐藏>"
        }
        if let url = URL(string: command), url.user != nil || url.password != nil {
            return "<含凭据 URL 已隐藏>"
        }
        return command
    }

    private func ensureInside(_ url: URL, root: URL) throws {
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard url.standardizedFileURL.path.hasPrefix(prefix) else {
            throw MCPConfigurationError.unsafePath(url.path)
        }
    }
}
