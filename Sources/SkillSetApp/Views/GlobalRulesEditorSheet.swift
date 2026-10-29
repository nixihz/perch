import SwiftUI
import SkillSetCore

/// 直接编辑宿主的全局规则文件；规则片段的组合与部署仍由全局配置草稿管理。
struct GlobalRulesEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let host: MCPHost
    let locations: GlobalConfigurationLocations

    @State private var text = ""
    @State private var originalText = ""
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var isLoading = true
    @State private var confirmDiscard = false

    private var fileURL: URL { locations.rulesURL(host) }
    private var fileName: String { fileURL.lastPathComponent }
    private var hasChanges: Bool { text != originalText }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.tr("编辑 \(host.displayName) 规则")).font(AppFont.title)
                Spacer()
                Text(fileName).font(AppFont.metadata.monospaced()).foregroundStyle(.secondary)
            }
            Text(L10n.tr("纯文本编辑宿主规则文件；保存后由 \(host.displayName) 在下一次读取时加载。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            Text(fileURL.path)
                .font(AppFont.code).foregroundStyle(.secondary)
                .textSelection(.enabled)
                .accessibilityIdentifier("global.rules.path")

            if isLoading {
                ProgressView(L10n.tr("正在读取规则文件…")).controlSize(.small)
            } else if let loadError {
                Text(L10n.text(loadError)).font(AppFont.secondary).foregroundStyle(.red)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("global.rules.loadError")
            } else {
                TextEditor(text: $text)
                    .font(AppFont.body.monospaced())
                    .appEditorSurface()
                    .accessibilityLabel(L10n.tr("规则文件正文"))
                    .accessibilityIdentifier("global.rules.editor")
            }

            if let saveError {
                Text(L10n.text(saveError)).font(AppFont.secondary).foregroundStyle(.red)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("global.rules.saveError")
            }

            HStack {
                Button(L10n.tr("取消")) { cancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.tr("保存规则")) { save() }
                    .buttonStyle(AppButtonStyle(kind: .primary))
                    .keyboardShortcut("s", modifiers: [.command])
                    .disabled(isLoading || loadError != nil)
                    .accessibilityIdentifier("global.rules.save")
            }
        }
        .appControls()
        .padding(24)
        .frame(minWidth: 700, idealWidth: 820, minHeight: 540, idealHeight: 640)
        .interactiveDismissDisabled(hasChanges)
        .task { load() }
        .confirmationDialog(L10n.tr("放弃未保存的修改？"), isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(L10n.tr("放弃修改"), role: .destructive) { dismiss() }
            Button(L10n.tr("继续编辑"), role: .cancel) {}
        }
    }

    private func load() {
        guard isLoading else { return }
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                text = try String(contentsOf: fileURL, encoding: .utf8)
            }
            originalText = text
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            originalText = text
            saveError = nil
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func cancel() {
        if hasChanges { confirmDiscard = true }
        else { dismiss() }
    }
}
