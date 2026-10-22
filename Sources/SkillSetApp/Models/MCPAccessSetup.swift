import Foundation
import SkillSetCore

struct MCPAccessInstallation {
    enum Origin: Equatable {
        case bundled, development
    }

    let executableURL: URL
    let origin: Origin

    static func detect(bundleURL: URL, repositoryRoot: URL?, fileManager: FileManager = .default) -> Self? {
        var candidates: [(URL, Origin)] = []
        if bundleURL.pathExtension == "app" {
            // Helpers 与 MacOS 分开，避免 skillset 命中大小写不敏感的 GUI 程序 SkillSet。
            candidates.append((bundleURL.appendingPathComponent("Contents/Helpers/skillset"), .bundled))
        }
        if let repositoryRoot {
            candidates.append((repositoryRoot.appendingPathComponent("dist/skillset"), .development))
            candidates.append((repositoryRoot.appendingPathComponent(".build/debug/skillset"), .development))
        }
        for (executable, origin) in candidates {
            let resources = executable.deletingLastPathComponent().appendingPathComponent("SkillSet_SkillSetCore.bundle")
            guard fileManager.isExecutableFile(atPath: executable.path),
                  fileManager.fileExists(atPath: resources.path),
                  let bundle = Bundle(url: resources),
                  bundle.url(forResource: "catalog", withExtension: "json") != nil else { continue }
            return Self(executableURL: executable.standardizedFileURL, origin: origin)
        }
        return nil
    }

    func draft(host: MCPHost, paths: SkillSetRuntimePaths) -> MCPConfigurationDraft {
        // MCP 与 App 使用同一本机状态目录；不依赖宿主启动时的工作目录或 PATH。
        var arguments = ["--state", paths.applicationSupportRoot.path]
        if let repositoryRoot = paths.repositoryRoot {
            arguments += ["--repository", repositoryRoot.path]
        }
        arguments += ["mcp", "serve", "--transport", "stdio"]
        return MCPConfigurationDraft(
            name: "perch", host: host, scope: .user, transport: "stdio",
            commandOrURL: executableURL.path, args: arguments
        )
    }
}

enum MCPAccessConnectionState: Equatable {
    case unconfigured, configured, updateNeeded, external, unreadable

    static func inspect(_ inspection: MCPConfigurationInspection?, installation: MCPAccessInstallation?) -> Self {
        guard let inspection else { return .unreadable }
        guard let server = inspection.servers.first(where: { $0.name == "perch" }) else {
            // 已有其他名称的同程序配置时不再自动新增一份。
            if let installation, inspection.servers.contains(where: { $0.command == installation.executableURL.path }) {
                return .external
            }
            return inspection.servers.isEmpty && !inspection.issues.isEmpty ? .unreadable : .unconfigured
        }
        guard server.managed else { return .external }
        guard let installation, server.command == installation.executableURL.path,
              server.transport == "stdio" else { return .updateNeeded }
        // 这里只证明发现配置，不能推断宿主加载状态或参数完全一致。
        return .configured
    }
}
