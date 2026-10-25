import SwiftUI
import SkillSetCore

private enum ConfigurationResourceTab: String, CaseIterable, Identifiable {
    case skills = "技能"
    case instructions = "AGENTS 片段"
    case mcp = "MCP 服务"
    case plugins = "插件"
    var id: String { rawValue }
}

struct ConfigurationResourceView: View {
    @Bindable var model: AppModel
    let projectID: UUID?
    @State private var tab: ConfigurationResourceTab = .skills
    @State private var query = ""
    @State private var availableHeight: CGFloat = 0
    @State private var plugins: PluginSelectionModel
    @State private var overwriteHost: MCPHost?

    init(model: AppModel, projectID: UUID? = nil) {
        self.model = model
        self.projectID = projectID
        _plugins = State(initialValue: PluginSelectionModel(paths: model.runtimePaths,
            home: model.globalConfiguration.locations.home, projectID: projectID,
            projectRoot: model.projects.first { $0.id == projectID?.uuidString }.map { URL(fileURLWithPath: $0.path) }))
    }

    private var global: GlobalConfigurationModel { model.globalConfiguration }
    private var isProject: Bool { projectID != nil }
    private var project: ProjectRecord? { model.projects.first { $0.id == projectID?.uuidString } }
    private var prefix: String { isProject ? "projects" : "global" }

    var body: some View {
        VStack(alignment: .leading, spacing: AppLayout.columnSpacing) {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: availableHeight < 500 ? 10 : 16) {
                        ConfigurationSectionHeader {
                            Text(L10n.tr("配置草稿")).font(AppFont.heading)
                        } actions: {
                            if let project {
                                Button(L10n.tr("使用预设…")) {
                                    model.presetSelection = PresetSelectionRequest(projectID: project.id)
                                }.accessibilityIdentifier("projects.usePreset")
                            }
                            previewActions
                        }
                        Picker(L10n.tr("资源类型"), selection: $tab) {
                            ForEach(ConfigurationResourceTab.allCases) { item in
                                Text(L10n.text(item.rawValue)).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("\(prefix).resourceTabs")
                        if tab == .skills {
                            selectedSkillPills
                        }
                        AppSearchField(query: $query, prompt: L10n.tr("搜索名称、来源或说明"),
                            label: L10n.tr("搜索配置资源"), identifier: "\(prefix).search")
                        HStack {
                            Text(L10n.tr("勾选只改草稿，预览后点击「保存」才会写入配置。"))
                                .font(AppFont.secondary).foregroundStyle(.secondary)
                            Spacer()
                            HStack(spacing: 10) {
                                hostLegend(.codex)
                                hostLegend(.claudeCode)
                            }
                        }
                        if (!isProject && global.isRefreshing) || plugins.isLoading {
                            ProgressView(L10n.tr("正在读取配置…")).controlSize(.small)
                        }
                        Divider()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                errors
                                switch tab {
                                case .skills: skillList
                                case .instructions: instructionList
                                case .mcp: mcpList
                                case .plugins: pluginList
                                }
                                if let project, tab == .mcp || tab == .plugins {
                                    ProjectPresetComponents(model: model, project: project)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { availableHeight = $0 }
        .task {
            if !isProject { await global.refreshInBackground() }
            model.mcpLibrary.refresh()
            for host in MCPHost.allCases { model.mcpLibrary.loadSelection(host: host, projectID: projectID) }
            await model.mcpLibrary.refreshUsageInBackground()
            await plugins.refresh()
        }
        .onChange(of: model.planPresented) { _, presented in
            if !presented { Task { await plugins.refresh(); await model.mcpLibrary.refreshUsageInBackground() } }
        }
        .confirmationDialog(L10n.tr("覆盖已有的同名 MCP 服务？"),
            isPresented: Binding(get: { overwriteHost != nil }, set: { if !$0 { overwriteHost = nil } }), titleVisibility: .visible) {
                if let host = overwriteHost {
                    Button(L10n.tr("覆盖并预览"), role: .destructive) {
                        let names = model.mcpLibrary.externalConflicts(host: host, projectID: projectID).map(\.name)
                        model.mcpLibrary.approveExternalOverwrite(host: host, projectID: projectID, names: names)
                        model.prepareMCPLibraryPlan(host: host, projectID: projectID)
                        overwriteHost = nil
                    }
                }
                Button(L10n.tr("先不覆盖"), role: .cancel) { overwriteHost = nil }
            } message: {
                if let host = overwriteHost {
                    Text(L10n.tr("同名服务将使用配置库中的连接信息；预览后保存才会覆盖，原文件会先备份。"))
                    Text(host.displayName + " · " + (model.mcpLibrary.usageTargets.first { $0.host == host && $0.projectID == projectID }?.configPath ?? "")
                        + "\n" + model.mcpLibrary.externalConflicts(host: host, projectID: projectID).map(\.name).joined(separator: "、"))
                }
            }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(prefix).configuration")
    }

    private func hostLegend(_ host: MCPHost) -> some View {
        HStack(spacing: 4) {
            Image(host == .codex ? "CodexLogo" : "ClaudeLogo", bundle: .module)
                .resizable().renderingMode(.template).scaledToFit().frame(width: 14, height: 14)
            Text(host.displayName).font(AppFont.metadata)
        }.foregroundStyle(.secondary).fixedSize()
    }

    private var previewActions: some View {
        HStack(spacing: 8) {
            ForEach(MCPHost.allCases) { host in
                if tab == .plugins {
                    let pending = plugins.pending(host: host)
                    if pending.count == 1, let plugin = pending.first {
                        Button(L10n.tr("预览 \(host.displayName)")) {
                            present(plugins.prepare(plugin, locations: global.locations))
                        }
                        .buttonStyle(AppButtonStyle(kind: .primary))
                        .disabled(model.isWorking || plugins.isLoading || !plugins.isReady
                            || (plugins.action(plugin) == .install && !plugins.acknowledgedRisk))
                        .accessibilityIdentifier("\(prefix).preview.plugins.\(host.rawValue)")
                    } else {
                      Menu(L10n.tr("预览 \(host.displayName)")) {
                        ForEach(plugins.pending(host: host)) { plugin in
                            Button(plugin.name + " · " + L10n.text(plugins.action(plugin)?.displayName ?? "")) {
                                present(plugins.prepare(plugin, locations: global.locations))
                            }
                            .disabled(plugins.action(plugin) == .install && !plugins.acknowledgedRisk)
                        }
                    }
                    .disabled(model.isWorking || plugins.isLoading || !plugins.isReady || plugins.pending(host: host).isEmpty)
                    .accessibilityIdentifier("\(prefix).preview.plugins.\(host.rawValue)")
                    }
                } else {
                    Button(L10n.tr("预览 \(host.displayName)")) {
                        if tab == .mcp { model.prepareMCPLibraryPlan(host: host, projectID: projectID) }
                        else if isProject { model.prepareDeploymentPlan(host: host) }
                        else { present(global.prepareDeployment(host: host)) }
                    }
                    .buttonStyle(AppButtonStyle(kind: .primary))
                    .disabled(model.isWorking || (tab != .mcp && !canEdit(host)))
                    .accessibilityIdentifier("\(prefix).preview.\(host.rawValue)")
                }
            }
        }
    }

    @ViewBuilder private var errors: some View {
        if !isProject, let error = global.error {
            Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red)
                .accessibilityIdentifier("global.error")
        }
        ForEach(MCPHost.allCases) { host in
            if !isProject, let error = global.skillEditingErrors[host], error != global.error {
                Text(host.displayName + ": " + L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red)
            }
        }
        if tab == .mcp, let error = model.mcpLibrary.error ?? model.mcpLibrary.usageError {
            Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red)
        }
        if tab == .plugins, let error = plugins.error {
            Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red)
        }
        if (!isProject && (global.error != nil || !global.skillEditingErrors.isEmpty)) || (tab == .plugins && plugins.error != nil) {
            Button(L10n.tr("重新扫描")) { Task { await global.refreshInBackground(); await plugins.refresh() } }
        }
    }

    private var selectedSkillPills: some View {
        let selected = Set(MCPHost.allCases.flatMap { skillIDs($0) })
        let entries = Dictionary(uniqueKeysWithValues: model.snapshot.catalog.entries.map { ($0.id, $0) })
        let items = selected.map { id in
            SelectedSkillPills.Item(id: id, name: model.skillDisplayTitle(id),
                detail: entries[id].map { model.skillDisplayTitle(id) + " · " + model.skillSourceTitle($0) }
                    ?? L10n.tr("技能不可用"))
        }.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
        return SelectedSkillPills(items: items, identifierPrefix: prefix, compact: availableHeight < 500,
            hostSelection: .init(
                isSelected: { skillIDs($1).contains($0) },
                isEnabled: { id, host in
                    !model.isWorking && canEdit(host)
                        && (skillIDs(host).contains(id) || entries[id].map { !$0.isBlocked } == true)
                },
                setSelected: { id, host, enabled in
                    if let skill = entries[id] { setSkill(skill, enabled: enabled, host: host) }
                    else if !enabled { removeSkill(id, host: host) }
                }),
            canRemove: { id in
                !model.isWorking && MCPHost.allCases.filter { skillIDs($0).contains(id) }.allSatisfy { canEdit($0) }
            },
            remove: { id in
                for host in MCPHost.allCases where skillIDs(host).contains(id) {
                    if let skill = entries[id] { setSkill(skill, enabled: false, host: host) }
                    else { removeSkill(id, host: host) }
                    // 保存失败时保留该工具的错误，不让另一工具的成功保存把它清掉。
                    if skillIDs(host).contains(id) { break }
                }
            })
    }

    private var skillList: some View {
        let skills = matchingSkills(model.snapshot.catalog.entries, query: query, sourceOrigins: model.sourceOrigins)
        return VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("\(skills.count) 个匹配")).font(AppFont.metadata).foregroundStyle(.secondary)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(skills) { skill in
                    resourceRow {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(skill.slug).font(AppFont.body.weight(.semibold)).lineLimit(1).help(skill.slug)
                            Text(model.skillSourceTitle(skill)).font(AppFont.metadata).foregroundStyle(.secondary).lineLimit(1)
                            Text(skill.description).font(AppFont.secondary).foregroundStyle(.secondary).lineLimit(2)
                            if skill.isBlocked {
                                Text(L10n.tr("未通过文件检查，请到技能库查看原因。"))
                                    .font(AppFont.secondary).foregroundStyle(.red)
                            }
                        }
                    } toggles: {
                        SkillHostToggles(skillName: skill.slug, identifierPrefix: "\(prefix).skill.\(skill.id)",
                            isSelected: { skillIDs($0).contains(skill.id) },
                            isEnabled: { host in !model.isWorking && canEdit(host)
                                && (!skill.isBlocked || skillIDs(host).contains(skill.id)) },
                            setSelected: { setSkill(skill, enabled: $1, host: $0) })
                    }
                }
            }
            if skills.isEmpty { empty("没有匹配的技能，请调整搜索或先加入技能库。", section: .skills) }
            ForEach(MCPHost.allCases) { host in
                ForEach(skillIDs(host).filter { id in
                    !model.snapshot.catalog.entries.contains { $0.id == id }
                }, id: \.self) { id in
                    HStack {
                        Text(host.displayName + " · " + model.skillDisplayTitle(id))
                        Text(L10n.tr("技能不可用")).foregroundStyle(.orange)
                        Spacer()
                        Button(L10n.tr("移除")) { removeSkill(id, host: host) }
                    }.font(AppFont.secondary)
                }
            }
            DisclosureGroup(L10n.tr("安装选项")) {
                VStack(alignment: .leading, spacing: 12) {
                    if isProject {
                        AppPicker(title: L10n.tr("技能安装方式"), selection: $model.skillInstallMethod,
                            valueLabel: L10n.tr(model.skillInstallMethod == .copy ? "复制独立文件" : "软链接（推荐）")) {
                            Text(L10n.tr("软链接（推荐）")).tag(SkillInstallMethod.symlink)
                            Text(L10n.tr("复制独立文件")).tag(SkillInstallMethod.copy)
                        }
                    } else {
                        ForEach(MCPHost.allCases) { host in
                            AppPicker(title: host.displayName,
                                selection: Binding(get: { global.selection(host: host)?.installMethod ?? .symlink },
                                                   set: { global.setInstallMethod($0, host: host) }),
                                valueLabel: L10n.tr(global.selection(host: host)?.installMethod == .copy ? "复制独立文件" : "软链接（推荐）")) {
                                    Text(L10n.tr("软链接（推荐）")).tag(SkillInstallMethod.symlink)
                                    Text(L10n.tr("复制独立文件")).tag(SkillInstallMethod.copy)
                                }.disabled(!canEdit(host))
                        }
                        Toggle(L10n.tr("接管所选资源的已有同名内容，并保留原始备份"),
                               isOn: Binding(get: { global.takeOverExisting }, set: { global.takeOverExisting = $0 }))
                            .toggleStyle(.checkbox)
                    }
                    Text(L10n.tr("软链接指向 ~/.perch 中的固定版本；复制后的文件可独立编辑。"))
                        .font(AppFont.secondary).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }
        }
    }

    private var instructionList: some View {
        let templates = model.snapshot.templates.filter { matches([$0.title, $0.purpose, $0.body]) }
        return VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("技能与 AGENTS 片段会在同一份工具计划中预览和保存。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            ForEach(templates) { template in
                resourceRow {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(UserFacingText.templateTitle(template)).font(AppFont.body.weight(.semibold))
                        Text(UserFacingText.templatePurpose(template)).font(AppFont.secondary).foregroundStyle(.secondary)
                        Text(template.body).font(AppFont.code).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } toggles: {
                    SkillHostToggles(skillName: UserFacingText.templateTitle(template), identifierPrefix: "\(prefix).instruction.\(template.id)",
                        isSelected: { instructionIDs($0).contains(template.id) },
                        isEnabled: { !model.isWorking && canEdit($0) },
                        setSelected: { setInstruction(template.id, enabled: $1, host: $0) })
                }
            }
            if templates.isEmpty { empty("没有匹配的 AGENTS 片段，请调整搜索或到「AGENTS 片段」添加。", section: .templates) }
            ForEach(MCPHost.allCases) { host in
                ForEach(instructionIDs(host).filter { id in
                    !model.snapshot.templates.contains { $0.id == id }
                }, id: \.self) { id in
                    HStack {
                        Text(host.displayName + " · " + L10n.tr("片段已删除，请移除引用后重新选择。"))
                            .foregroundStyle(.orange)
                        Spacer()
                        Button(L10n.tr("移除不可用的片段")) { setInstruction(id, enabled: false, host: host) }
                    }.font(AppFont.secondary)
                }
            }
        }
    }

    private var mcpList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isProject {
                Text(L10n.tr("仅配置当前项目；全局 MCP 仍可能生效。Codex 项目需设为受信任后才会加载。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }
            let entries = model.mcpLibrary.entries.filter { matches([$0.name, $0.commandOrURL]) }
            ForEach(entries) { entry in
                resourceRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.name).font(AppFont.body.weight(.semibold))
                        Text(MCPConnectionFields.transportTitle(entry.transport)).font(AppFont.secondary).foregroundStyle(.secondary)
                    }
                } toggles: {
                    SkillHostToggles(skillName: entry.name, identifierPrefix: "\(prefix).mcp.\(entry.id)",
                        isSelected: { model.mcpLibrary.selectedIDs(host: $0, projectID: projectID).contains(entry.id) },
                        isEnabled: { _ in !model.isWorking },
                        setSelected: { _ = model.mcpLibrary.select(entry.id, enabled: $1, host: $0, projectID: projectID) })
                }
            }
            if entries.isEmpty { empty("没有匹配的 MCP 服务，请调整搜索或到「MCP 服务」添加。", section: .mcp) }
            ForEach(MCPHost.allCases) { host in
                let conflicts = model.mcpLibrary.externalConflicts(host: host, projectID: projectID)
                if !conflicts.isEmpty {
                    Text(host.displayName + " · " + L10n.tr("已有同名 MCP 服务不属于本应用，默认不会覆盖。"))
                        .font(AppFont.secondary).foregroundStyle(.red)
                    Text(conflicts.map(\.name).joined(separator: "、")).font(AppFont.code)
                    Button(L10n.tr("覆盖同名服务…")) { overwriteHost = host }
                }
                let missing = model.mcpLibrary.selectedIDs(host: host, projectID: projectID).filter { id in
                    !model.mcpLibrary.entries.contains { $0.id == id }
                }
                ForEach(missing, id: \.self) { id in
                    HStack {
                        Text(host.displayName + " · " + L10n.tr("所选服务已从配置库删除，请取消引用。"))
                        Spacer()
                        Button(L10n.tr("移除引用")) { _ = model.mcpLibrary.select(id, enabled: false, host: host, projectID: projectID) }
                    }.font(AppFont.secondary)
                }
            }
            Text(L10n.tr("取消选择后保存，仅移除栖集写入且未经修改的服务；已有同名服务会阻止覆盖。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            Button(L10n.tr("管理 MCP 配置库")) { model.section = .mcp }
        }
    }

    private var pluginList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isProject {
                Text(L10n.tr("仅配置当前项目的 Claude Code 插件；全局插件仍可能生效。Codex 插件请到全局配置中管理。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }
            let visible = plugins.plugins.filter { matches([$0.name, $0.description, $0.marketplaceID ?? ""]) }
            if !isProject {
                Text(L10n.tr("插件仅支持所属工具。Claude Code 关闭表示停用；Codex 关闭表示卸载并保留数据。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }
            ForEach(visible) { plugin in
                resourceRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plugin.name).font(AppFont.body.weight(.semibold))
                        Text([plugin.marketplaceID, plugin.version].compactMap { $0 }.joined(separator: " · "))
                            .font(AppFont.metadata).foregroundStyle(.secondary)
                        Text(plugin.description).font(AppFont.secondary).foregroundStyle(.secondary).lineLimit(2)
                        if let action = plugins.action(plugin) {
                            Text(L10n.tr("待\(LocalizedText(stringLiteral: action.displayName))，预览后保存"))
                                .font(AppFont.metadata).foregroundStyle(AppColor.accentText)
                        }
                        ForEach(plugin.risks, id: \.self) { risk in
                            Text(L10n.text(UserFacingText.pluginRisk(risk))).font(AppFont.secondary).foregroundStyle(.orange)
                        }
                        if plugin.host == .codex && plugin.installed && plugin.enabled == false {
                            Text(L10n.tr("这个插件已停用，请到 Codex 中启用。"))
                                .font(AppFont.secondary).foregroundStyle(.secondary)
                        }
                    }
                } toggles: {
                    SkillHostToggles(skillName: plugin.name, identifierPrefix: "\(prefix).plugin.\(plugin.id)",
                        isSelected: { $0 == plugin.host && plugins.selected(plugin) },
                        isEnabled: { $0 == plugin.host && !model.isWorking && !plugins.isLoading && plugins.isReady
                            && !(plugin.host == .codex && plugin.installed && plugin.enabled == false) },
                        setSelected: { _, enabled in plugins.select(plugin, enabled: enabled) })
                }
            }
            if visible.isEmpty { empty("当前范围没有匹配的本机插件。请先在 AI 工具中取得插件包。", section: .plugins) }
            if plugins.plugins.contains(where: { plugins.action($0) == .install }) {
                Toggle(L10n.tr("我已核对插件中的自动运行脚本、命令和其他可运行内容。"), isOn: $plugins.acknowledgedRisk)
                    .toggleStyle(.checkbox).font(AppFont.secondary)
                Text(L10n.tr("安装插件前请确认可运行组件，再从预览菜单选择插件。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }
            ForEach(plugins.issues, id: \.self) { issue in
                Text(L10n.text(UserFacingText.diagnostic(issue, context: .plugin))).font(AppFont.secondary).foregroundStyle(.orange)
            }
            Button(L10n.tr("管理插件来源")) { model.section = .plugins }
        }
    }

    private func canEdit(_ host: MCPHost) -> Bool {
        if isProject { return project != nil && project?.id == model.selectedProjectID && !model.isWorking }
        return global.canEditSkills(host: host)
    }

    private func skillIDs(_ host: MCPHost) -> [String] {
        if isProject { return project?.harnessSelections[host.rawValue]?.skillIDs ?? [] }
        return global.selection(host: host)?.skillIDs ?? []
    }

    private func instructionIDs(_ host: MCPHost) -> [String] {
        if isProject { return project?.harnessSelections[host.rawValue]?.instructionIDs ?? [] }
        return global.selection(host: host)?.instructionIDs ?? []
    }

    private func setSkill(_ skill: SkillEntry, enabled: Bool, host: MCPHost) {
        if isProject { model.setSkill(skill, enabled: enabled, host: host) }
        else { global.setSkill(skill, enabled: enabled, host: host, catalog: model.snapshot.catalog.entries) }
    }

    private func removeSkill(_ id: String, host: MCPHost) {
        if isProject { model.removeUnavailableSkill(id, host: host) }
        else { global.setSkill(id, enabled: false, host: host) }
    }

    private func setInstruction(_ id: String, enabled: Bool, host: MCPHost) {
        if isProject { model.setInstruction(id, enabled: enabled, host: host) }
        else { global.setInstruction(id, enabled: enabled, host: host) }
    }

    private func resourceRow<Content: View, Toggles: View>(@ViewBuilder content: () -> Content,
                                                         @ViewBuilder toggles: () -> Toggles) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                content().frame(maxWidth: .infinity, alignment: .leading)
                toggles()
            }.padding(.vertical, 12)
            Divider()
        }
    }

    private func matches(_ fields: [String]) -> Bool {
        query.isEmpty || fields.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func empty(_ message: String, section: NavigationItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text(message)).font(AppFont.secondary).foregroundStyle(.secondary)
            Button(L10n.tr("前往资源库")) { model.section = section }
        }.padding(.vertical, 16)
    }

    private func present(_ plan: StoredDeploymentPlan?) {
        guard let plan else { return }
        model.preparedPlan = plan
        model.planPresented = true
    }
}
