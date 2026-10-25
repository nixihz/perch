import SwiftUI
import SkillSetCore

/// 批量加入技能库的面板数据：来源预览与勾选的候选。
struct SourceSkillBatchDraft: Identifiable {
    let id = UUID()
    let preview: SourcePreviewRecord
    let items: [SourceSkillBatchItem]
}

/// 批量加入技能库。整批共用存放方式与分类，技能标识逐条可改；
/// 标识与技能库重名时只加序号，不覆盖已有条目。
struct SourceSkillBatchImportSheet: View {
    @Bindable var model: AppModel
    let draft: SourceSkillBatchDraft
    let onFinished: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mode: SkillInstallMethod = .symlink
    @State private var category = ""
    @State private var slugs: [String: String]
    @State private var results: [SourceSkillBatchItemResult]?
    @State private var importing = false

    init(model: AppModel, draft: SourceSkillBatchDraft, onFinished: @escaping () -> Void = {}) {
        self.model = model
        self.draft = draft
        self.onFinished = onFinished
        // 库里的标识与本批次的标识一起参与去重，重名只加序号。
        var taken = Set(model.snapshot.catalog.entries.map(\.slug))
        var initial: [String: String] = [:]
        for item in draft.items {
            let unique = SourceSkillSlug.unique(SourceSkillSlug.normalized(item.slug), existing: taken)
            initial[item.path] = unique
            taken.insert(unique)
        }
        _slugs = State(initialValue: initial)
    }

    private var invalidItems: Int {
        draft.items.filter { slugIssue($0.path) != nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(results == nil ? L10n.tr("批量加入技能库") : L10n.tr("批量加入结果"))
                .font(AppFont.title.weight(.bold))
            if let results {
                resultView(results)
            } else {
                confirmView
            }
        }
        .appControls()
        .padding(24)
        .frame(width: 720, height: 640)
        .interactiveDismissDisabled(importing)
    }

    private var confirmView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.tr("一次加入 \(draft.items.count) 个技能。软链接跟随来源更新，复制保留独立文件；加入时不运行脚本。"))
                .font(AppFont.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker(L10n.tr("存放方式"), selection: $mode) {
                Text(L10n.tr("软链接")).tag(SkillInstallMethod.symlink)
                Text(L10n.tr("复制")).tag(SkillInstallMethod.copy)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("sources.batch.mode")
            HStack {
                Text(L10n.tr("分类"))
                TextField(L10n.tr("可选"), text: $category)
                    .textFieldStyle(AppTextFieldStyle())
                    .accessibilityIdentifier("sources.batch.category")
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(draft.items, id: \.path) { item in
                        itemRow(item)
                    }
                }
                .padding(.vertical, 2)
            }
            Divider()
            HStack {
                if importing {
                    ProgressView().controlSize(.small)
                    Text(L10n.tr("正在加入技能库，不会写入项目。"))
                        .font(AppFont.secondary)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.tr("取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(importing)
                Button(L10n.tr("加入技能库（\(draft.items.count)）")) {
                    Task { await importBatch() }
                }
                .buttonStyle(AppButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(importing || invalidItems > 0)
                .accessibilityIdentifier("sources.batch.confirm")
            }
        }
    }

    private func itemRow(_ item: SourceSkillBatchItem) -> some View {
        let candidate = draft.preview.candidates.first { $0.path == item.path }
        let slug = slugs[item.path] ?? ""
        let issue = slugIssue(item.path)
        let renamed = slug != SourceSkillSlug.normalized(item.slug)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(candidate?.declaredName ?? item.path)
                    .font(AppFont.body.weight(.semibold))
                Spacer()
                if let candidate {
                    Text(String(candidate.contentHash.prefix(16)) + "…")
                        .font(AppFont.metadata.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Text(item.path)
                .font(AppFont.secondary.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Text(L10n.tr("技能标识"))
                TextField("my-skill", text: Binding(
                    get: { slugs[item.path] ?? "" },
                    set: { slugs[item.path] = $0 }
                ))
                .textFieldStyle(AppTextFieldStyle())
                .accessibilityIdentifier("sources.batch.slug.\(item.path)")
            }
            if let issue {
                Text(issue)
                    .font(AppFont.secondary)
                    .foregroundStyle(.red)
            } else if renamed {
                Text(L10n.tr("技能库里已有同名标识，这里只加序号，不覆盖原技能。"))
                    .font(AppFont.secondary)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }

    private func resultView(_ results: [SourceSkillBatchItemResult]) -> some View {
        let imported = results.filter { if case .imported = $0.status { return true } else { return false } }
        let skipped = results.filter { if case .skipped = $0.status { return true } else { return false } }
        let failed = results.filter { if case .failed = $0.status { return true } else { return false } }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                StatusBadge(text: L10n.tr("已加入 \(imported.count) 个"), tone: .positive)
                StatusBadge(text: L10n.tr("已跳过 \(skipped.count) 个"), tone: .neutral)
                StatusBadge(text: L10n.tr("失败 \(failed.count) 个"), tone: failed.isEmpty ? .neutral : .danger)
                Spacer()
            }
            Text(L10n.tr("已加入的技能可在技能库查看。要在项目里使用，请到项目页选择并预览变更。"))
                .font(AppFont.secondary)
                .foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(results, id: \.path) { result in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(resultLabel(result.status))
                                .font(AppFont.metadata.weight(.semibold))
                            Text(result.slug)
                                .font(AppFont.secondary.monospaced())
                            Spacer()
                            if let reason = reasonText(result.status) {
                                Text(reason)
                                    .font(AppFont.metadata)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 2)
            }
            Divider()
            HStack {
                Spacer()
                if let first = imported.first, case .imported(let entry) = first.status {
                    Button(L10n.tr("在技能库查看")) {
                        dismiss()
                        model.showLibrarySkill(entry.id)
                    }
                    .accessibilityIdentifier("sources.batch.view")
                }
                Button(L10n.tr("完成")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(AppButtonStyle(kind: .primary))
                    .accessibilityIdentifier("sources.batch.done")
            }
        }
    }

    private func resultLabel(_ status: SourceSkillBatchItemResult.Status) -> String {
        switch status {
        case .imported: L10n.tr("已加入")
        case .skipped: L10n.tr("已跳过")
        case .failed: L10n.tr("失败")
        }
    }

    private func reasonText(_ status: SourceSkillBatchItemResult.Status) -> String? {
        switch status {
        case .imported: nil
        case .skipped(let code): UserFacingText.message(forCode: code)
        case .failed(let code): UserFacingText.message(forCode: code)
        }
    }

    /// 标识非法、与技能库重名或与本批其他项重名时给出原因。
    private func slugIssue(_ path: String) -> String? {
        let slug = slugs[path] ?? ""
        if slug.count > 80 || slug.range(of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) == nil {
            return L10n.tr("技能标识须为小写字母、数字和连字符，长度不超过 80 个字符。")
        }
        if model.snapshot.catalog.entries.contains(where: { $0.slug == slug }) {
            return L10n.tr("本地技能已有这个标识，请换一个标识。")
        }
        if slugs.values.filter({ $0 == slug }).count > 1 {
            return L10n.tr("这一批里有多个技能用了同一个标识，请改一个。")
        }
        return nil
    }

    private func importBatch() async {
        guard !importing else { return }
        importing = true
        let items = draft.items.map { item in
            SourceSkillBatchItem(path: item.path, slug: slugs[item.path] ?? item.slug)
        }
        let outcome = await model.importSourceSkills(
            previewID: draft.preview.id, items: items, mode: mode, category: category
        )
        importing = false
        guard let outcome else { return }
        results = outcome
        onFinished()
    }
}
