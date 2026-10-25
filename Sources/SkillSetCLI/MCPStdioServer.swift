import Foundation
import SkillSetCore

final class MCPStdioServer {
    private var libraryCache: MCPServiceCache
    /// 工具定义只依赖服务类型，不随本机状态变化；缓存后避免每次 tools/list 和参数校验重复组装 60 个 schema。
    private lazy var cachedTools: [[String: Any]] = makeTools()
    lazy var cachedToolByName: [String: [String: Any]] = Dictionary(
        uniqueKeysWithValues: cachedTools.compactMap { definition in
            guard let name = definition["name"] as? String else { return nil }
            return (name, definition)
        }
    )

    init(service: SkillSetService) {
        libraryCache = MCPServiceCache(service: service)
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
              let object = try? JSONSerialization.jsonObject(with: data) else {
            write(errorResponse(id: NSNull(), code: -32700, message: "JSON-RPC 消息无法解析"))
            return
        }
        if let batch = object as? [Any] {
            if batch.isEmpty {
                write(errorResponse(id: NSNull(), code: -32600, message: "空的 JSON-RPC 批量请求"))
                return
            }
            var responses: [[String: Any]] = []
            responses.reserveCapacity(batch.count)
            for item in batch {
                guard let request = item as? [String: Any] else {
                    responses.append(errorResponse(id: NSNull(), code: -32600, message: "无效的 JSON-RPC 批量项"))
                    continue
                }
                if let response = handleRequest(request) { responses.append(response) }
            }
            if !responses.isEmpty { writeJSON(responses) }
            return
        }
        guard let request = object as? [String: Any] else {
            write(errorResponse(id: NSNull(), code: -32600, message: "无效的 JSON-RPC 请求"))
            return
        }
        if let response = handleRequest(request) { write(response) }
    }

    private func handleRequest(_ request: [String: Any]) -> [String: Any]? {
        let id = request["id"]
        guard request["jsonrpc"] as? String == "2.0",
              let method = request["method"] as? String else {
            return id.map { errorResponse(id: $0, code: -32600, message: "无效的 JSON-RPC 请求") }
        }

        switch method {
        case "initialize":
            guard let id else { return nil }
            return resultResponse(id: id, result: [
                "protocolVersion": "2025-11-25",
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "perch", "version": "0.1.0"],
                "instructions": "Perch：支持技能库、来源、片段、预设、项目和 MCP 配置库的增删改查；库删除不卸载已部署内容。用 templates_list 读取规则片段，用 global_config_plan 或 deployment_plan 生成应用/移除计划。用 presets_list 列出预设、skills_search 搜索技能；用 skills_install 或 presets_install 为明确的已登记项目生成追加安装计划。mcp_batch 可在单请求内顺序处理最多 50 项工具调用。projectPath 必须是调用方当前项目的绝对路径，不能猜测服务工作目录。用户在本机 UI 或 CLI 批准后，再调用 deployment_apply 完成安装。"
            ])
        case "notifications/initialized", "notifications/cancelled":
            return nil
        case "ping":
            return id.map { resultResponse(id: $0, result: [:]) }
        case "tools/list":
            return id.map { resultResponse(id: $0, result: ["tools": tools]) }
        case "tools/call":
            guard let id else { return nil }
            let params = request["params"] as? [String: Any] ?? [:]
            guard let name = params["name"] as? String else {
                return errorResponse(id: id, code: -32602, message: "tools/call 缺少 name")
            }
            if let arguments = params["arguments"], !(arguments is [String: Any]) {
                return errorResponse(id: id, code: -32602, message: "arguments 必须是对象")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            return resultResponse(id: id, result: callTool(name: name, arguments: arguments))
        default:
            return id.map { errorResponse(id: $0, code: -32601, message: "不支持的 method：\(method)") }
        }
    }

    private func callTool(name: String, arguments: [String: Any]) -> [String: Any] {
        callTool(name: name, arguments: arguments, serviceOverride: nil)
    }

    private func callTool(
        name: String, arguments: [String: Any], serviceOverride: SkillSetService?
    ) -> [String: Any] {
        do {
            try validateToolArguments(name: name, arguments: arguments)
            // 技能索引、片段和预设未变化时复用已解析快照；变化后重新加载。项目和计划仍按调用读盘。
            let current: SkillSetService
            if let serviceOverride {
                current = serviceOverride
            } else {
                current = try libraryCache.current()
            }
            if name == "mcp_batch" {
                return try callBatch(arguments: arguments, service: current)
            }
            if let result = try callManagementTool(name: name, arguments: arguments, current: current) { return result }
            let service = current
            switch name {
            case "presets_list":
                let presets = try service.presets(query: arguments["query"] as? String ?? "")
                return toolResult(isError: false, text: "找到 \(presets.count) 个预设。",
                                  structured: ["count": presets.count, "presets": try jsonValue(presets)])

            case "skills_install", "presets_install":
                let projectID = try optionalUUID(arguments, key: "projectId")
                let projectPath = arguments["projectPath"] as? String
                let skillIDs: [String]
                let presetID: String?
                if name == "skills_install" {
                    guard let values = arguments["skillIds"] as? [String], !values.isEmpty else {
                        throw MCPToolError(code: "INVALID_ARGUMENTS", message: "skills_install 需要非空 skillIds。")
                    }
                    skillIDs = values
                    presetID = nil
                } else {
                    guard let value = arguments["presetId"] as? String, !value.isEmpty else {
                        throw MCPToolError(code: "INVALID_ARGUMENTS", message: "presets_install 需要 presetId。")
                    }
                    skillIDs = []
                    presetID = value
                }
                if let value = arguments["agents"], !(value is [String]) {
                    throw MCPToolError(code: "INVALID_ARGUMENTS", message: "agents 必须是宿主名称数组。")
                }
                let agents = arguments["agents"] as? [String]
                if let agents, agents.isEmpty || agents.contains(where: { !AgentDeploymentAdapter.supportedAgents.contains($0) }) {
                    throw MCPToolError(code: "INVALID_ARGUMENTS", message: "agents 只能包含 codex、claude-code，且不能为空。")
                }
                let record = try current.makeInstallationPlan(projectID: projectID, projectPath: projectPath,
                                                              skillIDs: skillIDs, presetID: presetID, agents: agents)
                var result = planObject(record)
                result["status"] = "awaiting-approval"
                result["nextTool"] = "deployment_apply"
                result["nextArguments"] = ["planId": record.id.uuidString, "planDigest": record.plan.digest]
                return toolResult(isError: false,
                                  text: "已准备项目安装计划；尚未安装。请在栖集审阅批准，再调用 deployment_apply。",
                                  structured: result)

            case "projects_list":
                let projects = try service.projects()
                let structured: [String: Any] = ["projects": try jsonValue(projects)]
                return toolResult(isError: false, text: "已读取 \(projects.count) 个项目。", structured: structured)

            case "skills_search":
                let query = arguments["query"] as? String ?? ""
                let sourceID = arguments["sourceId"] as? String
                let limit = min(max(arguments["limit"] as? Int ?? 50, 1), 200)
                let entries = Array(current.skills(query: query, sourceID: sourceID).prefix(limit))
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
                guard let method = SkillInstallMethod(rawValue: arguments["installMethod"] as? String ?? "symlink") else {
                    throw MCPToolError(code: "INVALID_ARGUMENTS", message: "installMethod 只能是 symlink 或 copy。")
                }
                let record = try service.makePlan(
                    projectID: id,
                    skillIDs: skillIDs,
                    instructionIDs: instructionIDs,
                    agents: agents,
                    ruleBlockID: ruleBlockID,
                    installMethod: method
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

    /// 在一个 MCP 调用内顺序处理多项操作。读操作共享服务快照；技能索引、片段或预设一旦变化就刷新，
    /// 使本批后续项看到刚才的写入。单项失败不会吞掉同批其它结果。
    private func callBatch(arguments: [String: Any], service initial: SkillSetService) throws -> [String: Any] {
        guard let operations = arguments["operations"] as? [[String: Any]],
              !operations.isEmpty, operations.count <= 50 else {
            throw MCPToolError(code: "INVALID_ARGUMENTS", message: "mcp_batch 需要非空 operations。")
        }
        var current = initial
        var generation = libraryCache.generation
        var results: [[String: Any]] = []
        results.reserveCapacity(operations.count)
        var succeeded = 0
        for (index, operation) in operations.enumerated() {
            guard let name = operation["name"] as? String, !name.isEmpty,
                  name != "mcp_batch" else {
                let result = toolResult(isError: true, text: "INVALID_ARGUMENTS：批量项必须包含 name 和对象 arguments。",
                                        structured: ["code": "INVALID_ARGUMENTS", "message": "第 \(index) 项格式无效。"])
                results.append(["index": index, "name": operation["name"] as? String ?? "", "result": result])
                continue
            }
            guard operation["arguments"] == nil || operation["arguments"] is [String: Any] else {
                let result = toolResult(isError: true, text: "INVALID_ARGUMENTS：批量项 arguments 必须是对象。",
                                        structured: ["code": "INVALID_ARGUMENTS", "message": "第 \(index) 项 arguments 格式无效。"])
                results.append(["index": index, "name": name, "result": result])
                continue
            }
            let args = operation["arguments"] as? [String: Any] ?? [:]
            let result = callTool(name: name, arguments: args, serviceOverride: current)
            if result["isError"] as? Bool != true { succeeded += 1 }
            results.append(["index": index, "name": name, "result": result])
            let now = MCPLibraryGeneration.capture(paths: libraryCache.paths)
            guard now != generation else { continue }
            do {
                current = try libraryCache.reload()
                generation = libraryCache.generation
            } catch {
                let message = error.localizedDescription
                for remaining in operations.indices.dropFirst(index + 1) {
                    let remainingName = operations[remaining]["name"] as? String ?? ""
                    let failed = toolResult(
                        isError: true,
                        text: "TOOL_EXECUTION_FAILED：\(message)",
                        structured: ["code": "TOOL_EXECUTION_FAILED", "message": message]
                    )
                    results.append(["index": remaining, "name": remainingName, "result": failed])
                }
                break
            }
        }
        return toolResult(
            isError: succeeded != operations.count,
            text: "批量处理完成：成功 \(succeeded) 项，失败 \(operations.count - succeeded) 项。",
            structured: [
                "count": operations.count,
                "succeeded": succeeded,
                "failed": operations.count - succeeded,
                "results": results
            ]
        )
    }

    private func makeTools() -> [[String: Any]] {
        [
            tool(
                name: "mcp_batch",
                description: "在一个请求中顺序处理最多 50 项 MCP 工具调用。读操作共享已加载的技能库快照；技能索引、片段或预设写入后刷新，后续项能看到新内容。单项失败会保留并返回其它结果。",
                properties: [
                    "operations": [
                        "type": "array",
                        "minItems": 1,
                        "maxItems": 50,
                        "items": [
                            "type": "object",
                            "additionalProperties": false,
                            "properties": [
                                "name": ["type": "string", "minLength": 1],
                                "arguments": ["type": "object"]
                            ],
                            "required": ["name"]
                        ]
                    ]
                ],
                required: ["operations"],
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
            tool(name: "presets_list", description: "列出或搜索可安装的预设，返回标识、版本、技能、规则、插件与 MCP 组件。",
                 properties: ["query": ["type": "string", "maxLength": 200]], required: [], readOnly: true),
            tool(name: "skills_install", description: "将所选技能追加安装到当前项目：必须提供已登记项目的 projectId 或绝对路径 projectPath（二选一）。返回待本机批准的安装计划，批准后调用 deployment_apply；保留原有受管技能和规则。",
                 properties: installationProperties.merging([
                    "skillIds": ["type": "array", "items": ["type": "string"], "minItems": 1, "maxItems": 200]
                 ]) { _, new in new }, required: ["skillIds"], readOnly: false, destructive: false, idempotent: false),
            tool(name: "presets_install", description: "将预设中的技能和规则追加安装到当前项目。必须提供已登记 projectId 或绝对路径 projectPath（二选一）；返回待本机批准的计划，批准后调用 deployment_apply。含插件或 MCP 的混合预设需转本机完整审阅，不会静默跳过组件。",
                 properties: installationProperties.merging(["presetId": ["type": "string", "minLength": 1]]) { _, new in new },
                 required: ["presetId"], readOnly: false, destructive: false, idempotent: false),
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
                description: "同步 Git 仓库或本地目录到栖集缓存并建立技能库搜索索引；不执行脚本或启用技能。",
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
                    "ruleBlockId": ["type": "string"],
                    "installMethod": ["type": "string", "enum": ["symlink", "copy"]]
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
        ] + managementTools
    }

    var tools: [[String: Any]] { cachedTools }

    func tool(
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

    private var installationProperties: [String: Any] {
        [
            "projectId": ["type": "string", "format": "uuid"],
            "projectPath": ["type": "string", "minLength": 1, "description": "调用方当前项目的绝对路径；项目须先在栖集或 CLI 登记。"],
            "agents": ["type": "array", "items": ["type": "string", "enum": ["codex", "claude-code"]], "minItems": 1, "maxItems": 2]
        ]
    }

    func planObject(_ record: StoredDeploymentPlan) -> [String: Any] {
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

    func requiredUUID(_ arguments: [String: Any], key: String) throws -> UUID {
        guard let value = arguments[key] as? String, let id = UUID(uuidString: value) else {
            throw MCPToolError(code: "INVALID_ARGUMENTS", message: "\(key) 必须是 UUID。")
        }
        return id
    }

    func optionalUUID(_ arguments: [String: Any], key: String) throws -> UUID? {
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

    func toolResult(isError: Bool, text: String, structured: [String: Any]) -> [String: Any] {
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
        writeJSON(object)
    }

    private func writeJSON(_ value: Any) {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes]) else {
            return
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

struct MCPToolError: Error, LocalizedError, Sendable {
    let code: String
    let message: String

    var errorDescription: String? { message }
}
