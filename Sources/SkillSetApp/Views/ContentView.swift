import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 320, ideal: 320, max: 400)
        } detail: {
            DetailView(model: model)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1080, minHeight: 700)
        .sheet(isPresented: $model.planPresented) {
            PlanSheet(model: model)
        }
        .sheet(item: $model.templateUseRequest, onDismiss: model.presentTemplatePlanIfReady) { request in
            TemplateUseSheet(model: model, template: request.template)
        }
        .sheet(item: $model.presetSelection) { request in
            PresetSelectionSheet(model: model, request: request)
        }
        .sheet(item: $model.presetEditor) { draft in
            PresetEditorSheet(model: model, draft: draft)
        }
        .tint(AppColor.accent)
        .accentColor(AppColor.accent)
        .disclosureGroupStyle(FullRowDisclosureGroupStyle())
        .appControls()
        .font(AppFont.body)
        .lineSpacing(2)
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
                        .padding(8)
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
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.text("设置"))
                                .font(AppFont.secondary.weight(.semibold))
                            Text(L10n.text("外观与语言"))
                                .font(AppFont.metadata)
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .selectionRow(model.section == .settings)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.settings")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
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
        .padding(.vertical, AppLayout.pageVerticalInset)
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
