import SwiftUI
import SkillSetCore

struct MCPSelectionCard: View {
    @Bindable var model: AppModel
    let host: MCPHost
    let projectID: UUID?
    @State private var query = ""
    @State private var selectedOnly = false
    private var library: MCPLibraryModel { model.mcpLibrary }
    private var unsupported: Bool { projectID != nil && host == .codex }
    private var selectedIDs: [UUID] { library.selectedIDs(host: host, projectID: projectID) }
    private var filtered: [MCPLibraryEntry] {
        library.entries.filter { entry in
            (!selectedOnly || selectedIDs.contains(entry.id)) && (query.isEmpty || entry.name.localizedCaseInsensitiveContains(query))
        }
    }
    private var target: MCPLibraryUsageTarget? {
        library.usageTargets.first { $0.host == host && $0.projectID == projectID }
    }

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.tr("MCP 服务")).font(AppFont.heading)
                    Spacer()
                    Text(host.displayName).font(AppFont.secondary).foregroundStyle(.secondary)
                }
                Text(L10n.tr(projectID == nil
                    ? "这里的选择影响当前用户该工具的全部项目。预览并批准后才写入配置文件。"
                    : "这里的选择只写入当前项目；全局 MCP 仍可能生效。预览并批准后才写入配置文件。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
                if unsupported {
                    Text(L10n.tr("Codex 目前只支持用户级 MCP，请在全局配置中勾选。"))
                        .font(AppFont.secondary).foregroundStyle(.orange)
                    Button(L10n.tr("前往 Codex 全局配置")) {
                        model.globalConfiguration.selectHost(.codex)
                        model.section = .globalConfiguration
                    }
                } else {
                    if let target {
                        Text(target.configPath).font(AppFont.code).foregroundStyle(.secondary).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    selectionList
                    Button(L10n.tr("预览 MCP 变更")) { model.prepareMCPLibraryPlan(host: host, projectID: projectID) }
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("mcp.selection.preview.\(host.rawValue)")
                }
                if let error = library.error { Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red) }
                Button(L10n.tr("管理 MCP 配置库")) { model.section = .mcp }
            }
        }
        .task(id: library.store.selectionKey(host: host, projectID: projectID)) {
            library.refresh()
            library.loadSelection(host: host, projectID: projectID)
            library.refreshUsage()
            model.refreshMCPConfigurations()
        }
    }

    private var selectionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if library.entries.isEmpty {
                Text(L10n.tr("配置库为空，先添加服务或扫描已有配置入库。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            } else {
                Text(L10n.tr("配置库 \(library.entries.count) 个 · 草稿已选 \(selectedIDs.count) 个"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
                    .accessibilityIdentifier("mcp.selection.summary")
                HStack {
                    AppSearchField(query: $query, prompt: L10n.tr("搜索 MCP 服务"),
                        label: L10n.tr("搜索 MCP 服务"), identifier: "mcp.selection.search")
                    Toggle(L10n.tr("只看已选"), isOn: $selectedOnly).toggleStyle(.checkbox)
                        .font(AppFont.secondary)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if filtered.isEmpty {
                            Text(L10n.tr("没有符合当前筛选的服务。"))
                                .font(AppFont.secondary).foregroundStyle(.secondary)
                            Button(L10n.tr("显示全部服务")) { query = ""; selectedOnly = false }
                        }
                        ForEach(filtered) { entry in
                            Toggle(isOn: Binding(
                                get: { selectedIDs.contains(entry.id) },
                                set: { library.select(entry.id, enabled: $0, host: host, projectID: projectID) }
                            )) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.name).font(AppFont.body.weight(.semibold))
                                    Text(MCPConnectionFields.transportTitle(entry.transport))
                                        .font(AppFont.secondary).foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .accessibilityIdentifier("mcp.selection.entry.\(entry.id)")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 220)
            }
            ForEach(selectedIDs.filter { id in !library.entries.contains { $0.id == id } }, id: \.self) { id in
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("所选服务已从配置库删除，请取消引用。"))
                        .font(AppFont.secondary).foregroundStyle(.orange)
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
