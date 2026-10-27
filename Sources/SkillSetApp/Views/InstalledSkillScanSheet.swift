import SwiftUI
import AppKit
import SkillSetCore

struct InstalledSkillScanSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var scanModel = InstalledSkillScanModel()
    @State private var roots: [URL] = []
    @State private var error: String?
    @State private var importing = false
    @State private var query = ""
    @State private var showAll = false
    @State private var authorizedURLs: [URL] = []
    @State private var deleting: InstalledSkillObservation?
    @State private var deletingAll = false

    private var items: [InstalledSkillObservation] { scanModel.items }
    private var available: [InstalledSkillObservation] { items.filter(\.canImport) }
    private var visibleItems: [InstalledSkillObservation] {
        items.filter { (showAll || $0.canImport || $0.issue != nil) &&
            (query.isEmpty || $0.path.localizedCaseInsensitiveContains(query)) }
    }
    private var collectedItems: [InstalledSkillObservation] { items.filter { $0.collected && !$0.managed } }
    private var busy: Bool { scanModel.scanning || importing || model.isWorking }
    private var displayedError: String? { error ?? scanModel.error }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("扫描已安装技能")).font(AppFont.title)
                    Label(L10n.tr("只扫描你追加的目录。Codex 与 Claude Code 的技能目录仅在首次初始化时读取。"), systemImage: "square.on.square")
                        .font(AppFont.secondary).foregroundStyle(.secondary)
                }
                Spacer()
                Button { scan() } label: { Image(systemName: "arrow.clockwise") }
                    .help(L10n.tr("重新扫描")).accessibilityLabel(L10n.tr("重新扫描"))
                    .accessibilityIdentifier("installed.scan.refresh")
                    .disabled(busy)
                Button(L10n.tr("添加目录…"), systemImage: "folder.badge.plus") { chooseDirectories() }
                    .disabled(busy)
            }
            HStack {
                Text(L10n.tr("可收录 \(available.count) 项")).font(AppFont.heading)
                Spacer()
                Toggle(L10n.tr("显示已收录"), isOn: $showAll).toggleStyle(AppCheckboxStyle())
                if !collectedItems.isEmpty {
                    Button(L10n.tr("批量删除原安装…"), role: .destructive) {
                        deletingAll = true
                    }.disabled(busy)
                }
                Button(L10n.tr(scanModel.selected.isEmpty ? "全选可收录项" : "清空勾选")) {
                    scanModel.selected = scanModel.selected.isEmpty ? Set(available.map(\.id)) : []
                }.disabled(busy || available.isEmpty)
            }
            TextField(L10n.tr("搜索技能"), text: $query)
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("installed.scan.search")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if scanModel.scanning {
                        HStack { Spacer(); ProgressView(L10n.tr("正在扫描…")); Spacer() }.padding(40)
                    } else if visibleItems.isEmpty {
                        ContentUnavailableView {
                            Label(L10n.tr(query.isEmpty ? "没有待收录技能" : "没有匹配的技能"), systemImage: "tray")
                        } actions: {
                            if !query.isEmpty { Button(L10n.tr("清空筛选")) { query = "" } }
                            else { Button(L10n.tr("添加扫描目录…")) { chooseDirectories() } }
                        }
                    } else {
                        ForEach(visibleItems) { item in
                            skillRow(item)
                            Divider()
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            if let error = displayedError {
                Label(L10n.text(error), systemImage: "exclamationmark.triangle")
                    .font(AppFont.secondary).foregroundStyle(.red).textSelection(.enabled)
            }
            if let error = model.installedSkillRemovalError {
                Label(L10n.text(error), systemImage: "exclamationmark.triangle")
                    .font(AppFont.secondary).foregroundStyle(.red).textSelection(.enabled)
            }
            if displayedError != nil || items.contains(where: { $0.issue != nil }) {
                HStack {
                    Label(L10n.tr("部分位置无法读取"), systemImage: "folder.badge.questionmark")
                        .font(AppFont.secondary).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.tr("选择目录…")) { chooseDirectories() }
                }.disabled(busy)
            }
            Divider()
            if scanModel.selected.isEmpty && !available.isEmpty && !busy {
                Text(L10n.tr("请勾选要加入技能库的技能。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }
            HStack {
                if importing { ProgressView().controlSize(.small) }
                Text(L10n.tr("已选 \(scanModel.selected.count) 项")).font(AppFont.secondary).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.tr("取消")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
                Button(L10n.tr("加入技能库")) { collect() }
                    .buttonStyle(AppButtonStyle(kind: .primary))
                    .disabled(scanModel.selected.isEmpty || busy)
                    .accessibilityIdentifier("installed.scan.import")
            }
        }.appControls().padding(24).frame(width: 780, height: 620)
            .onAppear { scan() }
            .onDisappear { for url in authorizedURLs { url.stopAccessingSecurityScopedResource() } }
            .interactiveDismissDisabled(busy)
            .confirmationDialog(L10n.tr("删除原安装？"), isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible) {
                Button(L10n.tr("删除原安装"), role: .destructive) {
                    guard let item = deleting else { return }
                    deleting = nil
                    Task {
                        if await model.removeInstalledSkill(item) { scan() }
                    }
                }
            Button(L10n.tr("先不删"), role: .cancel) { deleting = nil }
            } message: {
                Text(L10n.tr("删除原来的 Claude Code 或 Codex 安装入口，技能库中的收录副本会保留。"))
            }
            .confirmationDialog(L10n.tr("删除所有已收录技能的原安装？"), isPresented: $deletingAll, titleVisibility: .visible) {
                Button(L10n.tr("删除原安装"), role: .destructive) {
                    deletingAll = false
                    Task {
                        if await model.removeInstalledSkills(collectedItems) { scan() }
                    }
                }
            Button(L10n.tr("先不删"), role: .cancel) { deletingAll = false }
            } message: {
                Text(L10n.tr("将删除 \(collectedItems.count) 个原安装入口，技能库中的收录副本会保留。"))
            }
    }

    private func skillRow(_ item: InstalledSkillObservation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(L10n.tr("选择技能"), isOn: Binding(get: { scanModel.selected.contains(item.id) }, set: {
                if $0 { scanModel.selected.insert(item.id) } else { scanModel.selected.remove(item.id) }
            }))
            .toggleStyle(AppCheckboxStyle(showsLabel: false)).disabled(!item.canImport || busy)
            .accessibilityLabel(URL(fileURLWithPath: item.path).lastPathComponent)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(URL(fileURLWithPath: item.path).lastPathComponent).font(AppFont.heading)
                    Spacer()
                    if item.issue != nil {
                        Label(L10n.tr("无法读取"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    } else if item.managed || item.collected {
                        Label(L10n.tr(item.managed ? "栖集管理" : "已收录"), systemImage: "checkmark.circle").foregroundStyle(.secondary)
                    }
                }
                DisclosureGroup(L10n.tr("位置与详情")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.path).textSelection(.enabled)
                        if item.resolvedPath != item.path { Text(item.resolvedPath).textSelection(.enabled) }
                        if let issue = item.issue { Text(L10n.text(issue)).foregroundStyle(.orange) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                }.font(AppFont.secondary).foregroundStyle(.secondary)
                if item.collected {
                    Button(role: .destructive) { deleting = item } label: {
                        Label(L10n.tr("删除原安装"), systemImage: "trash")
                    }
                    .buttonStyle(AppButtonStyle(kind: .quiet))
                    .disabled(busy)
                }
            }
        }.padding(14)
    }

    private func collect() {
        importing = true
        error = nil
        Task {
            if await model.importInstalledSkills(items.filter { scanModel.selected.contains($0.id) }) {
                showAll = true
                scan()
            } else {
                error = model.installedSkillImportError ?? "收录失败，请重新扫描后重试；原安装未改变。"
            }
            importing = false
        }
    }

    private func chooseDirectories() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.showsHiddenFiles = true
        panel.message = L10n.tr("选择技能目录，或软链接指向的原始目录。")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !roots.contains(url) {
            if url.startAccessingSecurityScopedResource() { authorizedURLs.append(url) }
            roots.append(url)
        }
        scan()
    }

    private func scan() {
        error = nil
        let paths = model.runtimePaths
        let locations = model.globalConfiguration.locations
        let scanRoots = roots
        Task {
            await scanModel.scan(paths: paths, locations: locations, roots: scanRoots)
        }
    }
}
