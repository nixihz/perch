import SwiftUI
import SkillSetCore

struct PluginScanSheet: View {
    @Bindable var model: AppModel
    let library: PluginSourceLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [PluginScanCandidate] = []
    @State private var selected: Set<String> = []
    @State private var issues: [String] = []
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("扫描本机插件")).font(AppFont.title.weight(.bold))
            Text(L10n.tr("只读扫描 Codex、Claude Code 缓存和已登记项目。勾选后复制完整包，保留原始安装位置；不会启用、卸载或运行插件。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            if busy { ProgressView().controlSize(.small) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(candidates) { candidate in
                        VStack(alignment: .leading, spacing: 7) {
                            Toggle(isOn: Binding(get: { selected.contains(candidate.id) }, set: {
                                if $0 { selected.insert(candidate.id) } else { selected.remove(candidate.id) }
                            })) {
                                Text(candidate.records[0].name).font(AppFont.body.weight(.semibold))
                            }.toggleStyle(.checkbox).disabled(!candidate.canImport)
                            ForEach(candidate.records) { record in
                                Text(record.host.displayName + " · " + L10n.text(UserFacingText.pluginState(record)))
                                    .font(AppFont.secondary).foregroundStyle(.secondary)
                                Text(record.sourcePath).font(AppFont.code).textSelection(.enabled)
                            }
                            if candidate.collected { Text(L10n.tr("已收录相同内容")).font(AppFont.secondary).foregroundStyle(.secondary) }
                            if let issue = candidate.issue { Text(L10n.text(issue)).font(AppFont.secondary).foregroundStyle(.orange) }
                            Divider()
                        }
                    }
                    if !busy && candidates.isEmpty { Text(L10n.tr("没有发现本机插件。也可在插件来源页添加本地目录或仓库。")) }
                    ForEach(issues, id: \.self) { issue in
                        Text(L10n.text(UserFacingText.diagnostic(issue, context: .plugin))).font(AppFont.secondary).foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(2)
            }
            if let error { Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red) }
            HStack {
                Button(L10n.tr("重新扫描")) { scan() }
                Spacer()
                Button(L10n.tr("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("收录所选插件")) { importSelection() }
                    .buttonStyle(AppButtonStyle(kind: .primary)).disabled(selected.isEmpty)
                    .accessibilityIdentifier("plugins.scan.import")
            }
        }
        .disabled(busy).interactiveDismissDisabled(busy).appControls().padding(26).frame(width: 780, height: 660)
        .task { scan() }
    }

    private func scan() {
        busy = true; error = nil
        let paths = model.runtimePaths
        let ids = model.projects.compactMap { UUID(uuidString: $0.id) }
        Task {
            do {
                let result = try await Task.detached {
                    let service = try SkillSetService(paths: paths)
                    let snapshots = try ([nil] + ids.map(Optional.some)).map { try service.plugins(projectID: $0) }
                    return (try library.scan(records: snapshots.flatMap(\.records)), Array(Set(snapshots.flatMap(\.issues))).sorted())
                }.value
                candidates = result.0; issues = result.1
                selected.formIntersection(candidates.filter(\.canImport).map(\.id))
            } catch { self.error = UserFacingText.error(error) }
            busy = false
        }
    }

    private func importSelection() {
        busy = true; error = nil
        let selection = candidates.filter { selected.contains($0.id) }
        Task {
            // 逐项完成，失败保留剩余选择；不重复收录已经成功的条目。
            for candidate in selection {
                do {
                    _ = try await Task.detached { try library.importCandidate(candidate) }.value
                    selected.remove(candidate.id)
                } catch {
                    self.error = UserFacingText.error(error)
                    busy = false
                    return
                }
            }
            busy = false
            dismiss()
        }
    }
}
