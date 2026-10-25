import Foundation

extension MCPStdioServer {
    var managementTools: [[String: Any]] {
        let text: [String: Any] = ["type": "string", "minLength": 1]
        let uuid: [String: Any] = ["type": "string", "format": "uuid"]
        let query: [String: Any] = ["type": "string", "maxLength": 200]
        let host: [String: Any] = ["type": "string", "enum": ["codex", "claude-code"]]
        let scope: [String: Any] = ["type": "string", "enum": ["user", "project"]]
        let ids: [String: Any] = ["type": "array", "items": text, "maxItems": 200]
        let agents: [String: Any] = ["type": "array", "items": host, "maxItems": 2]
        let document: [String: Any] = ["type": "string", "minLength": 1, "maxLength": 2 * 1_024 * 1_024]
        let connection: [String: Any] = [
            "name": ["type": "string", "minLength": 1, "maxLength": 64],
            "transport": ["type": "string", "enum": ["stdio", "streamable-http"]],
            "commandOrURL": ["type": "string", "minLength": 1, "maxLength": 2_048],
            "args": ["type": "array", "items": ["type": "string"], "maxItems": 64],
            "envKeys": ["type": "array", "items": text, "maxItems": 32]
        ]
        func merging(_ a: [String: Any], _ b: [String: Any]) -> [String: Any] { a.merging(b) { _, new in new } }
        func array(_ fields: [String: Any], _ required: [String]) -> [String: Any] {
            ["type": "array", "maxItems": 200, "items": ["type": "object", "additionalProperties": false, "properties": fields, "required": required]]
        }
        var result: [[String: Any]] = []
        func add(_ name: String, _ description: String, _ properties: [String: Any], _ required: [String], read: Bool = false, destructive: Bool = false, idempotent: Bool? = nil, open: Bool = false) {
            result.append(tool(name: name, description: description, properties: properties, required: required, readOnly: read, destructive: destructive, idempotent: idempotent ?? (read || destructive), openWorld: open))
        }
        add("skills_get", "读取技能元数据与完整 SKILL.md。", ["skillId": text], ["skillId"], read: true)
        add("skills_create", "新建技能；可用 sourceSkillId 复制已有技能的完整包和来源证据，再用 document 替换正文。slug 必须是未占用的新技能名；不主动部署。", ["slug": text, "document": document, "sourceSkillId": text], ["slug", "document"])
        add("skills_update", "原地编辑 custom 技能的 SKILL.md 并保留附属文件。已软链部署的内容立即跟随；复制部署不变。来源技能需用 skills_create 的 sourceSkillId 复制完整包。", ["skillId": text, "document": document], ["skillId", "document"], destructive: true)
        add("skills_delete", "从技能库删除技能；custom 文件一并删除，跟随来源的条目只移除库内软链。已软链部署的技能会失效，复制部署不变；不会移除项目中的链接或引用。", ["skillId": text], ["skillId"], destructive: true)
        add("templates_list", "列出或搜索 AGENTS.md / CLAUDE.md 规则片段及正文。", ["query": query], [], read: true)
        add("templates_get", "按标识读取规则片段。", ["templateId": text], ["templateId"], read: true)
        let template: [String: Any] = ["title": ["type": "string", "maxLength": 80], "purpose": ["type": "string", "maxLength": 500], "body": ["type": "string", "maxLength": 256 * 1_024]]
        add("templates_create", "新增本机规则片段；使用 deployment_plan 或 global_config_plan 应用于项目或全局。", template, ["title", "body"])
        add("templates_update", "修改片段的指定字段，省略字段保留；不改写已有计划或宿主文件。", merging(template, ["templateId": text]), ["templateId"])
        add("templates_delete", "从片段库删除；引用保留并在后续计划中报告失效。", ["templateId": text], ["templateId"], destructive: true)
        add("presets_get", "读取预设完整组件。", ["presetId": text], ["presetId"], read: true)
        let plugin: [String: Any] = ["host": host, "pluginID": text, "name": text, "manifestDigest": ["type": "string", "pattern": "^[a-fA-F0-9]{64}$"], "sourceRevision": ["type": "string"], "scope": ["type": "string", "enum": ["user", "project", "local"]]]
        let preset: [String: Any] = ["name": ["type": "string", "maxLength": 80], "description": ["type": "string"], "skillIds": ids, "instructionIds": ids,
            "plugins": array(plugin, ["host", "pluginID", "name", "manifestDigest", "scope"]),
            "mcpServers": array(merging(connection, ["host": host, "scope": scope]), ["name", "host", "scope", "transport", "commandOrURL", "args", "envKeys"])]
        add("presets_create", "新增本机预设，支持技能、片段、插件和 MCP 组件；不安装。", preset, ["name"])
        add("presets_update", "更新指定预设字段，未提供的组件保留，保存时递增 revision。", merging(preset, ["presetId": text]), ["presetId"])
        add("presets_delete", "删除本机预设，不卸载已安装组件。", ["presetId": text], ["presetId"], destructive: true)
        add("sources_get", "读取来源预览及其全部候选技能、固定版本和许可线索。", ["previewId": uuid], ["previewId"], read: true)
        add("sources_update", "重新同步并替换来源，失败保留旧记录；ref 空字符串表示使用默认版本。跟随来源的库条目和软链部署会同步变化，复制内容不变。", ["previewId": uuid, "url": text, "ref": ["type": "string", "maxLength": 256]], ["previewId"], destructive: true, idempotent: false, open: true)
        add("sources_delete", "删除来源缓存；跟随该来源的技能库软链和对应软链部署会失效。复制到 custom 或部署目标的实体内容保留，项目链接与引用不自动移除。", ["previewId": uuid], ["previewId"], destructive: true)
        add("sources_import_skill", "把来源中的一个完整技能包加入技能库。mode 默认 symlink，跟随来源更新和删除；copy 复制到 custom，不跟随来源。不主动部署。", ["previewId": uuid, "path": text, "slug": text, "mode": ["type": "string", "enum": ["symlink", "copy"]], "category": text], ["previewId", "path"])
        add("projects_create", "显式登记绝对路径项目，建立后续计划可选目标；不写项目或宿主文件。", ["projectPath": text, "name": text, "agents": agents], ["projectPath"])
        add("projects_update", "更新项目名称和登记宿主，不移动目录或修改已部署选择。", ["projectId": uuid, "name": text, "agents": agents], ["projectId"])
        add("projects_delete", "取消项目登记，不删除目录、不卸载技能或规则。", ["projectId": uuid], ["projectId"], destructive: true)
        add("mcp_library_list", "列出本机可复用 MCP 配置库。", [:], [], read: true)
        add("mcp_library_get", "读取单条可复用 MCP 配置。", ["entryId": uuid], ["entryId"], read: true)
        add("mcp_library_create", "新增 MCP 配置库条目；不写宿主，只保存环境变量名称。", connection, ["name", "transport", "commandOrURL"])
        add("mcp_library_update", "修改 MCP 库指定字段，其他字段保留；不改变已部署连接。", merging(connection, ["entryId": uuid]), ["entryId"])
        add("mcp_library_delete", "删除 MCP 库条目；引用与已部署连接保留，取消选择后再规划移除。", ["entryId": uuid], ["entryId"], destructive: true)
        let target: [String: Any] = ["host": host, "projectId": uuid]
        add("mcp_library_selection_get", "读取宿主的库选择草稿；无 projectId 表示全局。", target, ["host"], read: true)
        add("mcp_library_selection_set", "替换指定宿主/项目的 MCP 选择草稿，空数组表示全部取消；不写宿主文件。", merging(target, ["entryIds": ["type": "array", "items": uuid, "maxItems": 200]]), ["host", "entryIds"])
        add("mcp_library_plan", "将该目标整组 MCP 选择生成待批准的应用/移除计划；全局影响该宿主全部项目。", target, ["host"])
        let existing: [String: Any] = ["host": host, "scope": scope, "projectId": uuid, "name": text]
        add("mcp_config_update_plan", "为明确选中的已有 MCP 连接生成编辑计划，保留未知键与凭据；省略 args 保留原参数。", merging(existing, ["commandOrURL": text, "args": connection["args"]!]), ["host", "scope", "name"])
        add("mcp_config_delete_plan", "为选中的已有 MCP 连接生成删除计划，批准后执行，保留其他服务。", existing, ["host", "scope", "name"])
        add("global_config_get", "读取宿主全局技能/规则的已部署选择、目标路径和受管状态。", ["host": host], ["host"], read: true)
        add("global_config_plan", "将完整技能与片段选择应用于全局的待批准计划；空数组规划移除受管内容，影响该宿主全部项目。", ["host": host, "skillIds": ids, "instructionIds": ids, "installMethod": ["type": "string", "enum": ["copy", "symlink"]]], ["host", "skillIds", "instructionIds"])
        add("plugin_sources_list", "列出本机插件来源，不执行插件代码。", [:], [], read: true)
        add("plugin_sources_get", "读取插件来源及组件盘点。", ["sourceId": uuid], ["sourceId"], read: true)
        let source: [String: Any] = ["url": text, "ref": ["type": "string", "maxLength": 256]]
        add("plugin_sources_create", "隔离收录插件来源；不注册宿主市场或安装插件。", source, ["url"], open: true)
        add("plugin_sources_update", "重新同步并替换插件来源，失败保留旧记录。", merging(source, ["sourceId": uuid]), ["sourceId", "url"], open: true)
        add("plugin_sources_delete", "移除本机插件来源，不卸载宿主插件。", ["sourceId": uuid], ["sourceId"], destructive: true)
        add("projects_draft_get", "读取本机项目编辑草稿；草稿不代表已应用。", ["projectId": uuid], ["projectId"], read: true)
        add("presets_apply_draft", "将完整预设用于项目草稿：替换指定宿主的技能与片段，同时保存插件和 MCP 组件；不部署。", ["projectId": uuid, "presetId": text, "host": host], ["projectId", "presetId", "host"])
        add("deployment_harness_plan", "仅替换指定宿主的完整技能/片段选择，其他宿主沿用已部署内容；空数组规划移除，仍需本机批准。", ["projectId": uuid, "host": host, "skillIds": ids, "instructionIds": ids, "installMethod": ["type": "string", "enum": ["copy", "symlink"]]], ["projectId", "host", "skillIds", "instructionIds"])
        add("templates_apply_plan", "将片段追加用于指定宿主的项目或全局配置，保留已部署技能与其他片段；无 projectId 表示全局。返回待批准计划。", ["projectId": uuid, "host": host, "instructionIds": ids], ["host", "instructionIds"])
        return result
    }
}
