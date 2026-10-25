import SwiftUI
import SkillSetCore

/// 预设载入后仍能在项目里逐项审阅；所有执行复用原有审批入口。
struct ProjectPresetComponents: View {
    @Bindable var model: AppModel
    let project: ProjectRecord
    @State private var acknowledged: Set<String> = []

    var body: some View {
        if !project.draftPlugins.isEmpty || !project.draftMCPServers.isEmpty {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 16) {
                    Label(L10n.tr("预设中的插件与 MCP"), systemImage: "rectangle.3.group").font(AppFont.heading)
                    Text(L10n.tr("这些组件已保存在草稿。逐项核对使用范围并预览计划，批准后才会安装、启用或写入连接配置。"))
                        .font(AppFont.secondary).foregroundStyle(.secondary)
                    ForEach(project.draftPlugins) { reference in
                        VStack(alignment: .leading, spacing: 10) {
                            ConfigurationSectionHeader {
                                componentTitle(reference.name, detail: "\(reference.host.displayName) · \(L10n.text(reference.scope.displayName)) · \(reference.manifestDigest.prefix(10))")
                            } actions: {
                                Button(L10n.tr("预览插件计划")) {
                                    model.preparePresetPlugin(reference, acknowledge: acknowledged.contains(reference.id))
                                }
                                .disabled(!acknowledged.contains(reference.id) || model.isWorking)
                            }
                            if reference.scope == .user { globalScopeNote }
                            Toggle(L10n.tr("我已核对插件中的自动运行脚本、命令和其他可运行内容。"), isOn: Binding(
                                get: { acknowledged.contains(reference.id) },
                                set: { checked in
                                    if checked { acknowledged.insert(reference.id) } else { acknowledged.remove(reference.id) }
                                }
                            ))
                            .toggleStyle(.checkbox).font(AppFont.secondary)
                            Button(L10n.tr("从草稿移除")) { model.removePresetComponent(pluginID: reference.id) }
                        }
                        Divider()
                    }
                    ForEach(project.draftMCPServers, id: \.presetID) { server in
                        VStack(alignment: .leading, spacing: 10) {
                            ConfigurationSectionHeader {
                                componentTitle(server.name, detail: "\(server.host.displayName) · \(L10n.text(server.scope.displayName)) · \(server.transport)")
                            } actions: {
                                Button(L10n.tr("预览 MCP 计划")) { _ = model.makeMCPConfigPlan(server) }
                                    .disabled(model.isWorking)
                            }
                            if server.scope == .user { globalScopeNote }
                            Text(server.commandOrURL).font(AppFont.metadata.monospaced()).foregroundStyle(.secondary)
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            if !server.envKeys.isEmpty {
                                Text(L10n.tr("环境变量引用：\(server.envKeys.joined(separator: "、"))（只保存名称）"))
                                    .font(AppFont.metadata).foregroundStyle(.secondary)
                            }
                            Button(L10n.tr("从草稿移除")) { model.removePresetComponent(mcpID: server.presetID) }
                        }
                        Divider()
                    }
                    Text(L10n.tr("从草稿移除不会卸载插件或删除已有 MCP 配置。"))
                        .font(AppFont.metadata).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var globalScopeNote: some View {
        Label(L10n.tr("使用范围：这个 AI 工具的所有项目。"), systemImage: "person.crop.circle.badge.exclamationmark")
            .font(AppFont.metadata).foregroundStyle(.orange)
    }

    private func componentTitle(_ name: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(AppFont.body.weight(.semibold))
            Text(detail).font(AppFont.metadata).foregroundStyle(.secondary)
        }
    }
}
