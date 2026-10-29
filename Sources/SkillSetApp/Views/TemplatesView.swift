import SwiftUI
import AppKit
import SkillSetCore

struct TemplatesView: View {
    @Bindable var model: AppModel
    @State private var showFileMarkers = false
    @State private var query = ""
    @State private var editor: TemplateEditorDraft?
    @State private var removal: TemplateRecord?
    @State private var referenceState = DetailSnapshotModel<String, [TemplateReference]>()
    @State private var copied = false
    @State private var referenceRevision = 0

    private var references: [TemplateReference] {
        referenceState.key == model.selectedTemplateID ? referenceState.snapshot ?? [] : []
    }

    private var referenceError: String? {
        referenceState.key == model.selectedTemplateID ? referenceState.error : nil
    }

    @AppStorage("templates.sortOrder") private var sortOrder: TemplateSortOrder = .original

    private var matches: [TemplateRecord] {
        sortOrder.sorted(model.matchingTemplates(query)) { $0.isLocal ? $0.title : L10n.text($0.title) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageActionHeader(
                eyebrow: "AGENTS SNIPPETS",
                title: L10n.tr("AGENTS 片段"),
                detail: L10n.tr("保存常用规则，选择项目或全局配置，预览并批准后写入 AGENTS.md 或 CLAUDE.md。")
            ) {
                Button {
                    model.templateError = nil
                    editor = TemplateEditorDraft()
                } label: { Label(L10n.tr("新增片段"), systemImage: "plus") }
                .buttonStyle(AppButtonStyle(kind: .primary)).keyboardShortcut("n", modifiers: [.command])
                .accessibilityIdentifier("templates.create")
                .disabled(model.templateLibraryError != nil)
            }
            if let error = model.templateLibraryError {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.text(error), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(templateFileURL.path).font(AppFont.code).textSelection(.enabled)
                    HStack {
                        Button(L10n.tr("重新读取")) { model.reloadTemplates() }
                            .accessibilityIdentifier("templates.reload")
                        Button(L10n.tr("在 Finder 中显示")) {
                            NSWorkspace.shared.activateFileViewerSelecting([templateFileURL])
                        }
                    }
                }
                .accessibilityIdentifier("templates.libraryError")
            } else if let error = model.templateError, editor == nil {
                Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red).textSelection(.enabled)
            }
            if !model.lastTemplateWritePaths.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label(L10n.tr("规则文件已写入并核对，请到 AI 工具中确认加载。"), systemImage: "checkmark.circle")
                        .foregroundStyle(AppColor.positive)
                    Text(model.lastTemplateWritePaths.joined(separator: "\n"))
                        .font(AppFont.code).textSelection(.enabled)
                }
                .accessibilityIdentifier("templates.writeResult")
            }
            HStack(alignment: .top, spacing: AppLayout.columnSpacing) {
                templateList
                    .frame(width: AppLayout.listWidth)
                templateDetail
            }
        }
        .sheet(item: $editor) { draft in TemplateEditorSheet(model: model, initialDraft: draft) }
        .confirmationDialog(L10n.tr("删除这个片段？"), isPresented: Binding(
            get: { removal != nil }, set: { if !$0 { removal = nil } }
        ), titleVisibility: .visible) {
            Button(L10n.tr("删除"), role: .destructive) {
                if let removal { model.removeTemplate(removal) }
                removal = nil
            }
            Button(L10n.tr("先不删"), role: .cancel) { removal = nil }
        } message: {
            Text(L10n.tr("片段将从本机片段库删除，已写入的规则文件保持不变。配置和预设中的引用会显示为不可用，需移除引用或重新选择片段后再部署。"))
        }
        .onChange(of: model.planPresented) { _, presented in if !presented { refreshReferences() } }
        .task(id: ReferenceRequest(templateID: model.selectedTemplateID,
                                   templates: model.snapshot.templates, revision: referenceRevision)) {
            await loadReferences()
        }
        .onChange(of: query) { _, _ in selectFirstMatchIfNeeded() }
        .onChange(of: model.selectedTemplateID) { _, _ in showFileMarkers = false }
        .onChange(of: model.snapshot.templates) { _, _ in
            if !matches.contains(where: { $0.id == model.selectedTemplateID }) { query = "" }
        }
    }

    private var templateFileURL: URL {
        TemplateStore(rootURL: model.runtimePaths.applicationSupportRoot).documentURL
    }

    private struct ReferenceRequest: Hashable {
        let templateID: String
        let templates: [TemplateRecord]
        let revision: Int
    }

    private func refreshReferences() {
        copied = false
        referenceRevision += 1
    }

    private func loadReferences() async {
        let id = model.selectedTemplateID
        copied = false
        await referenceState.load(for: id, errorMessage: { _ in
            "使用位置暂时无法读取，请检查项目、全局配置和预设后重试。"
        }) {
            try await model.templateReferencesInBackground(id)
        }
    }

    private var usageCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.tr("使用位置")).font(AppFont.heading)
                    Spacer()
                    Button(L10n.tr("刷新")) { refreshReferences() }
                        .disabled(referenceState.isLoading)
                }
                if referenceState.isLoading {
                    ProgressView(L10n.tr("正在读取使用位置…")).controlSize(.small)
                }
                if let referenceError {
                    Text(L10n.text(referenceError)).foregroundStyle(.red)
                    if !references.isEmpty {
                        Text(L10n.tr("显示上次读取结果。"))
                            .font(AppFont.secondary).foregroundStyle(.secondary)
                    }
                }
                if referenceState.key == model.selectedTemplateID, referenceState.snapshot != nil,
                   references.isEmpty && !referenceState.isLoading && referenceError == nil {
                    Text(L10n.tr("尚未被配置或预设引用。点击「用于配置…」开始使用。"))
                        .font(AppFont.secondary).foregroundStyle(.secondary)
                } else if !references.isEmpty {
                    ForEach(references) { reference in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(reference.name).font(AppFont.body.weight(.semibold))
                                Text(reference.presetID != nil ? L10n.tr("预设引用")
                                    : reference.needsUpdate ? L10n.tr("片段有更新或文件有变化 · 需重新预览")
                                    : reference.isApplied ? (reference.inDraft ? L10n.tr("草稿已选择 · 已写入，加载待验证") : L10n.tr("已写入 · 草稿已取消选择，待批准移除"))
                                    : L10n.tr("草稿已选择 · 尚未写入"))
                                    .font(AppFont.secondary).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(L10n.tr("查看配置")) { model.showTemplateReference(reference) }
                        }
                    }
                    Text(L10n.tr("编辑片段后需再次预览和批准，已有文件才会更新。删除片段后，配置和预设中的引用会显示为不可用。"))
                        .font(AppFont.secondary).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func selectFirstMatchIfNeeded() {
        if !matches.contains(where: { $0.id == model.selectedTemplateID }) {
            model.selectedTemplateID = matches.first?.id ?? ""
        }
    }

    private var templateList: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.tr("AGENTS 片段"))
                    .font(AppFont.heading)
                AppSearchField(query: $query, prompt: L10n.tr("搜索名称、说明或正文"),
                               label: L10n.tr("搜索片段"), identifier: "templates.search")
                AppPicker(title: L10n.tr("片段排序"), selection: $sortOrder, valueLabel: L10n.text(sortOrder.title)) {
                    ForEach(TemplateSortOrder.allCases, id: \.self) { order in
                        Text(L10n.text(order.title)).tag(order)
                    }
                }
                .accessibilityIdentifier("templates.sortOrder")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(matches) { template in
                            Button {
                                model.selectedTemplateID = template.id
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: template.id == model.selectedTemplateID ? "text.badge.checkmark" : "text.alignleft")
                                        .foregroundStyle(template.id == model.selectedTemplateID ? AppColor.accentText : .secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(UserFacingText.templateTitle(template))
                                            .font(AppFont.body.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(UserFacingText.templatePurpose(template))
                                            .lineLimit(2)
                                            .font(AppFont.secondary)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 8)
                                .selectionRow(template.id == model.selectedTemplateID)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(AppPressButtonStyle())
                        }
                        if matches.isEmpty {
                            Text(L10n.text(model.templateLibraryError != nil ? "片段列表暂不可用，请先修复文件并重新读取。"
                                : query.isEmpty ? "还没有片段，点击「新增片段」开始。" : "没有匹配的片段，换个关键词或清空搜索。"))
                                .font(AppFont.secondary).foregroundStyle(.secondary).padding(.vertical, 12)
                        }
                    }
                }
                Divider()
                Text(L10n.tr("写入片段不会改变 AI 工具读取其他规则文件的顺序。"))
                    .font(AppFont.secondary)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var templateDetail: some View {
        if let template = model.selectedTemplate {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SurfaceCard(emphasis: true) {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text(UserFacingText.templateTitle(template))
                                    .font(AppFont.title)
                                Spacer()
                                Button(L10n.tr("编辑")) {
                                    model.templateError = nil
                                    editor = TemplateEditorDraft(template: template)
                                }
                                .accessibilityIdentifier("templates.edit")
                                Button(L10n.tr("删除"), role: .destructive) { removal = template }
                                    .accessibilityIdentifier("templates.delete")
                            }
                            Text(UserFacingText.templatePurpose(template))
                                .font(AppFont.body)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button(L10n.tr("用于配置…")) {
                                    model.templateError = nil
                                    model.templateUseRequest = TemplateUseRequest(template: template)
                                }
                                .buttonStyle(AppButtonStyle(kind: .primary))
                                .accessibilityIdentifier("templates.use")
                                Button(copied ? L10n.tr("已复制正文") : L10n.tr("复制正文")) {
                                    NSPasteboard.general.clearContents()
                                    copied = NSPasteboard.general.setString(template.body, forType: .string)
                                }
                                .accessibilityIdentifier("templates.copy")
                                Button(L10n.tr("创建副本")) {
                                    var draft = TemplateEditorDraft()
                                    let stem = UserFacingText.templateTitle(template)
                                    var title = stem + L10n.tr(" 副本")
                                    var number = 2
                                    while model.snapshot.templates.contains(where: { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }) {
                                        title = stem + L10n.tr(" 副本 \(number)")
                                        number += 1
                                    }
                                    draft.title = title
                                    draft.purpose = UserFacingText.templatePurpose(template)
                                    draft.body = template.body
                                    model.templateError = nil
                                    editor = draft
                                }
                                .accessibilityIdentifier("templates.duplicate")
                            }
                            Divider()
                            Text(L10n.tr("写入位置：AGENTS.md 或 CLAUDE.md"))
                                .font(AppFont.secondary)
                                .foregroundStyle(AppColor.accentText)
                        }
                    }
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.tr("正文预览"))
                                .font(AppFont.heading)
                            Text(template.body)
                                .font(AppFont.code)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    usageCard
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.tr("栖集会修改哪部分内容"))
                                .font(AppFont.heading)
                            Text(L10n.tr("栖集会在写入的规则前后加上起止标记，只更新两条标记之间的内容。"))
                                .font(AppFont.body)
                            Text(L10n.tr("你自己写在标记外的内容会原样保留，避免更新片段时覆盖整个文件。"))
                                .font(AppFont.body)
                                .foregroundStyle(.secondary)
                            DisclosureGroup(L10n.tr("查看文件中的标记"), isExpanded: $showFileMarkers) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("<!-- skillset:begin id=project-rules schema=1 -->\n"
                                         + L10n.tr("这里是栖集写入的规则")
                                         + "\n<!-- skillset:end id=project-rules -->")
                                        .font(AppFont.code)
                                        .foregroundStyle(AppColor.ink)
                                        .textSelection(.enabled)
                                    Text(L10n.tr("标记由栖集自动添加，无需手动填写。请保留这两条标记，方便以后更新。"))
                                        .font(AppFont.secondary)
                                        .foregroundStyle(.secondary)
                                    Text(L10n.tr("已有标记不完整或位置冲突时，栖集会暂停写入，提示你检查文件。"))
                                        .font(AppFont.secondary)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 8)
                            }
                            .font(AppFont.secondary)
                            .accessibilityIdentifier("templates.fileMarkers")
                        }
                    }
                }
            }
        } else {
            if model.templateLibraryError != nil {
                EmptyState(icon: "exclamationmark.triangle", title: L10n.tr("片段库暂不可用"),
                           detail: L10n.tr("修复上方文件后点击「重新读取」，无需重启应用。"))
            } else {
                EmptyState(icon: "text.badge.checkmark", title: L10n.tr("选择一个 AGENTS 片段"), detail: L10n.tr("在左侧选择片段查看正文，或点击「新增片段」创建规则。"))
            }
        }
    }
}
