import SwiftUI
import AppKit
import SkillSetCore

struct ProjectsView: View {
    @Bindable var model: AppModel
    @State private var detailsPresented = false
    @State private var pendingPlan: StoredDeploymentPlan?

    var body: some View {
        VStack(alignment: .leading, spacing: AppLayout.columnSpacing) {
            PageActionHeader(eyebrow: "PROJECT WORKSPACE", title: L10n.tr("项目配置"),
                detail: L10n.tr("选择项目，点击工具图标选择资源，预览后保存到当前项目。")) {
                Button { chooseProject() } label: {
                    Label(L10n.tr("添加项目"), systemImage: "plus")
                }
                .buttonStyle(AppButtonStyle(kind: .primary))
                .accessibilityIdentifier("projects.addProject")
            }
            if let project = model.selectedProject, let projectID = UUID(uuidString: project.id) {
                projectSelector(project)
                if let notice = model.projectPlanNotice(for: project.id) {
                    HStack(alignment: .top) {
                        Label(L10n.text(notice.message), systemImage: notice.tone == .error ? "exclamationmark.triangle" : "checkmark.circle")
                            .font(AppFont.secondary).foregroundStyle(notice.tone == .error ? .red : .secondary)
                            .accessibilityIdentifier("projects.planNotice")
                        if let path = notice.relatedPath {
                            Button(L10n.tr("查看文件夹")) {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                            }
                            .fixedSize()
                            .accessibilityIdentifier("projects.revealProblemFolder")
                        }
                    }
                }
                ForEach((model.projectIssues[project.id] ?? []).filter { !UserFacingText.isInformationalProjectNote($0) }, id: \.self) { issue in
                    Text(L10n.text(UserFacingText.diagnostic(issue, context: .project)))
                        .font(AppFont.secondary).foregroundStyle(.orange)
                }
                ConfigurationResourceView(model: model, projectID: projectID)
                    // 每个项目持有自己的列表与插件草稿，切换时不沿用旧项目的异步结果。
                    .id(project.id)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        Text(L10n.tr("1. 添加项目 → 2. 选择资源或使用预设 → 3. 预览后保存"))
                            .font(AppFont.secondary).foregroundStyle(.secondary)
                            .accessibilityIdentifier("projects.workflowGuide")
                        EmptyState(icon: "folder", title: L10n.tr("还没有添加项目"),
                            detail: L10n.tr("点击「添加项目」选择文件夹，再选技能或使用预设，预览后保存到项目。"))
                        Button(L10n.tr("选择项目目录")) { chooseProject() }
                            .buttonStyle(AppButtonStyle(kind: .primary))
                        HStack(spacing: 12) {
                            Button(L10n.tr("浏览技能库")) { model.section = .skills }
                                .accessibilityIdentifier("projects.browseSkills")
                            Button(L10n.tr("查看预设")) { model.section = .presets }
                                .accessibilityIdentifier("projects.browsePresets")
                        }
                    }.frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            async let plans: Void = model.refreshPendingPlansInBackground()
            async let inheritance: Void = model.globalConfiguration.refreshInheritanceInBackground()
            _ = await (plans, inheritance)
        }
        .sheet(isPresented: $detailsPresented, onDismiss: {
            if let plan = pendingPlan { pendingPlan = nil; model.reviewPlan(plan) }
        }) {
            if let project = model.selectedProject {
                ProjectConfigurationDetails(model: model, project: project) { record in
                    pendingPlan = record
                    detailsPresented = false
                }
            }
        }
    }

    private func projectSelector(_ selected: ProjectRecord) -> some View {
        let selectorHeight = model.projects.count > 10 ? AppControl.selectorHeight : AppControl.height
        return SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(L10n.tr("项目")).font(AppFont.heading)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(model.projects) { project in
                                Button { model.selectedProjectID = project.id } label: {
                                    Text(project.name).lineLimit(1).frame(maxWidth: 180)
                                }
                                .buttonStyle(AppButtonStyle(selected: project.id == selected.id))
                                .accessibilityIdentifier("projects.select.\(project.id)")
                                .accessibilityAddTraits(project.id == selected.id ? [.isSelected] : [])
                                .help(project.path)
                            }
                        }
                        .frame(height: selectorHeight)
                    }
                    .frame(maxWidth: .infinity, minHeight: selectorHeight, maxHeight: selectorHeight)
                    Button(L10n.tr("项目详情…")) { detailsPresented = true }
                        .accessibilityIdentifier("projects.details")
                }
                Text(selected.path).font(AppFont.code).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).help(selected.path).textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projects.selector")
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
}

/// 项目信息按需打开，不挤占配置列表；观察与待批准计划仍可核对。
struct ProjectConfigurationDetails: View {
    @Bindable var model: AppModel
    let project: ProjectRecord
    let onReview: (StoredDeploymentPlan) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(project.name).font(AppFont.title)
            Text(project.path).font(AppFont.code).textSelection(.enabled)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.tr("全部工具草稿 \(project.pendingChanges) 项变更")).font(AppFont.secondary)
                    Text(L10n.tr("其他来源的影响")).font(AppFont.heading)
                    Text(UserFacingText.localizedInheritance(project.inherited)).font(AppFont.secondary)
                    ForEach(SkillConfigurationTarget.allCases) { host in
                        if let error = model.globalConfiguration.inheritanceErrors[host] {
                            Text(host.displayName + " · " + L10n.text(error)).foregroundStyle(.orange)
                        } else {
                            let resources = model.globalConfiguration.inheritedResources[host] ?? []
                            Text(L10n.tr("\(host.displayName) 全局资源：\(resources.count) 项；取消项目选择不会停用全局内容。"))
                                .font(AppFont.secondary)
                            ForEach(resources) { resource in
                                Text(resource.path).font(AppFont.code).textSelection(.enabled)
                            }
                        }
                    }
                    Text(L10n.tr("已读取全局技能和规则，尚未检查父目录与插件；同名内容如何取舍、是否已加载，请到 AI 工具中确认。"))
                        .font(AppFont.secondary).foregroundStyle(.secondary)
                    Divider()
                    Text(L10n.tr("项目技能现状")).font(AppFont.heading)
                    ForEach(model.projectIssues[project.id] ?? [], id: \.self) { issue in
                        Text(L10n.text(UserFacingText.diagnostic(issue, context: .project)))
                            .font(AppFont.secondary).foregroundStyle(.secondary)
                    }
                    Text(L10n.tr("项目原有技能会保留。取消选择只会移除栖集写入且未经修改的技能；仍需在 AI 工具中确认是否加载。"))
                        .font(AppFont.secondary).foregroundStyle(.secondary)
                    ForEach(model.projectSkillObservations[project.id] ?? [], id: \.relativePath) { observation in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(observation.skillID.map(model.skillDisplayTitle) ?? (observation.relativePath as NSString).lastPathComponent)
                                .font(AppFont.secondary.weight(.semibold))
                            Text(observation.relativePath).font(AppFont.code).textSelection(.enabled)
                            HStack {
                                StatusBadge(text: observation.ownership == "managed" ? L10n.tr("由栖集管理") : L10n.tr("项目已有"), tone: .neutral)
                                StatusBadge(text: observationStatus(observation.status), tone: observation.status == "matching" ? .neutral : .warning)
                            }
                        }
                    }
                    let plans = model.pendingPlans.filter { $0.plan.projectPath == project.path }
                    if !plans.isEmpty {
                        Divider()
                        Text(L10n.tr("待你批准的计划")).font(AppFont.heading)
                        ForEach(plans) { record in
                            HStack {
                                Text(L10n.tr("\(record.plan.changes.count) 项变更 · 有效期至 \(L10n.date(record.expiresAt))"))
                                    .font(AppFont.secondary)
                                Spacer()
                                Button(L10n.tr("审阅")) { onReview(record) }
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { Spacer(); Button(L10n.tr("完成")) { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 720, height: 600).appControls()
    }

    private func observationStatus(_ status: String) -> String {
        switch status {
        case "matching": L10n.tr("内容匹配")
        case "drifted": L10n.tr("存在本地修改")
        case "symlink": L10n.tr("符号链接，保留不改")
        default: L10n.tr("内容待核对")
        }
    }
}

struct PlanSheet: View {
    @Bindable var model: AppModel
    var savesFromPreview = false
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
        if savesFromPreview { return L10n.tr("保存") }
        return isGlobalPlan ? L10n.tr("批准并更新全局配置") : isPluginPlan ? L10n.tr("批准并执行命令") : isMCPPlan ? L10n.tr("批准并写入配置") : L10n.tr("批准并写入项目")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(isGlobalPlan ? L10n.tr("全局配置计划") : isPluginPlan ? L10n.tr("插件变更计划") : isMCPPlan ? L10n.tr("MCP 配置计划") : L10n.tr("变更计划"))
                    .font(AppFont.title)
                Spacer()
                if let record = model.preparedPlan {
                    StatusBadge(
                        text: record.isExpired(at: Date()) ? L10n.tr("已过期") : L10n.tr("待你批准"),
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
                    if savesFromPreview { _ = model.approveAndApplyPreparedPlan() }
                    else { confirmingApply = true }
                }
                .accessibilityIdentifier("plan.save")
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
            isGlobalPlan ? L10n.tr("更新全局配置？") : isPluginPlan ? L10n.tr("执行这条插件命令？") : isMCPPlan ? L10n.tr("更新 AI 工具配置？") : L10n.tr("写入这个项目？"),
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
                let target = SkillConfigurationTarget(rawValue: record.plan.metadata?["globalHost"] ?? "")
                Text((target?.displayName ?? "") + " · " + (target == .agents
                    ? L10n.tr("共享技能目录，Codex 也会加载其中的技能。")
                    : L10n.tr("影响所选 AI 工具的全部项目。")))
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
            } else {
                let hosts = MCPHost.allCases.filter { host in
                    guard let target = AgentDeploymentAdapter.target(for: host.rawValue) else { return false }
                    return record.plan.changes.contains {
                        $0.scope != "project-state" && ($0.relativePath == target.instructionsFile
                            || $0.relativePath.hasPrefix(target.skillsRoot + "/"))
                    }
                }
                if !hosts.isEmpty {
                    Text(L10n.tr("涉及工具：") + hosts.map(\.displayName).joined(separator: "、"))
                        .font(AppFont.secondary)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("plan.affectedHosts")
                }
                if hosts.count > 1 {
                    Text(L10n.tr("共用技能、规则或安装方式的更新会一并保存，请核对下方变更。"))
                        .font(AppFont.secondary)
                        .foregroundStyle(.secondary)
                }
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
            rulePreviewError = "规则文件超过 1 MiB，无法完整预览，请精简后重新生成计划。"
        } catch {
            rulePreviewError = "规则文件或预览内容已改变或无法读取，请取消并重新生成计划。"
        }
    }

}
