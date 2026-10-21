import Foundation

public enum PluginInventoryError: Error, LocalizedError, Equatable, Sendable {
    case unsafeRoot(String)
    case manifestUnreadable(String)

    public var code: String {
        switch self {
        case .unsafeRoot: "PLUGIN_INVENTORY_UNSAFE"
        case .manifestUnreadable: "PLUGIN_MANIFEST_UNREADABLE"
        }
    }

    public var errorDescription: String? {
        switch self {
        case let .unsafeRoot(path):
            return "插件扫描根目录不安全：\(path)"
        case let .manifestUnreadable(path):
            return "插件 manifest 无法读取：\(path)"
        }
    }
}

public struct PluginInventoryRecord: Codable, Identifiable, Hashable, Sendable {
    public let host: MCPHost
    public let pluginID: String
    public let name: String
    public let marketplaceID: String?
    public let version: String?
    public let sourceRevision: String?
    public let scope: String?
    public let installed: Bool
    public let enabled: Bool?
    public let description: String
    public let manifestPath: String
    public let sourcePath: String
    public let manifestDigest: String
    public let components: [String]
    public let dependencyCount: Int
    public let license: String?
    public let risks: [String]
    public let state: String

    public var id: String {
        "\(host.rawValue):\(pluginID):\(scope ?? "project"):\(manifestPath)"
    }

    public init(
        host: MCPHost,
        pluginID: String,
        name: String,
        marketplaceID: String?,
        version: String?,
        sourceRevision: String?,
        scope: String?,
        installed: Bool,
        enabled: Bool?,
        description: String,
        manifestPath: String,
        sourcePath: String,
        manifestDigest: String,
        components: [String],
        dependencyCount: Int,
        license: String?,
        risks: [String],
        state: String
    ) {
        self.host = host
        self.pluginID = pluginID
        self.name = name
        self.marketplaceID = marketplaceID
        self.version = version
        self.sourceRevision = sourceRevision
        self.scope = scope
        self.installed = installed
        self.enabled = enabled
        self.description = description
        self.manifestPath = manifestPath
        self.sourcePath = sourcePath
        self.manifestDigest = manifestDigest
        self.components = Array(Set(components)).sorted()
        self.dependencyCount = dependencyCount
        self.license = license
        self.risks = Array(Set(risks)).sorted()
        self.state = state
    }
}

public struct PluginInventorySnapshot: Codable, Hashable, Sendable {
    public let records: [PluginInventoryRecord]
    public let issues: [String]
    public let scannedRoots: [String]

    public init(records: [PluginInventoryRecord], issues: [String], scannedRoots: [String]) {
        self.records = records.sorted {
            ($0.host.rawValue, $0.name, $0.manifestPath)
                < ($1.host.rawValue, $1.name, $1.manifestPath)
        }
        self.issues = issues.sorted()
        self.scannedRoots = scannedRoots.sorted()
    }
}

private struct PluginInstallation {
    let pluginID: String
    let installationPath: String?
    let marketplaceID: String?
    let scope: String?
    let revision: String?
    let installed: Bool
    let enabled: Bool?
}

/// 只读取宿主插件缓存中的 manifest 和组件目录，不执行 hooks、commands 或安装器。
public struct PluginInventoryManager {
    public let projectRoot: URL?
    public let homeDirectory: URL

    private let fileManager: FileManager
    private let maxDirectories: Int
    private let maxDepth: Int

    public init(
        projectRoot: URL?,
        homeDirectory: URL = PluginInventoryManager.defaultHomeDirectory,
        fileManager: FileManager = .default,
        maxDirectories: Int = 2_000,
        maxDepth: Int = 7
    ) {
        self.projectRoot = projectRoot?.resolvingSymlinksInPath().standardizedFileURL
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.fileManager = fileManager
        self.maxDirectories = maxDirectories
        self.maxDepth = maxDepth
    }

    public static var defaultHomeDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["SKILLSET_HOME"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public func inspect() -> PluginInventorySnapshot {
        var manifests: Set<String> = []
        if let projectRoot {
            for container in [".claude-plugin", ".codex-plugin"] {
                let url = projectRoot.appendingPathComponent("\(container)/plugin.json")
                if fileManager.fileExists(atPath: url.path) {
                    manifests.insert(url.standardizedFileURL.path)
                }
            }
        }
        let roots = [
            homeDirectory.appendingPathComponent(".claude/plugins/cache", isDirectory: true),
            homeDirectory.appendingPathComponent(".codex/plugins/cache", isDirectory: true)
        ]
        var issues: [String] = []
        var visited = 0
        for root in roots where fileManager.fileExists(atPath: root.path) {
            let values = try? root.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                issues.append("插件扫描根是软链，已跳过：\(root.path)")
                continue
            }
            walk(
                directory: root.standardizedFileURL,
                depth: 0,
                visited: &visited,
                manifests: &manifests
            )
        }

        var records: [PluginInventoryRecord] = []
        let claudeInstallations = loadClaudeInstallations(issues: &issues)
        let codexInstallations = loadCodexInstallations(issues: &issues)
        for path in manifests.sorted() {
            do {
                let manifestURL = URL(fileURLWithPath: path)
                let installation = installation(
                    for: manifestURL,
                    claude: claudeInstallations,
                    codex: codexInstallations
                )
                records.append(try parseManifest(at: manifestURL, installation: installation))
            } catch {
                issues.append(error.localizedDescription)
            }
        }
        return PluginInventorySnapshot(
            records: records,
            issues: issues,
            scannedRoots: roots.map(\.path) + (projectRoot.map { [$0.path] } ?? [])
        )
    }

    private func walk(
        directory: URL,
        depth: Int,
        visited: inout Int,
        manifests: inout Set<String>
    ) {
        guard depth <= maxDepth, visited < maxDirectories else { return }
        visited += 1
        guard let children = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return
        }
        for child in children {
            let name = child.lastPathComponent
            guard !["node_modules", ".git", "artifacts", "dist", "build"].contains(name) else {
                continue
            }
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isSymbolicLink != true, values?.isDirectory == true else { continue }
            if name == ".claude-plugin" || name == ".codex-plugin" {
                let manifest = child.appendingPathComponent("plugin.json")
                if fileManager.fileExists(atPath: manifest.path) {
                    manifests.insert(manifest.standardizedFileURL.path)
                }
                continue
            }
            walk(
                directory: child,
                depth: depth + 1,
                visited: &visited,
                manifests: &manifests
            )
        }
    }

    private func parseManifest(
        at manifestURL: URL,
        installation: PluginInstallation?
    ) throws -> PluginInventoryRecord {
        let values = try? manifestURL.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
        guard let values,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize <= 2 * 1024 * 1024 else {
            throw PluginInventoryError.manifestUnreadable(manifestURL.path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
        } catch {
            throw PluginInventoryError.manifestUnreadable(manifestURL.path)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PluginInventoryError.manifestUnreadable(manifestURL.path)
        }
        let host: MCPHost = manifestURL.path.contains("/.codex-plugin/") ? .codex : .claudeCode
        let sourcePath = manifestURL.deletingLastPathComponent().deletingLastPathComponent()
        let cacheIdentity = cacheIdentity(for: sourcePath)
        let fallbackName = cacheIdentity?.name ?? sourcePath.lastPathComponent
        let name = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = name?.isEmpty == false ? name! : fallbackName
        let marketplaceID = installation?.marketplaceID ?? marketplaceID(for: sourcePath)
        let pluginID = installation?.pluginID
            ?? marketplaceID.map { "\(resolvedName)@\($0)" }
            ?? resolvedName
        let componentKeys: [(String, String)] = [
            ("skills", "skills"),
            ("commands", "commands"),
            ("agents", "agents"),
            ("hooks", "hooks"),
            ("mcpServers", "MCP"),
            ("lspServers", "LSP"),
            ("userConfig", "userConfig")
        ]
        var components = componentKeys.compactMap { key, label in
            object[key] == nil ? nil : label
        }
        let fileComponents: [(String, String)] = [
            (".mcp.json", "MCP"),
            (".lsp.json", "LSP"),
            ("hooks", "hooks"),
            ("commands", "commands"),
            ("skills", "skills")
        ]
        for (relative, label) in fileComponents {
            if fileManager.fileExists(atPath: sourcePath.appendingPathComponent(relative).path) {
                components.append(label)
            }
        }
        let dependencies = object["dependencies"]
            ?? (object["extensions"] as? [String: Any])?["com.openai"]
                .flatMap { ($0 as? [String: Any])?["dependencies"] }
        let dependencyCount: Int
        if let values = dependencies as? [Any] {
            dependencyCount = values.count
        } else if let values = dependencies as? [String: Any] {
            dependencyCount = values.count
        } else {
            dependencyCount = 0
        }
        var risks: [String] = []
        if components.contains("hooks") { risks.append("含 hook") }
        if components.contains("commands") { risks.append("含 command") }
        if components.contains("MCP") { risks.append("含 MCP") }
        if components.contains("LSP") { risks.append("启动 LSP") }
        if components.contains("userConfig") { risks.append("包含用户配置项") }
        if installation?.installed != true { risks.append("缓存不等于启用") }
        if risks.isEmpty { risks.append("未发现可执行副作用") }

        return PluginInventoryRecord(
            host: host,
            pluginID: pluginID,
            name: resolvedName,
            marketplaceID: marketplaceID,
            version: object["version"] as? String,
            sourceRevision: installation?.revision,
            scope: installation?.scope,
            installed: installation?.installed == true,
            enabled: installation?.enabled,
            description: object["description"] as? String ?? "",
            manifestPath: manifestURL.path,
            sourcePath: sourcePath.path,
            manifestDigest: SkillAssetCopier.sha256(data),
            components: components,
            dependencyCount: dependencyCount,
            license: object["license"] as? String,
            risks: risks,
            state: installationState(installation)
        )
    }

    private func installationState(_ installation: PluginInstallation?) -> String {
        guard let installation, installation.installed else {
            return "仅缓存 · 未确认安装"
        }
        switch installation.enabled {
        case true?: return "已安装 · 已启用"
        case false?: return "已安装 · 已停用"
        case nil: return "已安装 · 启用状态待确认"
        }
    }

    private func marketplaceID(for sourcePath: URL) -> String? {
        cacheIdentity(for: sourcePath)?.marketplace
    }

    private func cacheIdentity(
        for sourcePath: URL
    ) -> (marketplace: String, name: String, version: String)? {
        let roots = [
            homeDirectory.appendingPathComponent(".claude/plugins/cache", isDirectory: true),
            homeDirectory.appendingPathComponent(".codex/plugins/cache", isDirectory: true)
        ]
        for root in roots {
            let rootPath = root.standardizedFileURL.path
            let source = sourcePath.standardizedFileURL.path
            guard source.hasPrefix(rootPath + "/") else { continue }
            let relative = String(source.dropFirst(rootPath.count + 1))
            let components = relative.split(separator: "/")
            guard components.count >= 3 else { continue }
            return (
                marketplace: String(components[0]),
                name: String(components[1]),
                version: String(components[2])
            )
        }
        return nil
    }

    private func installation(
        for manifestURL: URL,
        claude: [PluginInstallation],
        codex: [PluginInstallation]
    ) -> PluginInstallation? {
        let sourcePath = manifestURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL
            .path
        if manifestURL.path.contains("/.claude-plugin/") {
            return claude.first {
                guard let installationPath = $0.installationPath else { return false }
                return sourcePath == installationPath
                    || sourcePath.hasPrefix(installationPath + "/")
            }
        }

        let codexCache = homeDirectory
            .appendingPathComponent(".codex/plugins/cache", isDirectory: true)
            .standardizedFileURL
            .path
        guard sourcePath.hasPrefix(codexCache + "/") else { return nil }
        let identity = cacheIdentity(for: URL(fileURLWithPath: sourcePath))
        let expectedID = identity.map { "\($0.name)@\($0.marketplace)" }
        return codex.first {
            $0.pluginID == expectedID
        }
    }

    private func loadClaudeInstallations(issues: inout [String]) -> [PluginInstallation] {
        let url = homeDirectory.appendingPathComponent(".claude/plugins/installed_plugins.json")
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let enabledPlugins = loadClaudeEnabledPlugins(issues: &issues)
        do {
            let data = try Data(contentsOf: url)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let plugins = root["plugins"] as? [String: Any] else {
                issues.append("Claude 插件安装索引格式无法识别：\(url.path)")
                return []
            }
            return plugins.flatMap { pluginKey, value -> [PluginInstallation] in
                let parts = pluginKey.split(separator: "@", maxSplits: 1).map(String.init)
                let marketplaceID = parts.count == 2 ? parts[1] : nil
                let entries = value as? [[String: Any]] ?? []
                return entries.compactMap { entry -> PluginInstallation? in
                    guard let installPath = entry["installPath"] as? String else { return nil }
                    let enabled = entry["enabled"] as? Bool ?? enabledPlugins[pluginKey] ?? false
                    return PluginInstallation(
                        pluginID: pluginKey,
                        installationPath: URL(fileURLWithPath: installPath).standardizedFileURL.path,
                        marketplaceID: marketplaceID,
                        scope: entry["scope"] as? String,
                        revision: entry["gitCommitSha"] as? String,
                        installed: true,
                        enabled: enabled
                    )
                }
            }
        } catch {
            issues.append("Claude 插件安装索引无法读取：\(url.path)")
            return []
        }
    }

    private func loadClaudeEnabledPlugins(issues: inout [String]) -> [String: Bool] {
        var settingsURLs = [
            homeDirectory.appendingPathComponent(".claude/settings.json"),
            homeDirectory.appendingPathComponent(".claude/settings.local.json")
        ]
        if let projectRoot {
            settingsURLs.append(projectRoot.appendingPathComponent(".claude/settings.json"))
            settingsURLs.append(projectRoot.appendingPathComponent(".claude/settings.local.json"))
        }
        var values: [String: Bool] = [:]
        for url in settingsURLs where fileManager.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                issues.append("Claude 插件启用设置无法读取：\(url.path)")
                continue
            }
            guard let enabled = object["enabledPlugins"] as? [String: Any] else { continue }
            for (pluginID, value) in enabled {
                if let enabled = value as? Bool {
                    values[pluginID] = enabled
                }
            }
        }
        return values
    }

    private func loadCodexInstallations(issues: inout [String]) -> [PluginInstallation] {
        let url = homeDirectory.appendingPathComponent(".codex/config.toml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var installations: [PluginInstallation] = []
        var currentID: String?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[plugins.\"") && line.hasSuffix("\"]") {
                let start = line.index(line.startIndex, offsetBy: 10)
                let end = line.index(line.endIndex, offsetBy: -2)
                currentID = String(line[start..<end])
                let parts = currentID?.split(separator: "@", maxSplits: 1).map(String.init) ?? []
                installations.append(
                    PluginInstallation(
                        pluginID: currentID ?? "",
                        installationPath: nil,
                        marketplaceID: parts.count == 2 ? parts[1] : nil,
                        scope: "host",
                        revision: nil,
                        installed: true,
                        enabled: nil
                    )
                )
                continue
            }
            if line.hasPrefix("[") {
                currentID = nil
                continue
            }
            guard currentID != nil,
                  line.hasPrefix("enabled"),
                  let equals = line.firstIndex(of: "="),
                  let index = installations.indices.last else {
                continue
            }
            let value = line[line.index(after: equals)...]
                .trimmingCharacters(in: .whitespaces)
            installations[index] = PluginInstallation(
                pluginID: installations[index].pluginID,
                installationPath: installations[index].installationPath,
                marketplaceID: installations[index].marketplaceID,
                scope: installations[index].scope,
                revision: installations[index].revision,
                installed: installations[index].installed,
                enabled: value == "true" ? true : value == "false" ? false : nil
            )
        }
        return installations
    }
}
