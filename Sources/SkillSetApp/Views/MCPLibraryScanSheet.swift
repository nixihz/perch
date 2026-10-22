import SwiftUI
import SkillSetCore

struct MCPLibraryScanSheet: View {
    @Bindable var library: MCPLibraryModel
    @State private var selected: Set<String> = []
    @State private var imported = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr(imported ? "已加入 MCP 配置库" : "扫描已有 MCP 配置")).font(AppFont.title.weight(.bold))
            Text(L10n.tr(imported
                ? "连接配置已保存在本机。下一步在配置库选择使用范围，再预览并批准写入。"
                : "扫描 Codex、Claude Code 的全局配置和已登记项目。只提取命令、参数、地址和环境变量名称；凭据值及其他扩展配置不会复制。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            if imported {
                importResult
            } else {
                HStack {
                    Text(L10n.tr("发现 \(library.candidates.count) 项 · 可选 \(library.availableCandidates.count) 项 · 已选 \(selected.count) 项"))
                        .font(AppFont.secondary).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.tr("选择无重名项")) { selected.formUnion(library.unambiguousCandidateIDs) }
                        .disabled(library.unambiguousCandidateIDs.isEmpty)
                    Button(L10n.tr("清空选择")) { selected = [] }.disabled(selected.isEmpty)
                }
                candidateList
                Text(L10n.tr("同名候选只保留一个选择；批量选择会跳过同名项，请逐项核对来源。入库不会修改原配置。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }
            if let error = library.error { Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red) }
            HStack {
                if !imported {
                    Button(L10n.tr("重新扫描")) { selected = []; library.scan() }
                }
                Spacer()
                if imported {
                    Button(L10n.tr("在配置库查看")) { dismiss() }
                        .buttonStyle(AppButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
                } else {
                    Button(L10n.tr("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(L10n.tr("将所选服务入库")) { imported = library.importCandidates(selected) }
                        .buttonStyle(AppButtonStyle(kind: .primary)).disabled(selected.isEmpty)
                        .accessibilityIdentifier("mcp.library.import")
                }
            }
        }.appControls().padding(26).frame(width: 720, height: 650)
    }

    private var candidateList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if library.candidates.isEmpty {
                    Text(L10n.tr("没有发现可扫描的 MCP 配置。可先手动添加服务，或登记包含 MCP 配置的项目。"))
                        .font(AppFont.secondary).foregroundStyle(.secondary)
                }
                ForEach(library.candidates) { candidate in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle(isOn: Binding(get: { selected.contains(candidate.id) }, set: { value in
                                selected = library.updatingScanSelection(selected, candidateID: candidate.id, enabled: value)
                            })) { Text(candidate.name).font(AppFont.body.weight(.semibold)) }
                            .toggleStyle(.checkbox).disabled(candidate.entry == nil || library.duplicate(candidate))
                            Spacer()
                            StatusBadge(text: L10n.tr(library.duplicate(candidate) ? "已在配置库" : candidate.entry == nil ? "不可入库" : "可入库"),
                                tone: candidate.entry == nil ? .warning : .neutral)
                        }
                        Text(candidate.source).font(AppFont.metadata).foregroundStyle(.secondary)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        if let issue = candidate.issue { Text(L10n.text(issue)).font(AppFont.secondary).foregroundStyle(.orange) }
                        if library.duplicate(candidate) {
                            Text(L10n.tr("配置库已有同名服务，保留现有配置。"))
                                .font(AppFont.secondary).foregroundStyle(.secondary)
                        }
                        if let entry = candidate.entry {
                            Text(entry.transport + " · " + entry.commandOrURL).font(AppFont.code).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            if !entry.args.isEmpty || !entry.envKeys.isEmpty {
                                Text(L10n.tr("\(entry.args.count) 个参数 · \(entry.envKeys.count) 个环境变量"))
                                    .font(AppFont.metadata).foregroundStyle(.secondary)
                            }
                            DisclosureGroup(L10n.tr("查看连接详情")) { MCPConnectionFields(entry: entry) }
                                .font(AppFont.secondary)
                        }
                    }
                    Divider()
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var importResult: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label(L10n.tr("已入库 \(library.lastImportedIDs.count) 个服务"), systemImage: "checkmark.circle")
                    .foregroundStyle(AppColor.positive).font(AppFont.heading)
                ForEach(library.entries.filter { library.lastImportedIDs.contains($0.id) }) { entry in
                    HStack {
                        Text(entry.name).font(AppFont.body.weight(.semibold))
                        Spacer()
                        StatusBadge(text: entry.transport, tone: .neutral)
                    }
                }
                Divider()
                Text(L10n.tr("原配置保持不变。入库不代表已在新的项目或全局范围使用。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("mcp.library.importResult")
    }
}
