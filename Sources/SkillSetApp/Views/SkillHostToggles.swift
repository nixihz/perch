import SwiftUI
import SkillSetCore

/// 两个工具共享同一行，但各自读写独立草稿；控件本身不执行部署。
struct SkillHostToggles: View {
    let skillName: String
    let identifierPrefix: String
    let isSelected: (MCPHost) -> Bool
    let isEnabled: (MCPHost) -> Bool
    let setSelected: (MCPHost, Bool) -> Void

    init(
        skillName: String,
        identifierPrefix: String,
        isSelected: @escaping (MCPHost) -> Bool,
        isEnabled: @escaping (MCPHost) -> Bool = { _ in true },
        setSelected: @escaping (MCPHost, Bool) -> Void
    ) {
        self.skillName = skillName
        self.identifierPrefix = identifierPrefix
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.setSelected = setSelected
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach([MCPHost.codex, .claudeCode]) { host in
                hostButton(host)
            }
        }
        .fixedSize()
    }

    private func hostButton(_ host: MCPHost) -> some View {
        let selected = isSelected(host)
        return Button {
            setSelected(host, !isSelected(host))
        } label: {
            Image(host == .codex ? "CodexLogo" : "ClaudeLogo", bundle: .module)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        }
        .buttonStyle(SkillHostButtonStyle(selected: selected))
        .disabled(!isEnabled(host))
        .accessibilityIdentifier("\(identifierPrefix).\(host.rawValue)")
        .accessibilityLabel(L10n.tr("在 \(host.displayName) 草稿中选择「\(skillName)」"))
        .accessibilityValue(selected ? L10n.tr("已选择") : L10n.tr("未选择"))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(help(host, selected: selected))
    }

    private func help(_ host: MCPHost, selected: Bool) -> String {
        if !isEnabled(host) {
            return L10n.tr("当前无法切换 \(host.displayName) 草稿中的「\(skillName)」。")
        }
        return selected
            ? L10n.tr("从 \(host.displayName) 草稿中取消选择「\(skillName)」，预览后保存。")
            : L10n.tr("在 \(host.displayName) 草稿中选择「\(skillName)」，预览后保存。")
    }
}

private struct SkillHostButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        SkillHostButtonBody(configuration: configuration, selected: selected)
    }
}

private struct SkillHostButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    private var fill: Color {
        if configuration.isPressed && isEnabled { return AppColor.accentSoft.opacity(0.7) }
        if selected { return AppColor.accentSoft }
        return hovered && isEnabled ? AppColor.controlHover : AppColor.controlSurface
    }

    var body: some View {
        configuration.label
            .foregroundStyle(selected ? AppColor.accentText : AppColor.ink)
            .frame(width: AppControl.height, height: AppControl.height)
            .background(fill, in: RoundedRectangle(cornerRadius: AppControl.radius))
            .overlay {
                RoundedRectangle(cornerRadius: AppControl.radius)
                    .strokeBorder(selected ? AppColor.accentText : AppColor.border)
            }
            .overlay(alignment: .bottomTrailing) {
                if selected {
                    // 勾号同时表达开启状态，避免只靠底色区分。
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(AppColor.onSelection)
                        .frame(width: 12, height: 12)
                        .background(AppColor.selection, in: Circle())
                        .overlay { Circle().strokeBorder(AppColor.controlSurface, lineWidth: 1) }
                        .padding(2)
                        .accessibilityHidden(true)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: AppControl.radius))
            // 保留原生 Button 的鼠标、键盘与辅助功能动作。
            .onHover { hovered = $0 }
    }
}
