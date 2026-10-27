import AppKit
import SwiftUI
import SkillSetCore

struct PluginConfigurationView: View {
    @Bindable var model: AppModel
    let host: MCPHost
    let projectID: UUID?
    let onPlan: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var acknowledgedExecutableRisk = false
    @State private var plugins: [PluginInventoryRecord] = []
    @State private var pluginIssues: [String] = []
    @State private var pluginScanRoots: [String] = []
    @State private var selectedPluginID = ""
    @State private var error: String?

    private var selectedPlugin: PluginInventoryRecord? { plugins.first { $0.id == selectedPluginID } }
    private var scope: PluginLifecycleScope { projectID == nil ? .user : .project }

    private func refresh() {
        do {
            let service = try SkillSetService(paths: model.runtimePaths)
            let snapshot = try service.plugins(projectID: projectID)
            plugins = snapshot.records.filter { $0.host == host && ($0.scope == nil || $0.scope == scope.rawValue) }
            pluginIssues = snapshot.issues
            pluginScanRoots = snapshot.scannedRoots
            if !plugins.contains(where: { $0.id == selectedPluginID }) { selectedPluginID = plugins.first?.id ?? "" }
            error = nil
        } catch { self.error = UserFacingText.error(error) }
    }

    private func makePlan(_ plugin: PluginInventoryRecord, action: PluginLifecycleAction, acknowledge: Bool) {
        do {
            let service = try SkillSetService(paths: model.runtimePaths)
            let plan = try service.makePluginLifecyclePlan(projectID: projectID,
                request: PluginLifecycleRequest(host: host, pluginID: plugin.pluginID, action: action,
                    scope: scope, expectedManifestDigest: plugin.manifestDigest,
                    acknowledgeExecutableComponents: acknowledge))
            model.preparedPlan = plan
            onPlan()
            // 先关闭配置面板，再由父视图呈现已有的批准面板。
            dismiss()
        } catch { self.error = UserFacingText.error(error) }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(eyebrow: "PLUGIN CONFIGURATION", title: host.displayName + " · " + L10n.text(scope.displayName),
                    detail: L10n.tr("从本机已发现的插件中选择，核对当前配置范围后预览计划；批准后才会调用 AI 工具。"))
                Text(projectID == nil ? L10n.tr("使用范围：这个 AI 工具的所有项目。") : L10n.tr("仅配置当前项目；全局插件仍可能生效。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
                if let error { Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red) }
                HStack(alignment: .top, spacing: AppLayout.columnSpacing) {
                    pluginList.frame(width: AppLayout.listWidth)
                    pluginDetail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .onAppear { refresh() }
        .onChange(of: selectedPluginID) { acknowledgedExecutableRisk = false }
    }

    private var pluginList: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.tr("已发现的插件")).font(AppFont.heading)
                    Spacer()
                    Button(L10n.tr("重新扫描")) { refresh() }
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(plugins) { plugin in
                            Button { selectedPluginID = plugin.id } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(plugin.name).font(AppFont.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                    Text(plugin.marketplaceID ?? L10n.tr("项目或本地目录")).font(AppFont.metadata).foregroundStyle(.secondary).lineLimit(1)
                                    Text(L10n.text(UserFacingText.pluginState(plugin)))
                                        .font(AppFont.secondary).foregroundStyle(.secondary).lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                .selectionRow(plugin.id == selectedPluginID).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        if plugins.isEmpty {
                            Text(L10n.tr("当前范围没有可配置的插件，请先在 AI 工具中下载插件包，再重新扫描。"))
                                .font(AppFont.secondary).foregroundStyle(.secondary)
                        }
                    }
                }
                if !pluginIssues.isEmpty {
                    Text(L10n.tr("\(pluginIssues.count) 个读取问题"))
                        .font(AppFont.secondary).foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder private var pluginDetail: some View {
        if let plugin = selectedPlugin {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SurfaceCard(emphasis: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(plugin.name).font(AppFont.title)
                            if let marketplace = plugin.marketplaceID, !marketplace.isEmpty {
                                Text(marketplace).font(AppFont.secondary).foregroundStyle(.secondary)
                            }
                            Text(plugin.description).font(AppFont.secondary).foregroundStyle(.secondary)
                            Text(L10n.text(UserFacingText.pluginState(plugin))).font(AppFont.secondary)
                            Text(plugin.components.map { L10n.text(UserFacingText.metadata($0, field: .component)) }.joined(separator: " · "))
                                .font(AppFont.secondary).foregroundStyle(.secondary)
                        }
                    }
                    lifecycleCard(plugin)
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.tr("来源与版本")).font(AppFont.heading)
                            KeyValueLine(key: L10n.tr("市场"), value: plugin.marketplaceID ?? L10n.tr("项目或本地目录"))
                            KeyValueLine(key: L10n.tr("声明版本"), value: plugin.version ?? L10n.tr("未声明"))
                            Text(plugin.manifestDigest).font(AppFont.code).textSelection(.enabled)
                            Text(plugin.sourcePath).font(AppFont.code).foregroundStyle(.secondary).textSelection(.enabled)
                            Button(L10n.tr("查看清单文件")) {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: plugin.manifestPath)])
                            }
                            ForEach(plugin.risks, id: \.self) { risk in
                                Text(L10n.text(UserFacingText.pluginRisk(risk))).font(AppFont.secondary).foregroundStyle(.orange)
                            }
                            Text(L10n.tr("停用或卸载不会撤销脚本已造成的改动；加载新插件可能需要重启 AI 会话。"))
                                .font(AppFont.secondary).foregroundStyle(.secondary)
                        }
                    }
                    if !pluginIssues.isEmpty {
                        SurfaceCard {
                            ForEach(pluginIssues, id: \.self) { issue in
                                Text(L10n.text(UserFacingText.diagnostic(issue, context: .plugin))).font(AppFont.secondary).foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
        } else {
            EmptyState(icon: "puzzlepiece.extension", title: L10n.tr("选择一个插件"),
                detail: L10n.tr("选择左侧插件，核对来源、具体版本和自动运行脚本的风险。"))
        }
    }

    private func lifecycleCard(_ plugin: PluginInventoryRecord) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.tr("插件操作")).font(AppFont.heading)
                if !plugin.installed || host == .claudeCode {
                    Toggle(L10n.tr("我已核对插件中的自动运行脚本、命令和其他可运行内容。"), isOn: $acknowledgedExecutableRisk)
                        .toggleStyle(AppCheckboxStyle()).font(AppFont.secondary)
                    if !acknowledgedExecutableRisk {
                        Text(L10n.tr("请先核对并勾选上方说明，再预览安装或更新计划。"))
                            .font(AppFont.secondary).foregroundStyle(.secondary)
                    }
                }
                if !plugin.installed {
                    actionButton(plugin, action: .install, title: "生成安装计划", risk: true)
                } else {
                    if host == .claudeCode {
                        actionButton(plugin, action: plugin.enabled == false ? .enable : .disable,
                            title: plugin.enabled == false ? "生成启用计划" : "生成停用计划")
                        actionButton(plugin, action: .update, title: "生成更新计划", risk: true)
                    }
                    actionButton(plugin, action: .uninstall, title: "生成卸载计划")
                }
                Text(L10n.tr("先预览插件操作计划，核对后再批准。栖集会调用本机 Claude Code 或 Codex 完成操作。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }
        }
    }

    private func actionButton(_ plugin: PluginInventoryRecord, action: PluginLifecycleAction, title: String, risk: Bool = false) -> some View {
        Button(L10n.text(title)) { makePlan(plugin, action: action, acknowledge: risk && acknowledgedExecutableRisk) }
            .buttonStyle(AppButtonStyle()).disabled(risk && !acknowledgedExecutableRisk)
    }
}
