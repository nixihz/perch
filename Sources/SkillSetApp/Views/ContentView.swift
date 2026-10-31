import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 240, ideal: 240, max: 300)
        } detail: {
            DetailView(model: model)
                .buttonStyle(AppButtonStyle())
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1080, minHeight: 700)
        .sheet(isPresented: $model.planPresented) {
            PlanSheet(model: model, savesFromPreview: model.section == .globalConfiguration || model.section == .projects)
                .buttonStyle(AppButtonStyle())
        }
        .sheet(item: $model.templateUseRequest, onDismiss: model.presentTemplatePlanIfReady) { request in
            TemplateUseSheet(model: model, template: request.template)
                .buttonStyle(AppButtonStyle())
        }
        .sheet(item: $model.presetSelection) { request in
            PresetSelectionSheet(model: model, request: request)
                .buttonStyle(AppButtonStyle())
        }
        .sheet(item: $model.presetEditor) { draft in
            PresetEditorSheet(model: model, draft: draft)
                .buttonStyle(AppButtonStyle())
        }
        .tint(AppColor.accent)
        .accentColor(AppColor.accent)
        .disclosureGroupStyle(FullRowDisclosureGroupStyle())
        // 系统边栏按钮继承根样式；页面与弹窗在各自边界恢复常规按钮。
        .appControls(buttonKind: .quiet)
        .font(AppFont.body)
        .lineSpacing(1)
        .background(SplitDividerStyle())
        .task { await model.observeLibraryChanges() }
    }
}

struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var relationshipPresented = false

    var body: some View {
        SidebarList(selection: $model.section, skillCount: model.snapshot.catalog.entries.count)
        .safeAreaInset(edge: .top, spacing: 0) {
            BrandHeader()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Divider()
                Button {
                    relationshipPresented = true
                } label: {
                    Label(L10n.tr("配置关系图"), systemImage: "point.3.filled.connected.trianglepath.dotted")
                        .font(AppFont.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .frame(minHeight: AppControl.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.relationships")
                Button {
                    model.section = .settings
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "gearshape")
                            .foregroundStyle(AppColor.accentText)
                        Text(L10n.text("设置"))
                            .font(AppFont.secondary.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .frame(minHeight: AppControl.height)
                    .selectionRow(model.section == .settings)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.settings")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        // 分栏由 AppKit 动画；内部内容不再叠加 SwiftUI 的出现与布局动画。
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .sheet(isPresented: $relationshipPresented) {
            ConfigurationMapSheet(model: model)
        }
    }

}

struct DetailView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            switch model.section {
            case .globalConfiguration:
                GlobalConfigurationView(model: model)
            case .projects:
                ProjectsView(model: model)
            case .skills:
                SkillsView(model: model)
            case .mcp:
                MCPServersView(model: model)
            case .plugins:
                PluginsView(model: model)
            case .sources:
                SourcesView(model: model)
            case .presets:
                PresetsView(model: model)
            case .templates:
                TemplatesView(model: model)
            case .aiAccess:
                AIAccessView(model: model)
            case .settings:
                SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, AppLayout.pageHorizontalInset)
        // 详情区横跨标题栏下方的安全区，只保留小段顶部呼吸空间，避免空工具栏挤占首屏高度。
        .padding(.top, AppLayout.pageTopInset)
        .padding(.bottom, AppLayout.pageBottomInset)
        .ignoresSafeArea(.container, edges: .top)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [AppColor.accent.opacity(0.045), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 240)
                }
                .ignoresSafeArea()
        }
    }
}
