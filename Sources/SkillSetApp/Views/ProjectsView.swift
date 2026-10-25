import SwiftUI
import AppKit
import SkillSetCore

struct ProjectsView: View {
    @State private var removingHost = false
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppLayout.columnSpacing) {
                PageActionHeader(
                    eyebrow: "PROJECT WORKSPACE",
                    title: L10n.tr("为项目配置技能"),
                    detail: L10n.tr("把需要的技能和规则用于本机项目。先选择配置，再审阅并批准写入。")
                ) {
                    Button {
                        chooseProject()
                    } label: {
                        Label(L10n.tr("添加项目"), systemImage: "plus")
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(AppButtonStyle(kind: .primary))
                    .accessibilityIdentifier("projects.addProject")
                    .help(L10n.tr("添加本机项目"))
                }

                Text(L10n.tr("1. 添加项目 → 2. 选择技能或使用预设 → 3. 预览并批准"))
                    .font(AppFont.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("projects.workflowGuide")

                HStack(alignment: .top, spacing: AppLayout.columnSpacing) {
                    projectRail
                        .frame(width: AppLayout.listWidth)
                    projectDetail
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            async let plans: Void = model.refreshPendingPlansInBackground()
            async let inheritance: Void = model.globalConfiguration.refreshInheritanceInBackground()
            _ = await (plans, inheritance)
        }
    }

    private var projectRail: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(L10n.tr("项目"))
                        .font(AppFont.heading)
                    Spacer()
                }
                if !model.projects.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(model.projects) { project in
                                Button {
                                    model.selectedProjectID = project.id
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: project.id == model.selectedProjectID ? "folder.fill" : "folder")
                                            .foregroundStyle(project.id == model.selectedProjectID ? AppColor.accentText : .secondary)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(project.name)
                                                .font(AppFont.body.weight(.semibold))
                                                .lineLimit(1)
                                                .foregroundStyle(.primary)
                                            Text(L10n.tr("\(project.allDraftSkillIDs.count) 个技能 · \(L10n.text(project.adapter))"))
                                                .font(AppFont.secondary)
                                                .lineLimit(2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        if project.pendingChanges > 0 {
                                            Text("\(project.pendingChanges)")
                                                .font(AppFont.metadata.weight(.bold))
                                                .foregroundStyle(AppColor.accentText)
                                                .padding(5)
                                                .background(AppColor.accentSoft, in: Circle())
                                        }
                                    }
                                    .padding(.vertical, 7)
                                    .padding(.horizontal, 8)
                                    .selectionRow(project.id == model.selectedProjectID)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(project.path)
                            }
                        }
                    }
                    .frame(height: min(360, CGFloat(model.projects.count) * 74))
                }
                Divider()
                Text(L10n.tr("技能和规则只写入当前项目"))
                    .font(AppFont.secondary.weight(.semibold))
                Text(L10n.tr("全局、父目录或插件提供的技能和规则仍可能生效。插件与 MCP 连接需逐项核对使用范围。"))
                    .font(AppFont.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var projectDetail: some View {
        if let project = model.selectedProject {
            VStack(alignment: .leading, spacing: 18) {
                SurfaceCard(emphasis: true) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(project.name)
                            .font(AppFont.title.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    Text(project.path)
                        .font(AppFont.secondary.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { projectStateBadges(project) }
                        VStack(alignment: .leading, spacing: 6) { projectStateBadges(project) }
                    }
                    if let notice = model.projectPlanNotice(for: project.id) {
                        Label {
                            Text(notice.message)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: notice.tone == .error ? "exclamationmark.triangle" : "checkmark.circle")
                        }
                        .font(AppFont.secondary)
                        .foregroundStyle(notice.tone == .error ? .red : .secondary)
                        .accessibilityIdentifier("projects.planNotice")
                    }
                    Divider()
                    if (model.projectIssues[project.id] ?? []).isEmpty {
                        DisclosureGroup(L10n.tr("其他来源的影响")) {
                            inheritanceDetails(project)
                        }
                        .font(AppFont.secondary)
                        .accessibilityIdentifier("projects.inheritanceDetails")
                    } else {
                        // 读取失败时直接给出原因，恢复操作不能藏在折叠内容里。
                        Label(L10n.tr("其他来源的影响"), systemImage: "exclamationmark.triangle")
                            .font(AppFont.secondary.weight(.semibold))
                            .foregroundStyle(.orange)
                        inheritanceDetails(project)
                    }
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 15) {
                        ConfigurationSectionHeader {
                            Text(L10n.tr("项目配置草稿")).font(AppFont.heading)
                        } actions: {
                            Button(L10n.tr("预览 \(project.editingAgentName) 变更")) {
                                model.prepareDeploymentPlan()
                            }
                            .buttonStyle(AppButtonStyle(kind: .primary))
                            .tint(AppColor.accent)
                            .fixedSize()
                            .disabled(!model.canPrepareDeploymentPlan)
                            .help(model.isWorking
                                ? L10n.tr("正在处理，请稍候")
                                : L10n.tr("生成变更计划，审阅后再写入"))
                            .accessibilityIdentifier("projects.previewChanges")
                        }
                        HStack {
                            Button(L10n.tr("使用预设…")) {
                                model.presetSelection = PresetSelectionRequest(projectID: project.id)
                            }
                            .accessibilityIdentifier("projects.usePreset")
                            Spacer()
                            Text(L10n.tr("\(project.draftSkillIDs.count) 条"))
                                .font(AppFont.secondary).foregroundStyle(.secondary)
                        }
                        hostPicker(project: project)
                        AppPicker(title: L10n.tr("技能安装方式"), selection: $model.skillInstallMethod,
                                  valueLabel: L10n.tr(model.skillInstallMethod == .copy ? "复制独立文件" : "软链接（推荐）"), showsLabel: false) {
                            Text(L10n.tr("软链接（推荐）")).tag(SkillInstallMethod.symlink)
                            Text(L10n.tr("复制独立文件")).tag(SkillInstallMethod.copy)
                        }
                        Text(L10n.tr("软链接指向 ~/.perch 中的固定版本；复制后的文件可独立编辑。"))
                            .font(AppFont.secondary).foregroundStyle(.secondary)

                        Divider()
                        skillChooser(project: project)
                    }
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L10n.tr("AGENTS 片段"))
                                .font(AppFont.heading)
                            Spacer()
                            StatusBadge(text: project.editingAgent == "codex" ? "AGENTS.md" : "CLAUDE.md", tone: .neutral)
                        }
                        ForEach(model.snapshot.templates) { template in
                            Button {
                                model.toggleInstruction(template)
                            } label: {
                                HStack(alignment: .top, spacing: 9) {
                                    Image(systemName: project.fragments.contains(template.id) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(project.fragments.contains(template.id) ? AppColor.accentText : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(UserFacingText.templateTitle(template))
                                            .font(AppFont.secondary.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(UserFacingText.templatePurpose(template))
                                            .font(AppFont.metadata)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(project.fragments.filter { id in !model.snapshot.templates.contains { $0.id == id } }, id: \.self) { id in
                            HStack {
                                Text(L10n.tr("片段已删除，请移除引用后重新选择。"))
                                    .font(AppFont.secondary).foregroundStyle(.red)
                                Spacer()
                                Button(L10n.tr("移除引用")) { model.toggleInstructionID(id) }
                            }
                        }
                        Text(L10n.tr("只更新栖集起止标记之间的规则，保留文件中的其他内容。已有标记不完整或位置冲突时，会暂停写入并提示检查。"))
                            .font(AppFont.secondary)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(MCPHost.allCases.filter { $0.rawValue == project.editingAgent }) { host in
                    MCPSelectionCard(model: model, host: host, projectID: UUID(uuidString: project.id))
                    if let projectID = UUID(uuidString: project.id) {
                        PluginConfigurationCard(model: model, host: host, projectID: projectID)
                    }
                }

                ProjectPresetComponents(model: model, project: project)

                if let observations = model.projectSkillObservations[project.id], !observations.isEmpty {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.tr("项目技能现状"))
                                .font(AppFont.heading)
                            Text(L10n.tr("项目原有技能会保留。取消选择只会移除栖集写入且未经修改的技能；仍需在 AI 工具中确认是否加载。"))
                                .font(AppFont.secondary)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(observations, id: \.relativePath) { observation in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(observation.skillID.map(model.skillDisplayTitle) ?? (observation.relativePath as NSString).lastPathComponent)
                                        .font(AppFont.secondary.weight(.semibold))
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                    ViewThatFits(in: .horizontal) {
                                        HStack(spacing: 8) { observationBadges(observation) }
                                        VStack(alignment: .leading, spacing: 4) { observationBadges(observation) }
                                    }
                                    Text(observation.relativePath)
                                        .font(AppFont.metadata.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }

                if let issues = model.projectIssues[project.id], !issues.isEmpty {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(L10n.tr("需要检查"), systemImage: "exclamationmark.triangle")
                                .font(AppFont.heading)
                                .foregroundStyle(.orange)
                            ForEach(issues, id: \.self) { issue in
                                Text(L10n.text(UserFacingText.diagnostic(issue, context: .project)))
                                    .font(AppFont.secondary)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                let plans = model.pendingPlans.filter { $0.plan.projectPath == project.path }
                if !plans.isEmpty {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(L10n.tr("待你批准的计划"), systemImage: "tray.full")
                                    .font(AppFont.heading)
                                Spacer()
                                StatusBadge(text: L10n.tr("\(plans.count) 个"), tone: .warning)
                            }
                            ForEach(plans) { record in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(record.plan.digest.prefix(16) + "…")
                                            .font(AppFont.secondary.monospaced())
                                        Text(L10n.tr("\(record.plan.changes.count) 项变更 · 有效期至 \(L10n.date(record.expiresAt))"))
                                            .font(AppFont.metadata)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(L10n.tr("审阅")) {
                                        model.reviewPlan(record)
                                    }
                                    .buttonStyle(AppButtonStyle())
                                }
                            }
                            Text(L10n.tr("AI 可以生成计划和执行已批准的计划；每份计划都需要你在本机窗口批准。"))
                                .font(AppFont.secondary)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 16) {
                EmptyState(icon: "folder", title: L10n.tr("还没有添加项目"), detail: L10n.tr("先选择项目文件夹。添加后可以选择技能或使用预设，预览并批准后才会修改项目文件。"))
                Button(L10n.tr("选择项目目录")) {
                    chooseProject()
                }
                .buttonStyle(AppButtonStyle(kind: .primary))
                .tint(AppColor.accent)
                HStack(spacing: 12) {
                    Button(L10n.tr("浏览技能库")) { model.section = .skills }
                        .accessibilityIdentifier("projects.browseSkills")
                    Button(L10n.tr("查看预设")) { model.section = .presets }
                        .accessibilityIdentifier("projects.browsePresets")
                }
                .buttonStyle(AppButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func inheritanceDetails(_ project: ProjectRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(UserFacingText.localizedInheritance(project.inherited))
                .font(AppFont.secondary)
            ForEach(MCPHost.allCases.filter { project.agents.contains($0.displayName) }) { host in
                if let error = model.globalConfiguration.inheritanceErrors[host] {
                    Text(host.displayName + " · " + L10n.text(error)).foregroundStyle(.orange)
                } else {
                    let resources = model.globalConfiguration.inheritedResources[host] ?? []
                    Text(L10n.tr("\(host.displayName) 全局资源：\(resources.count) 项；取消项目选择不会停用全局内容。"))
                    ForEach(resources) { resource in
                        Text(resource.path).font(AppFont.code).textSelection(.enabled)
                    }
                }
            }
            Text(L10n.tr("已扫描用户级技能与规则文件；父目录和插件内容尚未检查，同名优先级及会话加载仍需宿主确认。"))
                .font(AppFont.metadata)
        }
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func observationStatus(_ status: String) -> String {
        switch status {
        case "matching": L10n.tr("内容匹配")
        case "drifted": L10n.tr("存在本地修改")
        case "symlink": L10n.tr("符号链接，保留不改")
        default: L10n.tr("内容待核对")
        }
    }

    @ViewBuilder
    private func projectStateBadges(_ project: ProjectRecord) -> some View {
        StatusBadge(text: project.adapter, tone: .accent).fixedSize()
        StatusBadge(text: lockStatusLabel(project.lockStatus), tone: project.lockStatus == "valid" ? .positive : .warning).fixedSize()
        StatusBadge(text: L10n.tr("全部工具草稿 \(project.pendingChanges) 项变更"), tone: project.pendingChanges > 0 ? .warning : .positive).fixedSize()
    }

    @ViewBuilder
    private func observationBadges(_ observation: ProjectSkillObservation) -> some View {
        StatusBadge(text: observation.ownership == "managed" ? L10n.tr("由栖集管理") : L10n.tr("项目已有"), tone: .neutral).fixedSize()
        StatusBadge(text: observationStatus(observation.status), tone: observation.status == "matching" ? .neutral : .warning).fixedSize()
    }

    private func hostPicker(project: ProjectRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("正在配置的 AI 工具"))
                .font(AppFont.secondary.weight(.semibold))
            HStack(spacing: 8) {
                ForEach(AgentHost.allCases) { host in
                    let agent = host == .codex ? "codex" : "claude-code"
                    let selected = project.editingAgent == agent
                    let selection = project.harnessSelections[agent]
                    Button {
                        model.selectProjectHost(host)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(host.rawValue).font(AppFont.secondary.weight(.semibold))
                            Text(selection.map { L10n.tr("\($0.skillIDs.count) 个技能 · \($0.instructionIDs.count) 个片段") }
                                ?? L10n.tr("尚未配置"))
                                .font(AppFont.metadata).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(AppButtonStyle(selected: selected))
                    .accessibilityIdentifier("projects.host.\(agent)")
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
            Text(L10n.tr("技能和规则按 AI 工具分别保存。切换工具不会复制选择，也不会修改项目文件。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.tr("预览只提交当前工具的技能与规则，其他工具的未部署草稿会保留。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 8) {
                Text(project.editingAgent == "codex" ? ".agents/skills · AGENTS.md" : ".claude/skills · CLAUDE.md")
                    .font(AppFont.code).foregroundStyle(.secondary).textSelection(.enabled)
                Spacer()
                if project.harnessSelections[project.editingAgent] != nil {
                    Button(L10n.tr("移除此工具的配置…")) { removingHost = true }
                        .buttonStyle(AppButtonStyle(kind: .quiet))
                        .accessibilityIdentifier("projects.removeHost")
                }
            }
        }
        .confirmationDialog(L10n.tr("移除当前 AI 工具的项目配置？"), isPresented: $removingHost) {
            Button(L10n.tr("从草稿移除"), role: .destructive) {
                model.toggleAgent(project.editingAgent == "codex" ? .codex : .claude)
            }
        } message: {
            Text(L10n.tr("将清空此工具的技能与规则选择。预览并批准后，才会移除栖集管理的内容；另一个工具及项目已有内容保留。"))
        }
    }

    private func skillChooser(project: ProjectRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.tr("可选技能"))
                    .font(AppFont.secondary.weight(.semibold))
                Spacer()
                Text(L10n.tr("搜索框可筛选 \(model.snapshot.catalog.entries.count) 条"))
                    .font(AppFont.metadata)
                    .foregroundStyle(.secondary)
            }
            SkillSearchField(model: model)
            Text(L10n.tr("点击右侧图标，分别选择 Codex 和 Claude Code 的技能。选择只保存草稿；切换到对应工具后预览并批准。"))
                .font(AppFont.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(model.filteredSkills.prefix(12)) { skill in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(skill.slug)
                            .font(AppFont.body.weight(.semibold))
                            .lineLimit(1)
                            .help(skill.slug)
                        Text(model.skillSourceTitle(skill))
                            .font(AppFont.metadata.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(skill.description)
                            .font(AppFont.secondary)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if skill.isBlocked {
                            StatusBadge(text: L10n.tr("阻塞"), tone: .danger)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    SkillHostToggles(
                        skillName: skill.slug,
                        identifierPrefix: "projects.skill.\(skill.id)",
                        isSelected: { model.isDraftSelected(skill, host: $0) },
                        isEnabled: { host in
                            !model.isWorking && (!skill.isBlocked || model.isDraftSelected(skill, host: host))
                        },
                        setSelected: { host, enabled in
                            model.setSkill(skill, enabled: enabled, host: host)
                        }
                    )
                }
                .padding(.vertical, 6)
            }
            if model.filteredSkills.count > 12 {
                Text(L10n.tr("还有 \(model.filteredSkills.count - 12) 条匹配结果，请到「技能库」查看完整列表。"))
                    .font(AppFont.secondary)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("添加本机项目")
        panel.prompt = L10n.tr("添加项目")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = model.registerProject(url)
    }

    private func lockStatusLabel(_ status: String) -> String {
        switch status {
        case "valid": L10n.tr("配置记录有效")
        case "stale": L10n.tr("配置内容已改变")
        case "unlocked": L10n.tr("尚无配置记录")
        case "corrupt": L10n.tr("配置记录无法读取")
        default: L10n.tr("配置状态待检查")
        }
    }
}

struct PlanSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingApply = false
    @State private var rulePreviews: [RuleFilePreview] = []
    @State private var rulePreviewError: String?
    @State private var rulePreviewsLoaded = false
    @State private var selectedChangePath = ""

    private var isPluginPlan: Bool {
        model.preparedPlan?.plan.metadata?["planType"] == "plugin-lifecycle"
    }

    private var isMCPPlan: Bool {
        model.preparedPlan?.plan.metadata?["planType"] == "mcp-configuration"
    }

    private var isGlobalPlan: Bool {
        model.preparedPlan?.plan.metadata?["planType"] == "global-configuration"
    }

    private var approvalTitle: String {
        isGlobalPlan ? L10n.tr("批准并更新全局配置") : isPluginPlan ? L10n.tr("批准并执行命令") : isMCPPlan ? L10n.tr("批准并写入配置") : L10n.tr("批准并写入项目")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(isGlobalPlan ? L10n.tr("全局配置计划") : isPluginPlan ? L10n.tr("插件变更计划") : isMCPPlan ? L10n.tr("MCP 配置计划") : L10n.tr("变更计划"))
                    .font(AppFont.title.weight(.bold))
                Spacer()
                if let record = model.preparedPlan {
                    StatusBadge(
                        text: record.isExpired(at: Date()) ? L10n.tr("已过期") : L10n.tr("待人工批准"),
                        tone: record.isExpired(at: Date()) ? .danger : .warning
                    )
                }
            }
            if let record = model.preparedPlan {
                planContext(record)
                reviewArea(record)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                DisclosureGroup(L10n.tr("计划详情（指纹与有效期）")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(planIntro)
                            .font(AppFont.secondary)
                            .foregroundStyle(.secondary)
                        KeyValueLine(key: L10n.tr("计划指纹"), value: record.plan.digest, monospaced: true)
                        KeyValueLine(key: L10n.tr("有效至"), value: L10n.date(record.expiresAt))
                        if isPluginPlan {
                            KeyValueLine(
                                key: L10n.tr("目标清单指纹"),
                                value: record.plan.metadata?["pluginExpectedManifestDigest"].flatMap {
                                    $0.isEmpty ? nil : $0
                                } ?? L10n.tr("未指定（仅允许唯一记录）"),
                                monospaced: true
                            )
                        }
                        ForEach(record.plan.changes, id: \.relativePath) { change in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayedPath(change, record: record))
                                    .font(AppFont.code)
                                    .textSelection(.enabled)
                                Text(hashLine(change))
                                    .font(AppFont.metadata.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .font(AppFont.secondary)
                DisclosureGroup(L10n.tr("批准前须知")) {
                  VStack(alignment: .leading, spacing: 8) {
                    Label(
                        isPluginPlan
                            ? L10n.tr("批准仅对当前计划、插件、范围、清单和命令参数有效")
                            : L10n.tr("批准仅对当前计划、目标路径和原文件内容有效"),
                        systemImage: "checkmark.shield"
                    )
                    Label(L10n.tr("AI 不能代替你批准计划"), systemImage: "checkmark.shield")
                    Label(
                        isPluginPlan
                            ? L10n.tr("执行前重新读取插件状态；变化会使计划失效，命令不自动重试")
                            : L10n.tr("写入前再次核对原文件内容；任一步失败会尝试恢复"),
                        systemImage: "checkmark.shield"
                    )
                  }.padding(.top, 8)
                }
                .font(AppFont.secondary)
                .foregroundStyle(.secondary)
                let warnings = visibleWarnings(record)
                if !warnings.isEmpty {
                    Text(warnings.map { L10n.text(UserFacingText.diagnostic($0, context: .plan)) }.joined(separator: "\n"))
                        .font(AppFont.secondary).foregroundStyle(.orange)
                }
            } else {
                EmptyState(icon: "doc.badge.gearshape", title: L10n.tr("没有可审阅的计划"), detail: L10n.tr("返回项目页重新生成。"))
            }
            if let error = model.planError ?? rulePreviewError {
                Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red).textSelection(.enabled)
                    .accessibilityIdentifier("plan.error")
            }
            HStack {
                Spacer()
                Button(L10n.tr("取消")) {
                    model.dismissPlan()
                    dismiss()
                }
                    .keyboardShortcut(.cancelAction)
                Button(approvalTitle) {
                    confirmingApply = true
                }
                .buttonStyle(AppButtonStyle(kind: .primary))
                .tint(AppColor.accent)
                .disabled(model.preparedPlan == nil || model.isWorking || rulePreviewError != nil
                    || !rulePreviewsLoaded || model.preparedPlan?.isExpired(at: Date()) == true)
            }
        }
        .appControls()
        .padding(20)
        .frame(width: 880, height: 680)
        .task(id: model.preparedPlan?.id) { loadRulePreviews() }
        .confirmationDialog(
            isGlobalPlan ? L10n.tr("确认更新当前用户的全局配置？") : isPluginPlan ? L10n.tr("执行这条插件命令？") : isMCPPlan ? L10n.tr("更新 AI 工具配置？") : L10n.tr("确认写入这个项目？"),
            isPresented: $confirmingApply,
            titleVisibility: .visible
        ) {
            Button(approvalTitle, role: .destructive) {
                _ = model.approveAndApplyPreparedPlan()
            }
            Button(L10n.tr("返回审阅"), role: .cancel) {}
        } message: {
            if let record = model.preparedPlan {
                Text(
                    isPluginPlan
                        ? L10n.tr("将在 \(record.plan.projectPath) 调用 AI 工具运行命令。批准只对本次计划有效；插件状态变化或命令失败会保留操作记录。")
                        : L10n.tr("将修改 \(record.plan.projectPath) 中列出的 \(record.plan.changes.count) 项内容。批准只对本次计划有效；文件内容改变后需要重新生成计划。")
                )
            }
        }
    }

    private var planIntro: String {
        isPluginPlan
            ? L10n.tr("核对 AI 工具、插件、影响范围和将运行的命令。批准后，栖集会调用对应工具完成操作。")
            : L10n.tr("核对目标路径、内容指纹和变更内容。写入前会备份原文件并保存操作记录。")
    }

    /// 标题下只留目标路径和范围。指纹、哈希与备份说明放到差异下方，避免挤占正文。
    private func planContext(_ record: StoredDeploymentPlan) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(record.plan.projectPath)
                .font(AppFont.code)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            if isGlobalPlan {
                Text((MCPHost(rawValue: record.plan.metadata?["globalHost"] ?? "")?.displayName ?? "")
                    + " · " + L10n.tr("此操作影响当前用户在该 AI 工具中的全部项目。"))
                    .font(AppFont.secondary)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            } else if isMCPPlan {
                Text((MCPHost(rawValue: record.plan.metadata?["host"] ?? "")?.displayName ?? "") + " · "
                    + (record.plan.metadata?["scope"] == "user" ? L10n.tr("当前用户的全部项目") : L10n.tr("项目")))
                    .font(AppFont.secondary)
                    .foregroundStyle(.secondary)
                Text(record.plan.metadata?["configPath"] ?? "")
                    .font(AppFont.code)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if isPluginPlan {
                Text("\(MCPHost(rawValue: record.plan.metadata?["pluginHost"] ?? "")?.displayName ?? L10n.tr("未识别工具")) · "
                    + L10n.text(UserFacingText.metadata(record.plan.metadata?["pluginScope"] ?? "", field: .scope)))
                    .font(AppFont.secondary)
                    .foregroundStyle(.secondary)
                Text(model.pluginDisplayTitle(record.plan.metadata?["pluginID"]))
                    .font(AppFont.code)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func visibleWarnings(_ record: StoredDeploymentPlan) -> [String] {
        record.plan.warnings.filter { warning in
            !UserFacingText.isInformationalPlanNote(warning)
                && !(isGlobalPlan && warning == "此操作影响当前用户在该 AI 工具中的全部项目。")
        }
    }

    @ViewBuilder
    private func reviewArea(_ record: StoredDeploymentPlan) -> some View {
        let changes = record.plan.changes
        VStack(alignment: .leading, spacing: 8) {
            Text(isPluginPlan ? L10n.tr("工具命令 \(changes.count) 项") : L10n.tr("文件变更 \(changes.count) 项"))
                .font(AppFont.heading)
            if isPluginPlan || isMCPPlan {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(changes, id: \.relativePath) { change in
                            changeSummary(change, record: record)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if changes.count > 1 {
                HStack(alignment: .top, spacing: 12) {
                    changeList(changes)
                        .frame(maxHeight: .infinity, alignment: .top)
                    selectedChangeDetail(record, changes: changes)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            } else {
                selectedChangeDetail(record, changes: changes)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
            }
        }
    }

    private func changeList(_ changes: [PlannedChange]) -> some View {
        let selected = resolvedSelection(changes)
        return ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(changes, id: \.relativePath) { change in
                    Button {
                        selectedChangePath = change.relativePath
                    } label: {
                        HStack(spacing: 8) {
                            StatusBadge(
                                text: L10n.text(UserFacingText.changeAction(change.action)),
                                tone: change.action == "add" ? .positive : .warning
                            )
                            Text(change.relativePath)
                                .font(AppFont.code)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .selectionRow(change.relativePath == selected)
                    .accessibilityLabel(change.relativePath)
                }
            }
        }
        .frame(width: 248)
    }

    @ViewBuilder
    private func selectedChangeDetail(_ record: StoredDeploymentPlan, changes: [PlannedChange]) -> some View {
        let path = resolvedSelection(changes)
        if let change = changes.first(where: { $0.relativePath == path }) {
            if let preview = rulePreviews.first(where: { $0.id == change.relativePath }) {
                RuleFilePreviewView(preview: preview)
            } else {
                ScrollView {
                    changeSummary(change, record: record)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func changeSummary(_ change: PlannedChange, record: StoredDeploymentPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayedPath(change, record: record))
                .font(AppFont.code.weight(.semibold))
                .textSelection(.enabled)
            Text(UserFacingText.planSummary(change))
                .font(AppFont.secondary)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(hashLine(change))
                .font(AppFont.metadata.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }

    private func resolvedSelection(_ changes: [PlannedChange]) -> String {
        if changes.contains(where: { $0.relativePath == selectedChangePath }) {
            return selectedChangePath
        }
        return changes.first { isRuleChange($0) }?.relativePath ?? changes.first?.relativePath ?? ""
    }

    private func isRuleChange(_ change: PlannedChange) -> Bool {
        change.scope != "project-state"
            && ["AGENTS.md", "CLAUDE.md"].contains(URL(fileURLWithPath: change.relativePath).lastPathComponent)
    }

    private func displayedPath(_ change: PlannedChange, record: StoredDeploymentPlan) -> String {
        if change.scope == "project-state" {
            return ProjectLockStore(
                projectRoot: URL(fileURLWithPath: record.plan.projectPath),
                stateRoot: model.runtimePaths.applicationSupportRoot
            ).directoryURL.appendingPathComponent(change.relativePath).path
        }
        if isGlobalPlan {
            return URL(fileURLWithPath: record.plan.projectPath).appendingPathComponent(change.relativePath).path
        }
        return change.relativePath
    }

    private func hashLine(_ change: PlannedChange) -> String {
        isPluginPlan
            ? L10n.tr("观察 \(change.beforeHash ?? L10n.tr("不存在")) · 命令 \(change.afterHash ?? L10n.tr("未记录"))")
            : L10n.tr("旧 \(change.beforeHash ?? L10n.tr("不存在")) · 新 \(change.afterHash ?? L10n.tr("删除"))")
    }

    private func loadRulePreviews() {
        rulePreviews = []
        rulePreviewError = nil
        rulePreviewsLoaded = false
        guard let record = model.preparedPlan else { return }
        if let preferred = record.plan.changes.first(where: isRuleChange)?.relativePath ?? record.plan.changes.first?.relativePath {
            selectedChangePath = preferred
        }
        if isPluginPlan || isMCPPlan { rulePreviewsLoaded = true; return }
        do {
            rulePreviews = try record.plan.changes.filter(isRuleChange).map { try RuleFilePreview.load(record: record, change: $0) }
            rulePreviewsLoaded = true
        } catch RulePreviewError.tooLarge {
            rulePreviewError = "规则文件超过 1 MiB，无法在此完整审阅；请先精简文件，再重新生成计划。"
        } catch {
            rulePreviewError = "规则文件或预览内容已改变或无法读取，请取消并重新生成计划。"
        }
    }

}
