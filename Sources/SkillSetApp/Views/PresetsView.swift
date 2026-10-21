import SwiftUI
import SkillSetCore

struct PresetsView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                eyebrow: "PRESETS",
                title: L10n.tr("技能与规则预设"),
                detail: L10n.tr("保存常用的技能和规则组合。载入只更新草稿，不会直接修改项目；预设更新也不会自动改动项目。")
            )
            HStack(alignment: .top, spacing: AppLayout.columnSpacing) {
                presetList
                    .frame(width: AppLayout.listWidth)
                presetDetail
            }
        }
    }

    private var presetList: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.tr("已保存预设"))
                        .font(AppFont.heading)
                    Spacer()
                    Text(L10n.tr("暂不支持新建"))
                        .font(AppFont.secondary)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.snapshot.presets) { preset in
                    Button {
                        model.selectedPresetID = preset.id
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: preset.id == model.selectedPresetID ? "rectangle.3.group.fill" : "rectangle.3.group")
                                .foregroundStyle(preset.id == model.selectedPresetID ? AppColor.accentText : .secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.text(preset.name))
                                    .font(AppFont.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(L10n.tr("版本 \(preset.revision) · \(preset.skills.count) 个技能"))
                                    .font(AppFont.secondary)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusBadge(text: L10n.text(UserFacingText.metadata(preset.status, field: .presetStatus)), tone: .warning)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                        .selectionRow(preset.id == model.selectedPresetID)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Divider()
                Text(L10n.tr("载入会替换草稿中的技能和规则。项目文件只有在计划批准后才会改变。"))
                    .font(AppFont.secondary)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var presetDetail: some View {
        if let preset = model.selectedPreset {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SurfaceCard(emphasis: true) {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text(L10n.text(preset.name))
                                    .font(AppFont.title.weight(.bold))
                                Spacer()
                                StatusBadge(text: L10n.tr("版本 \(preset.revision)"), tone: .accent)
                            }
                            Text(L10n.text(preset.description))
                                .font(AppFont.body)
                                .foregroundStyle(.secondary)
                            Text(L10n.tr("应用到：\(model.selectedProject?.name ?? L10n.tr("未选择项目"))"))
                                .font(AppFont.secondary)
                                .foregroundStyle(AppColor.accentText)
                            Button(L10n.tr("载入草稿")) {
                                model.loadPreset(preset)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppColor.accent)
                            .disabled(model.selectedProject == nil)
                            if model.selectedProject == nil {
                                Text(L10n.tr("请先到「项目」添加并选择一个项目。"))
                                    .font(AppFont.secondary)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(L10n.tr("包含的技能"))
                                    .font(AppFont.heading)
                                Spacer()
                                Text(L10n.tr("\(preset.skills.count) 条"))
                                    .font(AppFont.secondary)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(preset.skills, id: \.self) { id in
                                Label {
                                    Text(id)
                                        .font(AppFont.secondary.monospaced())
                                } icon: {
                                    Image(systemName: "checkmark.circle")
                                        .foregroundStyle(AppColor.accentText)
                                }
                            }
                        }
                    }
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(L10n.tr("规则片段"))
                                .font(AppFont.heading)
                            Text(preset.instructionFragments.map { "#\($0)" }.joined(separator: "  "))
                                .font(AppFont.secondary.monospaced())
                                .foregroundStyle(AppColor.accentText)
                            KeyValueLine(key: L10n.tr("策略"), value: L10n.text(UserFacingText.metadata(preset.mergePolicy, field: .mergePolicy)))
                            Text(L10n.tr("预设更新后，如需同步到项目，请重新载入草稿、生成计划并批准。"))
                                .font(AppFont.secondary)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } else {
            EmptyState(icon: "rectangle.3.group", title: L10n.tr("选择一个预设"), detail: L10n.tr("预设详情会展示固定版本和规则组合。"))
        }
    }
}

