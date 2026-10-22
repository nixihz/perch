import Foundation
import SkillSetCore

struct CLIInvocation {
    static func run(arguments: [String]) {
        var args = arguments
        var json = consumeFlag("--json", from: &args)
        do {
            let repository = consumeOption("--repository", from: &args)
            let state = consumeOption("--state", from: &args)
            guard let command = args.first else {
                throw CLIError("缺少命令。运行 `skillset doctor` 或 `skillset mcp serve --transport stdio`。", exitCode: 2)
            }
            args.removeFirst()

            let detected = SkillSetRuntimePaths.detect()
            let repositoryRoot = repository.map {
                URL(fileURLWithPath: $0, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
            } ?? detected.repositoryRoot
            let stateRoot = state.map {
                URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
            } ?? detected.applicationSupportRoot
            let paths = SkillSetRuntimePaths(applicationSupportRoot: stateRoot, repositoryRoot: repositoryRoot)

            switch command {
            case "doctor":
                let service = try SkillSetService(paths: paths)
                try doctor(service: service, paths: paths, json: json)
            case "projects":
                try projects(arguments: args, paths: paths, json: &json)
            case "skills":
                try skills(arguments: args, paths: paths, json: &json)
            case "sources":
                try sources(arguments: args, paths: paths, json: &json)
            case "objects":
                try objects(arguments: args, paths: paths, json: json)
            case "plugins":
                try plugins(arguments: args, paths: paths, json: json)
            case "inspect":
                try inspect(arguments: args, paths: paths, json: json)
            case "plan":
                try plan(arguments: args, paths: paths, json: json)
            case "plans":
                try plans(arguments: args, paths: paths, json: json)
            case "approve":
                try approve(arguments: args, paths: paths, json: json)
            case "apply":
                try apply(arguments: args, paths: paths, json: json)
            case "operations":
                try operations(arguments: args, paths: paths, json: json)
            case "rollback":
                try rollback(arguments: args, paths: paths, json: json)
            case "mcp":
                try mcp(arguments: args, paths: paths, json: &json)
            default:
                throw CLIError("未知命令：\(command)", exitCode: 2)
            }
        } catch {
            emitError(error, json: json)
        }
    }

    private static func doctor(service: SkillSetService, paths: SkillSetRuntimePaths, json: Bool) throws {
        let projects = try service.projects()
        let output: [String: Any] = [
            "repositoryRoot": paths.repositoryRoot?.path ?? NSNull(),
            "applicationSupportRoot": paths.applicationSupportRoot.path,
            "catalogEntries": service.snapshot.catalog.entries.count,
            "blockedEntries": service.snapshot.catalog.entries.filter(\.isBlocked).count,
            "registeredProjects": projects.count,
            "plans": try service.pendingPlans().count,
            "status": "ready"
        ]
        if json {
            emitJSON(output)
        } else {
            print("Skill Set 诊断")
            print("仓库：\(paths.repositoryRoot?.path ?? "未找到")")
            print("本机状态：\(paths.applicationSupportRoot.path)")
            print("Catalog：\(service.snapshot.catalog.entries.count) 条，\(output["blockedEntries"]!) 条阻塞")
            print("项目：\(projects.count) 个；待审计划：\(output["plans"]!) 个")
        }
    }

    private static func projects(arguments: [String], paths: SkillSetRuntimePaths, json: inout Bool) throws {
        guard let subcommand = arguments.first else {
            throw CLIError("用法：skillset projects list|add <path> [--name ...]", exitCode: 2)
        }
        var rest = Array(arguments.dropFirst())
        let service = try SkillSetService(paths: paths)
        switch subcommand {
        case "list":
            let items = try service.projects()
            if json {
                emitJSON(["projects": try jsonValue(items)])
            } else if items.isEmpty {
                print("尚未登记项目。运行 `skillset projects add <path>`。")
            } else {
                for project in items {
                    print("\(project.id.uuidString)  \(project.name)  \(project.path)")
                    print("  desired=\(project.desiredSkillIDs.count) observed=\(project.observedSkillIDs.count) agents=\(project.agents.joined(separator: ",")) lock=\(project.lockStatus)")
                }
            }
        case "add":
            guard let path = rest.first else {
                throw CLIError("projects add 需要目录路径。", exitCode: 2)
            }
            let name = consumeOption("--name", from: &rest)
            let store = ProjectStore(rootURL: paths.applicationSupportRoot)
            let registration = try store.register(path: URL(fileURLWithPath: path, isDirectory: true), name: name)
            guard let summary = try service.projects().first(where: { $0.id == registration.id }) else {
                throw CLIError("项目登记后无法读取摘要。")
            }
            if json {
                emitJSON(["project": try jsonValue(summary)])
            } else {
                print("已登记 \(registration.name)：\(registration.canonicalPath)")
            }
        case "remove":
            guard let id = rest.first.flatMap(UUID.init(uuidString:)) else {
                throw CLIError("projects remove 需要项目 UUID。", exitCode: 2)
            }
            try ProjectStore(rootURL: paths.applicationSupportRoot).unregister(id: id)
            try ProjectDraftStore(rootURL: paths.applicationSupportRoot).remove(projectID: id)
            if json { emitJSON(["removed": id.uuidString]) } else { print("已移除登记：\(id.uuidString)") }
        default:
            throw CLIError("未知 projects 子命令：\(subcommand)", exitCode: 2)
        }
    }

    private static func skills(arguments: [String], paths: SkillSetRuntimePaths, json: inout Bool) throws {
        guard arguments.first == "search" else {
            throw CLIError("用法：skillset skills search <query> [--source ID] [--limit N]", exitCode: 2)
        }
        var rest = Array(arguments.dropFirst())
        let query = rest.first ?? ""
        if !rest.isEmpty { rest.removeFirst() }
        let source = consumeOption("--source", from: &rest)
        let limit = min(max(Int(consumeOption("--limit", from: &rest) ?? "50") ?? 50, 1), 200)
        let service = try SkillSetService(paths: paths)
        let entries = Array(service.skills(query: query, sourceID: source).prefix(limit))
        if json {
            emitJSON([
                "query": query,
                "count": entries.count,
                "skills": try jsonValue(entries)
            ])
        } else {
            for entry in entries {
                print("\(entry.id)\t\(entry.contentHash)\t\(entry.integrity)\t\(entry.description)")
            }
        }
    }

    private static func sources(arguments: [String], paths: SkillSetRuntimePaths, json: inout Bool) throws {
        guard let subcommand = arguments.first else {
            throw CLIError("用法：skillset sources preview <url> [--ref ...] | sources list | sources show <id>", exitCode: 2)
        }
        var rest = Array(arguments.dropFirst())
        let service = try SkillSetService(paths: paths)
        switch subcommand {
        case "preview":
            guard let url = rest.first, !url.hasPrefix("--") else {
                throw CLIError("sources preview 需要仓库根 URL。", exitCode: 2)
            }
            rest.removeFirst()
            let ref = consumeOption("--ref", from: &rest)
            let preview = try service.previewSource(urlString: url, ref: ref)
            if json {
                emitJSON(try jsonValue(preview))
            } else {
                print("预览 \(preview.canonicalURL)")
                print("commit：\(preview.resolvedCommit)")
                print("候选：\(preview.candidates.count) 个；许可：\(preview.licenseEvidence)")
                for candidate in preview.candidates {
                    let state = candidate.state.rawValue
                    let issue = candidate.issues.isEmpty ? "" : " · \(candidate.issues.joined(separator: "；"))"
                    print("  \(state)\t\(candidate.id)\t\(candidate.shortHash)\(issue)")
                }
                print("隔离区：\(preview.workspacePath)")
                print("已同步到技能库，可搜索；尚未启用或写入项目。")
            }
        case "list":
            let previews = try service.sourcePreviews()
            if json {
                emitJSON(["previews": try jsonValue(previews)])
            } else if previews.isEmpty {
                print("尚无来源预览。运行 `skillset sources preview <url>`。")
            } else {
                for preview in previews {
                    print("\(preview.id.uuidString)\t\(preview.resolvedCommit.prefix(12))\t\(preview.candidates.count) 个候选\t\(preview.canonicalURL)")
                }
            }
        case "show":
            guard let rawID = rest.first, let id = UUID(uuidString: rawID) else {
                throw CLIError("sources show 需要预览 UUID。", exitCode: 2)
            }
            let preview = try service.sourcePreview(id: id)
            if json {
                emitJSON(try jsonValue(preview))
            } else {
                print("\(preview.canonicalURL) @ \(preview.resolvedCommit)")
                print("许可：\(preview.licenseEvidence)")
                for candidate in preview.candidates {
                    print("  \(candidate.state.rawValue)\t\(candidate.id)\t\(candidate.description)")
                }
            }
        default:
            throw CLIError("未知 sources 子命令：\(subcommand)", exitCode: 2)
        }
    }

    private static func inspect(arguments: [String], paths: SkillSetRuntimePaths, json: Bool) throws {
        guard let rawID = arguments.first, let id = UUID(uuidString: rawID) else {
            throw CLIError("用法：skillset inspect <project-id> [--json]", exitCode: 2)
        }
        let service = try SkillSetService(paths: paths)
        guard let summary = try service.projects().first(where: { $0.id == id }) else {
            throw SkillSetStoreError.projectNotFound(rawID)
        }
        if json {
            emitJSON(["project": try jsonValue(summary)])
        } else {
            print("\(summary.name)  \(summary.path)")
            print("agents：\(summary.agents.joined(separator: ", "))")
            print("lock：\(summary.lockStatus)")
            print("desired：\(summary.desiredSkillIDs.joined(separator: ", "))")
            print("observed：\(summary.observedSkillIDs.joined(separator: ", "))")
            if !summary.issues.isEmpty {
                print("问题：")
                summary.issues.forEach { print("  \($0)") }
            }
        }
    }

    private static func plan(arguments: [String], paths: SkillSetRuntimePaths, json: Bool) throws {
        var rest = arguments
        guard let rawID = rest.first, let projectID = UUID(uuidString: rawID) else {
            throw CLIError("用法：skillset plan <project-id> --skills id1,id2 --instructions base-zh [--json]", exitCode: 2)
        }
        rest.removeFirst()
        let skills = splitList(consumeOption("--skills", from: &rest) ?? "")
        let instructions = splitList(consumeOption("--instructions", from: &rest) ?? "")
        let agents = splitList(consumeOption("--agents", from: &rest) ?? "")
        let ruleBlock = consumeOption("--rule-block", from: &rest) ?? "project-rules"
        guard let method = SkillInstallMethod(rawValue: consumeOption("--method", from: &rest) ?? "symlink") else {
            throw CLIError("--method 只能是 symlink 或 copy。", exitCode: 2)
        }
        let service = try SkillSetService(paths: paths)
        let record = try service.makePlan(
            projectID: projectID,
            skillIDs: skills,
            instructionIDs: instructions,
            agents: agents.isEmpty ? nil : agents,
            ruleBlockID: ruleBlock,
            installMethod: method
        )
        if json {
            emitJSON(try planJSON(record))
        } else {
            print("计划 \(record.id.uuidString)")
            print("digest：\(record.plan.digest)")
            print("项目：\(record.plan.projectPath)")
            for change in record.plan.changes {
                let target = change.scope == "project-state"
                    ? ProjectLockStore(projectRoot: URL(fileURLWithPath: record.plan.projectPath), stateRoot: paths.applicationSupportRoot).directoryURL.appendingPathComponent(change.relativePath).path
                    : change.relativePath
                print("  \(change.action)  \(target)")
            }
            print("等待人工批准：skillset approve \(record.id.uuidString)")
        }
    }

    private static func plans(arguments: [String], paths: SkillSetRuntimePaths, json: Bool) throws {
        guard arguments.first == "list" else {
            throw CLIError("用法：skillset plans list [--json]", exitCode: 2)
        }
        let plans = try SkillSetService(paths: paths).pendingPlans()
        if json {
            emitJSON(["plans": try plans.map(planJSON)])
        } else {
            for plan in plans {
                print("\(plan.id.uuidString)\t\(plan.approvalState.rawValue)\t\(plan.expiresAt.formatted(date: .abbreviated, time: .shortened))\t\(plan.plan.projectPath)")
            }
        }
    }

    private static func approve(arguments: [String], paths: SkillSetRuntimePaths, json: Bool) throws {
        var rest = arguments
        guard let rawID = rest.first, let id = UUID(uuidString: rawID) else {
            throw CLIError("用法：skillset approve <plan-id> [--digest ...]", exitCode: 2)
        }
        rest.removeFirst()
        let service = try SkillSetService(paths: paths)
        let digest: String
        if let provided = consumeOption("--digest", from: &rest) {
            digest = provided
        } else {
            digest = try service.plan(id).plan.digest
        }
        let record = try service.approve(planID: id, digest: digest)
        if json {
            emitJSON(try planJSON(record))
        } else {
            print("已人工批准计划 \(id.uuidString)")
            print("下一步：skillset apply \(id.uuidString) --digest \(digest)")
        }
    }

    private static func apply(arguments: [String], paths: SkillSetRuntimePaths, json: Bool) throws {
        var rest = arguments
        guard let rawID = rest.first, let id = UUID(uuidString: rawID) else {
            throw CLIError("用法：skillset apply <plan-id> [--digest ...]", exitCode: 2)
        }
        rest.removeFirst()
        let service = try SkillSetService(paths: paths)
        let digest: String
        if let provided = consumeOption("--digest", from: &rest) {
            digest = provided
        } else {
            digest = try service.plan(id).plan.digest
        }
        let result = try service.apply(planID: id, digest: digest)
        if json {
            emitJSON(try jsonValue(result))
        } else {
            print("已写入 \(result.changedPaths.count) 个受管路径")
            print("operation：\(result.operationID.uuidString)")
            print("journal：\(result.journalPath)")
            if let message = result.message {
                print("状态：\(message)")
            }
        }
    }

    private static func operations(arguments: [String], paths: SkillSetRuntimePaths, json: Bool) throws {
        var rest = arguments
        guard rest.first == "get" else {
            throw CLIError("用法：skillset operations get <operation-id> [--json]", exitCode: 2)
        }
        rest.removeFirst()
        guard let rawID = rest.first, let id = UUID(uuidString: rawID) else {
            throw CLIError("operations get 需要 operation UUID。", exitCode: 2)
        }
        let operation = try SkillSetService(paths: paths).operationInspection(id)
        if json {
            emitJSON(try jsonValue(operation))
        } else {
            print("operation：\(operation.operationID.uuidString)  kind=\(operation.kind.rawValue)  state=\(operation.state)")
            operation.steps.forEach { print("  \($0.state)  \($0.relativePath)") }
            if let plugin = operation.plugin {
                print("\(plugin.host.displayName) · \(plugin.action.displayName) · \(plugin.pluginID)")
                print("范围：\(plugin.scope.displayName)  工作目录：\(plugin.workingDirectory)")
                print("退出码：\(plugin.exitCode.map(String.init) ?? "未启动")")
                if !plugin.sanitizedStdout.isEmpty {
                    print("stdout：\(plugin.sanitizedStdout)")
                }
                if !plugin.sanitizedStderr.isEmpty {
                    print("stderr：\(plugin.sanitizedStderr)")
                }
                print("结果：\(plugin.message)")
            }
        }
    }

    private static func rollback(arguments: [String], paths: SkillSetRuntimePaths, json: Bool) throws {
        guard let rawID = arguments.first, let id = UUID(uuidString: rawID) else {
            throw CLIError("用法：skillset rollback <operation-id> [--json]", exitCode: 2)
        }
        let restored = try SkillSetService(paths: paths).rollback(operationID: id)
        if json {
            emitJSON(["operationId": id.uuidString, "restored": restored])
        } else {
            print("已回滚 \(restored.count) 个路径。")
        }
    }

    private static func mcp(arguments: [String], paths: SkillSetRuntimePaths, json: inout Bool) throws {
        guard let subcommand = arguments.first else {
            throw CLIError("用法：skillset mcp serve|servers|plan ...", exitCode: 2)
        }
        var rest = Array(arguments.dropFirst())
        let service = try SkillSetService(paths: paths)
        switch subcommand {
        case "serve":
            let transportIndex = rest.firstIndex(of: "--transport")
            let transport = transportIndex.flatMap { index in
                rest.indices.contains(index + 1) ? rest[index + 1] : nil
            } ?? "stdio"
            guard transport == "stdio" else {
                throw CLIError("首版只支持 stdio transport。", exitCode: 2)
            }
            MCPStdioServer(service: service).run()
        case "servers":
            let projectID = try optionalProjectID(consumeOption("--project", from: &rest))
            let inspections = try service.mcpConfigurations(projectID: projectID)
            if json {
                emitJSON(["configurations": try jsonValue(inspections)])
            } else {
                for inspection in inspections {
                    print("\(inspection.host.displayName) · \(inspection.scope.displayName) · \(inspection.exists ? "已存在" : "未创建")")
                    print("  \(inspection.configPath)")
                    for server in inspection.servers {
                        print("  \(server.managed ? "受管" : "观察")\t\(server.name)\t\(server.transport)\t变量 \(server.envKeys.joined(separator: ","))")
                    }
                    for issue in inspection.issues {
                        print("  问题：\(issue)")
                    }
                }
            }
        case "plan":
            guard let hostRaw = consumeOption("--host", from: &rest),
                  let host = MCPHost(rawValue: hostRaw),
                  let scopeRaw = consumeOption("--scope", from: &rest),
                  let scope = MCPConfigurationScope(rawValue: scopeRaw),
                  let name = consumeOption("--name", from: &rest) else {
                throw CLIError("mcp plan 需要 --host、--scope 和 --name。", exitCode: 2)
            }
            let projectID = try optionalProjectID(consumeOption("--project", from: &rest))
            let transport = consumeOption("--transport", from: &rest) ?? "stdio"
            let commandOrURL = consumeOption("--command", from: &rest)
                ?? consumeOption("--url", from: &rest)
                ?? ""
            let arguments = consumeAllOptions("--arg", from: &rest)
            let envKeys = consumeAllOptions("--env", from: &rest)
            let record = try service.makeMCPConfigPlan(
                projectID: projectID,
                draft: MCPConfigurationDraft(
                    name: name,
                    host: host,
                    scope: scope,
                    transport: transport,
                    commandOrURL: commandOrURL,
                    args: arguments,
                    envKeys: envKeys
                )
            )
            if json {
                emitJSON(try planJSON(record))
            } else {
                print("MCP 配置计划 \(record.id.uuidString)")
                print("digest：\(record.plan.digest)")
                print("目标：\(record.plan.metadata?["configPath"] ?? record.plan.projectPath)")
                print("等待本机人工批准：skillset approve \(record.id.uuidString)")
            }
        default:
            throw CLIError("未知 mcp 子命令：\(subcommand)", exitCode: 2)
        }
    }

    private static func optionalProjectID(_ rawValue: String?) throws -> UUID? {
        guard let rawValue else { return nil }
        guard let id = UUID(uuidString: rawValue) else {
            throw CLIError("--project 需要项目 UUID。", exitCode: 2)
        }
        return id
    }

    private static func objects(arguments: [String], paths: SkillSetRuntimePaths, json: Bool) throws {
        guard arguments.first == "verify" else {
            throw CLIError("用法：skillset objects verify [--project ID] [--json]", exitCode: 2)
        }
        var rest = Array(arguments.dropFirst())
        let projectID = try consumeOption("--project", from: &rest).map { rawValue -> UUID in
            guard let id = UUID(uuidString: rawValue) else {
                throw CLIError("--project 需要项目 UUID。", exitCode: 2)
            }
            return id
        }
        let verification = try SkillSetService(paths: paths).verifyProjectObjects(projectID: projectID)
        if json {
            emitJSON(try jsonValue(verification))
        } else {
            print("离线对象核验通过：\(verification.checkedObjects) 个对象，\(verification.checkedBytes) 字节。")
        }
    }

    private static func plugins(arguments: [String], paths: SkillSetRuntimePaths, json: Bool) throws {
        guard let subcommand = arguments.first else {
            throw CLIError(
                "用法：skillset plugins list|plan ...",
                exitCode: 2
            )
        }
        var rest = Array(arguments.dropFirst())
        let service = try SkillSetService(paths: paths)
        switch subcommand {
        case "list":
            let projectID = try consumeOption("--project", from: &rest).map { rawValue -> UUID in
                guard let id = UUID(uuidString: rawValue) else {
                    throw CLIError("--project 需要项目 UUID。", exitCode: 2)
                }
                return id
            }
            let snapshot = try service.plugins(projectID: projectID)
            if json {
                emitJSON([
                    "plugins": try jsonValue(snapshot.records),
                    "issues": snapshot.issues,
                    "scannedRoots": snapshot.scannedRoots
                ])
            } else if snapshot.records.isEmpty {
                print("没有发现插件 manifest。")
            } else {
                for plugin in snapshot.records {
                    let components = plugin.components.isEmpty ? "manifest" : plugin.components.joined(separator: ",")
                    print(
                        "\(plugin.host.rawValue)\t\(plugin.pluginID)\t"
                            + "\(plugin.version ?? "未声明")\t\(plugin.state)\t\(components)"
                    )
                    print("  \(plugin.sourcePath)")
                }
                if !snapshot.issues.isEmpty {
                    print("读取问题：")
                    snapshot.issues.forEach { print("  \($0)") }
                }
            }
        case "plan":
            guard let hostRaw = consumeOption("--host", from: &rest),
                  let host = MCPHost(rawValue: hostRaw),
                  let pluginID = consumeOption("--plugin", from: &rest),
                  let actionRaw = consumeOption("--action", from: &rest),
                  let action = PluginLifecycleAction(rawValue: actionRaw) else {
                throw CLIError(
                    "plugins plan 需要 --host、--plugin 和 --action（install/update/enable/disable/uninstall）。",
                    exitCode: 2
                )
            }
            let scope = try consumeOption("--scope", from: &rest).map { rawValue -> PluginLifecycleScope in
                guard let value = PluginLifecycleScope(rawValue: rawValue) else {
                    throw CLIError("--scope 只能是 user、project 或 local。", exitCode: 2)
                }
                return value
            }
            let projectID = try consumeOption("--project", from: &rest).map { rawValue -> UUID in
                guard let id = UUID(uuidString: rawValue) else {
                    throw CLIError("--project 需要项目 UUID。", exitCode: 2)
                }
                return id
            }
            let keepData = consumeFlag("--remove-data", from: &rest) ? false : true
            let acknowledged = consumeFlag(
                "--acknowledge-executable-components",
                from: &rest
            )
            let manifestDigest = consumeOption("--manifest-digest", from: &rest)
            let record = try service.makePluginLifecyclePlan(
                projectID: projectID,
                request: PluginLifecycleRequest(
                    host: host,
                    pluginID: pluginID,
                    action: action,
                    scope: scope,
                    expectedManifestDigest: manifestDigest,
                    keepData: keepData,
                    acknowledgeExecutableComponents: acknowledged
                )
            )
            if json {
                emitJSON(try planJSON(record))
            } else {
                print("Plugin 变更计划 \(record.id.uuidString)")
                print("digest：\(record.plan.digest)")
                print(
                    "目标 manifest："
                        + (record.plan.metadata?["pluginExpectedManifestDigest"].flatMap {
                            $0.isEmpty ? nil : $0
                        } ?? "未指定（仅允许唯一记录）")
                )
                print("命令：\(record.plan.metadata?["pluginCommandPreview"] ?? "未记录")")
                record.plan.warnings.forEach { print("  \($0)") }
                print("等待人工批准：skillset approve \(record.id.uuidString)")
            }
        default:
            throw CLIError("未知 plugins 子命令：\(subcommand)", exitCode: 2)
        }
    }

    private static func planJSON(_ record: StoredDeploymentPlan) throws -> [String: Any] {
        [
            "planId": record.id.uuidString,
            "digest": record.plan.digest,
            "projectPath": record.plan.projectPath,
            "createdAt": ISO8601DateFormatter().string(from: record.plan.createdAt),
            "expiresAt": ISO8601DateFormatter().string(from: record.expiresAt),
            "approvalState": record.approvalState.rawValue,
            "approvalRequired": record.approvalState == .pending,
            "changes": try jsonValue(record.plan.changes),
            "warnings": record.plan.warnings,
            "metadata": record.plan.metadata ?? [:]
        ]
    }

    private static func consumeOption(_ name: String, from arguments: inout [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
            return nil
        }
        let value = arguments[index + 1]
        arguments.removeSubrange(index...(index + 1))
        return value
    }

    private static func consumeFlag(_ name: String, from arguments: inout [String]) -> Bool {
        guard let index = arguments.firstIndex(of: name) else { return false }
        arguments.remove(at: index)
        return true
    }

    private static func consumeAllOptions(_ name: String, from arguments: inout [String]) -> [String] {
        var values: [String] = []
        while let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) {
            values.append(arguments[index + 1])
            arguments.removeSubrange(index...(index + 1))
        }
        return values
    }

    private static func splitList(_ value: String) -> [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

struct CLIError: Error, LocalizedError, Sendable {
    let message: String
    let exitCode: Int32

    init(_ message: String, exitCode: Int32 = 1) {
        self.message = message
        self.exitCode = exitCode
    }

    var errorDescription: String? { message }
}

func emitJSON(_ object: Any) {
    do {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
        let fallback = "{\"error\":{\"code\":\"JSON_ENCODING_FAILED\",\"message\":\"无法编码 JSON\"}}\n"
        FileHandle.standardOutput.write(Data(fallback.utf8))
    }
}

func jsonValue<T: Encodable>(_ value: T) throws -> Any {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.withoutEscapingSlashes]
    let data = try encoder.encode(value)
    return try JSONSerialization.jsonObject(with: data)
}

private func jsonValue(_ value: Any) throws -> Any {
    if JSONSerialization.isValidJSONObject(value) {
        return value
    }
    return NSNull()
}

private func emitError(_ error: Error, json: Bool) {
    let code = (error as? SkillSetCodedError)?.code ?? (error as? CLIError).map { $0.exitCode == 2 ? "INVALID_ARGUMENT" : "COMMAND_FAILED" } ?? "COMMAND_FAILED"
    let message = error.localizedDescription
    let exitCode: Int32 = {
        if let error = error as? CLIError { return error.exitCode }
        switch code {
        case "APPROVAL_REQUIRED", "APPROVAL_EXPIRED", "PLAN_EXPIRED", "PLUGIN_RISK_APPROVAL_REQUIRED": return 4
        case "PLAN_STALE", "PLAN_DIGEST_MISMATCH", "PLAN_ALREADY_APPLIED", "RECOVERY_REQUIRED", "PROJECT_LOCK_STALE", "SKILL_TARGET_CONFLICT", "SKILL_MANAGED_DRIFT", "RULE_TARGET_CONFLICT", "RULE_MANAGED_DRIFT", "PLUGIN_STATE_STALE", "PLUGIN_EXECUTION_UNCERTAIN": return 3
        case "SOURCE_INVALID_URL", "SOURCE_INVALID_REF", "SOURCE_CREDENTIALS_REJECTED", "SOURCE_HOST_NOT_ALLOWED", "AGENT_UNSUPPORTED", "PLUGIN_ID_INVALID", "PLUGIN_SCOPE_UNSUPPORTED", "PLUGIN_SCOPE_AMBIGUOUS", "PLUGIN_VERSION_AMBIGUOUS", "PLUGIN_VERSION_NOT_FOUND", "PLUGIN_MANIFEST_DIGEST_INVALID", "PLUGIN_PROJECT_REQUIRED", "PLUGIN_ACTION_UNSUPPORTED": return 2
        case "REPOSITORY_NOT_FOUND", "SKILL_SOURCE_MISSING", "OFFLINE_OBJECT_MISSING", "OFFLINE_OBJECT_CORRUPT": return 5
        default: return 1
        }
    }()
    if json {
        emitJSON(["error": ["code": code, "message": message]])
    } else {
        FileHandle.standardError.write(Data("错误 [\(code)]：\(message)\n".utf8))
    }
    exit(exitCode)
}

private extension SourceSkillCandidate {
    var shortHash: String {
        contentHash.isEmpty ? "无指纹" : String(contentHash.prefix(12))
    }
}
