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
                    detail: L10n.tr("添加本机项目，选择 AI 工具、技能和规则。审阅计划并再次批准后，才会写入项目。")
                )

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
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.tr("登记一个本机项目"))
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
                                Text("\(project.draftSkillIDs.count) skills · \(L10n.text(project.adapter))")
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
                Text(L10n.tr("项目是写入边界"))
                    .font(AppFont.secondary.weight(.semibold))
                Text(L10n.tr("全局、父目录和插件带来的内容只会显示为继承观察，不会被“取消选择”误认为已关闭。"))
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
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(project.name)
                                .font(AppFont.title.weight(.bold))
                            Text(project.path)
                                .font(AppFont.secondary.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            HStack(spacing: 8) {
                                StatusBadge(text: project.adapter, tone: .accent)
                                StatusBadge(
                                    text: lockStatusLabel(project.lockStatus),
                                    tone: project.lockStatus == "valid" ? .positive : .warning
                                )
                                StatusBadge(text: L10n.tr("草稿 \(project.pendingChanges) 项变更"), tone: project.pendingChanges > 0 ? .warning : .positive)
                            }
                        }
                        Spacer()
                        Button(L10n.tr("预览变更")) {
                            model.prepareDeploymentPlan()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColor.accent)
                        .disabled(model.isWorking || model.runtimePaths.repositoryRoot == nil)
                    }
                    Divider()
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.tr("继承观察"))
                                .font(AppFont.secondary.weight(.semibold))
                            Text(UserFacingText.localizedInheritance(project.inherited))
                                .font(AppFont.secondary)
                                .foregroundStyle(.secondary)
                            Text(L10n.tr("取消项目选择不会覆盖这些来源；当前只观察项目内的受管路径。"))
                                .font(AppFont.metadata)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Text(L10n.tr("项目配置草稿"))
                                .font(AppFont.heading)
                            Spacer()
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
                            Text(L10n.tr("规则片段"))
                                .font(AppFont.heading)
                            Spacer()
                            StatusBadge(text: L10n.tr("写入 AGENTS.md / CLAUDE.md 受管块"), tone: .neutral)
                        }
                        ForEach(model.snapshot.templates) { template in
                            Button {
                                model.toggleInstruction(template)
                            } label: {
                                HStack(alignment: .top, spacing: 9) {
                                    Image(systemName: project.fragments.contains(template.id) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(project.fragments.contains(template.id) ? AppColor.accentText : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(L10n.text(template.title))
                                            .font(AppFont.secondary.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(L10n.text(template.purpose))
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
                        Text(L10n.tr("只替换 skillset:begin/end 之间的字节；重复、交叉或缺尾标记会阻塞计划。"))
                            .font(AppFont.secondary)
                            .foregroundStyle(.secondary)
                    }
                }

                if let issues = model.projectIssues[project.id], !issues.isEmpty {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(L10n.tr("观察问题"), systemImage: "exclamationmark.triangle")
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
                                Label(L10n.tr("待本机审批的计划"), systemImage: "tray.full")
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
                            Text(L10n.tr("CLI 或 MCP 只能生成计划；批准动作仍在当前本机窗口完成。"))
                                .font(AppFont.secondary)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 16) {
                EmptyState(icon: "folder", title: L10n.tr("还没有登记项目"), detail: L10n.tr("选择一个本机目录。登记只写入应用数据目录，不扫描或改写项目。"))
                Button(L10n.tr("选择项目目录")) {
                    chooseProject()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
        panel.title = L10n.tr("登记本机项目")
        panel.prompt = L10n.tr("登记")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = model.registerProject(url)
    }

    private func lockStatusLabel(_ status: String) -> String {
        switch status {
        case "valid": L10n.tr("锁有效")
        case "stale": L10n.tr("锁已漂移")
        case "unlocked": L10n.tr("缺锁文件")
        case "corrupt": L10n.tr("锁损坏")
        default: L10n.tr("未锁定")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isPluginPlan ? L10n.tr("插件变更计划") : L10n.tr("变更计划"))
                        .font(AppFont.title.weight(.bold))
                    Text(
                        isPluginPlan
                            ? L10n.tr("核对宿主、插件、范围、当前状态和将要执行的固定命令。批准后由本机宿主 CLI 执行。")
                            : L10n.tr("核对真实路径、内容指纹和受管块。执行前会备份旧内容并保存操作记录。")
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
                    key: isPluginPlan ? L10n.tr("工作目录") : L10n.tr("项目"),
                    value: record.plan.projectPath,
                    monospaced: true
                )
                KeyValueLine(key: L10n.tr("计划"), value: record.id.uuidString, monospaced: true)
                KeyValueLine(key: L10n.tr("计划指纹"), value: record.plan.digest, monospaced: true)
                KeyValueLine(key: L10n.tr("有效至"), value: L10n.date(record.expiresAt))
                if isPluginPlan {
                    KeyValueLine(
                        key: L10n.tr("宿主 / 范围"),
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
                Text(isPluginPlan ? L10n.tr("宿主命令 \(record.plan.changes.count) 项") : L10n.tr("文件变更 \(record.plan.changes.count) 项"))
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
                    Text(L10n.tr("安全门"))
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
                Button(isPluginPlan ? L10n.tr("批准并执行宿主命令") : L10n.tr("批准并执行")) {
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
            isPluginPlan ? L10n.tr("执行这条插件命令？") : L10n.tr("确认写入这个项目？"),
            isPresented: $confirmingApply,
            titleVisibility: .visible
        ) {
            Button(isPluginPlan ? L10n.tr("批准并执行宿主命令") : L10n.tr("批准并写入项目"), role: .destructive) {
                _ = model.approveAndApplyPreparedPlan()
            }
            Button(L10n.tr("返回审阅"), role: .cancel) {}
        } message: {
            if let record = model.preparedPlan {
                Text(
                    isPluginPlan
                        ? L10n.tr("将在 \(record.plan.projectPath) 调用宿主 CLI。批准不可复用；插件状态变化或命令失败会保留操作记录。")
                        : L10n.tr("将修改 \(record.plan.projectPath) 中的 \(record.plan.changes.count) 个受管路径。批准不可复用；文件漂移会导致计划失效。")
                )
            }
        }
    }
}

