import SwiftUI
import SkillSetCore

struct TemplatesView: View {
    @Bindable var model: AppModel
    @State private var showFileMarkers = false
    @State private var query = ""
    @State private var editor: TemplateEditorDraft?
    @State private var removal: TemplateRecord?

    private var matches: [TemplateRecord] { model.matchingTemplates(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                PageHeader(
                    eyebrow: "AGENTS SNIPPETS",
                    title: L10n.tr("AGENTS 片段"),
                    detail: L10n.tr("管理可写入 AGENTS.md 或 CLAUDE.md 的AGENTS 片段。在项目页选择片段，预览并批准后写入。")
                )
                Spacer(minLength: 0)
                Button {
                    model.templateError = nil
                    editor = TemplateEditorDraft()
                } label: { Label(L10n.tr("新增片段"), systemImage: "plus") }
                .buttonStyle(AppButtonStyle(kind: .primary)).keyboardShortcut("n", modifiers: [.command])
                .accessibilityIdentifier("templates.create")
            }
            if let error = model.templateError, editor == nil {
                Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red).textSelection(.enabled)
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
            Text(L10n.tr("片段将从本机片段库删除，已写入项目的规则保持不变。引用它的草稿或预设需重新选择片段。"))
        }
        .onChange(of: query) { _, _ in selectFirstMatchIfNeeded() }
        .onChange(of: model.selectedTemplateID) { _, _ in showFileMarkers = false }
        .onChange(of: model.snapshot.templates) { _, _ in
            if !matches.contains(where: { $0.id == model.selectedTemplateID }) { query = "" }
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
                            .buttonStyle(.plain)
                        }
                        if matches.isEmpty {
                            Text(L10n.text(query.isEmpty ? "还没有片段，点击“新增片段”开始。" : "没有匹配的片段，换个关键词或清空搜索。"))
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
                                    .font(AppFont.title.weight(.bold))
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
            EmptyState(icon: "text.badge.checkmark", title: L10n.tr("选择一个AGENTS 片段"), detail: L10n.tr("在左侧选择片段查看正文，或点击“新增片段”创建规则。"))
        }
    }
}

