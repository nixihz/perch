import SwiftUI

/// 同一行的输入、选择和操作共享几何尺寸，页面不再单独调整控件高度。
enum AppControl {
    static let height: CGFloat = 32
    static let radius: CGFloat = 6
    static let horizontalInset: CGFloat = 10
    static let iconTarget: CGFloat = 32
    // 横向项目与预设选择器需要保留滚动条和可拖动的命中高度。
    static let selectorHeight: CGFloat = 46
}

enum AppButtonKind {
    case primary, secondary, quiet
}

struct AppButtonStyle: ButtonStyle {
    var kind: AppButtonKind = .secondary
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        AppButtonBody(configuration: configuration, kind: kind, selected: selected)
    }
}

private struct AppButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: AppButtonKind
    let selected: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    private var foreground: Color {
        if !isEnabled { return .secondary }
        if configuration.role == .destructive { return .red }
        return kind == .primary ? AppColor.onSelection : selected ? AppColor.accentText : AppColor.ink
    }

    private var fill: Color {
        if kind == .primary { return AppColor.selection.opacity(isEnabled ? (configuration.isPressed ? 0.84 : 1) : 0.16) }
        if (configuration.isPressed || selected) && isEnabled { return AppColor.accentSoft }
        if hovered && isEnabled { return AppColor.controlHover }
        return kind == .quiet ? .clear : AppColor.controlSurface
    }

    var body: some View {
        configuration.label
            .font(AppFont.body.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, AppControl.horizontalInset)
            .frame(minWidth: AppControl.iconTarget, minHeight: AppControl.height)
            .foregroundStyle(foreground)
            .background(fill, in: RoundedRectangle(cornerRadius: AppControl.radius))
            .overlay {
                RoundedRectangle(cornerRadius: AppControl.radius)
                    .strokeBorder(kind == .quiet ? .clear : selected ? AppColor.accent.opacity(0.4) : AppColor.border.opacity(isEnabled ? 1 : 0.5))
            }
            .contentShape(RoundedRectangle(cornerRadius: AppControl.radius))
            // 按压状态由 Button 提供；零距离拖拽会截走 macOS 的鼠标点击。
            .onHover { hovered = $0 }
    }
}

@MainActor
struct AppTextFieldStyle: @preconcurrency TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        AppTextFieldBody(content: configuration)
    }
}

private struct AppTextFieldBody<Content: View>: View {
    let content: Content
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var focused: Bool

    var body: some View {
        content
            .textFieldStyle(.plain)
            .font(AppFont.body)
            .focused($focused)
            .padding(.horizontal, AppControl.horizontalInset)
            .padding(.vertical, 5)
            .frame(minHeight: AppControl.height)
            .background {
                RoundedRectangle(cornerRadius: AppControl.radius)
                    .fill(AppColor.controlSurface.opacity(isEnabled ? 1 : 0.5))
                    // 原生文本区域之外的留白也应聚焦，文字内仍保留系统光标定位。
                    .onTapGesture { if isEnabled { focused = true } }
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppControl.radius)
                    .strokeBorder(focused ? AppColor.accent : AppColor.border, lineWidth: focused ? 2 : 1)
                    .allowsHitTesting(false)
            }
    }
}

struct AppFormField<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AppFont.secondary.weight(.medium))
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 保留系统菜单、选项勾选和键盘导航，只统一菜单触发器的外观。
struct AppPicker<Selection: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: Selection
    let valueLabel: String
    var showsLabel = true
    @ViewBuilder let options: () -> Options
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var focused: Bool

    var body: some View {
        if showsLabel {
            AppFormField(title) { menu }
        } else {
            menu
        }
    }

    private var menu: some View {
        Menu {
            Picker(title, selection: $selection, content: options)
                .pickerStyle(.inline)
        } label: {
            Text(valueLabel).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, minHeight: AppControl.height, alignment: .leading)
                .contentShape(Rectangle())
        }
        // button 菜单才会把统一按钮样式的留白纳入触发器，borderlessButton 只命中文字。
        .menuStyle(.button)
        .buttonStyle(AppButtonStyle())
        .menuIndicator(.visible)
        .font(AppFont.secondary)
        .tint(AppColor.ink)
        .focused($focused)
        .frame(maxWidth: .infinity)
        .background(AppColor.controlSurface.opacity(isEnabled ? 1 : 0.5), in: RoundedRectangle(cornerRadius: AppControl.radius))
        .overlay {
            RoundedRectangle(cornerRadius: AppControl.radius)
                .strokeBorder(focused ? AppColor.accent : AppColor.border, lineWidth: focused ? 2 : 1)
                .allowsHitTesting(false)
        }
        .accessibilityLabel(title)
        .accessibilityValue(valueLabel)
        .help(valueLabel)
    }
}

extension View {
    func appControls(buttonKind: AppButtonKind = .secondary) -> some View {
        self
            .buttonStyle(AppButtonStyle(kind: buttonKind))
            .textFieldStyle(AppTextFieldStyle())
            .controlSize(.regular)
            .toggleStyle(AppCheckboxStyle())
            .menuStyle(.button)
    }

    func appEditorSurface() -> some View {
        self
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(AppColor.controlSurface, in: RoundedRectangle(cornerRadius: AppControl.radius))
            .overlay {
                RoundedRectangle(cornerRadius: AppControl.radius).strokeBorder(AppColor.border)
            }
    }
}
