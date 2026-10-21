import SwiftUI
import SkillSetCore

struct SkillsView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                eyebrow: "SKILL CATALOG",
                title: L10n.tr("技能库"),
                detail: L10n.tr("追溯来源、版本与内容指纹。收录不等于启用；已快照也不代表安全或许可审核完成。")
            )
            HStack(spacing: 8) {
                StatusBadge(text: L10n.tr("\(model.snapshot.catalog.entries.count) 条记录"), tone: .accent)
                StatusBadge(text: L10n.tr("\(model.blockedCount) 条阻塞"), tone: model.blockedCount > 0 ? .danger : .positive)
                StatusBadge(text: L10n.tr("内容指纹包含文件路径与执行权限"), tone: .neutral)
                Spacer()
            }
            HStack(alignment: .top, spacing: AppLayout.columnSpacing) {
                skillList
                    .frame(width: AppLayout.listWidth)
                skillDetail
            }
        }
    }

    private var skillList: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.tr("技能列表"))
                        .font(AppFont.heading)
                    Spacer()
                    Text(L10n.tr("\(model.filteredSkills.count) 个匹配"))
                        .font(AppFont.secondary)
                        .foregroundStyle(.secondary)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.filteredSkills) { skill in
                            Button {
                                model.selectedSkillID = skill.id
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: skill.id == model.selectedSkillID ? "circle.inset.filled" : "circle")
                                        .foregroundStyle(skill.id == model.selectedSkillID ? AppColor.accentText : .secondary)
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(alignment: .top, spacing: 7) {
                                            Text(skill.slug)
                                                .font(AppFont.body.weight(.semibold))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                                .help(skill.slug)
                                            Spacer(minLength: 0)
                                            if skill.wasSymlink {
                                                StatusBadge(text: L10n.tr("曾为软链"), tone: .warning)
                                            }
                                            if skill.isBlocked {
                                                StatusBadge(text: L10n.tr("阻塞"), tone: .danger)
                                            }
                                        }
                                        Text(skill.sourceId)
                                            .font(AppFont.metadata.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Text(skill.description)
                                            .font(AppFont.secondary)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 9)
                                .padding(.horizontal, 7)
                                .selectionRow(skill.id == model.selectedSkillID)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var skillDetail: some View {
        if let skill = model.selectedSkill {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SurfaceCard(emphasis: true) {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text(skill.slug)
                                    .font(AppFont.title.weight(.bold))
                                Spacer()
                                StatusBadge(
                                    text: L10n.text(UserFacingText.metadata(skill.integrity, field: .integrity)),
                                    tone: skill.isBlocked ? .danger : skill.integrity == "snapshotted" ? .positive : .warning
                                )
                            }
                            Text(skill.description)
                                .font(AppFont.body)
                                .foregroundStyle(.secondary)
                            Divider()
                            KeyValueLine(key: L10n.tr("来源标识"), value: skill.sourceId)
                            KeyValueLine(key: L10n.tr("版本"), value: skill.declaredVersion ?? L10n.tr("未声明"))
                            KeyValueLine(key: L10n.tr("内容指纹"), value: skill.contentHash, monospaced: true)
                            KeyValueLine(key: L10n.tr("文件大小"), value: L10n.tr("\(skill.fileCount) 文件 · \(L10n.byteCount(Int64(skill.bytes)))"))
                        }
                    }
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.tr("来源与边界"))
                                .font(AppFont.heading)
                            KeyValueLine(key: L10n.tr("仓内路径"), value: skill.path, monospaced: true)
                            KeyValueLine(key: L10n.tr("许可"), value: L10n.text(UserFacingText.metadata(skill.licenseReview, field: .licenseReview)))
                            KeyValueLine(key: L10n.tr("元数据"), value: L10n.text(UserFacingText.metadata(skill.metadataReview, field: .metadataReview)))
                            if !skill.excludedPaths.isEmpty {
                                Text(L10n.tr("排除路径：\(skill.excludedPaths.joined(separator: "、"))"))
                                    .font(AppFont.secondary)
                                    .foregroundStyle(.secondary)
                            }
                            if skill.wasSymlink {
                                Label(L10n.tr("原始来源含软链，快照已实体化；本页面不回写旧目标。"), systemImage: "link")
                                    .font(AppFont.secondary)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    if skill.isBlocked {
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 9) {
                                Label(L10n.tr("阻塞原因"), systemImage: "exclamationmark.triangle.fill")
                                    .font(AppFont.heading)
                                    .foregroundStyle(.red)
                                if skill.issues.isEmpty {
                                    Text(L10n.tr("来源未通过完整性检查，请核对来源文件。"))
                                        .font(AppFont.secondary)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(skill.issues, id: \.self) { issue in
                                        if let path = issue.path {
                                            KeyValueLine(key: L10n.tr("问题路径"), value: path, monospaced: true)
                                        }
                                        Text(L10n.text(UserFacingText.catalogIssue(issue)))
                                            .font(AppFont.secondary)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text(L10n.tr("请修复原始来源，再重新生成快照。链接目标不明确时无法部署。"))
                                    .font(AppFont.secondary)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            EmptyState(icon: "wand.and.stars", title: L10n.tr("没有匹配的技能"), detail: L10n.tr("请清空搜索，或到「来源」预览其他仓库。"))
        }
    }
}

