import SwiftUI

struct GlobalConfigurationView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppLayout.columnSpacing) {
            PageHeader(eyebrow: "USER CONFIGURATION", title: L10n.tr("全局配置"),
                detail: L10n.tr("点击工具图标选择资源，预览后保存。配置用于所选 AI 工具的全部项目。"))
            ConfigurationResourceView(model: model)
        }
    }
}
