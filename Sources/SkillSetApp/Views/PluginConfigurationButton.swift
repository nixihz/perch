import SwiftUI
import SkillSetCore

struct PluginConfigurationCard: View {
    @Bindable var model: AppModel
    let host: MCPHost
    var projectID: UUID? = nil

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(host.displayName + " · " + L10n.tr("插件配置")).font(AppFont.heading)
                Text(projectID == nil ? L10n.tr("使用范围：这个 AI 工具的所有项目。") : L10n.tr("仅配置当前项目；全局插件仍可能生效。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
                if projectID != nil && host == .codex {
                    Text(L10n.tr("Codex 插件目前只支持用户范围，请到全局配置中管理。"))
                        .font(AppFont.secondary).foregroundStyle(.secondary)
                }
                HStack {
                    PluginConfigurationButton(model: model, host: host, projectID: projectID)
                    Button(L10n.tr("管理插件来源")) { model.section = .plugins }
                }
            }
        }
    }
}

/// 配置上下文在打开时固定，不能从来源页或当前选择推断作用域。
struct PluginConfigurationButton: View {
    @Bindable var model: AppModel
    let host: MCPHost
    var projectID: UUID? = nil
    @State private var presented = false
    @State private var pendingPlan = false

    var body: some View {
        Button(L10n.tr("配置插件…")) { presented = true }
            .accessibilityIdentifier("plugins.configure.\(host.rawValue)")
            .disabled(projectID != nil && host == .codex)
            .help(projectID != nil && host == .codex
                ? L10n.tr("Codex 插件目前只支持用户范围，请到全局配置中管理。")
                : L10n.tr("核对当前范围的插件并预览变更计划"))
            .sheet(isPresented: $presented, onDismiss: {
                if pendingPlan {
                    pendingPlan = false
                    model.planPresented = true
                }
            }) {
                VStack(alignment: .leading, spacing: 12) {
                    PluginConfigurationView(model: model, host: host, projectID: projectID) { pendingPlan = true }
                    HStack {
                        Spacer()
                        Button(L10n.tr("完成")) { presented = false }.keyboardShortcut(.cancelAction)
                    }
                }
                .padding(24).frame(width: 1000, height: 680).appControls()
            }
    }
}
