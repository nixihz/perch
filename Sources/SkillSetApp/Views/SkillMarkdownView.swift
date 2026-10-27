import SwiftUI

struct SkillMarkdownView: View {
    let source: String
    @State private var parsed = SkillMarkdownDocument(source: "")

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let metadata = parsed.metadata {
                DisclosureGroup {
                    Text(metadata)
                        .font(AppFont.code)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                } label: {
                    Text(L10n.tr("元信息")).font(AppFont.metadata).foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("skills.markdown.metadata")
            }
            if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(L10n.tr("输入 Markdown 后可在这里预览。"))
                    .font(AppFont.secondary).foregroundStyle(.secondary)
            } else {
                blockStack(parsed.blocks)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(AppFont.reading)
        .lineSpacing(3)
        .textSelection(.enabled)
        .tint(AppColor.accentText)
        .task(id: source) { parsed = SkillMarkdownDocument(source: source) }
    }

    private func blockStack(_ blocks: [SkillMarkdownBlock]) -> some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    private func blockView(_ block: SkillMarkdownBlock) -> AnyView {
        switch block {
        case let .heading(level, content):
            AnyView(Text(content)
                .font(level == 1 ? AppFont.pageTitle : level == 2 ? AppFont.title : AppFont.heading)
                .padding(.top, level == 1 ? 0 : 10)
                .accessibilityAddTraits(.isHeader))
        case let .paragraph(content):
            AnyView(Text(content).frame(maxWidth: .infinity, alignment: .leading))
        case let .code(language, content):
            AnyView(VStack(alignment: .leading, spacing: 8) {
                if let language, !language.isEmpty {
                    Text(language).font(AppFont.metadata).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    Text(content.hasSuffix("\n") ? String(content.dropLast()) : content)
                        .font(AppFont.code).fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.controlSurface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.border, lineWidth: 1)))
        case let .quote(blocks):
            AnyView(HStack(alignment: .top, spacing: 12) {
                Rectangle().fill(AppColor.accentText).frame(width: 3)
                blockStack(blocks).padding(.vertical, 8)
            }.padding(.trailing, 10).background(AppColor.accentSoft))
        case let .list(items):
            AnyView(VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text(item.marker).monospacedDigit().frame(minWidth: 18, alignment: .trailing)
                        blockStack(item.blocks)
                    }
                }
            })
        case let .table(header, rows):
            AnyView(ScrollView(.horizontal) {
                Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                    tableRow(header, isHeader: true)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in tableRow(row, isHeader: false) }
                }
            }.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading))
        case .separator:
            AnyView(Divider())
        case let .literal(text):
            AnyView(Text(text).font(AppFont.code).frame(maxWidth: .infinity, alignment: .leading))
        }
    }

    private func tableRow(_ cells: [AttributedString], isHeader: Bool) -> some View {
        GridRow {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell)
                    .font(isHeader ? AppFont.body.weight(.semibold) : AppFont.body)
                    .frame(minWidth: 110, maxWidth: 220, alignment: .leading)
                    .padding(10)
                    .background(isHeader ? AppColor.accentSoft : AppColor.controlSurface)
                    .overlay(Rectangle().stroke(AppColor.border, lineWidth: 0.5))
            }
        }
    }
}
