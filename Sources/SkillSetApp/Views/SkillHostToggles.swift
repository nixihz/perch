import SwiftUI
import SkillSetCore

/// 工具资源仍只接受实际宿主，不能把共享目录用于 MCP 或插件。
struct SkillHostToggles: View {
    let skillName: String
    let identifierPrefix: String
    var savesImmediately = false
    let isSelected: (MCPHost) -> Bool
    let isEnabled: (MCPHost) -> Bool
    let setSelected: (MCPHost, Bool) -> Void

    init(
        skillName: String,
        identifierPrefix: String,
        savesImmediately: Bool = false,
        isSelected: @escaping (MCPHost) -> Bool,
        isEnabled: @escaping (MCPHost) -> Bool = { _ in true },
        setSelected: @escaping (MCPHost, Bool) -> Void
    ) {
        self.skillName = skillName
        self.identifierPrefix = identifierPrefix
        self.savesImmediately = savesImmediately
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.setSelected = setSelected
    }

    var body: some View {
        SkillTargetToggles(skillName: skillName, identifierPrefix: identifierPrefix,
            targets: MCPHost.allCases.map(SkillConfigurationTarget.init),
            savesImmediately: savesImmediately,
            isSelected: { $0.mcpHost.map(isSelected) ?? false },
            isEnabled: { $0.mcpHost.map(isEnabled) ?? false },
            setSelected: { target, enabled in
                if let host = target.mcpHost { setSelected(host, enabled) }
            })
    }
}

struct SkillTargetIcon: View {
    let target: SkillConfigurationTarget

    private var assetName: String {
        switch target {
        case .agents: "AgentsLogo"
        case .codex: "CodexLogo"
        case .claudeCode: "ClaudeLogo"
        }
    }

    var body: some View {
        Image(assetName, bundle: .module)
            .resizable().renderingMode(.template).scaledToFit()
            .accessibilityHidden(true)
    }
}

/// 配置目标独立选择；共享目录不改变另一个工具的草稿。
struct SkillTargetToggles: View {
    let skillName: String
    let identifierPrefix: String
    let targets: [SkillConfigurationTarget]
    var savesImmediately = false
    let isSelected: (SkillConfigurationTarget) -> Bool
    var isEnabled: (SkillConfigurationTarget) -> Bool = { _ in true }
    let setSelected: (SkillConfigurationTarget, Bool) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(targets) { host in hostButton(host) }
        }.fixedSize()
    }

    private func hostButton(_ host: SkillConfigurationTarget) -> some View {
        let selected = isSelected(host)
        return Button {
            setSelected(host, !isSelected(host))
        } label: {
            SkillTargetIcon(target: host).frame(width: 16, height: 16)
        }
        .buttonStyle(SkillHostButtonStyle(selected: selected))
        .disabled(!isEnabled(host))
        .accessibilityIdentifier("\(identifierPrefix).\(host.rawValue)")
        .accessibilityLabel(savesImmediately
            ? L10n.tr("在 \(host.displayName) 中保存「\(skillName)」")
            : L10n.tr("在 \(host.displayName) 草稿中选择「\(skillName)」"))
        .accessibilityValue(selected ? L10n.tr("已选择") : L10n.tr("未选择"))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(savesImmediately
            ? (selected
                ? L10n.tr("从 \(host.displayName) 中取消「\(skillName)」，立即保存。")
                : L10n.tr("在 \(host.displayName) 中启用「\(skillName)」，立即保存。"))
            : isEnabled(host)
            ? (selected
                ? L10n.tr("从 \(host.displayName) 草稿中取消选择「\(skillName)」，预览后保存。")
                : L10n.tr("在 \(host.displayName) 草稿中选择「\(skillName)」，预览后保存。"))
            : L10n.tr("当前无法切换 \(host.displayName) 草稿中的「\(skillName)」。"))
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
        return hovered && isEnabled ? AppColor.controlHover : .clear
    }

    var body: some View {
        configuration.label
            .foregroundStyle(selected ? AppColor.accentText : AppColor.ink)
            .frame(width: AppControl.height, height: AppControl.height)
            .background(fill, in: RoundedRectangle(cornerRadius: AppControl.radius))
            .overlay {
                RoundedRectangle(cornerRadius: AppControl.radius)
                    .strokeBorder(selected ? AppColor.accentText.opacity(0.6) : AppColor.border.opacity(0.55))
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: AppControl.radius))
            // 保留原生 Button 的鼠标、键盘与辅助功能动作。
            .onHover { hovered = $0 }
    }
}
