import SwiftUI

struct GlobalConfigurationView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppLayout.columnSpacing) {
            PageHeader(eyebrow: "USER CONFIGURATION", title: L10n.tr("全局配置"),
                detail: L10n.tr("点击 Agents、Codex 或 Claude Code 图标即可保存技能。Agents 为共享目录，其他资源按工具配置。"))
            ConfigurationResourceView(model: model)
        }
    }
}
