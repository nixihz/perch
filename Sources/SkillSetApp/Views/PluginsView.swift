import AppKit
import SwiftUI
import SkillSetCore

struct PluginsView: View {
    @Bindable var model: AppModel
    @State private var acknowledgedExecutableRisk = false

    private var installedCount: Int {
        model.plugins.filter(\.installed).count
    }

    private var hookCount: Int {
        model.plugins.filter { $0.components.contains("hooks") }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                eyebrow: "PLUGIN INVENTORY",
                title: L10n.tr("插件管理"),
                detail: L10n.tr("查看 Claude Code 和 Codex 的本机插件。安装、启用或卸载前，先审阅命令、范围和风险；本机批准后才会执行。")
            )
            HStack(spacing: 8) {
                StatusBadge(text: L10n.tr("\(model.plugins.count) 个缓存包"), tone: .accent)
                StatusBadge(text: L10n.tr("\(installedCount) 个已安装"), tone: installedCount > 0 ? .positive : .warning)
                StatusBadge(text: L10n.tr("\(hookCount) 个含自动运行脚本"), tone: hookCount > 0 ? .danger : .positive)
                if !model.pluginIssues.isEmpty {
                    StatusBadge(text: L10n.tr("\(model.pluginIssues.count) 个读取问题"), tone: .warning)
                }
                Spacer()
                Button(L10n.tr("重新扫描")) {
                    model.refreshPlugins()
                }
                .buttonStyle(.bordered)
            }
            HStack(alignment: .top, spacing: AppLayout.columnSpacing) {
                pluginList
                    .frame(width: AppLayout.listWidth)
                pluginDetail
            }
        }
        .onAppear {
            model.refreshPlugins()
        }
        .onChange(of: model.selectedProjectID) {
            model.refreshPlugins()
        }
        .onChange(of: model.selectedPluginID) {
            acknowledgedExecutableRisk = false
        }
    }

    private var pluginList: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.tr("本机观察"))
                        .font(AppFont.heading)
                    Spacer()
                    Text("\(model.plugins.count)")
                        .font(AppFont.secondary.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if model.plugins.isEmpty {
                    EmptyState(
                        icon: "puzzlepiece.extension",
                        title: L10n.tr("还没有发现插件"),
                        detail: L10n.tr("请先选择项目，或在 Claude Code / Codex 中配置插件市场，再重新扫描。")
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(model.plugins) { plugin in
                                pluginRow(plugin)
                            }
                        }
                    }
                }

                Divider()
                Text(L10n.tr("扫描不运行插件命令、自动运行脚本或市场脚本。只有计划批准后才会调用所属工具。"))
                    .font(AppFont.secondary)
                    .foregroundStyle(.secondary)

                if !model.pluginIssues.isEmpty {
                    DisclosureGroup(L10n.tr("读取问题")) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(model.pluginIssues, id: \.self) { issue in
                                Text(L10n.text(UserFacingText.diagnostic(issue, context: .plugin)))
                                    .font(AppFont.secondary)
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.top, 6)
                    }
                    .font(AppFont.secondary.weight(.medium))
                }

                DisclosureGroup(L10n.tr("扫描根 \(model.pluginScanRoots.count)")) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.pluginScanRoots, id: \.self) { root in
                            Text(root)
                                .font(AppFont.secondary.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(AppFont.secondary.weight(.medium))
            }
        }
    }

    private func pluginRow(_ plugin: PluginInventoryRecord) -> some View {
        Button {
            model.inspectPlugin(plugin)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: plugin.installed ? "puzzlepiece.extension.fill" : "shippingbox")
                    .foregroundStyle(plugin.id == model.selectedPluginID ? AppColor.accentText : .secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text(plugin.name)
                        .font(AppFont.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(plugin.host.displayName) · \(plugin.pluginID)")
                        .font(AppFont.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(L10n.text(UserFacingText.pluginState(plugin)))
                        .font(AppFont.metadata)
                        .foregroundStyle(plugin.installed ? AppColor.positive : .secondary)
                }
                Spacer(minLength: 6)
                StatusBadge(
                    text: plugin.components.contains("hooks") ? L10n.tr("含自动运行脚本") : (plugin.version ?? L10n.tr("未声明版本")),
                    tone: plugin.components.contains("hooks") ? .danger : .warning
                )
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 6)
            .selectionRow(plugin.id == model.selectedPluginID)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var pluginDetail: some View {
        if let plugin = model.selectedPlugin {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SurfaceCard(emphasis: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(plugin.name)
                                        .font(AppFont.title.weight(.bold))
                                    Text(plugin.pluginID)
                                        .font(AppFont.body.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                Spacer()
                                StatusBadge(text: L10n.text(UserFacingText.pluginState(plugin)), tone: statusTone(plugin))
                            }
                            if !plugin.description.isEmpty {
                                Text(plugin.description)
                                    .font(AppFont.body)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Divider()
                            HStack(spacing: 8) {
                                ForEach(plugin.components.isEmpty ? ["manifest"] : plugin.components, id: \.self) {
                                    StatusBadge(text: L10n.text(UserFacingText.metadata($0, field: .component)), tone: $0 == "hooks" || $0 == "MCP" ? .danger : .accent)
                                }
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 16) {
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(L10n.tr("来源与版本"))
                                    .font(AppFont.heading)
                                KeyValueLine(key: L10n.tr("宿主"), value: plugin.host.displayName)
                                KeyValueLine(key: L10n.tr("市场"), value: plugin.marketplaceID ?? L10n.tr("项目或本地目录"))
                                KeyValueLine(key: L10n.tr("声明版本"), value: plugin.version ?? L10n.tr("未声明"))
                                KeyValueLine(key: L10n.tr("安装范围"), value: plugin.scope.map { L10n.text(UserFacingText.metadata($0, field: .scope)) } ?? L10n.tr("尚未确认"))
                                KeyValueLine(
                                    key: L10n.tr("安装版本"),
                                    value: plugin.sourceRevision ?? L10n.tr("未从安装索引获得"),
                                    monospaced: true
                                )
                                KeyValueLine(
                                    key: L10n.tr("清单指纹"),
                                    value: String(plugin.manifestDigest.prefix(20)) + "…",
                                    monospaced: true
                                )
                            }
                        }
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(L10n.tr("依赖与路径"))
                                    .font(AppFont.heading)
                                KeyValueLine(
                                    key: L10n.tr("依赖"),
                                    value: plugin.dependencyCount == 0
                                        ? L10n.tr("未声明")
                                        : L10n.tr("\(plugin.dependencyCount) 项，安装解析由宿主负责")
                                )
                                KeyValueLine(key: L10n.tr("许可"), value: plugin.license ?? L10n.tr("未声明"))
                                Text(plugin.sourcePath)
                                    .font(AppFont.secondary.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .lineLimit(4)
                                Text(L10n.tr("仅凭版本号无法确认内容一致，还需核对来源、具体版本和清单指纹。"))
                                    .font(AppFont.secondary)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(L10n.tr("权限与副作用"), systemImage: "hand.raised.fill")
                                .font(AppFont.heading)
                            ForEach(plugin.risks, id: \.self) { risk in
                                Label(L10n.text(UserFacingText.pluginRisk(risk)), systemImage: risk.contains("hook") ? "exclamationmark.triangle.fill" : "info.circle")
                                    .font(AppFont.secondary)
                                    .foregroundStyle(risk.contains("hook") ? .red : .secondary)
                            }
                            Text(L10n.tr("安装、停用或卸载不能撤销脚本已经造成的改动；加载新插件可能需要重启会话。"))
                                .font(AppFont.secondary)
                                .foregroundStyle(.secondary)
                        }
                    }

                    lifecycleCard(plugin)

                    HStack {
                        Button(L10n.tr("查看清单文件")) {
                            NSWorkspace.shared.activateFileViewerSelecting([
                                URL(fileURLWithPath: plugin.manifestPath)
                            ])
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColor.accent)

                        Button(L10n.tr("复制插件标识")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(plugin.pluginID, forType: .string)
                            model.report("已复制 \(plugin.pluginID)")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        } else {
            EmptyState(
                icon: "puzzlepiece.extension",
                title: L10n.tr("选择一个插件"),
                detail: L10n.tr("选择左侧插件，核对来源、具体版本和自动运行脚本的风险。")
            )
        }
    }

    private func lifecycleCard(_ plugin: PluginInventoryRecord) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(L10n.tr("插件操作"), systemImage: "gearshape.2.fill")
                    .font(AppFont.heading)
                Text(L10n.tr("本应用只生成固定宿主命令的计划；批准后调用本机 Claude Code 或 Codex CLI。不会拼接任意 shell 参数。"))
                    .font(AppFont.secondary)
                    .foregroundStyle(.secondary)

                if requiresRiskAcknowledgement(plugin) {
                    Toggle(
                        L10n.tr("已核对完整插件包、自动运行脚本、命令、服务和配置风险，允许生成计划"),
                        isOn: $acknowledgedExecutableRisk
                    )
                    .font(AppFont.secondary)
                    .toggleStyle(.checkbox)
                    if !acknowledgedExecutableRisk {
                        Text(L10n.tr("请先勾选风险确认，再生成安装或更新计划。"))
                            .font(AppFont.secondary)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    if !plugin.installed {
                        lifecycleButton(
                            plugin,
                            action: .install,
                            title: L10n.tr("生成安装计划"),
                            requiresRiskAcknowledgement: true
                        )
                    } else {
                        if plugin.host == .claudeCode {
                            if plugin.enabled == false {
                                lifecycleButton(
                                    plugin,
                                    action: .enable,
                                    title: L10n.tr("生成启用计划")
                                )
                            } else {
                                lifecycleButton(
                                    plugin,
                                    action: .disable,
                                    title: L10n.tr("生成停用计划")
                                )
                            }
                            lifecycleButton(
                                plugin,
                                action: .update,
                                title: L10n.tr("生成更新计划"),
                                requiresRiskAcknowledgement: true
                            )
                        }
                        lifecycleButton(
                            plugin,
                            action: .uninstall,
                            title: L10n.tr("生成卸载计划")
                        )
                    }
                    Spacer()
                }

                if plugin.host == .codex {
                    Text(L10n.tr("Codex 当前公开 CLI 只提供 add / remove；本应用不会推断 enable、disable 或 update。"))
                        .font(AppFont.secondary)
                        .foregroundStyle(.secondary)
                }
                if plugin.installed, plugin.enabled == nil {
                    Text(L10n.tr("宿主尚未给出启用状态；生成动作计划时会重新读取，执行前仍未知则拒绝猜测。"))
                        .font(AppFont.secondary)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func lifecycleButton(
        _ plugin: PluginInventoryRecord,
        action: PluginLifecycleAction,
        title: String,
        requiresRiskAcknowledgement: Bool = false
    ) -> some View {
        Button(title) {
            model.makePluginLifecyclePlan(
                plugin,
                action: action,
                acknowledgeExecutableComponents: requiresRiskAcknowledgement
                    && acknowledgedExecutableRisk
            )
        }
        .buttonStyle(.bordered)
        .tint(action == .uninstall ? Color.secondary : AppColor.accentText)
        .disabled(
            requiresRiskAcknowledgement
                && !acknowledgedExecutableRisk
        )
    }

    private func requiresRiskAcknowledgement(_ plugin: PluginInventoryRecord) -> Bool {
        !plugin.installed || plugin.host == .claudeCode
    }

    private func hasExecutableComponents(_ plugin: PluginInventoryRecord) -> Bool {
        !Set(plugin.components)
            .intersection(["hooks", "commands", "MCP", "LSP", "userConfig"])
            .isEmpty
    }

    private func statusTone(_ plugin: PluginInventoryRecord) -> BadgeTone {
        if plugin.components.contains("hooks") {
            return .danger
        }
        if plugin.installed {
            return plugin.enabled == false ? .warning : .positive
        }
        return .warning
    }
}
