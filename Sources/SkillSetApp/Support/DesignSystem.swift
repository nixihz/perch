import SwiftUI
import AppKit

enum AppLayout {
    static let listWidth: CGFloat = 320
    static let columnSpacing: CGFloat = 18
    static let pageHorizontalInset: CGFloat = 28
    static let pageVerticalInset: CGFloat = 24
}

enum AppFont {
    // macOS 的 caption 仅约 10–11pt，持续阅读的内容不能沿用脚注字号。
    static let body = Font.system(size: 15)
    static let secondary = Font.system(size: 14)
    static let metadata = Font.system(size: 13)
    static let heading = Font.system(size: 17, weight: .semibold)
    static let title = Font.system(size: 22, weight: .semibold)
    static let pageTitle = Font.system(size: 30, weight: .semibold)
    static let code = Font.system(size: 13, design: .monospaced)
}

enum AppColor {
    // 沿用 Samantha 的明暗陶土红，避免固定浅色填充破坏深色窗口的对比度。
    static let accent = Color("AccentColor", bundle: .module)
    static let accentText = adaptive(light: 0xA6472D, dark: 0xE6A48B)
    static let accentSoft = adaptive(light: 0xF7EAE3, dark: 0x3C2C26)
    static let ink = adaptive(light: 0x302B26, dark: 0xF1E9DF)
    static let surface = adaptive(light: 0xFFFDFA, dark: 0x2B2927)
    static let border = adaptive(light: 0xE3DDD5, dark: 0x47413C)
    static let positive = adaptive(light: 0x2D7050, dark: 0x88C5A0)
    static let selection = adaptive(light: 0xA6472D, dark: 0xDC896B)
    static let onSelection = adaptive(light: 0xFFFFFF, dark: 0x302B26)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

struct StatusBadge: View {
    let text: String
    let tone: BadgeTone

    var body: some View {
        Text(text)
            .font(AppFont.metadata.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(tone.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tone.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            .help(text)
    }
}

struct SurfaceCard<Content: View>: View {
    let content: Content
    var emphasis = false

    init(emphasis: Bool = false, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.emphasis = emphasis
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(emphasis ? AppColor.accentSoft : AppColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(emphasis ? AppColor.accent.opacity(0.22) : AppColor.border, lineWidth: 1)
            )
    }
}

struct PageHeader: View {
    let eyebrow: String
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow.uppercased())
                .font(AppFont.metadata.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(AppColor.accentText)
            Text(title)
                .font(AppFont.pageTitle)
                .foregroundStyle(AppColor.ink)
            Text(detail)
                .font(AppFont.body)
                .foregroundStyle(.secondary)
        }
    }
}

struct KeyValueLine: View {
    let key: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(AppFont.secondary)
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(monospaced ? AppFont.code : AppFont.secondary)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(monospaced ? nil : 2)
            Spacer(minLength: 0)
        }
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AppColor.accentText)
            Text(title)
                .font(AppFont.heading)
            Text(detail)
                .font(AppFont.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

/// 标题与空白共用一个按钮，避免把展开操作限制在箭头上。
struct FullRowDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                        .accessibilityHidden(true)
                    configuration.label
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onKeyPress(.rightArrow) {
                configuration.isExpanded = true
                return .handled
            }
            .onKeyPress(.leftArrow) {
                configuration.isExpanded = false
                return .handled
            }
            // 视觉由整行按钮负责，辅助功能沿用原生展开控件的角色与状态。
            .accessibilityRepresentation {
                DisclosureGroup(isExpanded: configuration.$isExpanded) {
                    EmptyView()
                } label: {
                    configuration.label
                }
                .disclosureGroupStyle(.automatic)
            }
            if configuration.isExpanded {
                configuration.content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func selectionRow(_ selected: Bool) -> some View {
        self
            .background(selected ? AppColor.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? AppColor.accent.opacity(0.28) : .clear, lineWidth: 1)
            }
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

