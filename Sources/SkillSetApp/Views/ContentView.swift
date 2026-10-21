import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
        } detail: {
            DetailView(model: model)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1080, minHeight: 700)
        .searchable(
            text: Binding(
                get: { model.query },
                set: { model.updateQuery($0) }
            ),
            placement: .toolbar,
            prompt: L10n.tr("搜索技能、来源或路径")
        )
        .toolbar {
            ToolbarItem(placement: .status) {
                HStack(spacing: 7) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text(model.lastAction)
                        .font(AppFont.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .sheet(isPresented: $model.planPresented) {
            PlanSheet(model: model)
        }
        .tint(AppColor.accent)
        .accentColor(AppColor.accent)
        .font(AppFont.body)
        .lineSpacing(2)
    }
}

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        SidebarList(selection: $model.section, skillCount: model.snapshot.catalog.entries.count)
        .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        .safeAreaInset(edge: .top, spacing: 0) {
            BrandHeader()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Divider()
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
                        Spacer(minLength: 0)
                        Text("⌘,")
                            .font(AppFont.metadata)
                            .foregroundStyle(.secondary)
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
    }

}

struct DetailView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            switch model.section {
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

