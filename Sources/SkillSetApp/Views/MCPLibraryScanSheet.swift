import SwiftUI
import SkillSetCore

struct MCPLibraryScanSheet: View {
    @Bindable var library: MCPLibraryModel
    @State private var selected: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("扫描已有 MCP 配置")).font(AppFont.title.weight(.bold))
            Text(L10n.tr("扫描 Codex、Claude Code 的全局配置和已登记项目。只提取命令、参数、地址和环境变量名称；凭据值及其他扩展配置不会复制。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if library.candidates.isEmpty {
                        Text(L10n.tr("没有发现可扫描的 MCP 配置。可先手动添加服务，或登记包含 MCP 配置的项目。"))
                            .font(AppFont.secondary).foregroundStyle(.secondary)
                    }
                    ForEach(library.candidates) { candidate in
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: Binding(get: { selected.contains(candidate.id) }, set: { value in
                                if value { selected.insert(candidate.id) } else { selected.remove(candidate.id) }
                            })) { Text(candidate.name).font(AppFont.body.weight(.semibold)) }
                            .toggleStyle(.checkbox).disabled(candidate.entry == nil || library.duplicate(candidate))
                            Text(candidate.source).font(AppFont.metadata).foregroundStyle(.secondary)
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            if let issue = candidate.issue { Text(L10n.text(issue)).font(AppFont.secondary).foregroundStyle(.orange) }
                            if library.duplicate(candidate) {
                                Text(L10n.tr("配置库已有同名服务，保留现有配置。"))
                                    .font(AppFont.secondary).foregroundStyle(.orange)
                            }
                            if let entry = candidate.entry {
                                Text(entry.commandOrURL).font(AppFont.code).textSelection(.enabled)
                                if !entry.args.isEmpty {
                                    Text(entry.args.joined(separator: "\n")).font(AppFont.code).textSelection(.enabled)
                                }
                                if !entry.envKeys.isEmpty {
                                    Text(L10n.tr("环境变量引用：\(entry.envKeys.joined(separator: "、"))（只保存名称）"))
                                        .font(AppFont.secondary).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Divider()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = library.error { Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red) }
            Text(L10n.tr("入库不会改动原配置或自动启用服务。同名候选每次只选择一个。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            HStack {
                Button(L10n.tr("重新扫描")) { selected = []; library.scan() }
                Spacer()
                Button(L10n.tr("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("将所选服务入库")) { if library.importCandidates(selected) { dismiss() } }
                    .buttonStyle(AppButtonStyle(kind: .primary)).disabled(selected.isEmpty)
                    .accessibilityIdentifier("mcp.library.import")
            }
        }.appControls().padding(26).frame(width: 720, height: 650)
    }
}
