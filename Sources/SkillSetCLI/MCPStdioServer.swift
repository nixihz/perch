import Foundation
import SkillSetCore

final class MCPStdioServer {
    private let service: SkillSetService

    init(service: SkillSetService) {
        self.service = service
    }

    func run() {
        while let line = readLine() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            handle(line: trimmed)
        }
    }

    private func handle(line: String) {
        guard let data = line.data(using: .utf8),
              let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            write(errorResponse(id: NSNull(), code: -32700, message: "JSON-RPC 消息无法解析"))
            return
        }
        let id = request["id"]
        guard request["jsonrpc"] as? String == "2.0",
              let method = request["method"] as? String else {
            if let id { write(errorResponse(id: id, code: -32600, message: "无效的 JSON-RPC 请求")) }
            return
        }

        switch method {
        case "initialize":
            guard let id else { return }
            write(resultResponse(id: id, result: [
                "protocolVersion": "2025-11-25",
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "skill-set", "version": "0.1.0"],
                "instructions": "Skill Set 的来源预览、只读查询和计划生成不会写项目；部署写入必须先在本机 UI 或 CLI 批准同一 plan digest。"
            ]))
        case "notifications/initialized", "notifications/cancelled":
            return
        case "ping":
            if let id { write(resultResponse(id: id, result: [:])) }
        case "tools/list":
            if let id { write(resultResponse(id: id, result: ["tools": tools])) }
        case "tools/call":
            guard let id else { return }
            let params = request["params"] as? [String: Any] ?? [:]
            guard let name = params["name"] as? String else {
                write(errorResponse(id: id, code: -32602, message: "tools/call 缺少 name"))
                return
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            write(resultResponse(id: id, result: callTool(name: name, arguments: arguments)))
        default:
            if let id {
                write(errorResponse(id: id, code: -32601, message: "不支持的 method：\(method)"))
            }
        }
    }

    private func callTool(name: String, arguments: [String: Any]) -> [String: Any] {
        do {
            switch name {
            case "projects_list":
                let projects = try service.projects()
                let structured: [String: Any] = ["projects": try jsonValue(projects)]
                return toolResult(isError: false, text: "已读取 \(projects.count) 个项目。", structured: structured)

            case "skills_search":
                let query = arguments["query"] as? String ?? ""
                let sourceID = arguments["sourceId"] as? String
                let limit = min(max(arguments["limit"] as? Int ?? 50, 1), 200)
                let entries = Array(service.skills(query: query, sourceID: sourceID).prefix(limit))
                return toolResult(
                    isError: false,
                    text: "找到 \(entries.count) 个 Skill。",
                    structured: ["count": entries.count, "skills": try jsonValue(entries)]
                )

            case "sources_list":
                let previews = try service.sourcePreviews()
                return toolResult(
                    isError: false,
                    text: "有 \(previews.count) 个已保存的来源预览。",
                    structured: ["previews": try jsonValue(previews)]
                )

            case "sources_preview":
                guard let url = arguments["url"] as? String, !url.isEmpty else {
                    throw MCPToolError(code: "INVALID_ARGUMENTS", message: "sources_preview 需要仓库根 URL。")
                }
                let ref = arguments["ref"] as? String
                let preview = try service.previewSource(urlString: url, ref: ref)
                return toolResult(
                    isError: false,
                    text: "已隔离预览 \(preview.candidates.count) 个候选；尚未收录或启用。",
                    structured: try castObject(jsonValue(preview))
                )

            case "projects_inspect":
                let id = try requiredUUID(arguments, key: "projectId")
                guard let project = try service.projects().first(where: { $0.id == id }) else {
                    throw SkillSetStoreError.projectNotFound(id.uuidString)
                }
                return toolResult(
                    isError: false,
                    text: "项目 \(project.name)：desired \(project.desiredSkillIDs.count)，observed \(project.observedSkillIDs.count)。",
                    structured: ["project": try jsonValue(project)]
                )

            case "deployment_plan":
                let id = try requiredUUID(arguments, key: "projectId")
                let skillIDs = arguments["skillIds"] as? [String] ?? []
                let instructionIDs = arguments["instructionIds"] as? [String] ?? []
                let agents = arguments["agents"] as? [String]
                let ruleBlockID = arguments["ruleBlockId"] as? String ?? "project-rules"
                let record = try service.makePlan(
                    projectID: id,
                    skillIDs: skillIDs,
                    instructionIDs: instructionIDs,
                    agents: agents,
                    ruleBlockID: ruleBlockID
                )
                return toolResult(
                    isError: false,
                    text: "已生成计划 \(record.id.uuidString)。需要本机人工批准后才能 apply。",
                    structured: planObject(record)
                )

            case "deployment_apply":
                let id = try requiredUUID(arguments, key: "planId")
                guard let digest = arguments["planDigest"] as? String, !digest.isEmpty else {
                    throw MCPToolError(code: "INVALID_ARGUMENTS", message: "deployment_apply 需要完整 planDigest。")
                }
                let result = try service.apply(planID: id, digest: digest)
                return toolResult(
                    isError: false,
                    text: result.message ?? "已执行 \(result.changedPaths.count) 个受管目标。",
                    structured: try castObject(jsonValue(result))
                )

            case "plans_pending":
                let plans = try service.pendingPlans()
                return toolResult(
                    isError: false,
                    text: "有 \(plans.count) 个待审计划。",
                    structured: ["plans": plans.map(planObject)]
                )

            case "operations_get":
                let id = try requiredUUID(arguments, key: "operationId")
                let operation = try service.operationInspection(id)
                return toolResult(
                    isError: false,
                    text: "操作 \(id.uuidString)（\(operation.kind.rawValue)）状态：\(operation.state)。",
                    structured: ["operation": try jsonValue(operation)]
                )

            case "objects_verify":
                let projectID: UUID?
                if let rawID = arguments["projectId"] as? String {
                    guard let id = UUID(uuidString: rawID) else {
                        throw MCPToolError(code: "INVALID_ARGUMENTS", message: "projectId 必须是 UUID。")
                    }
                    projectID = id
                } else {
                    projectID = nil
                }
                let verification = try service.verifyProjectObjects(projectID: projectID)
                return toolResult(
                    isError: false,
                    text: "离线对象核验通过：\(verification.checkedObjects) 个。",
                    structured: try castObject(jsonValue(verification))
                )

            case "mcp_servers_list":
                let projectID = try optionalUUID(arguments, key: "projectId")
                let inspections = try service.mcpConfigurations(projectID: projectID)
                return toolResult(
                    isError: false,
                    text: "读取 \(inspections.count) 个 MCP 配置目标。",
                    structured: ["configurations": try jsonValue(inspections)]
                )

            case "mcp_config_plan":
                guard let hostRaw = arguments["host"] as? String,
                      let host = MCPHost(rawValue: hostRaw),
                      let scopeRaw = arguments["scope"] as? String,
                      let scope = MCPConfigurationScope(rawValue: scopeRaw),
                      let name = arguments["name"] as? String else {
                    throw MCPToolError(code: "INVALID_ARGUMENTS", message: "mcp_config_plan 需要 host、scope 和 name。")
                }
                let projectID = try optionalUUID(arguments, key: "projectId")
                let record = try service.makeMCPConfigPlan(
                    projectID: projectID,
                    draft: MCPConfigurationDraft(
                        name: name,
                        host: host,
                        scope: scope,
                        transport: arguments["transport"] as? String ?? "stdio",
                        commandOrURL: arguments["commandOrURL"] as? String ?? "",
                        args: arguments["args"] as? [String] ?? [],
                        envKeys: arguments["envKeys"] as? [String] ?? []
                    )
                )
                return toolResult(
                    isError: false,
                    text: "已生成 MCP 配置计划 \(record.id.uuidString)；需要本机人工批准。",
                    structured: planObject(record)
                )

            case "plugins_list":
                let projectID = try optionalUUID(arguments, key: "projectId")
                let snapshot = try service.plugins(projectID: projectID)
                let installed = snapshot.records.filter(\.installed).count
                return toolResult(
                    isError: false,
                    text: "读取 \(snapshot.records.count) 个插件 manifest，其中 \(installed) 个已安装。",
                    structured: [
                        "plugins": try jsonValue(snapshot.records),
                        "issues": snapshot.issues,
                        "scannedRoots": snapshot.scannedRoots
                    ]
                )

            case "plugin_lifecycle_plan":
                guard let hostRaw = arguments["host"] as? String,
                      let host = MCPHost(rawValue: hostRaw),
                      let pluginID = arguments["pluginId"] as? String,
                      let actionRaw = arguments["action"] as? String,
                      let action = PluginLifecycleAction(rawValue: actionRaw) else {
                    throw MCPToolError(
                        code: "INVALID_ARGUMENTS",
                        message: "plugin_lifecycle_plan 需要 host、pluginId 和 action。"
                    )
                }
                let scope: PluginLifecycleScope?
                if let scopeRaw = arguments["scope"] as? String {
                    guard let value = PluginLifecycleScope(rawValue: scopeRaw) else {
                        throw MCPToolError(
                            code: "INVALID_ARGUMENTS",
                            message: "scope 只能是 user、project 或 local。"
                        )
                    }
                    scope = value
                } else {
                    scope = nil
                }
                let projectID = try optionalUUID(arguments, key: "projectId")
                let record = try service.makePluginLifecyclePlan(
                    projectID: projectID,
                    request: PluginLifecycleRequest(
                        host: host,
                        pluginID: pluginID,
                        action: action,
                        scope: scope,
                        expectedManifestDigest: arguments["manifestDigest"] as? String,
                        keepData: arguments["keepData"] as? Bool ?? true,
                        acknowledgeExecutableComponents: false
                    )
                )
                return toolResult(
                    isError: false,
                    text: "已生成 Plugin 生命周期计划 \(record.id.uuidString)；需要本机人工批准。",
                    structured: planObject(record)
                )

            default:
                throw MCPToolError(code: "TOOL_NOT_FOUND", message: "未知工具：\(name)")
            }
        } catch {
            let code = (error as? SkillSetCodedError)?.code
                ?? (error as? MCPToolError)?.code
                ?? "TOOL_EXECUTION_FAILED"
            let message = error.localizedDescription
            return toolResult(
                isError: true,
                text: "\(code)：\(message)",
                structured: ["code": code, "message": message]
            )
        }
    }

    private var tools: [[String: Any]] {
        [
            tool(
                name: "projects_list",
                description: "列出本机已登记项目及其 desired / observed Skills。",
                properties: [:],
                required: [],
                readOnly: true
            ),
            tool(
                name: "skills_search",
                description: "按名称、namespace 或描述搜索本地 Skill catalog。",
                properties: [
                    "query": ["type": "string", "maxLength": 200],
                    "sourceId": ["type": "string"],
                    "limit": ["type": "integer", "minimum": 1, "maximum": 200]
                ],
                required: ["query"],
                readOnly: true
            ),
            tool(
                name: "sources_list",
                description: "列出已保存的隔离来源预览、固定 commit 和候选数量。",
                properties: [:],
                required: [],
                readOnly: true
            ),
            tool(
                name: "sources_preview",
                description: "隔离 clone 受信任 GitHub 仓库根并读取候选；不执行脚本，不收录或启用。",
                properties: [
                    "url": ["type": "string", "maxLength": 2_048],
                    "ref": ["type": "string", "maxLength": 256]
                ],
                required: ["url"],
                readOnly: false,
                destructive: false,
                idempotent: false,
                openWorld: true
            ),
            tool(
                name: "projects_inspect",
                description: "读取项目 desired、observed 和完整性提示。",
                properties: ["projectId": ["type": "string", "format": "uuid"]],
                required: ["projectId"],
                readOnly: true
            ),
            tool(
                name: "deployment_plan",
                description: "生成绑定真实路径、旧 hash 和新 hash 的变更计划；不会写入。",
                properties: [
                    "projectId": ["type": "string", "format": "uuid"],
                    "skillIds": ["type": "array", "items": ["type": "string"], "maxItems": 200],
                    "instructionIds": ["type": "array", "items": ["type": "string"], "maxItems": 20],
                    "agents": [
                        "type": "array",
                        "items": ["type": "string", "enum": ["codex", "claude-code"]],
                        "minItems": 1,
                        "maxItems": 2
                    ],
                    "ruleBlockId": ["type": "string"]
                ],
                required: ["projectId", "skillIds"],
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
            tool(
                name: "deployment_apply",
                description: "只执行已由本机 UI 或 CLI 人工批准且 digest 完全一致的项目、MCP 或 Plugin 计划。",
                properties: [
                    "planId": ["type": "string", "format": "uuid"],
                    "planDigest": ["type": "string", "minLength": 64, "maxLength": 64]
                ],
                required: ["planId", "planDigest"],
                readOnly: false
            ),
            tool(
                name: "plans_pending",
                description: "列出未执行且未过期的计划，供用户打开本机 UI 审批。",
                properties: [:],
                required: [],
                readOnly: true
            ),
            tool(
                name: "operations_get",
                description: "读取写入 journal、逐步状态和恢复信息。",
                properties: ["operationId": ["type": "string", "format": "uuid"]],
                required: ["operationId"],
                readOnly: true
            ),
            tool(
                name: "objects_verify",
                description: "核验项目锁引用的离线对象是否存在且 hash 一致；可选 projectId 限定一个项目。",
                properties: ["projectId": ["type": "string", "format": "uuid"]],
                required: [],
                readOnly: true
            ),
            tool(
                name: "mcp_servers_list",
                description: "读取 Codex TOML 和 Claude JSON 的 MCP Server 名称、transport 与变量名；不返回凭据值。",
                properties: ["projectId": ["type": "string", "format": "uuid"]],
                required: [],
                readOnly: true
            ),
            tool(
                name: "mcp_config_plan",
                description: "生成新增或管理受管 MCP Server 的配置计划；不会在批准前写宿主配置。",
                properties: [
                    "projectId": ["type": "string", "format": "uuid"],
                    "host": ["type": "string", "enum": ["codex", "claude-code"]],
                    "scope": ["type": "string", "enum": ["project", "user"]],
                    "name": ["type": "string", "maxLength": 64],
                    "transport": ["type": "string", "enum": ["stdio", "streamable-http"]],
                    "commandOrURL": ["type": "string", "maxLength": 2_048],
                    "args": ["type": "array", "items": ["type": "string"], "maxItems": 64],
                    "envKeys": ["type": "array", "items": ["type": "string"], "maxItems": 32]
                ],
                required: ["host", "scope", "name", "transport", "commandOrURL"],
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
            tool(
                name: "plugins_list",
                description: "读取 Claude Code 与 Codex 插件缓存、安装索引、组件和 hooks 风险；不执行插件代码。",
                properties: ["projectId": ["type": "string", "format": "uuid"]],
                required: [],
                readOnly: true
            ),
            tool(
                name: "plugin_lifecycle_plan",
                description: "基于本机已发现插件生成安装、更新、启用、停用或卸载计划；不批准、不执行宿主命令。含 hooks/commands/MCP 的安装或更新仍需本机人工确认。",
                properties: [
                    "projectId": ["type": "string", "format": "uuid"],
                    "host": ["type": "string", "enum": ["claude-code", "codex"]],
                    "pluginId": ["type": "string", "minLength": 1, "maxLength": 200],
                    "action": [
                        "type": "string",
                        "enum": ["install", "update", "enable", "disable", "uninstall"]
                    ],
                    "scope": ["type": "string", "enum": ["user", "project", "local"]],
                    "manifestDigest": [
                        "type": "string",
                        "pattern": "^[a-fA-F0-9]{64}$"
                    ],
                    "keepData": ["type": "boolean"]
                ],
                required: ["host", "pluginId", "action"],
                readOnly: false,
                destructive: false,
                idempotent: false
            )
        ]
    }

    private func tool(
        name: String,
        description: String,
        properties: [String: Any],
        required: [String],
        readOnly: Bool,
        destructive: Bool? = nil,
        idempotent: Bool = true,
        openWorld: Bool = false
    ) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object",
                "additionalProperties": false,
                "properties": properties,
                "required": required
            ],
            "annotations": [
                "readOnlyHint": readOnly,
                "destructiveHint": destructive ?? !readOnly,
                "idempotentHint": idempotent,
                "openWorldHint": openWorld
            ]
        ]
    }

    private func planObject(_ record: StoredDeploymentPlan) -> [String: Any] {
        [
            "planId": record.id.uuidString,
            "digest": record.plan.digest,
            "projectPath": record.plan.projectPath,
            "createdAt": ISO8601DateFormatter().string(from: record.plan.createdAt),
            "expiresAt": ISO8601DateFormatter().string(from: record.expiresAt),
            "approvalState": record.approvalState.rawValue,
            "approvalRequired": record.approvalState == .pending,
            "changes": (try? jsonValue(record.plan.changes)) ?? [],
            "warnings": record.plan.warnings,
            "metadata": record.plan.metadata ?? [:]
        ]
    }

    private func requiredUUID(_ arguments: [String: Any], key: String) throws -> UUID {
        guard let value = arguments[key] as? String, let id = UUID(uuidString: value) else {
            throw MCPToolError(code: "INVALID_ARGUMENTS", message: "\(key) 必须是 UUID。")
        }
        return id
    }

    private func optionalUUID(_ arguments: [String: Any], key: String) throws -> UUID? {
        guard let value = arguments[key] as? String, !value.isEmpty else { return nil }
        guard let id = UUID(uuidString: value) else {
            throw MCPToolError(code: "INVALID_ARGUMENTS", message: "\(key) 必须是 UUID。")
        }
        return id
    }

    private func castObject(_ value: Any) throws -> [String: Any] {
        guard let object = value as? [String: Any] else {
            throw MCPToolError(code: "INTERNAL_ERROR", message: "结构化结果不是对象。")
        }
        return object
    }

    private func toolResult(isError: Bool, text: String, structured: [String: Any]) -> [String: Any] {
        [
            "content": [["type": "text", "text": text]],
            "structuredContent": structured,
            "isError": isError
        ]
    }

    private func resultResponse(id: Any, result: Any) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func errorResponse(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    private func write(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

private struct MCPToolError: Error, LocalizedError, Sendable {
    let code: String
    let message: String

    var errorDescription: String? { message }
}
