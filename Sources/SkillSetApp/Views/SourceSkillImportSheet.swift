import SwiftUI
import SkillSetCore

struct SourceSkillImportSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SourceSkillImportDraft
    @State private var addedID: String?
    @FocusState private var slugFocused: Bool

    init(model: AppModel, initialDraft: SourceSkillImportDraft) {
        self.model = model
        _draft = State(initialValue: initialDraft)
    }

    private var invalidSlug: Bool {
        draft.slug.count > 80 || draft.slug.range(of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) == nil
    }

    private var duplicate: Bool { model.snapshot.catalog.entries.contains { $0.id == "personal/\(draft.slug)" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr(addedID == nil ? "加入技能库" : "已加入技能库")).font(AppFont.title.weight(.bold))
            if addedID == nil {
                Text(L10n.tr("完整保存技能正文、附带文件和仓库许可文件。加入后可在项目中选择，导入时不运行脚本。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
                HStack {
                    Text(L10n.tr("技能标识"))
                    TextField("my-skill", text: $draft.slug)
                        .textFieldStyle(.roundedBorder).focused($slugFocused)
                        .disabled(model.isWorking).accessibilityIdentifier("sources.import.slug")
                }
                if invalidSlug {
                    Text(L10n.tr("技能标识须为小写字母、数字和连字符，长度不超过 80 个字符。"))
                        .font(AppFont.secondary).foregroundStyle(.red)
                } else if duplicate {
                    Text(L10n.tr("本地技能已有这个标识，请换一个标识后保存。"))
                        .font(AppFont.secondary).foregroundStyle(.red)
                }
            } else {
                Text(L10n.tr("技能已独立保存在本机，删除来源预览不会影响它。到项目页勾选技能，再预览变更并批准写入。"))
                    .font(AppFont.body)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let id = addedID { KeyValueLine(key: L10n.tr("技能标识"), value: id, monospaced: true) }
                    KeyValueLine(key: L10n.tr("原始仓库"), value: draft.origin.url)
                    KeyValueLine(key: L10n.tr("来源版本"), value: draft.origin.commit, monospaced: true)
                    KeyValueLine(key: L10n.tr("仓内路径"), value: draft.origin.path, monospaced: true)
                    KeyValueLine(key: L10n.tr("许可线索"), value: L10n.text(UserFacingText.licenseEvidence(draft.origin.licenseEvidence)))
                    if !draft.origin.licenseHashes.isEmpty {
                        Text(draft.origin.licenseHashes.keys.sorted().joined(separator: " · "))
                            .font(AppFont.metadata.monospaced())
                    }
                    DisclosureGroup(L10n.tr("附属文件")) {
                        ForEach(draft.files, id: \.path) { file in
                            Text(verbatim: file.path).font(AppFont.metadata.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Divider()
                    Text("SKILL.md").font(AppFont.heading)
                    Text(verbatim: draft.document).font(AppFont.body.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
            }
            if let error = model.sourceImportError {
                Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red)
            }
            HStack {
                Button(L10n.tr(addedID == nil ? "取消" : "完成")) { model.sourceImportError = nil; dismiss() }
                    .keyboardShortcut(.cancelAction).disabled(model.isWorking)
                Spacer()
                if let id = addedID {
                    Button(L10n.tr("在技能库查看")) { dismiss(); model.showLibrarySkill(id) }
                        .accessibilityIdentifier("sources.import.view")
                    Button(L10n.tr("前往项目")) { dismiss(); model.section = .projects }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("sources.import.projects")
                } else {
                    if model.isWorking { ProgressView().controlSize(.small) }
                    Button(L10n.tr("加入技能库")) {
                        Task { if await model.importSourceSkill(draft) { addedID = "personal/\(draft.slug)" } }
                    }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(model.isWorking || invalidSlug || duplicate)
                    .accessibilityIdentifier("sources.import.confirm")
                }
            }
        }
        .padding(24).frame(width: 720, height: 640)
        .interactiveDismissDisabled(model.isWorking)
        .onAppear { slugFocused = true }
    }
}
