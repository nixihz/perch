import AppKit
import SwiftUI
import SkillSetCore

/// 阅读状态只属于当前详情，切换技能或版本后默认回到正文。
struct SkillContentView: View {
    @Bindable var model: AppModel
    @State private var showsFiles = false
    @State private var showsSource = false
    private var canBrowseFiles: Bool { !model.selectedSkillFiles.isEmpty || model.skillFilesError != nil }

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                if model.isLoadingSkillDocument {
                    ProgressView(L10n.tr("正在读取技能…")).controlSize(.small)
                }
                if canBrowseFiles {
                    AppSegmentedPicker(title: L10n.tr("阅读内容"), selection: $showsFiles,
                        options: [(false, L10n.tr("正文")), (true, model.skillFilesError == nil ? L10n.tr("附属文件 · \(model.selectedSkillFiles.count)") : L10n.tr("附属文件"))])
                    .labelsHidden()
                    .accessibilityIdentifier("skills.content.tabs")
                    .onChange(of: showsFiles) { _, _ in model.closeSkillFile() }
                }
                if showsFiles && canBrowseFiles {
                    if let file = model.selectedSkillFile { filePreview(file) }
                    else { fileList }
                } else {
                    HStack {
                        Text("SKILL.md").font(AppFont.heading)
                        Spacer()
                        AppSegmentedPicker(title: L10n.tr("显示方式"), selection: $showsSource,
                            options: [(false, L10n.tr("预览")), (true, L10n.tr("原文"))])
                        .labelsHidden()
                        .fixedSize()
                        .accessibilityIdentifier("skills.content.format")
                    }
                    if !model.selectedSkillDocument.isEmpty {
                        if showsSource { document(model.selectedSkillDocument) }
                        else {
                            SkillMarkdownView(source: model.selectedSkillDocument)
                                .accessibilityIdentifier("skills.content.preview")
                        }
                    }
                    else if !model.isLoadingSkillDocument {
                        Text(L10n.tr("暂无可读取的正文，请核对来源文件。"))
                            .font(AppFont.secondary).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = model.skillFilesError {
                Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red)
                Button(L10n.tr("重新读取")) { Task { await model.loadSelectedSkillDocumentInBackground() } }
                    .padding(.top, 12)
            } else if model.selectedSkillFiles.isEmpty {
                Text(L10n.tr("这个技能没有附属文件，可在「SKILL.md」查看正文。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            } else {
                Text(L10n.tr("参考文档、脚本与资源，仅供查看。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary).padding(.bottom, 12)
                ForEach(model.selectedSkillFiles) { file in
                    Button { model.openSkillFile(file) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(AppFont.heading).foregroundStyle(AppColor.accentText)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(file.name).font(AppFont.body.weight(.medium))
                                    .foregroundStyle(.primary).lineLimit(2)
                                if !file.directory.isEmpty {
                                    Text(file.directory).font(AppFont.metadata.monospaced())
                                        .foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(L10n.byteCount(Int64(file.bytes)))
                                .font(AppFont.metadata).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(AppFont.metadata).foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 12).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(file.path)
                    .accessibilityLabel(file.path)
                    .accessibilityIdentifier("skills.file.\(file.path)")
                    Divider()
                }
            }
        }
    }

    private func filePreview(_ file: SkillPackageFile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { model.closeSkillFile() } label: {
                    Label(L10n.tr("附属文件"), systemImage: "chevron.left")
                        .frame(minHeight: 32)
                }
                .help(L10n.tr("附属文件"))
                .accessibilityIdentifier("skills.file.back")
                Spacer(minLength: 8)
                Button {
                    if let url = model.selectedSkillFileURL() {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } label: {
                    Label(L10n.tr("在 Finder 中显示"), systemImage: "folder")
                        .frame(minHeight: 32)
                }
                .help(L10n.tr("在 Finder 中显示"))
                .accessibilityIdentifier("skills.file.reveal")
            }
            Text(file.path).font(AppFont.code).foregroundStyle(.secondary).textSelection(.enabled)
            Divider()
            if let error = model.skillFilePreviewError {
                Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red)
                Button(L10n.tr("重新读取")) { model.openSkillFile(file) }
            } else {
                switch model.selectedSkillFilePreview {
                case let .text(text):
                    if text.isEmpty {
                        Text(L10n.tr("这个文件还没有内容。"))
                            .font(AppFont.secondary).foregroundStyle(.secondary)
                    } else { document(text) }
                case .tooLarge:
                    previewNotice("文件超过 2 MiB，请在 Finder 中查看。")
                case .unsupported:
                    previewNotice("这个格式暂不支持预览，请在 Finder 中查看。")
                case nil:
                    EmptyView()
                }
            }
        }
    }

    private func previewNotice(_ message: LocalizedText) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "doc").font(.system(size: 28)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(L10n.tr(message)).font(AppFont.body).foregroundStyle(.secondary)
            if let file = model.selectedSkillFile {
                Text(L10n.byteCount(Int64(file.bytes))).font(AppFont.metadata).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 20)
    }

    private func document(_ text: String) -> some View {
        Text(text).font(AppFont.code).lineSpacing(3).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("skills.content.document")
    }
}
