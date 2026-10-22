import SwiftUI
import SkillSetCore

struct MCPServersView: View {
    @Bindable var model: AppModel
    @State private var tab = "library"
    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var editor: MCPLibraryEntry?
    @State private var deleting: MCPLibraryEntry?
    @State private var scanPresented = false
    private var library: MCPLibraryModel { model.mcpLibrary }
    private var filtered: [MCPLibraryEntry] {
        library.entries.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.commandOrURL.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker(L10n.tr("MCP 服务"), selection: $tab) {
                Text(L10n.tr("配置库")).tag("library")
                Text(L10n.tr("已有连接")).tag("observed")
            }.pickerStyle(.segmented).frame(maxWidth: 340)
            if tab == "observed" {
                MCPObservedServersView(model: model)
            } else {
                libraryContent
            }
        }
        .task { library.refresh() }
        .sheet(item: $editor) { entry in MCPLibraryEditorSheet(library: library, entry: entry) }
        .sheet(isPresented: $scanPresented) { MCPLibraryScanSheet(library: library) }
        .confirmationDialog(L10n.tr("从配置库删除服务？"), isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button(L10n.tr("删除"), role: .destructive) {
                if let deleting { library.remove(deleting) }
                deleting = nil
            }
            Button(L10n.tr("取消"), role: .cancel) { deleting = nil }
        } message: {
            Text(L10n.tr("删除只影响配置库，已写入的连接保持原样。全局或项目中的失效引用需要取消，并预览 MCP 移除计划。"))
        }
        .appControls()
    }

    private var libraryContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(eyebrow: "MCP LIBRARY", title: L10n.tr("MCP 配置库"),
                detail: L10n.tr("在这里管理可复用的 MCP 配置，再到全局配置或项目中勾选使用。保存配置不会写入 AI 工具。"))
            HStack {
                Text(L10n.tr("\(library.entries.count) 个服务")).font(AppFont.secondary).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.tr("扫描已有配置…")) { library.scan(); scanPresented = true }
                    .accessibilityIdentifier("mcp.library.scan")
                Button { editor = MCPLibraryEntry() } label: {
                    Label(L10n.tr("添加 MCP 服务"), systemImage: "plus")
                }
                .buttonStyle(AppButtonStyle(kind: .primary))
                .accessibilityIdentifier("mcp.library.add")
            }
            if let error = library.error { Text(L10n.text(error)).foregroundStyle(.red) }
            HStack(alignment: .top, spacing: AppLayout.columnSpacing) {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        AppSearchField(query: $query, prompt: L10n.tr("搜索名称或命令"),
                            label: L10n.tr("搜索 MCP 服务"), identifier: "mcp.library.search")
                        if filtered.isEmpty {
                            Text(L10n.tr("没有匹配的服务。添加配置，或扫描已有连接入库。"))
                                .font(AppFont.secondary).foregroundStyle(.secondary)
                        }
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(filtered) { entry in
                                    Button { selectedID = entry.id } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(entry.name).font(AppFont.body.weight(.semibold)).foregroundStyle(.primary)
                                            Text(entry.transport).font(AppFont.secondary).foregroundStyle(.secondary)
                                        }
                                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                        .selectionRow(selectedID == entry.id).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }.frame(width: AppLayout.listWidth)
                if let entry = filtered.first(where: { $0.id == selectedID }) ?? filtered.first {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(entry.name).font(AppFont.title.weight(.bold))
                            StatusBadge(text: entry.transport, tone: .accent)
                            Text(entry.commandOrURL).font(AppFont.code).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            if !entry.args.isEmpty {
                                Text(entry.args.joined(separator: "\n")).font(AppFont.code).textSelection(.enabled)
                            }
                            if !entry.envKeys.isEmpty {
                                Text(L10n.tr("环境变量引用：\(entry.envKeys.joined(separator: "、"))（只保存名称）"))
                                    .font(AppFont.secondary).foregroundStyle(.secondary)
                            }
                            Divider()
                            Text(L10n.tr("在全局配置或项目中勾选这个服务，再预览并批准 MCP 变更。修改配置库后，已写入的连接需重新预览更新。"))
                                .font(AppFont.secondary).foregroundStyle(.secondary)
                            HStack {
                                Button(L10n.tr("编辑…")) { editor = entry }
                                Button(L10n.tr("删除…"), role: .destructive) { deleting = entry }
                                Spacer()
                                Button(L10n.tr("前往全局配置")) { model.section = .globalConfiguration }
                                Button(L10n.tr("前往项目")) { model.section = .projects }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    EmptyState(icon: "point.3.connected.trianglepath.dotted", title: L10n.tr("添加可复用的 MCP 配置"),
                        detail: L10n.tr("手动添加服务，或从系统已有配置扫描入库。"))
                }
            }
        }
    }
}
