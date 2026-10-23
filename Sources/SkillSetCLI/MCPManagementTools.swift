import Foundation
import CoreFoundation
import SkillSetCore

extension MCPStdioServer {
    // 所有入口共享 schema 和运行时校验，避免无效字段被静默忽略。
    func validateToolArguments(name: String, arguments: [String: Any]) throws {
        guard let definition = tools.first(where: { $0["name"] as? String == name }),
              let schema = definition["inputSchema"] as? [String: Any] else {
            throw MCPToolError(code: "TOOL_NOT_FOUND", message: "未知工具：\(name)")
        }
        try validate(arguments, schema: schema, path: "arguments")
    }

    private func validate(_ value: Any, schema: [String: Any], path: String) throws {
        func invalid() -> MCPToolError { MCPToolError(code: "INVALID_ARGUMENTS", message: "\(path) 不符合工具参数约定。") }
        switch schema["type"] as? String {
        case "object":
            guard let object = value as? [String: Any] else { throw invalid() }
            let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
            if schema["additionalProperties"] as? Bool == false, !Set(object.keys).isSubset(of: Set(properties.keys)) { throw invalid() }
            for key in schema["required"] as? [String] ?? [] where object[key] == nil { throw invalid() }
            for (key, child) in object {
                if let field = properties[key] { try validate(child, schema: field, path: path + "." + key) }
            }
        case "string":
            guard let string = value as? String else { throw invalid() }
            if let min = schema["minLength"] as? Int, string.count < min { throw invalid() }
            if let max = schema["maxLength"] as? Int, string.count > max { throw invalid() }
            if let choices = schema["enum"] as? [String], !choices.contains(string) { throw invalid() }
            if schema["format"] as? String == "uuid", UUID(uuidString: string) == nil { throw invalid() }
            if let pattern = schema["pattern"] as? String, string.range(of: pattern, options: .regularExpression) == nil { throw invalid() }
        case "array":
            guard let array = value as? [Any] else { throw invalid() }
            if let min = schema["minItems"] as? Int, array.count < min { throw invalid() }
            if let max = schema["maxItems"] as? Int, array.count > max { throw invalid() }
            if let items = schema["items"] as? [String: Any] {
                for (index, item) in array.enumerated() { try validate(item, schema: items, path: "\(path)[\(index)]") }
            }
        case "boolean":
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw invalid() }
        case "integer":
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.rounded() == number.doubleValue else { throw invalid() }
            if let min = schema["minimum"] as? Int, number.intValue < min { throw invalid() }
            if let max = schema["maximum"] as? Int, number.intValue > max { throw invalid() }
        default: break
        }
    }

    func callManagementTool(name: String, arguments a: [String: Any], current: SkillSetService) throws -> [String: Any]? {
        let paths = current.paths
        let root = paths.applicationSupportRoot
        let library = SkillLibraryStore(rootURL: paths.libraryRoot)
        let templates = TemplateStore(rootURL: root)
        let presets = PresetStore(rootURL: root)
        let connections = MCPLibraryStore(rootURL: root)
        let projects = ProjectStore(rootURL: root)
        let pluginSources = PluginSourceLibrary(stateRoot: root)
        func string(_ key: String) -> String { a[key] as? String ?? "" }
        func strings(_ key: String) -> [String] { a[key] as? [String] ?? [] }
        func missing(_ id: String) -> MCPToolError { MCPToolError(code: "RESOURCE_NOT_FOUND", message: "找不到条目：\(id)") }
        func result(_ key: String, _ value: some Encodable) throws -> [String: Any] {
            toolResult(isError: false, text: "操作完成。", structured: [key: try jsonValue(value)])
        }
        func deleted(_ id: String) -> [String: Any] {
            toolResult(isError: false, text: "已从本机库或登记记录移除；已部署内容和引用保留。", structured: ["id": id, "deleted": true])
        }
        func pending(_ record: StoredDeploymentPlan) -> [String: Any] {
            var value = planObject(record)
            value["status"] = "awaiting-approval"
            value["nextTool"] = "deployment_apply"
            value["nextArguments"] = ["planId": record.id.uuidString, "planDigest": record.plan.digest]
            return toolResult(isError: false, text: "已生成计划；尚未应用，需在本机审阅批准。", structured: value)
        }
        func skill() throws -> SkillEntry {
            guard let entry = current.snapshot.catalog.entries.first(where: { $0.id == string("skillId") }) else { throw missing(string("skillId")) }
            return entry
        }
        func host() throws -> MCPHost {
            guard let host = MCPHost(rawValue: string("host")) else { throw missing(string("host")) }
            return host
        }
        switch name {
        case "skills_get":
            let entry = try skill()
            return toolResult(isError: false, text: "已读取技能正文。", structured: ["skill": try jsonValue(entry), "document": try library.document(for: entry, repositoryRoot: paths.repositoryRoot)])
        case "skills_create", "skills_update":
            let original = name == "skills_update" ? try skill() : nil
            // 外部来源不可原地修改；必须显式创建个人副本。
            if let original, original.sourceId != SkillLibraryStore.sourceID {
                throw MCPToolError(code: "LIBRARY_READ_ONLY_SOURCE", message: "来源技能不可原地编辑，请使用 skills_create 创建个人技能。")
            }
            return try result("skill", library.save(SkillEditorDraft(slug: original?.slug ?? string("slug"), document: string("document"), original: original), repositoryRoot: paths.repositoryRoot))
        case "skills_delete":
            let entry = try skill()
            try library.remove(entry)
            return deleted(entry.id)
        case "skills_restore_hidden":
            try library.restoreHidden()
            return toolResult(isError: false, text: "已恢复隐藏的来源技能。", structured: ["restored": true])
        case "templates_list":
            let query = string("query")
            return try result("templates", current.snapshot.templates.filter { query.isEmpty || [$0.id, $0.title, $0.purpose, $0.body].joined(separator: " ").localizedCaseInsensitiveContains(query) })
        case "templates_get", "templates_delete":
            let id = string("templateId")
            guard let record = current.snapshot.templates.first(where: { $0.id == id }) else { throw missing(id) }
            if name == "templates_get" { return try result("template", record) }
            _ = try templates.remove(id: id, initial: current.snapshot.templates)
            return deleted(id)
        case "templates_create", "templates_update":
            let id = name == "templates_create" ? UUID().uuidString.lowercased() : string("templateId")
            let old = current.snapshot.templates.first { $0.id == id }
            if name == "templates_update", old == nil { throw missing(id) }
            let record = TemplateRecord(id: id, title: a["title"] as? String ?? old?.title ?? "", body: a["body"] as? String ?? old?.body ?? "", purpose: a["purpose"] as? String ?? old?.purpose ?? "", isLocal: true)
            let saved = try templates.save(record, initial: current.snapshot.templates)
            return try result("template", saved.first { $0.id == id }!)
        case "presets_get", "presets_delete":
            let id = string("presetId")
            guard let record = current.snapshot.presets.first(where: { $0.id == id }) else { throw missing(id) }
            if name == "presets_get" { return try result("preset", record) }
            _ = try presets.remove(id: id)
            return deleted(id)
        case "presets_create", "presets_update":
            let id = name == "presets_create" ? UUID().uuidString.lowercased() : string("presetId")
            let old = current.snapshot.presets.first { $0.id == id }
            if name == "presets_update", old == nil { throw missing(id) }
            func decode<T: Decodable>(_ key: String, fallback: T) throws -> T {
                guard let value = a[key] else { return fallback }
                return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: value))
            }
            let record = try PresetRecord(id: id, name: a["name"] as? String ?? old?.name ?? "", description: a["description"] as? String ?? old?.description ?? "",
                skills: a["skillIds"] as? [String] ?? old?.skills ?? [], instructionFragments: a["instructionIds"] as? [String] ?? old?.instructionFragments ?? [],
                plugins: decode("plugins", fallback: old?.plugins ?? []), mcpServers: decode("mcpServers", fallback: old?.mcpServers ?? []))
            let saved = try presets.save(record, initial: current.snapshot.presets)
            return try result("preset", saved.first { $0.id == id }!)
        case "sources_get":
            return try result("preview", current.sourcePreview(id: requiredUUID(a, key: "previewId")))
        case "sources_update":
            let id = try requiredUUID(a, key: "previewId")
            let old = try current.sourcePreview(id: id)
            return try result("preview", current.previewSource(urlString: a["url"] as? String ?? old.inputURL, ref: a["ref"] as? String ?? old.requestedRef, replacing: id))
        case "sources_delete":
            let id = try requiredUUID(a, key: "previewId")
            try current.removeSource(id)
            return deleted(id.uuidString)
        case "sources_import_skill":
            var draft = try current.sourceSkillImportDraft(previewID: requiredUUID(a, key: "previewId"), path: string("path"))
            if let slug = a["slug"] as? String { draft.slug = slug }
            return try result("skill", current.importSourceSkill(draft))
        case "projects_create":
            guard string("projectPath").hasPrefix("/") else { throw MCPToolError(code: "INVALID_ARGUMENTS", message: "projectPath 必须是绝对路径。") }
            return try result("project", projects.register(path: URL(fileURLWithPath: string("projectPath")), name: a["name"] as? String, agents: strings("agents")))
        case "projects_update":
            return try result("project", projects.update(id: requiredUUID(a, key: "projectId"), name: a["name"] as? String, agents: a["agents"] as? [String]))
        case "projects_delete":
            let id = try requiredUUID(a, key: "projectId")
            try projects.unregister(id: id)
            return deleted(id.uuidString)
        case "projects_draft_get":
            let id = try requiredUUID(a, key: "projectId")
            _ = try projects.project(id: id)
            return try result("draft", ProjectDraftStore(rootURL: root).load(projectID: id))
        case "presets_apply_draft":
            let id = try requiredUUID(a, key: "projectId")
            let project = try projects.project(id: id)
            let target = try host().rawValue
            guard let preset = current.snapshot.presets.first(where: { $0.id == string("presetId") }) else { throw missing(string("presetId")) }
            // 完整保存混合预设，不能把插件或 MCP 组件静默丢弃。
            for skillID in preset.skills {
                guard current.snapshot.catalog.entries.contains(where: { $0.id == skillID && !$0.isBlocked }) else { throw missing(skillID) }
            }
            for instructionID in preset.instructionFragments {
                guard current.snapshot.templates.contains(where: { $0.id == instructionID }) else { throw missing(instructionID) }
            }
            let store = ProjectDraftStore(rootURL: root)
            let previous = try store.load(projectID: id)
            let manifest = try current.projectState(projectID: id).manifest
            var selections = previous?.resolvedHarnessSelections ?? manifest?.resolvedHarnessSelections ?? [:]
            selections[target] = ProjectHarnessSelection(skillIDs: preset.skills, instructionIDs: preset.instructionFragments)
            let draft = try store.save(projectID: project.id, skillIDs: preset.skills, instructionIDs: preset.instructionFragments,
                agents: selections.keys.sorted(), plugins: preset.plugins, mcpServers: preset.mcpServers, harnessSelections: selections)
            return toolResult(isError: false, text: "已将完整预设载入项目草稿；尚未应用。技能和片段使用 deployment_harness_plan，MCP 和插件分别生成计划并在本机审阅。",
                structured: ["status": "draft-only", "draft": try jsonValue(draft)])
        case "deployment_harness_plan":
            let id = try requiredUUID(a, key: "projectId")
            let target = try host().rawValue
            let method = SkillInstallMethod(rawValue: a["installMethod"] as? String ?? "symlink")!
            return try pending(current.makeHarnessPlan(projectID: id, agent: target,
                selection: ProjectHarnessSelection(skillIDs: strings("skillIds"), instructionIDs: strings("instructionIds")), installMethod: method))
        case "templates_apply_plan":
            let target = try host()
            let instructionIDs = strings("instructionIds")
            if let id = try optionalUUID(a, key: "projectId") {
                let manifest = try current.projectState(projectID: id).manifest
                let selected = manifest?.resolvedHarnessSelections[target.rawValue]
                let selection = ProjectHarnessSelection(skillIDs: selected?.skillIDs ?? [], instructionIDs: Array(Set((selected?.instructionIDs ?? []) + instructionIDs)).sorted())
                return try pending(current.makeHarnessPlan(projectID: id, agent: target.rawValue, selection: selection))
            }
            var selection = try current.globalConfiguration.appliedSelection(host: target)
            selection.instructionIDs = Array(Set(selection.instructionIDs + instructionIDs)).sorted()
            return try pending(current.makeGlobalPlan(host: target, selection: selection))
        case "mcp_library_list":
            return try result("entries", connections.entries())
        case "mcp_library_get", "mcp_library_delete":
            let id = try requiredUUID(a, key: "entryId")
            guard let record = try connections.entries().first(where: { $0.id == id }) else { throw missing(id.uuidString) }
            if name == "mcp_library_get" { return try result("entry", record) }
            try connections.remove(id)
            return deleted(id.uuidString)
        case "mcp_library_create", "mcp_library_update":
            var entry = MCPLibraryEntry()
            if name == "mcp_library_update" {
                let id = try requiredUUID(a, key: "entryId")
                guard let old = try connections.entries().first(where: { $0.id == id }) else { throw missing(id.uuidString) }
                entry = old
            }
            if let value = a["name"] as? String { entry.name = value }
            if let value = a["transport"] as? String { entry.transport = value }
            if let value = a["commandOrURL"] as? String { entry.commandOrURL = value }
            if let value = a["args"] as? [String] { entry.args = value }
            if let value = a["envKeys"] as? [String] { entry.envKeys = value }
            return try result("entry", connections.save(entry))
        case "mcp_library_selection_get", "mcp_library_selection_set", "mcp_library_plan":
            let projectID = try optionalUUID(a, key: "projectId")
            if let projectID { _ = try projects.project(id: projectID) }
            let target = try host()
            if name == "mcp_library_plan" { return try pending(current.makeMCPLibraryPlan(host: target, projectID: projectID)) }
            if name == "mcp_library_selection_set" {
                let ids = try strings("entryIds").map { value -> UUID in
                    guard let id = UUID(uuidString: value) else { throw missing(value) }
                    return id
                }
                let available = Set(try connections.entries().map(\.id))
                guard Set(ids).isSubset(of: available) else { throw MCPLibraryError.missingSelection }
                try connections.saveSelection(ids, host: target, projectID: projectID)
            }
            return try result("entryIds", connections.selectedIDs(host: target, projectID: projectID))
        case "mcp_config_update_plan", "mcp_config_delete_plan":
            let projectID = try optionalUUID(a, key: "projectId")
            let target = try host()
            let scope = MCPConfigurationScope(rawValue: string("scope"))!
            guard scope == .user || projectID != nil else { throw MCPToolError(code: "INVALID_ARGUMENTS", message: "项目范围必须提供 projectId。") }
            let inspections = try current.mcpConfigurations(projectID: projectID)
            guard let server = inspections.filter({ $0.host == target && $0.scope == scope }).flatMap(\.servers).first(where: { $0.name == string("name") }) else { throw missing(string("name")) }
            let draft = MCPConfigurationDraft(name: server.name, host: target, scope: scope, transport: server.transport, commandOrURL: a["commandOrURL"] as? String ?? server.command, args: strings("args"), envKeys: server.envKeys)
            return try pending(current.makeMCPConfigPlan(projectID: projectID, draft: draft, existingServer: server, remove: name == "mcp_config_delete_plan", replaceArguments: a["args"] != nil))
        case "global_config_get":
            let target = try host()
            let inspection = try current.globalConfiguration.inspect(host: target)
            return toolResult(isError: false, text: "已读取全局选择和受管状态。", structured: ["host": target.rawValue, "selection": try jsonValue(inspection.selection), "skillsPath": inspection.skillsPath, "rulesPath": inspection.rulesPath, "hasManagement": inspection.hasManagement,
                "resources": inspection.resources.map { ["path": $0.path, "managed": $0.managed, "modified": $0.modified, "symbolicLink": $0.symbolicLink] as [String: Any] }])
        case "global_config_plan":
            let method = SkillInstallMethod(rawValue: a["installMethod"] as? String ?? "symlink")!
            return try pending(current.makeGlobalPlan(host: host(), selection: GlobalConfigurationDraft(skillIDs: strings("skillIds"), instructionIDs: strings("instructionIds"), installMethod: method)))
        case "plugin_sources_list":
            return try result("sources", pluginSources.sources())
        case "plugin_sources_get":
            let id = try requiredUUID(a, key: "sourceId")
            guard let source = try pluginSources.sources().first(where: { $0.id == id }) else { throw missing(id.uuidString) }
            return toolResult(isError: false, text: "已读取插件来源与组件盘点。", structured: ["source": try jsonValue(source), "inventory": try jsonValue(pluginSources.inventory(id))])
        case "plugin_sources_create", "plugin_sources_update":
            let id = name == "plugin_sources_update" ? try requiredUUID(a, key: "sourceId") : nil
            return try result("source", pluginSources.save(address: string("url"), ref: a["ref"] as? String, replacing: id))
        case "plugin_sources_delete":
            let id = try requiredUUID(a, key: "sourceId")
            guard try pluginSources.sources().contains(where: { $0.id == id }) else { throw missing(id.uuidString) }
            try pluginSources.remove(id)
            return deleted(id.uuidString)
        default: return nil
        }
    }
}
