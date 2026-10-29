import AppKit
import SwiftUI
import SkillSetCore

struct SourcesView: View {
    @Bindable var model: AppModel
    @State private var editor: SourceEditorDraft?
    @State private var deletingPreview: SourcePreviewRecord?
    @State private var importingSkill: SourceSkillImportDraft?
    @State private var browsingSkillsSh = false
    @State private var checkedCandidatePaths: Set<String> = []
    @State private var batchDraft: SourceSkillBatchDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageActionHeader(
                eyebrow: "SOURCE REGISTRY",
                title: L10n.tr("技能来源"),
                detail: L10n.tr("添加仓库或本地目录，同步后可在技能库搜索；也可从 skills.sh 选择技能加入。")
            ) {
                Button {
                    browsingSkillsSh = true
                } label: {
                    Label("skills.sh", systemImage: "sparkle.magnifyingglass")
                        .frame(minHeight: AppControl.height)
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
                        .frame(minHeight: AppControl.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AppButtonStyle(kind: .primary))
                .help(L10n.tr("添加技能来源"))
                .accessibilityLabel(L10n.tr("添加技能来源"))
                .accessibilityIdentifier("sources.add")
                .disabled(model.isWorking)
            }

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
        .sheet(item: $batchDraft) { draft in
            SourceSkillBatchImportSheet(model: model, draft: draft) {
                checkedCandidatePaths.subtract(draft.items.map(\.path))
            }
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
            Button(L10n.tr("先不删"), role: .cancel) { deletingPreview = nil }
        } message: { preview in
            Text(L10n.tr("将删除 \(preview.canonicalURL) 的来源配置、下载缓存和搜索条目。已部署的技能版本和项目配置保留。"))
        }
        .task {
            await model.reloadSourcePreviews()
        }
        .onChange(of: model.selectedPreviewID) { _, _ in
            // 换来源后旧勾选不再对应当前列表。
            checkedCandidatePaths.removeAll()
        }
    }

    private var sourceList: some View {
        SurfaceCard {
            HStack {
                Text(L10n.tr("技能来源"))
                    .font(AppFont.heading)
                Spacer()
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
                                        Text(model.sourceListTitle(preview))
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
                            .buttonStyle(AppPressButtonStyle())
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
            EmptyState(icon: "arrow.down.doc", title: L10n.tr("选择一个来源"), detail: L10n.tr("选择左侧来源，查看技能、路径和版本。"))
        }
    }

    private func sourcePreviewDetail(_ preview: SourcePreviewRecord) -> some View {
        let folders = model.sourceFolders(for: preview)
        let candidates = model.sourceCandidates(for: preview)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                SurfaceCard(emphasis: true) {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preview.canonicalURL)
                                    .font(AppFont.title)
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
                                    .frame(minHeight: AppControl.height)
                            }
                            .buttonStyle(AppButtonStyle())
                            .accessibilityIdentifier("sources.preview.reveal")
                            HStack {
                                Button {
                                    editor = SourceEditorDraft(preview: preview)
                                } label: {
                                    Label(L10n.tr("编辑来源"), systemImage: "pencil")
                                        .frame(minHeight: AppControl.height)
                                }
                                .disabled(model.isWorking)
                                .accessibilityIdentifier("sources.preview.edit")
                                Spacer(minLength: 8)
                                Menu {
                                    deletePreviewAction(preview)
                                } label: {
                                    Label(L10n.tr("更多操作"), systemImage: "ellipsis")
                                        .frame(minHeight: AppControl.height)
                                        .padding(.horizontal, 8)
                                        .contentShape(Rectangle())
                                }
                                .menuStyle(.button)
                                .buttonStyle(AppButtonStyle(kind: .quiet))
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
                        ForEach(folders, id: \.0) { folder, count in
                            HStack {
                                Text(verbatim: folder)
                                    .font(AppFont.secondary.monospaced())
                                    .textSelection(.enabled)
                                Spacer()
                                Text("\(count)")
                                    .font(AppFont.secondary.monospaced())
                            }
                        }
                        ForEach(preview.warnings.filter { $0 != "内容指纹与许可提示不等于安全、合规或模型行为审核。" }, id: \.self) { warning in
                            Text(L10n.text(UserFacingText.diagnostic(warning, context: .source)))
                                .font(AppFont.secondary)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.tr("发现的技能"))
                        .font(AppFont.heading)
                    batchControls(preview: preview, candidates: candidates)
                    if candidates.isEmpty {
                        EmptyState(
                            icon: "doc.questionmark",
                            title: L10n.tr("没有找到 SKILL.md"),
                            detail: L10n.tr("请检查仓库链接、分支或标签，再重新预览。技能库未改变。")
                        )
                        .frame(minHeight: 180)
                    }
                }
                ForEach(candidates, id: \.path) { candidate in
                    candidateRow(preview: preview, candidate: candidate)
                }
            }
        }
    }

    /// 未导入且内容完整的候选才能勾选；有完整性问题或没有指纹的条目保持单项导入的禁用状态。
    private func isSelectable(preview: SourcePreviewRecord, candidate: SourceSkillCandidate) -> Bool {
        model.importedSkillID(preview: preview, candidate: candidate) == nil
            && candidate.issues.isEmpty && !candidate.contentHash.isEmpty
    }

    private func candidateRow(preview: SourcePreviewRecord, candidate: SourceSkillCandidate) -> some View {
        let imported = model.importedSkillID(preview: preview, candidate: candidate)
        let selectable = isSelectable(preview: preview, candidate: candidate)
        return HStack(alignment: .top, spacing: 10) {
            if selectable {
                Toggle(isOn: Binding(
                    get: { checkedCandidatePaths.contains(candidate.path) },
                    set: { checked in
                        if checked { checkedCandidatePaths.insert(candidate.path) }
                        else { checkedCandidatePaths.remove(candidate.path) }
                    }
                )) {
                    Text(L10n.tr("勾选技能") + " " + candidate.declaredName)
                }
                .toggleStyle(AppCheckboxStyle(showsLabel: false))
                .accessibilityIdentifier("sources.check.\(candidate.path)")
                .padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(candidate.declaredName)
                        .font(AppFont.body.weight(.semibold))
                    Spacer()
                    if let id = imported {
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
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }

    /// 批量入口：勾选后一次加入。已在技能库里的技能不参与勾选。
    @ViewBuilder
    private func batchControls(preview: SourcePreviewRecord, candidates: [SourceSkillCandidate]) -> some View {
        let selectable = candidates.filter { isSelectable(preview: preview, candidate: $0) }
        if !selectable.isEmpty {
            // 计数与操作分开两行；窄栏下按钮换行，文字不被压缩也不被裁掉。
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    StatusBadge(text: L10n.tr("可加入 \(selectable.count) 个"), tone: .accent)
                        .fixedSize(horizontal: true, vertical: false)
                    StatusBadge(text: L10n.tr("已选 \(checkedCandidatePaths.count) 个"), tone: checkedCandidatePaths.isEmpty ? .neutral : .positive)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        selectAllButton(selectable: selectable)
                        clearSelectionButton
                        importSelectedButton(preview: preview, candidates: candidates)
                    }
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(spacing: 10) {
                            selectAllButton(selectable: selectable)
                            clearSelectionButton
                        }
                        importSelectedButton(preview: preview, candidates: candidates)
                    }
                }
            }
        }
    }

    private func selectAllButton(selectable: [SourceSkillCandidate]) -> some View {
        Button(L10n.tr("全选")) {
            checkedCandidatePaths = Set(selectable.map(\.path))
        }
        .disabled(checkedCandidatePaths.count == selectable.count)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var clearSelectionButton: some View {
        Button(L10n.tr("清空勾选")) { checkedCandidatePaths.removeAll() }
            .disabled(checkedCandidatePaths.isEmpty)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func importSelectedButton(preview: SourcePreviewRecord, candidates: [SourceSkillCandidate]) -> some View {
        Button(L10n.tr("加入所选技能（\(checkedCandidatePaths.count)）")) {
            openBatch(preview: preview, candidates: candidates)
        }
        .buttonStyle(AppButtonStyle(kind: .primary))
        .disabled(checkedCandidatePaths.isEmpty || model.isWorking)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityIdentifier("sources.importBatch")
    }

    private func openBatch(preview: SourcePreviewRecord, candidates: [SourceSkillCandidate]) {
        let chosen = candidates.filter { checkedCandidatePaths.contains($0.path) }
        guard !chosen.isEmpty else { return }
        batchDraft = SourceSkillBatchDraft(
            preview: preview,
            items: chosen.map { candidate in
                SourceSkillBatchItem(path: candidate.path, slug: SourceSkillSlug.normalized(candidate.slug))
            }
        )
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
                    Text(L10n.tr("正在读取来源并扫描技能，项目文件保持不变。"))
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
