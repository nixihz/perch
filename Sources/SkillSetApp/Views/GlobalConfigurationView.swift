import SwiftUI
import SkillSetCore

struct GlobalConfigurationView: View {
    @Bindable var model: AppModel

    private var global: GlobalConfigurationModel { model.globalConfiguration }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: AppLayout.columnSpacing) {
                    PageHeader(eyebrow: "USER CONFIGURATION", title: L10n.tr("全局配置"),
                        detail: L10n.tr("为当前用户配置技能与规则，影响所选 AI 工具中的全部项目。"))
                    // 最小窗口按操作顺序纵向排列，避免双栏最小宽度反向挤出侧栏。
                    if geometry.size.width < 850 {
                        hostCard
                        configurationCards
                    } else {
                        HStack(alignment: .top, spacing: AppLayout.columnSpacing) {
                            hostCard.frame(width: AppLayout.listWidth)
                            configurationCards
                        }
                    }
                }
                .frame(width: geometry.size.width, alignment: .leading)
            }
        }
        .task { global.refresh() }
        .accessibilityIdentifier("global.configuration")
    }

    private var configurationCards: some View {
        VStack(alignment: .leading, spacing: AppLayout.columnSpacing) {
            draftCard
            MCPSelectionCard(model: model, host: global.host, projectID: nil)
            PluginConfigurationCard(model: model, host: global.host)
            observationsCard
            historyCard
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hostCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.tr("AI 工具")).font(AppFont.heading)
                ForEach(MCPHost.allCases) { host in
                    Button { global.selectHost(host) } label: {
                        HStack {
                            Text(host.displayName)
                            Spacer()
                            if global.host == host { Image(systemName: "checkmark") }
                        }
                        .padding(10)
                        .selectionRow(global.host == host)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("global.host.\(host.rawValue)")
                }
                Divider()
                Text(L10n.tr("技能目录")).font(AppFont.secondary.weight(.semibold))
                path(global.locations.skillsRoot(global.host).path)
                Text(L10n.tr("规则文件")).font(AppFont.secondary.weight(.semibold))
                path(global.locations.rulesURL(global.host).path)
                Text(L10n.tr("本机管理记录")).font(AppFont.secondary.weight(.semibold))
                path(global.locations.stateRoot.appendingPathComponent("global").path)
                Divider()
                Text(L10n.tr("在下方选择 MCP 服务和插件，分别预览配置计划。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
                Button(L10n.tr("管理 MCP 服务")) { model.section = .mcp }
                Button(L10n.tr("管理插件来源")) { model.section = .plugins }
            }
        }
    }

    private var draftCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(L10n.tr("全局配置草稿")).font(AppFont.heading)
                    Spacer()
                    Button(L10n.tr("预览变更")) { present(global.prepareDeployment()) }
                        .buttonStyle(AppButtonStyle(kind: .primary))
                        .disabled(model.isWorking || global.inspection == nil)
                        .accessibilityIdentifier("global.preview")
                }
                Text(L10n.tr("勾选只保存草稿；批准计划后才会写入全局目录。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
                if let error = global.error {
                    Text(L10n.text(error)).foregroundStyle(.red)
                        .accessibilityIdentifier("global.error")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("技能安装方式")).font(AppFont.secondary.weight(.semibold))
                    AppPicker(title: L10n.tr("技能安装方式"),
                              selection: Binding(get: { global.draft.installMethod ?? .symlink }, set: { global.setInstallMethod($0) }),
                              valueLabel: L10n.tr(global.draft.installMethod == .copy ? "复制独立文件" : "软链接（推荐）"), showsLabel: false) {
                        Text(L10n.tr("软链接（推荐）")).tag(SkillInstallMethod.symlink)
                        Text(L10n.tr("复制独立文件")).tag(SkillInstallMethod.copy)
                    }
                }
                Text(L10n.tr("软链接指向 ~/.perch 中的固定版本；复制后的文件可独立编辑。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
                SkillSearchField(query: Binding(get: { global.query }, set: { global.query = $0 }))
                let skills = matchingSkills(model.snapshot.catalog.entries, query: global.query, sourceOrigins: model.sourceOrigins)
                ScrollView {
                  VStack(alignment: .leading, spacing: 12) {
                    ForEach(skills) { skill in
                    Toggle(isOn: Binding(get: { global.draft.skillIDs.contains(skill.id) }, set: { global.setSkill(skill.id, enabled: $0) })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(skill.slug).font(AppFont.body.weight(.semibold))
                            Text(skill.id).font(AppFont.metadata).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            Text(skill.description).font(AppFont.secondary).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(skill.isBlocked || global.inspection == nil)
                    .accessibilityIdentifier("global.skill.\(skill.id)")
                    }
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: skills.isEmpty ? 0 : min(280, CGFloat(skills.count) * 90))
                if skills.isEmpty { Text(L10n.tr("没有匹配的技能，请调整搜索或先加入技能库。")) }
                let missing = global.draft.skillIDs.filter { id in !model.snapshot.catalog.entries.contains { $0.id == id } }
                ForEach(missing, id: \.self) { id in
                    HStack {
                        Text(id).font(AppFont.code)
                        Text(L10n.tr("技能不可用")).foregroundStyle(.orange)
                        Spacer()
                        Button(L10n.tr("移除")) { global.setSkill(id, enabled: false) }
                    }
                }
                Divider()
                Text(L10n.tr("AGENTS 片段")).font(AppFont.heading)
                ForEach(model.snapshot.templates) { template in
                    Toggle(isOn: Binding(get: { global.draft.instructionIDs.contains(template.id) }, set: { global.setInstruction(template.id, enabled: $0) })) {
                        Text(UserFacingText.templateTitle(template))
                    }
                    .toggleStyle(.checkbox)
                    .disabled(global.inspection == nil)
                    DisclosureGroup(L10n.tr("查看规则正文")) {
                        Text(template.body).font(AppFont.code).textSelection(.enabled)
                    }
                }
                ForEach(global.draft.instructionIDs.filter { id in !model.snapshot.templates.contains { $0.id == id } }, id: \.self) { id in
                    HStack {
                        Text(id).font(AppFont.code)
                        Spacer()
                        Button(L10n.tr("移除不可用的片段")) { global.setInstruction(id, enabled: false) }
                    }
                }
                Divider()
                Toggle(L10n.tr("接管所选资源的已有同名内容，并保留原始备份"),
                    isOn: Binding(get: { global.takeOverExisting }, set: { global.takeOverExisting = $0 }))
                    .toggleStyle(.checkbox)
                Text(L10n.tr("默认保留已有内容；接管后可恢复原始版本。用户后续改动会阻止覆盖或还原。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }
        }
    }

    private var observationsCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.tr("全局文件现状")).font(AppFont.heading)
                    Spacer()
                    Button(L10n.tr("重新扫描")) { global.refresh() }
                }
                ForEach(global.inspection?.resources ?? []) { resource in
                    VStack(alignment: .leading, spacing: 5) {
                        path(resource.path)
                        HStack {
                            StatusBadge(text: resource.managed ? L10n.tr("由栖集管理") : L10n.tr("用户已有"), tone: .neutral)
                            if resource.modified { StatusBadge(text: L10n.tr("存在本地修改"), tone: .warning) }
                            if resource.symbolicLink { StatusBadge(text: L10n.tr("符号链接，保留不改"), tone: .warning) }
                        }
                    }
                }
                Text(L10n.tr("文件存在不代表当前会话已加载；同名优先级由 AI 工具决定。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }
        }
    }

    private var historyCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.tr("还原与操作历史")).font(AppFont.heading)
                ViewThatFits(in: .horizontal) {
                    HStack { restoreButtons }
                    VStack(alignment: .leading) { restoreButtons }
                }
                .disabled(global.inspection?.hasManagement != true || model.isWorking)
                Text(L10n.tr("恢复原始内容会退出管理；停止管理则保留当前文件。两项操作均需预览并批准。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
                if global.operations.isEmpty { Text(L10n.tr("尚无全局操作记录")) }
                ForEach(global.operations) { record in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(L10n.date(record.journal.createdAt)).font(AppFont.secondary)
                            Text(L10n.text(actionTitle(record.action)))
                            Spacer()
                            StatusBadge(text: L10n.text(stateTitle(record.journal.state)), tone: record.journal.state == "applied" ? .positive : .warning)
                        }
                        path(record.id.uuidString)
                        if record.canUndo {
                            Button(L10n.tr("撤销此次操作…")) { present(global.prepareUndo(record.id)) }
                                .disabled(model.isWorking)
                        }
                    }
                }
            }
        }
    }

    private var restoreButtons: some View {
        Group {
            Button(L10n.tr("恢复接管前状态…")) { present(global.prepareRestore(.baseline)) }
                .accessibilityIdentifier("global.restoreBaseline")
            Button(L10n.tr("停止管理，保留文件…")) { present(global.prepareRestore(.keepFiles)) }
                .accessibilityIdentifier("global.keepFiles")
        }
    }

    private func path(_ value: String) -> some View {
        Text(value).font(AppFont.code).foregroundStyle(.secondary)
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    }

    private func present(_ plan: StoredDeploymentPlan?) {
        guard let plan else { return }
        model.preparedPlan = plan
        model.planPresented = true
    }

    private func actionTitle(_ value: String) -> String {
        switch value {
        case "baseline": "恢复接管前状态"
        case "keepFiles": "停止管理"
        case "undo": "撤销操作"
        default: "部署全局配置"
        }
    }
    private func stateTitle(_ value: String) -> String {
        switch value {
        case "applied": "已完成"
        case "rolled-back", "failed-rolled-back": "已恢复"
        case "failed", "rolling-back", "applying": "待恢复"
        default: "状态待核对"
        }
    }
}
