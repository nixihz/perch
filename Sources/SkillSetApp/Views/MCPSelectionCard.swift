import SwiftUI
import SkillSetCore

struct MCPSelectionCard: View {
    @Bindable var model: AppModel
    let host: MCPHost
    let projectID: UUID?
    @State private var query = ""
    private var library: MCPLibraryModel { model.mcpLibrary }
    private var unsupported: Bool { projectID != nil && host == .codex }

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.tr("MCP 服务")).font(AppFont.heading)
                    Text(host.displayName).font(AppFont.secondary).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.tr("预览 MCP 变更")) { model.prepareMCPLibraryPlan(host: host, projectID: projectID) }
                        .disabled(unsupported || model.isWorking)
                        .accessibilityIdentifier("mcp.selection.preview.\(host.rawValue)")
                }
                Text(L10n.tr(projectID == nil ? "勾选配置库中的服务，影响当前用户该工具的全部项目。批准 MCP 计划后生效。" : "勾选配置库中的服务用于当前项目。全局 MCP 仍可能生效；批准 MCP 计划后写入。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
                if unsupported {
                    Text(L10n.tr("Codex 目前只支持用户级 MCP，请在全局配置中勾选。"))
                        .font(AppFont.secondary).foregroundStyle(.orange)
                } else {
                    selectionList
                }
                if let error = library.error {
                    Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red)
                }
                Button(L10n.tr("管理 MCP 配置库")) { model.section = .mcp }
            }
        }
        .task(id: library.store.selectionKey(host: host, projectID: projectID)) {
            library.refresh()
            library.loadSelection(host: host, projectID: projectID)
            model.refreshMCPConfigurations()
        }

    }

    private var selectionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if library.entries.isEmpty {
                Text(L10n.tr("配置库为空，先添加服务或扫描已有配置入库。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            } else {
                AppSearchField(query: $query, prompt: L10n.tr("搜索 MCP 服务"),
                    label: L10n.tr("搜索 MCP 服务"), identifier: "mcp.selection.search")
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(library.entries.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { entry in
                            Toggle(isOn: Binding(
                                get: { library.selectedIDs(host: host, projectID: projectID).contains(entry.id) },
                                set: { library.select(entry.id, enabled: $0, host: host, projectID: projectID) }
                            )) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.name).font(AppFont.body.weight(.semibold))
                                    Text(entry.transport).font(AppFont.secondary).foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .accessibilityIdentifier("mcp.selection.entry.\(entry.id)")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 220)
            }
            ForEach(library.selectedIDs(host: host, projectID: projectID).filter { id in !library.entries.contains { $0.id == id } }, id: \.self) { id in
                HStack {
                    Text(L10n.tr("所选服务已从配置库删除，请取消引用。"))
                        .font(AppFont.secondary).foregroundStyle(.orange)
                    Spacer()
                    Button(L10n.tr("移除引用")) { library.select(id, enabled: false, host: host, projectID: projectID) }
                }
            }
            let inherited = model.mcpConfigInspections.filter { $0.host == host && $0.scope == .user }.flatMap(\.servers)
            if projectID != nil && !inherited.isEmpty {
                Text(L10n.tr("全局已有连接：\(inherited.map(\.name).joined(separator: "、"))"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }
            Text(L10n.tr("勾选只保存草稿。取消勾选后批准计划，才会移除配置库写入且未经修改的服务。"))
                .font(AppFont.metadata).foregroundStyle(.secondary)
        }
    }
}
