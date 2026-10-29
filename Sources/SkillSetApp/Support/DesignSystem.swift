import SwiftUI
import AppKit

enum AppLayout {
    static let listWidth: CGFloat = 320
    static let columnSpacing: CGFloat = 18
    static let pageHorizontalInset: CGFloat = 28
    static let pageVerticalInset: CGFloat = 24
}

enum AppFont {
    // 工作台保持紧凑，长文单独保留阅读字号；中文辅助信息不降到系统 caption 的 10–11pt。
    static let body = Font.system(size: 13)
    static let secondary = Font.system(size: 12)
    static let metadata = Font.system(size: 12)
    static let heading = Font.system(size: 14, weight: .semibold)
    static let title = Font.system(size: 18, weight: .semibold)
    static let pageTitle = Font.system(size: 24, weight: .semibold)
    static let reading = Font.system(size: 14)
    static let code = Font.system(size: 12, design: .monospaced)
}

/// 交互动效只保留短促的反馈，避免高频操作被动画拖慢。
enum AppMotion {
    static let buttonPress = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.14)
}

struct AppThemePalette {
    let accentLight: UInt32
    let accentDark: UInt32
    let accentTextLight: UInt32
    let accentTextDark: UInt32
    let accentSoftLight: UInt32
    let accentSoftDark: UInt32
    let inkLight: UInt32
    let inkDark: UInt32
    let surfaceLight: UInt32
    let surfaceDark: UInt32
    let borderLight: UInt32
    let borderDark: UInt32
    let controlSurfaceLight: UInt32
    let controlSurfaceDark: UInt32
    let controlHoverLight: UInt32
    let controlHoverDark: UInt32
    let selectionLight: UInt32
    let selectionDark: UInt32
    let onSelectionLight: UInt32
    let onSelectionDark: UInt32

    static func forTheme(_ theme: AppTheme) -> Self {
        switch theme {
        case .terracotta:
            Self(accentLight: 0xA6472D, accentDark: 0xE6A48B,
                 accentTextLight: 0xA6472D, accentTextDark: 0xE6A48B,
                 accentSoftLight: 0xF7EAE3, accentSoftDark: 0x3C2C26,
                 inkLight: 0x302B26, inkDark: 0xF1E9DF,
                 surfaceLight: 0xFFFDFA, surfaceDark: 0x2B2927,
                 borderLight: 0xE3DDD5, borderDark: 0x47413C,
                 controlSurfaceLight: 0xFFFFFF, controlSurfaceDark: 0x242220,
                 controlHoverLight: 0xF6F1EB, controlHoverDark: 0x36312D,
                 selectionLight: 0xA6472D, selectionDark: 0xDC896B,
                 onSelectionLight: 0xFFFFFF, onSelectionDark: 0x302B26)
        case .obsidian:
            Self(accentLight: 0x242424, accentDark: 0xE2E2E2,
                 accentTextLight: 0x242424, accentTextDark: 0xF0F0F0,
                 accentSoftLight: 0xEEEEEE, accentSoftDark: 0x343434,
                 inkLight: 0x171717, inkDark: 0xF2F2F2,
                 surfaceLight: 0xFCFCFC, surfaceDark: 0x252525,
                 borderLight: 0xD8D8D8, borderDark: 0x494949,
                 controlSurfaceLight: 0xFFFFFF, controlSurfaceDark: 0x2B2B2B,
                 controlHoverLight: 0xF1F1F1, controlHoverDark: 0x3A3A3A,
                 selectionLight: 0x2A2A2A, selectionDark: 0xD8D8D8,
                 onSelectionLight: 0xFFFFFF, onSelectionDark: 0x1E1E1E)
        case .snow:
            Self(accentLight: 0x707070, accentDark: 0xD7D7D7,
                 accentTextLight: 0x555555, accentTextDark: 0xE1E1E1,
                 accentSoftLight: 0xF1F1F1, accentSoftDark: 0x3A3A3A,
                 inkLight: 0x252525, inkDark: 0xF0F0F0,
                 surfaceLight: 0xFFFFFF, surfaceDark: 0x282828,
                 borderLight: 0xDEDEDE, borderDark: 0x4B4B4B,
                 controlSurfaceLight: 0xFFFFFF, controlSurfaceDark: 0x2E2E2E,
                 controlHoverLight: 0xF5F5F5, controlHoverDark: 0x3D3D3D,
                 selectionLight: 0x707070, selectionDark: 0xD0D0D0,
                 onSelectionLight: 0xFFFFFF, onSelectionDark: 0x242424)
        }
    }
}

enum AppColor {
    // 主题以中性色建立层次，避免强调色抢过内容本身；成功状态仍保留绿色语义。
    static let accent = adaptive(light: { $0.accentLight }, dark: { $0.accentDark })
    static let accentText = adaptive(light: { $0.accentTextLight }, dark: { $0.accentTextDark })
    static let accentSoft = adaptive(light: { $0.accentSoftLight }, dark: { $0.accentSoftDark })
    static let ink = adaptive(light: { $0.inkLight }, dark: { $0.inkDark })
    static let surface = adaptive(light: { $0.surfaceLight }, dark: { $0.surfaceDark })
    static let border = adaptive(light: { $0.borderLight }, dark: { $0.borderDark })
    static let controlSurface = adaptive(light: { $0.controlSurfaceLight }, dark: { $0.controlSurfaceDark })
    static let controlHover = adaptive(light: { $0.controlHoverLight }, dark: { $0.controlHoverDark })
    static let positive = adaptive(light: 0x2D7050, dark: 0x88C5A0)
    static let selection = adaptive(light: { $0.selectionLight }, dark: { $0.selectionDark })
    static let onSelection = adaptive(light: { $0.onSelectionLight }, dark: { $0.onSelectionDark })

    private static func adaptive(light: @escaping (AppThemePalette) -> UInt32,
                                 dark: @escaping (AppThemePalette) -> UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let palette = AppThemePalette.forTheme(AppThemeRuntime.shared.current())
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            let value = hex(palette)
            return NSColor(
                srgbRed: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        adaptive(light: { _ in light }, dark: { _ in dark })
    }
}

struct StatusBadge: View {
    let text: String
    let tone: BadgeTone

    var body: some View {
        Text(text)
            .font(AppFont.metadata.weight(.medium))
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

    var heading: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow.uppercased())
                .font(AppFont.metadata.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(AppColor.accentText)
            Text(title)
                .font(AppFont.pageTitle)
                .foregroundStyle(AppColor.ink)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            heading
            Text(detail)
                .font(AppFont.body)
                .foregroundStyle(.secondary)
        }
    }
}

/// 添加入口固定在标题右侧，辅助入口由调用方排列在主操作左侧。
struct PageActionHeader<Actions: View>: View {
    let eyebrow: String
    let title: String
    let detail: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 12) {
                PageHeader(eyebrow: eyebrow, title: title, detail: detail).heading
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                HStack(spacing: 8, content: actions)
                    .fixedSize(horizontal: true, vertical: false)
            }
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
                .frame(maxWidth: .infinity, minHeight: AppControl.height, alignment: .leading)
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
            .frame(minHeight: AppControl.height)
            .background(selected ? AppColor.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? AppColor.accent.opacity(0.28) : .clear, lineWidth: 1)
            }
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
