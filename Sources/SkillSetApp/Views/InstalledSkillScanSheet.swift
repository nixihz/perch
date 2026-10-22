import SwiftUI
import AppKit
import SkillSetCore

struct InstalledSkillScanSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [InstalledSkillObservation] = []
    @State private var selected: Set<String> = []
    @State private var roots: [URL] = []
    @State private var error: String?
    @State private var importing = false
    @State private var authorizedURLs: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("扫描已安装技能")).font(AppFont.title)
            Text(L10n.tr("扫描 Codex、Claude Code 的技能目录。收录会复制完整技能包到 ~/.perch，原安装保持原样；相同内容合并，原始路径全部保留。"))
                .foregroundStyle(.secondary)
            HStack {
                Button(L10n.tr("添加扫描目录…")) {
                    chooseDirectories()
                }
                Button(L10n.tr("重新扫描")) { scan() }
                Spacer()
                Button(L10n.tr("全选可收录项")) { selected = Set(items.filter(\.canImport).map(\.id)) }
            }.disabled(importing)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if items.isEmpty { Text(L10n.tr("未发现技能，可添加其他技能目录后重新扫描。")) }
                    ForEach(items) { item in
                        Toggle(isOn: Binding(get: { selected.contains(item.id) }, set: {
                            if $0 { selected.insert(item.id) } else { selected.remove(item.id) }
                        })) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(URL(fileURLWithPath: item.path).lastPathComponent).font(AppFont.heading)
                                Text(item.path).font(AppFont.secondary).textSelection(.enabled)
                                if item.resolvedPath != item.path {
                                    Text(item.resolvedPath).font(AppFont.secondary).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                                if let issue = item.issue { Text(L10n.text(issue)).foregroundStyle(.red) }
                                if item.collected && !item.managed { Text(L10n.tr("相同内容已在技能库中")).foregroundStyle(.secondary) }
                                if item.managed { Text(L10n.tr("栖集管理，无需重复收录")).foregroundStyle(.secondary) }
                            }
                        }.disabled(!item.canImport || importing)
                        Divider()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error { Text(L10n.text(error)).foregroundStyle(.red) }
            if error != nil || items.contains(where: { $0.issue != nil }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("无法访问目录？先点击「选择目录并授权…」，选择原技能目录；若技能是软链，还需选择链接指向的真实目录。"))
                    Text(L10n.tr("仍被 macOS 拒绝时：系统设置 → 隐私与安全性 → 文件与文件夹，允许栖集访问对应位置；若没有此项，可在「完全磁盘访问权限」中添加并开启栖集。按系统提示退出并重新打开应用后重试。写入 ~/.perch 失败时还需检查该目录的所有者与写入权限。"))
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(L10n.tr("选择目录并授权…")) { chooseDirectories() }
                        Button(L10n.tr("打开隐私设置")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }.disabled(importing)
                }.font(AppFont.secondary)
            }
            Text(L10n.tr("收录后，在技能库勾选技能并选择「启用到 AI 工具…」，可预览接管已有安装、备份与软链变更。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(L10n.tr("取消")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(importing)
                Button(L10n.tr("收录所选技能")) {
                    importing = true
                    Task {
                        if await model.importInstalledSkills(items.filter { selected.contains($0.id) }) { dismiss() }
                        else { error = model.installedSkillImportError ?? "收录失败，请重新扫描后重试；原安装未改变。" }
                        importing = false
                    }
                }.buttonStyle(AppButtonStyle(kind: .primary)).disabled(selected.isEmpty || importing)
            }
        }.appControls().padding(24).frame(width: 780, height: 680)
            .onAppear { scan() }
            .onDisappear {
                for url in authorizedURLs { url.stopAccessingSecurityScopedResource() }
            }
            .interactiveDismissDisabled(importing)
    }

    private func chooseDirectories() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.showsHiddenFiles = true
        panel.message = L10n.tr("选择允许栖集读取的技能目录；软链技能请选择其真实目录。")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if url.startAccessingSecurityScopedResource() { authorizedURLs.append(url) }
            roots.append(url)
        }
        scan()
    }

    private func scan() {
        do {
            items = try model.scanInstalledSkills(additionalRoots: roots)
            selected.formIntersection(items.filter(\.canImport).map(\.id))
            error = nil
        } catch { self.error = UserFacingText.error(error) }
    }
}
