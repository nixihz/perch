import AppKit
import SwiftUI
import SkillSetCore

struct PluginsView: View {
    @Bindable var model: AppModel
    @State private var sources: [SourcePreviewRecord] = []
    @State private var selectedID: UUID?
    @State private var detailState = DetailSnapshotModel<UUID, PluginSourceDetailSnapshot>()
    @State private var editing: SourcePreviewRecord?
    @State private var editorPresented = false
    @State private var scanPresented = false
    @State private var deleting: SourcePreviewRecord?
    @State private var query = ""
    @State private var error: String?
    @State private var detailRevision = 0

    private var inventory: PluginInventorySnapshot? { detailState.key == selectedID ? detailState.snapshot?.inventory : nil }
    private var evidence: PluginImportEvidence? { detailState.key == selectedID ? detailState.snapshot?.evidence : nil }
    private var detailError: String? { detailState.key == selectedID ? detailState.error : nil }

    private var library: PluginSourceLibrary { PluginSourceLibrary(stateRoot: model.runtimePaths.applicationSupportRoot) }
    private var selected: SourcePreviewRecord? { sources.first { $0.id == selectedID } }
    private var filtered: [SourcePreviewRecord] {
        sources.filter { query.isEmpty || [$0.namespace, $0.inputURL].contains { $0.localizedCaseInsensitiveContains(query) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageActionHeader(eyebrow: "PLUGIN SOURCES", title: L10n.tr("插件来源"),
                detail: L10n.tr("保存插件仓库或本地包，也可扫描本机插件后收录。需要使用时，再到全局配置或项目选择范围并预览计划。")) {
                Button(L10n.tr("扫描本机插件…")) { scanPresented = true }
                    .accessibilityIdentifier("plugins.scan")
                Button { editing = nil; editorPresented = true } label: {
                    Label(L10n.tr("添加插件来源"), systemImage: "plus")
                }
                .buttonStyle(AppButtonStyle(kind: .primary))
                .accessibilityIdentifier("plugins.source.add")
            }
            if let error { Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red) }
            HStack(alignment: .top, spacing: AppLayout.columnSpacing) {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(L10n.tr("插件来源")).font(AppFont.heading)
                            Spacer()
                        }
                        AppSearchField(query: $query, prompt: L10n.tr("搜索名称或来源"),
                            label: L10n.tr("搜索插件来源"), identifier: "plugins.source.search")

                        if filtered.isEmpty {
                            Text(L10n.tr("还没有匹配的插件来源。添加仓库、本地目录，或扫描本机插件。"))
                                .font(AppFont.secondary).foregroundStyle(.secondary)
                        }
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(filtered) { source in
                                    Button { select(source) } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(source.namespace).font(AppFont.body.weight(.semibold)).foregroundStyle(.primary)
                                            Text(source.inputURL).font(AppFont.metadata).foregroundStyle(.secondary).lineLimit(2)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                        .selectionRow(source.id == selectedID).contentShape(Rectangle())
                                    }.buttonStyle(AppPressButtonStyle())
                                }
                            }
                        }
                        Text(L10n.tr("保存来源不安装插件，也不修改 AI 工具的市场或配置。"))
                            .font(AppFont.secondary).foregroundStyle(.secondary)
                    }
                }.frame(width: AppLayout.listWidth)
                sourceDetail
            }
        }
        .task { reload() }
        .task(id: DetailRequest(sourceID: selectedID, revision: detailRevision)) {
            guard let selectedID else { detailState.reset(); return }
            let root = model.runtimePaths.applicationSupportRoot
            await detailState.load(for: selectedID) {
                try await Task.detached(priority: .userInitiated) {
                    let library = PluginSourceLibrary(stateRoot: root)
                    return PluginSourceDetailSnapshot(inventory: try library.inventory(selectedID),
                                                      evidence: try library.evidence(selectedID))
                }.value
            }
        }
        .sheet(isPresented: $editorPresented) {
            PluginSourceEditor(library: library, source: editing) { source in reload(preferred: source.id) }
        }
        .sheet(isPresented: $scanPresented, onDismiss: { reload() }) {
            PluginScanSheet(model: model, library: library)
        }
        .confirmationDialog(L10n.tr("移除插件来源？"), isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(L10n.tr("移除"), role: .destructive) {
                guard let source = deleting else { return }
                do { try library.remove(source.id); deleting = nil; reload() }
                catch { self.error = UserFacingText.error(error) }
            }
            Button(L10n.tr("先不移除"), role: .cancel) { deleting = nil }
        } message: {
            Text(L10n.tr("移除来源及栖集中的隔离副本，保留原始目录和已有插件安装。"))
        }
    }

    @ViewBuilder private var sourceDetail: some View {
        if let source = selected, filtered.contains(where: { $0.id == source.id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SurfaceCard(emphasis: true) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(source.namespace).font(AppFont.title)
                            DisclosureGroup(L10n.tr("详细信息")) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(source.inputURL).font(AppFont.code).textSelection(.enabled)
                                    KeyValueLine(key: L10n.tr("快照版本"), value: source.resolvedCommit, monospaced: true)
                                }
                            }
                            HStack {
                                Button(L10n.tr("编辑来源…")) { editing = source; editorPresented = true }
                                Button(L10n.tr("移除来源…"), role: .destructive) { deleting = source }
                            }
                            Text(L10n.tr("编辑会重新读取来源，失败时保留旧记录。已有安装不会跟随来源更新。"))
                                .font(AppFont.secondary).foregroundStyle(.secondary)
                        }
                    }
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.tr("来源中的插件")).font(AppFont.heading)
                            if detailState.isLoading {
                                ProgressView(L10n.tr("正在读取插件内容…")).controlSize(.small)
                            }
                            if let error = detailError {
                                Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red)
                                if inventory != nil {
                                    Text(L10n.tr("显示上次读取结果。"))
                                        .font(AppFont.secondary).foregroundStyle(.secondary)
                                }
                                Button(L10n.tr("重新读取")) { detailRevision += 1 }
                            }
                            if inventory?.records.isEmpty == true && !detailState.isLoading && detailError == nil {
                                Text(L10n.tr("没有找到可识别的插件清单，请检查来源目录，并确认 AI 工具是否支持这个插件。"))
                                    .font(AppFont.secondary).foregroundStyle(.secondary)
                            }
                            ForEach(inventory?.records ?? []) { plugin in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(plugin.name).font(AppFont.body.weight(.semibold))
                                    Text(plugin.host.displayName + " · " + (plugin.version ?? L10n.tr("未声明版本")))
                                        .font(AppFont.secondary).foregroundStyle(.secondary)
                                    Text(plugin.description).font(AppFont.secondary)
                                    Text(plugin.components.map { L10n.text(UserFacingText.metadata($0, field: .component)) }.joined(separator: " · "))
                                        .font(AppFont.metadata).foregroundStyle(.secondary)
                                    Button(L10n.tr("查看清单文件")) {
                                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: plugin.manifestPath)])
                                    }
                                }
                                Divider()
                            }
                            ForEach(inventory?.issues ?? [], id: \.self) { issue in
                                Text(L10n.text(UserFacingText.diagnostic(issue, context: .plugin)))
                                    .font(AppFont.secondary).foregroundStyle(.orange)
                            }
                        }
                    }
                    if let evidence {
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(L10n.tr("扫描收录记录")).font(AppFont.heading)
                                Text(L10n.date(evidence.scannedAt)).font(AppFont.secondary)
                                ForEach(evidence.installations) { installation in
                                    Text(installation.host.displayName + " · " + installation.pluginID).font(AppFont.secondary)
                                    Text(installation.sourcePath).font(AppFont.code).textSelection(.enabled)
                                    Text(L10n.text(UserFacingText.pluginState(installation))).font(AppFont.metadata).foregroundStyle(.secondary)
                                }
                                Text(L10n.tr("这里保存扫描时的安装证据，当前安装状态请在配置入口重新扫描。"))
                                    .font(AppFont.secondary).foregroundStyle(.secondary)
                            }
                        }
                    }
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.tr("按需配置")).font(AppFont.heading)
                            Text(L10n.tr("到「全局配置」或「项目」选择插件并预览变更；请先在 AI 工具中下载所需插件包。"))
                                .font(AppFont.secondary).foregroundStyle(.secondary)
                            HStack {
                                Button(L10n.tr("前往全局配置")) { model.section = .globalConfiguration }
                                Button(L10n.tr("前往项目")) { model.section = .projects }
                            }
                        }
                    }
                }
            }
        } else {
            EmptyState(icon: "puzzlepiece.extension", title: L10n.tr("选择一个插件来源"),
                detail: L10n.tr("查看来源、固定版本和插件内容，或扫描本机插件收录完整包。"))
        }
    }

    private func reload(preferred: UUID? = nil) {
        do {
            sources = try library.sources()
            selectedID = preferred ?? selectedID
            if let source = sources.first(where: { $0.id == selectedID }) ?? sources.first { select(source) }
            else { selectedID = nil; detailState.reset() }
            error = nil
        } catch { self.error = UserFacingText.error(error) }
    }

    private func select(_ source: SourcePreviewRecord) {
        selectedID = source.id
        detailRevision += 1
    }

    private struct DetailRequest: Hashable {
        let sourceID: UUID?
        let revision: Int
    }
}

private struct PluginSourceDetailSnapshot: Sendable {
    let inventory: PluginInventorySnapshot
    let evidence: PluginImportEvidence?
}

private struct PluginSourceEditor: View {
    let library: PluginSourceLibrary
    let source: SourcePreviewRecord?
    let onSave: (SourcePreviewRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var address: String
    @State private var ref: String
    @State private var busy = false
    @State private var error: String?

    init(library: PluginSourceLibrary, source: SourcePreviewRecord?, onSave: @escaping (SourcePreviewRecord) -> Void) {
        self.library = library; self.source = source; self.onSave = onSave
        _address = State(initialValue: source?.inputURL ?? "")
        _ref = State(initialValue: source?.requestedRef ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr(source == nil ? "添加插件来源" : "编辑插件来源")).font(AppFont.title)
            Text(L10n.tr("隔离读取完整来源，不执行插件脚本；保存后不会自动安装到 AI 工具。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            AppFormField(L10n.tr("Git 仓库链接或本地目录")) { TextField("owner/repository", text: $address) }
            Button(L10n.tr("选择本地目录…")) {
                let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.showsHiddenFiles = true
                if panel.runModal() == .OK, let url = panel.url { address = url.path; ref = "" }
            }
            AppFormField(L10n.tr("分支、标签或提交（可选）")) { TextField("", text: $ref) }
            if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(L10n.tr("请填写仓库链接，或选择本地目录。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }
            if let error { Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red) }
            if busy { ProgressView().controlSize(.small) }
            HStack {
                Spacer()
                Button(L10n.tr("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("保存来源")) {
                    busy = true; error = nil
                    let input = address, revision = ref, replacing = source?.id
                    Task {
                        do {
                            let result = try await Task.detached { try library.save(address: input, ref: revision, replacing: replacing) }.value
                            onSave(result); dismiss()
                        } catch { self.error = UserFacingText.error(error) }
                        busy = false
                    }
                }.keyboardShortcut("s", modifiers: .command).buttonStyle(AppButtonStyle(kind: .primary))
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .disabled(busy).interactiveDismissDisabled(busy).appControls().padding(26).frame(width: 620)
    }
}
