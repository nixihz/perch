import SwiftUI
import SkillSetCore

struct MCPLibraryEditorSheet: View {
    @Bindable var library: MCPLibraryModel
    @State var entry: MCPLibraryEntry
    var onSaved: (MCPLibraryEntry) -> Void = { _ in }
    @State private var validation: [String] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("MCP 服务配置")).font(AppFont.title)
            Text(L10n.tr("只保存到本机配置库。AI 工具和使用范围在全局配置或项目中选择。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    AppFormField(L10n.tr("名称")) {
                        TextField("my-server", text: $entry.name)
                            .accessibilityLabel(L10n.tr("名称"))
                            .accessibilityIdentifier("mcp.library.name")
                    }
                    AppPicker(title: L10n.tr("连接方式"), selection: $entry.transport, valueLabel: entry.transport) {
                        Text("stdio").tag("stdio")
                        Text("streamable-http").tag("streamable-http")
                    }
                    AppFormField(entry.transport == "stdio" ? L10n.tr("启动命令") : "URL") {
                        TextField(entry.transport == "stdio" ? "/path/to/server" : "https://example.com/mcp", text: $entry.commandOrURL)
                            .accessibilityLabel(entry.transport == "stdio" ? L10n.tr("启动命令") : "URL")
                            .accessibilityIdentifier("mcp.library.command")
                    }
                    if entry.transport == "stdio" {
                        AppFormField(L10n.tr("启动参数（每行一项，保留项内空格）")) {
                            TextField("--option", text: Binding(get: { entry.args.joined(separator: "\n") },
                                set: { entry.args = $0.components(separatedBy: "\n").filter { !$0.isEmpty } }), axis: .vertical)
                                .accessibilityLabel(L10n.tr("启动参数（每行一项，保留项内空格）"))
                        }
                    }
                    AppFormField(L10n.tr("环境变量名称（逗号分隔）")) {
                        TextField("API_TOKEN", text: Binding(get: { entry.envKeys.joined(separator: ", ") },
                            set: { entry.envKeys = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }))
                            .accessibilityLabel(L10n.tr("环境变量名称（逗号分隔）"))
                    }
                }
            }
            ForEach(validation, id: \.self) { Text(L10n.text($0)).font(AppFont.secondary).foregroundStyle(.red) }
            if let error = library.error { Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(L10n.tr("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("保存到配置库")) {
                    validation = entry.draft(host: .codex, scope: .user).validationIssues()
                    if validation.isEmpty, library.save(entry) {
                        onSaved(library.entries.first { $0.id == entry.id } ?? entry)
                        dismiss()
                    }
                }
                .buttonStyle(AppButtonStyle(kind: .primary)).keyboardShortcut("s", modifiers: .command)
                .accessibilityIdentifier("mcp.library.save")
            }
        }.appControls().padding(26).frame(width: 600, height: 570)
    }
}
