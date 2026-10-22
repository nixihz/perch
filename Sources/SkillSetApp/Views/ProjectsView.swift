import SwiftUI
import AppKit
import SkillSetCore

struct ProjectsView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppLayout.columnSpacing) {
                PageHeader(
                    eyebrow: "PROJECT WORKSPACE",
                    title: L10n.tr("为项目配置技能"),
                    detail: L10n.tr("把需要的技能和规则用于本机项目。先选择配置，再审阅并批准写入。")
                )

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
            model.refreshPendingPlans()
        }
    }

    private var projectRail: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(L10n.tr("项目"))
                        .font(AppFont.heading)
                    Spacer()
                    Button {
                        chooseProject()
                    } label: {
                        Label(L10n.tr("添加项目"), systemImage: "plus")
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("projects.addProject")
                    .help(L10n.tr("添加本机项目"))
                }
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
                                    .foregroundStyle(.primary)
                                Text(L10n.tr("\(project.draftSkillIDs.count) 个技能 · \(L10n.text(project.adapter))"))
                                    .font(AppFont.secondary)
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
                        Button(L10n.tr("预览变更")) {
                            model.prepareDeploymentPlan()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColor.accent)
                        .fixedSize()
                        .disabled(model.isWorking || model.runtimePaths.repositoryRoot == nil)
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
                        HStack {
                            Text(L10n.tr("项目配置草稿"))
                                .font(AppFont.heading)
                            Spacer()
                            Button(L10n.tr("使用预设…")) {
                                model.presetSelection = PresetSelectionRequest(projectID: project.id)
                            }
                            .accessibilityIdentifier("projects.usePreset")
                            Text(L10n.tr("\(project.draftSkillIDs.count) 条"))
                                .font(AppFont.secondary)
                                .foregroundStyle(.secondary)
                        }
                        hostPicker(project: project)
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
                            StatusBadge(text: L10n.tr("写入 AGENTS.md / CLAUDE.md"), tone: .neutral)
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
                                    Text("#\(template.id)")
                                        .font(AppFont.metadata.monospaced())
                                        .foregroundStyle(.secondary)
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
                                    Text(observation.skillID ?? (observation.relativePath as NSString).lastPathComponent)
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
                                    .buttonStyle(.bordered)
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
                .buttonStyle(.borderedProminent)
                .tint(AppColor.accent)
                HStack(spacing: 12) {
                    Button(L10n.tr("浏览技能库")) { model.section = .skills }
                        .accessibilityIdentifier("projects.browseSkills")
                    Button(L10n.tr("查看预设")) { model.section = .presets }
                        .accessibilityIdentifier("projects.browsePresets")
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func inheritanceDetails(_ project: ProjectRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(UserFacingText.localizedInheritance(project.inherited))
                .font(AppFont.secondary)
            Text(L10n.tr("目前只读取项目配置，尚未检查全局、父目录或插件提供的内容。"))
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
        StatusBadge(text: L10n.tr("草稿 \(project.pendingChanges) 项变更"), tone: project.pendingChanges > 0 ? .warning : .positive).fixedSize()
    }

    @ViewBuilder
    private func observationBadges(_ observation: ProjectSkillObservation) -> some View {
        StatusBadge(text: observation.ownership == "managed" ? L10n.tr("由栖集管理") : L10n.tr("项目已有"), tone: .neutral).fixedSize()
        StatusBadge(text: observationStatus(observation.status), tone: observation.status == "matching" ? .neutral : .warning).fixedSize()
    }

    private func hostPicker(project: ProjectRecord) -> some View {
        HStack(spacing: 8) {
            Text(L10n.tr("目标 AI 工具"))
                .font(AppFont.secondary.weight(.semibold))
            ForEach(AgentHost.allCases) { host in
                let selected = project.agents.contains(host.rawValue)
                Button {
                    model.toggleAgent(host)
                } label: {
                    Label(host.rawValue, systemImage: selected ? "checkmark.circle.fill" : "circle")
                        .font(AppFont.secondary)
                }
                .buttonStyle(.bordered)
                .tint(selected ? AppColor.accentText : .secondary)
            }
            Spacer()
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
            ForEach(model.filteredSkills.prefix(12)) { skill in
                Button {
                    model.toggleSkill(skill)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: model.isDraftSelected(skill) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(model.isDraftSelected(skill) ? AppColor.accentText : .secondary)
                            .font(AppFont.heading)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Text(skill.slug)
                                    .font(AppFont.body.weight(.semibold))
                                Text(skill.sourceId)
                                    .font(AppFont.metadata.monospaced())
                                    .foregroundStyle(.secondary)
                                if skill.isBlocked {
                                    StatusBadge(text: L10n.tr("阻塞"), tone: .danger)
                                }
                            }
                            Text(skill.description)
                                .font(AppFont.secondary)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Text(skill.shortHash)
                            .font(AppFont.metadata.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(skill.isBlocked)
                .accessibilityIdentifier("projects.skill.\(skill.id)")
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

    private var isPluginPlan: Bool {
        model.preparedPlan?.plan.metadata?["planType"] == "plugin-lifecycle"
    }

    private var isMCPPlan: Bool {
        model.preparedPlan?.plan.metadata?["planType"] == "mcp-configuration"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isPluginPlan ? L10n.tr("插件变更计划") : isMCPPlan ? L10n.tr("MCP 配置计划") : L10n.tr("变更计划"))
                        .font(AppFont.title.weight(.bold))
                    Text(
                        isPluginPlan
                            ? L10n.tr("核对 AI 工具、插件、影响范围和将运行的命令。批准后，栖集会调用对应工具完成操作。")
                            : L10n.tr("核对目标路径、内容指纹和变更内容。写入前会备份原文件并保存操作记录。")
                    )
                        .font(AppFont.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let record = model.preparedPlan {
                    StatusBadge(
                        text: record.isExpired(at: Date()) ? L10n.tr("已过期") : L10n.tr("待人工批准"),
                        tone: record.isExpired(at: Date()) ? .danger : .warning
                    )
                }
            }
            Divider()
            if let record = model.preparedPlan {
                KeyValueLine(
                    key: isPluginPlan ? L10n.tr("工作目录") : isMCPPlan ? L10n.tr("配置目录") : L10n.tr("项目"),
                    value: record.plan.projectPath,
                    monospaced: true
                )
                KeyValueLine(key: L10n.tr("计划"), value: record.id.uuidString, monospaced: true)
                KeyValueLine(key: L10n.tr("计划指纹"), value: record.plan.digest, monospaced: true)
                KeyValueLine(key: L10n.tr("有效至"), value: L10n.date(record.expiresAt))
                if isPluginPlan {
                    KeyValueLine(
                        key: L10n.tr("AI 工具 / 使用范围"),
                        value: "\(MCPHost(rawValue: record.plan.metadata?["pluginHost"] ?? "")?.displayName ?? L10n.tr("未识别工具")) / "
                            + L10n.text(UserFacingText.metadata(record.plan.metadata?["pluginScope"] ?? "", field: .scope))
                    )
                    KeyValueLine(
                        key: L10n.tr("插件标识"),
                        value: record.plan.metadata?["pluginID"] ?? L10n.tr("未知"),
                        monospaced: true
                    )
                    KeyValueLine(
                        key: L10n.tr("目标清单指纹"),
                        value: record.plan.metadata?["pluginExpectedManifestDigest"].flatMap {
                            $0.isEmpty ? nil : $0
                        } ?? L10n.tr("未指定（仅允许唯一记录）"),
                        monospaced: true
                    )
                }
                Divider()
                Text(isPluginPlan ? L10n.tr("工具命令 \(record.plan.changes.count) 项") : L10n.tr("文件变更 \(record.plan.changes.count) 项"))
                    .font(AppFont.heading)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(record.plan.changes, id: \.relativePath) { change in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    StatusBadge(text: L10n.text(UserFacingText.changeAction(change.action)), tone: change.action == "add" ? .positive : .warning)
                                    Text(change.relativePath)
                                        .font(AppFont.code.weight(.semibold))
                                    Spacer()
                                }
                                Text(UserFacingText.planSummary(change))
                                    .font(AppFont.secondary)
                                    .foregroundStyle(.secondary)
                                Text(
                                    isPluginPlan
                                        ? L10n.tr("观察 \(change.beforeHash ?? L10n.tr("不存在")) · 命令 \(change.afterHash ?? L10n.tr("未记录"))")
                                        : L10n.tr("旧 \(change.beforeHash ?? L10n.tr("不存在")) · 新 \(change.afterHash ?? L10n.tr("删除"))")
                                )
                                    .font(AppFont.metadata.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(maxHeight: 260)
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("批准前须知"))
                        .font(AppFont.secondary.weight(.semibold))
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
                    if !record.plan.warnings.isEmpty {
                        Text(record.plan.warnings.map { L10n.text(UserFacingText.diagnostic($0, context: .plan)) }.joined(separator: "\n"))
                            .foregroundStyle(.orange)
                    }
                }
                .font(AppFont.secondary)
                .foregroundStyle(.secondary)
            } else {
                EmptyState(icon: "doc.badge.gearshape", title: L10n.tr("没有可审阅的计划"), detail: L10n.tr("返回项目页重新生成。"))
            }
            Spacer()
            HStack {
                Spacer()
                Button(L10n.tr("取消")) {
                    model.dismissPlan()
                    dismiss()
                }
                    .keyboardShortcut(.cancelAction)
                Button(isPluginPlan ? L10n.tr("批准并执行命令") : isMCPPlan ? L10n.tr("批准并写入配置") : L10n.tr("批准并写入项目")) {
                    confirmingApply = true
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.accent)
                .disabled(model.preparedPlan == nil || model.isWorking)
            }
        }
        .padding(26)
        .frame(width: 700, height: 680)
        .confirmationDialog(
            isPluginPlan ? L10n.tr("执行这条插件命令？") : isMCPPlan ? L10n.tr("更新 AI 工具配置？") : L10n.tr("确认写入这个项目？"),
            isPresented: $confirmingApply,
            titleVisibility: .visible
        ) {
            Button(isPluginPlan ? L10n.tr("批准并执行命令") : isMCPPlan ? L10n.tr("批准并写入配置") : L10n.tr("批准并写入项目"), role: .destructive) {
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
}

