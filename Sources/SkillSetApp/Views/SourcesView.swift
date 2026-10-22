import AppKit
import SwiftUI
import SkillSetCore

struct SourcesView: View {
    @Bindable var model: AppModel
    @State private var editor: SourceEditorDraft?
    @State private var deletingPreview: SourcePreviewRecord?
    @State private var importingSkill: SourceSkillImportDraft?
    @State private var browsingSkillsSh = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                eyebrow: "SOURCE REGISTRY",
                title: L10n.tr("技能来源"),
                detail: L10n.tr("配置来源后同步到 ~/.perch，全部技能可在技能库搜索；也可浏览 skills.sh 目录，将技能安装到本机技能库。")
            )

            if let error = model.sourceImportError, importingSkill == nil {
                Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red)
            }

            HStack(alignment: .top, spacing: AppLayout.columnSpacing) {
                sourceList
                    .frame(width: AppLayout.listWidth)
                sourceDetail
            }
        }
        .sheet(item: $editor) { draft in
            SourceEditorSheet(model: model, draft: draft)
        }
        .sheet(item: $importingSkill) { draft in
            SourceSkillImportSheet(model: model, initialDraft: draft)
        }
        .sheet(isPresented: $browsingSkillsSh) {
            SkillsShBrowserSheet(model: model)
        }
        .confirmationDialog(
            L10n.tr("删除这个技能来源？"),
            isPresented: Binding(
                get: { deletingPreview != nil },
                set: { if !$0 { deletingPreview = nil } }
            ),
            titleVisibility: .visible,
            presenting: deletingPreview
        ) { preview in
            Button(L10n.tr("删除来源"), role: .destructive) {
                model.removeSourcePreview(preview.id)
                deletingPreview = nil
            }
            Button(L10n.tr("取消"), role: .cancel) { deletingPreview = nil }
        } message: { preview in
            Text(L10n.tr("将删除 \(preview.canonicalURL) 的来源配置、下载缓存和搜索条目。已部署的技能版本和项目配置保留。"))
        }
        .task {
            model.refreshSourcePreviews()
        }
    }

    private var sourceList: some View {
        SurfaceCard {
            HStack {
                Text(L10n.tr("技能来源"))
                    .font(AppFont.heading)
                Spacer()
                Button {
                    browsingSkillsSh = true
                } label: {
                    Label("skills.sh", systemImage: "sparkle.magnifyingglass")
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AppButtonStyle(kind: .quiet))
                .help(L10n.tr("浏览 skills.sh"))
                .accessibilityLabel(L10n.tr("浏览 skills.sh"))
                .accessibilityIdentifier("sources.skillsSh.browse")
                .disabled(model.isWorking)
                Button {
                    editor = SourceEditorDraft()
                } label: {
                    Label(L10n.tr("添加技能来源"), systemImage: "plus")
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AppButtonStyle(kind: .quiet))
                .help(L10n.tr("添加技能来源"))
                .accessibilityLabel(L10n.tr("添加技能来源"))
                .accessibilityIdentifier("sources.add")
                .disabled(model.isWorking)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L10n.tr("已配置来源"))
                            .font(AppFont.secondary.weight(.semibold))
                        Spacer()
                        Text("\(model.sourcePreviews.count)")
                            .font(AppFont.secondary.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if model.sourcePreviews.isEmpty {
                        Text(L10n.tr("还没有技能来源。点「添加技能来源」同步仓库或本地目录。"))
                            .font(AppFont.secondary)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.sourcePreviews) { preview in
                            Button {
                                model.selectedPreviewID = preview.id
                            } label: {
                                HStack(alignment: .top, spacing: 9) {
                                    Image(systemName: preview.id == model.selectedPreviewID ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(preview.id == model.selectedPreviewID ? AppColor.accentText : .secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(repositoryName(preview.canonicalURL))
                                            .font(AppFont.body.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(L10n.tr("\(preview.resolvedCommit.prefix(12)) · \(preview.candidates.count) 个技能"))
                                            .font(AppFont.metadata.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .selectionRow(preview.id == model.selectedPreviewID)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("sources.preview.\(preview.id.uuidString)")
                            .contextMenu {
                                previewActions(preview)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 620)
        }
    }

    @ViewBuilder
    private var sourceDetail: some View {
        if let preview = model.selectedSourcePreview {
            sourcePreviewDetail(preview)
        } else {
            EmptyState(icon: "arrow.down.doc", title: L10n.tr("选择一个来源"), detail: L10n.tr("选择左侧来源，查看路径、版本和许可审查状态。"))
        }
    }

    private func sourcePreviewDetail(_ preview: SourcePreviewRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SurfaceCard(emphasis: true) {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preview.canonicalURL)
                                    .font(AppFont.title.weight(.bold))
                                    .textSelection(.enabled)
                                Text(L10n.tr("固定于 \(preview.resolvedCommit.prefix(16))…"))
                                    .font(AppFont.secondary.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            StatusBadge(text: L10n.tr("已配置来源"), tone: .neutral)
                        }
                        Divider()
                        KeyValueLine(key: L10n.tr("来源标识"), value: preview.namespace, monospaced: true)
                        KeyValueLine(key: L10n.tr("完整版本标识"), value: preview.resolvedCommit, monospaced: true)
                        KeyValueLine(key: L10n.tr("许可线索"), value: L10n.text(UserFacingText.licenseEvidence(preview.licenseEvidence)))
                        KeyValueLine(
                            key: L10n.tr("创建时间"),
                            value: L10n.date(preview.createdAt)
                        )
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([
                                    URL(fileURLWithPath: preview.workspacePath, isDirectory: true)
                                ])
                            } label: {
                                Text(L10n.tr("在 Finder 中显示预览文件"))
                                    .frame(minHeight: 32)
                            }
                            .buttonStyle(AppButtonStyle())
                            .accessibilityIdentifier("sources.preview.reveal")
                            HStack {
                                Button {
                                    editor = SourceEditorDraft(preview: preview)
                                } label: {
                                    Label(L10n.tr("编辑来源"), systemImage: "pencil")
                                        .frame(minHeight: 32)
                                }
                                .disabled(model.isWorking)
                                .accessibilityIdentifier("sources.preview.edit")
                                Spacer(minLength: 8)
                                Menu {
                                    deletePreviewAction(preview)
                                } label: {
                                    Label(L10n.tr("更多操作"), systemImage: "ellipsis")
                                        .frame(minHeight: 32)
                                        .padding(.horizontal, 8)
                                        .contentShape(Rectangle())
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                .help(L10n.tr("更多操作"))
                                .accessibilityLabel(L10n.tr("更多操作"))
                                .accessibilityIdentifier("sources.preview.more")
                                .disabled(model.isWorking)
                            }
                        }
                        Text(L10n.tr("同步完成的技能已在技能库中，可到项目页选择并预览变更。"))
                            .font(AppFont.secondary)
                            .foregroundStyle(.secondary)
                    }
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L10n.tr("文件夹"))
                                .font(AppFont.heading)
                            Spacer()
                            Text(L10n.tr("\(preview.candidates.count) 个 SKILL.md"))
                                .font(AppFont.secondary)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(
                            Dictionary(grouping: preview.candidates) { candidate in
                                let folder = (candidate.path as NSString).deletingLastPathComponent
                                return folder.isEmpty ? "." : folder
                            }.sorted(by: { $0.key < $1.key }),
                            id: \.key
                        ) { folder, candidates in
                            HStack {
                                Text(verbatim: folder)
                                    .font(AppFont.secondary.monospaced())
                                    .textSelection(.enabled)
                                Spacer()
                                Text("\(candidates.count)")
                                    .font(AppFont.secondary.monospaced())
                            }
                        }
                        ForEach(preview.warnings, id: \.self) { warning in
                            Text(L10n.text(UserFacingText.diagnostic(warning, context: .source)))
                                .font(AppFont.secondary)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.tr("发现的技能"))
                            .font(AppFont.heading)
                        if preview.candidates.isEmpty {
                            EmptyState(
                                icon: "doc.questionmark",
                                title: L10n.tr("没有找到 SKILL.md"),
                                detail: L10n.tr("请检查仓库链接、分支或标签，再重新预览。技能库未改变。")
                            )
                            .frame(minHeight: 180)
                        } else {
                            ForEach(preview.candidates.sorted { $0.path < $1.path }, id: \.path) { candidate in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(candidate.declaredName)
                                            .font(AppFont.body.weight(.semibold))
                                        Text(candidate.id)
                                            .font(AppFont.metadata.monospaced())
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        if let id = model.importedSkillID(preview: preview, candidate: candidate) {
                                            Button(L10n.tr("在技能库查看")) { model.showLibrarySkill(id) }
                                                .accessibilityIdentifier("sources.view.\(candidate.path)")
                                        } else {
                                            Button(L10n.tr("加入技能库…")) {
                                                Task {
                                                    importingSkill = await model.prepareSourceSkillImport(previewID: preview.id, path: candidate.path)
                                                }
                                            }
                                            .disabled(model.isWorking || !candidate.issues.isEmpty || candidate.contentHash.isEmpty)
                                            .accessibilityIdentifier("sources.import.\(candidate.path)")
                                        }
                                    }
                                    Text(candidate.path)
                                        .font(AppFont.secondary.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                    if !candidate.description.isEmpty {
                                        Text(candidate.description)
                                            .font(AppFont.secondary)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                    }
                                    HStack {
                                        Text(candidate.contentHash.isEmpty ? L10n.tr("无内容指纹") : String(candidate.contentHash.prefix(16)) + "…")
                                            .font(AppFont.metadata.monospaced())
                                        Text(L10n.tr("· \(candidate.fileCount) 文件 · \(candidate.bytes) 字节"))
                                            .font(AppFont.metadata)
                                        Spacer()
                                    }
                                    .foregroundStyle(.secondary)
                                    ForEach(candidate.issues, id: \.self) { issue in
                                        Text(L10n.text(UserFacingText.diagnostic(issue, context: .candidate)))
                                            .font(AppFont.secondary)
                                            .foregroundStyle(.red)
                                    }
                                }
                                .padding(11)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                            }
                        }
                    }
                }
            }
        }
    }

    private func repositoryName(_ url: String) -> String {
        guard let components = URLComponents(string: url) else { return url }
        return components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    @ViewBuilder
    private func previewActions(_ preview: SourcePreviewRecord) -> some View {
        Button(L10n.tr("同步来源")) {
            Task { _ = await model.previewSource(urlString: preview.canonicalURL, ref: preview.requestedRef, replacing: preview.id) }
        }.disabled(model.isWorking)
        Button {
            editor = SourceEditorDraft(preview: preview)
        } label: {
            Label(L10n.tr("编辑来源"), systemImage: "pencil")
        }
        .disabled(model.isWorking)
        deletePreviewAction(preview)
    }

    private func deletePreviewAction(_ preview: SourcePreviewRecord) -> some View {
        Button(role: .destructive) {
            deletingPreview = preview
        } label: {
            Label(L10n.tr("删除来源"), systemImage: "trash")
        }
        .disabled(model.isWorking)
        .accessibilityIdentifier("sources.preview.delete")
    }

}

struct SourceEditorDraft: Identifiable {
    let id = UUID()
    var replacingID: UUID?
    var url = ""
    var ref = ""

    init() {}

    init(preview: SourcePreviewRecord) {
        replacingID = preview.id
        url = preview.canonicalURL
        ref = preview.canonicalURL.hasPrefix("/") ? "" : (preview.requestedRef ?? preview.resolvedCommit)
    }
}

struct SourceEditorSheet: View {
    @Bindable var model: AppModel
    @State var draft: SourceEditorDraft
    @State private var failure: LocalizedText?
    @FocusState private var urlFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(draft.replacingID == nil ? L10n.tr("添加技能来源") : L10n.tr("编辑技能来源"))
                .font(AppFont.title)
            Text(draft.replacingID == nil
                ? L10n.tr("填写 Git 仓库链接或本地目录，同步后即可在技能库搜索。")
                : L10n.tr("修改链接或版本后重新预览，成功后替换原记录；失败时保留原预览。"))
                .font(AppFont.body)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("Git 仓库链接或本地目录"))
                    .font(AppFont.secondary.weight(.semibold))
                TextField("https://git.example.com/group/repo 或 owner/repo", text: $draft.url)
                    .textFieldStyle(AppTextFieldStyle())
                    .accessibilityLabel(L10n.tr("Git 仓库链接或本地目录"))
                    .focused($urlFocused)
                Text(L10n.tr("分支、标签或提交（可选）"))
                    .font(AppFont.secondary.weight(.semibold))
                    .padding(.top, 8)
                TextField(L10n.tr("留空使用默认分支"), text: $draft.ref)
                    .textFieldStyle(AppTextFieldStyle())
                    .accessibilityLabel(L10n.tr("分支、标签或提交（可选）"))
            }
            .disabled(model.isWorking)
            Label(L10n.tr("预览不会运行脚本或把技能加入项目。私有仓库需先通过系统 Git 登录。"), systemImage: "lock.shield")
                .font(AppFont.secondary)
                .foregroundStyle(.secondary)
            if let failure {
                Label(L10n.tr(failure), systemImage: "exclamationmark.circle")
                    .font(AppFont.secondary)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            HStack(spacing: 12) {
                if model.isWorking {
                    ProgressView().controlSize(.small)
                    Text(L10n.tr("正在下载并扫描技能，不会修改项目。"))
                        .font(AppFont.secondary)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.tr("取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isWorking)
                Button(draft.replacingID == nil ? L10n.tr("同步来源") : L10n.tr("保存并同步")) {
                    failure = nil
                    Task {
                        if await model.previewSource(urlString: draft.url, ref: draft.ref, replacing: draft.replacingID) {
                            dismiss()
                        } else {
                            failure = model.actionMessage
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(AppButtonStyle(kind: .primary))
                .tint(AppColor.accent)
                .disabled(model.isWorking || draft.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .appControls()
        .padding(26)
        .frame(width: 560)
        .interactiveDismissDisabled(model.isWorking)
        .onAppear { urlFocused = true }
    }
}
