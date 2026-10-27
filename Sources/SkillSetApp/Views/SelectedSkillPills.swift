import SwiftUI
import SkillSetCore

/// 三个配置入口共用呈现；选择状态和写入边界仍由各自的草稿持有。
struct SelectedSkillPills: View {
    struct Item: Identifiable {
        let id: String
        let name: String
        let detail: String
    }

    struct HostSelection {
        var targets: [SkillConfigurationTarget] = [.codex, .claudeCode]
        var savesImmediately = false
        let isSelected: (String, SkillConfigurationTarget) -> Bool
        let isEnabled: (String, SkillConfigurationTarget) -> Bool
        let setSelected: (String, SkillConfigurationTarget, Bool) -> Void
    }

    let items: [Item]
    let identifierPrefix: String
    var compact = false
    var hostSelection: HostSelection? = nil
    var canRemove: (String) -> Bool = { _ in true }
    let remove: (String) -> Void
    private let iconTarget: CGFloat = 28
    private var rowHeight: CGFloat { iconTarget + 2 }
    @State private var contentHeight: CGFloat = 30

    var body: some View {
        Group {
            if compact {
                HStack(alignment: .top, spacing: 8) {
                    heading.fixedSize().frame(minHeight: rowHeight)
                    content
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { heading; Spacer(minLength: 0) }
                    content
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(identifierPrefix).selectedSkills")
    }

    private var heading: some View {
        HStack(spacing: 8) {
            Text(L10n.tr("已选技能")).font(AppFont.metadata.weight(.semibold))
            Text(items.count.formatted()).font(AppFont.metadata.monospacedDigit())
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var content: some View {
        if items.isEmpty {
            Text(L10n.tr("从下方列表选择技能，已选名称会显示在这里。"))
                .font(AppFont.metadata).foregroundStyle(.secondary)
                .frame(minHeight: compact ? rowHeight : 0, alignment: .leading)
        } else {
            ScrollView {
                PillFlowLayout(spacing: 6) {
                    ForEach(items) { item in pill(item) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            // 小窗口只保留一行并允许滚动，不能让已选区挤走可选列表。
            .frame(height: min(max(contentHeight, rowHeight), compact ? rowHeight : 102))
        }
    }

    private func pill(_ item: Item) -> some View {
        HStack(spacing: 2) {
            Text(item.name)
                .font(AppFont.metadata)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 220, alignment: .leading)
                .help(item.detail)
            if let hostSelection {
                ForEach(hostSelection.targets) { host in
                    hostButton(item, host: host, selection: hostSelection)
                }
            }
            Button { remove(item.id) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                    .frame(width: iconTarget, height: iconTarget).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canRemove(item.id))
            .accessibilityIdentifier("\(identifierPrefix).selectedSkill.\(item.id).remove")
            .accessibilityLabel(removalHelp(item))
            .help(removalHelp(item))
        }
        .padding(.leading, 10).padding(.trailing, 1).padding(.vertical, 1)
        .foregroundStyle(AppColor.accentText)
        .background(AppColor.accentSoft, in: Capsule())
        .overlay { Capsule().strokeBorder(AppColor.accentText.opacity(0.5)) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(identifierPrefix).selectedSkill.\(item.id)")
    }

    private func hostButton(_ item: Item, host: SkillConfigurationTarget, selection: HostSelection) -> some View {
        let selected = selection.isSelected(item.id, host)
        return Button { selection.setSelected(item.id, host, !selected) } label: {
            SkillTargetIcon(target: host).frame(width: 15, height: 15)
                .frame(width: iconTarget, height: iconTarget)
                .opacity(selected ? 1 : 0.4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!selection.isEnabled(item.id, host))
        .accessibilityIdentifier("\(identifierPrefix).selectedSkill.\(item.id).\(host.rawValue)")
        .accessibilityLabel(selection.savesImmediately
            ? L10n.tr("在 \(host.displayName) 中保存「\(item.name)」")
            : L10n.tr("在 \(host.displayName) 草稿中选择「\(item.name)」"))
        .accessibilityValue(selected ? L10n.tr("已选择") : L10n.tr("未选择"))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(selection.savesImmediately
            ? (selected
                ? L10n.tr("从 \(host.displayName) 中取消「\(item.name)」，立即保存。")
                : L10n.tr("在 \(host.displayName) 中启用「\(item.name)」，立即保存。"))
            : selected
            ? L10n.tr("从 \(host.displayName) 草稿中取消选择「\(item.name)」，预览后保存。")
            : L10n.tr("在 \(host.displayName) 草稿中选择「\(item.name)」，预览后保存。"))
    }

    private func removalHelp(_ item: Item) -> String {
        if hostSelection?.savesImmediately == true {
            return L10n.tr("从 Agents、Codex 和 Claude Code 中移除「\(item.name)」，立即保存。")
        }
        return hostSelection == nil
            ? L10n.tr("从预设草稿中移除「\(item.name)」")
            : (hostSelection?.targets.contains(.agents) == true
                ? L10n.tr("从 Agents、Codex 和 Claude Code 草稿中移除「\(item.name)」；预览并批准后应用。")
                : L10n.tr("从 Codex 和 Claude Code 草稿中移除「\(item.name)」；预览并批准后应用。"))
    }
}
