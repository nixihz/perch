import SwiftUI

struct TemplatesView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                eyebrow: "INSTRUCTION TEMPLATES",
                title: L10n.tr("AGENTS.md 与 CLAUDE.md"),
                detail: L10n.tr("选择规则片段，写入项目的 AGENTS.md 或 CLAUDE.md。只更新本应用管理的部分，保留其他内容。")
            )
            HStack(alignment: .top, spacing: AppLayout.columnSpacing) {
                templateList
                    .frame(width: AppLayout.listWidth)
                templateDetail
            }
        }
    }

    private var templateList: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.tr("片段"))
                    .font(AppFont.heading)
                ForEach(model.snapshot.templates) { template in
                    Button {
                        model.selectedTemplateID = template.id
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: template.id == model.selectedTemplateID ? "text.badge.checkmark" : "text.alignleft")
                                .foregroundStyle(template.id == model.selectedTemplateID ? AppColor.accentText : .secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.text(template.title))
                                    .font(AppFont.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(template.id)
                                    .font(AppFont.secondary.monospaced())
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
                Divider()
                Text(L10n.tr("当前项目按宿主写入 AGENTS.md 或 CLAUDE.md 的受管块；不会自动抢占其他规则来源的优先级。"))
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
                                Text(L10n.text(template.title))
                                    .font(AppFont.title.weight(.bold))
                                Spacer()
                                StatusBadge(text: template.id, tone: .accent)
                            }
                            Text(L10n.text(template.purpose))
                                .font(AppFont.body)
                                .foregroundStyle(.secondary)
                            Divider()
                            Text(L10n.tr("目标文件：AGENTS.md / CLAUDE.md · 受管块：project-rules · schema 1"))
                                .font(AppFont.secondary)
                                .foregroundStyle(AppColor.accentText)
                        }
                    }
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(L10n.tr("正文预览"))
                                    .font(AppFont.heading)
                                Spacer()
                                Text(L10n.tr("选中文字后按 ⌘C 复制"))
                                    .font(AppFont.secondary)
                                    .foregroundStyle(.secondary)
                            }
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
                            Text(L10n.tr("受管块边界"))
                                .font(AppFont.heading)
                            Text("<!-- skillset:begin id=project-rules schema=1 -->\n…\n<!-- skillset:end id=project-rules -->")
                                .font(AppFont.secondary.monospaced())
                                .foregroundStyle(AppColor.ink)
                            Text(L10n.tr("重复、交叉、缺尾标记，或块外文件为软链时，计划必须阻塞；块外字节按原样保留。"))
                                .font(AppFont.secondary)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } else {
            EmptyState(icon: "text.badge.checkmark", title: L10n.tr("选择一个规则片段"), detail: L10n.tr("查看正文、受管块和宿主加载边界。"))
        }
    }
}

