import Foundation
import SwiftUI
import Markdown

struct SkillMarkdownDocument {
    let metadata: String?
    let blocks: [SkillMarkdownBlock]

    init(source: String) {
        let sections = Self.sections(source)
        metadata = sections.metadata
        blocks = Self.blocks(in: Document(parsing: sections.body))
    }

    private static func sections(_ source: String) -> (metadata: String?, body: String) {
        // 只规范化预览副本，原文与编辑草稿保留全部字节语义。
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard lines.first == "---", let closing = lines.dropFirst().firstIndex(of: "---") else {
            return (nil, source)
        }
        return (lines[1..<closing].joined(separator: "\n"), lines.dropFirst(closing + 1).joined(separator: "\n"))
    }

    private static func blocks(in markup: any Markup) -> [SkillMarkdownBlock] {
        markup.children.flatMap { child -> [SkillMarkdownBlock] in
            switch child {
            case let heading as Heading:
                return [.heading(level: heading.level, content: inline(heading))]
            case let paragraph as Paragraph:
                return [.paragraph(inline(paragraph))]
            case let code as CodeBlock:
                return [.code(language: code.language, content: code.code)]
            case let quote as BlockQuote:
                return [.quote(blocks(in: quote))]
            case let list as OrderedList:
                return [.list(list.children.enumerated().map { offset, item in
                    SkillMarkdownListItem(marker: "\(list.startIndex + UInt(offset)).", blocks: blocks(in: item))
                })]
            case let list as UnorderedList:
                return [.list(list.children.map { item in
                    let checkbox = (item as? ListItem)?.checkbox
                    let marker = checkbox.map { $0 == .checked ? "☑" : "☐" } ?? "•"
                    return SkillMarkdownListItem(marker: marker, blocks: blocks(in: item))
                })]
            case let table as Markdown.Table:
                let header = table.head.children.map { inline($0) }
                let rows = table.body.children.map { row in row.children.map { inline($0) } }
                return [.table(header: header, rows: rows)]
            case is ThematicBreak:
                return [.separator]
            case let html as HTMLBlock:
                // 原始 HTML 仅作可选择的文本显示，不交给浏览器执行或加载资源。
                return [.literal(html.rawHTML)]
            default:
                return blocks(in: child)
            }
        }
    }

    private static func inline(_ markup: any Markup) -> AttributedString {
        switch markup {
        case let text as Markdown.Text:
            return AttributedString(text.string)
        case let code as InlineCode:
            var text = AttributedString(code.code)
            text.font = .system(size: 13, design: .monospaced)
            text.foregroundColor = AppColor.accentText
            text.backgroundColor = AppColor.accentSoft
            return text
        case is SoftBreak:
            return AttributedString(" ")
        case is LineBreak:
            return AttributedString("\n")
        case let html as InlineHTML:
            return AttributedString(html.rawHTML)
        default:
            var text = markup.children.reduce(into: AttributedString()) { $0.append(inline($1)) }
            if markup is Strong || markup is Emphasis || markup is Strikethrough {
                for run in text.runs {
                    if markup is Strikethrough { text[run.range].strikethroughStyle = .single }
                    else {
                        let intent: InlinePresentationIntent = markup is Strong ? .stronglyEmphasized : .emphasized
                        text[run.range].inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(intent)
                    }
                }
            }
            if let link = markup as? Markdown.Link, let url = allowedLink(link.destination) { text.link = url }
            if let image = markup as? Markdown.Image {
                // 图片保留替代文本；阅读文件不会悄悄请求来源中的远程地址。
                text = AttributedString("[" + image.plainText + "]")
                if let url = allowedLink(image.source) { text.link = url }
            }
            return text
        }
    }

    static func allowedLink(_ destination: String?) -> URL? {
        guard let destination, let url = URL(string: destination),
              let scheme = url.scheme?.lowercased(), ["https", "http", "mailto"].contains(scheme) else { return nil }
        return url
    }
}

indirect enum SkillMarkdownBlock {
    case heading(level: Int, content: AttributedString)
    case paragraph(AttributedString)
    case code(language: String?, content: String)
    case quote([SkillMarkdownBlock])
    case list([SkillMarkdownListItem])
    case table(header: [AttributedString], rows: [[AttributedString]])
    case separator
    case literal(String)
}

struct SkillMarkdownListItem {
    let marker: String
    let blocks: [SkillMarkdownBlock]
}
