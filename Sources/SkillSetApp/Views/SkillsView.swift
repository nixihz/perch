import SwiftUI
import SkillSetCore

struct SkillsView: View {
    @Bindable var model: AppModel
    @State private var editor: SkillEditorDraft?
    @State private var removal: [SkillEntry] = []
    @State private var checkedSkillIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                PageHeader(
                    eyebrow: "SKILL CATALOG",
                    title: L10n.tr("技能库"),
                    detail: L10n.tr("搜索、阅读和编辑技能。要让 AI 在项目中使用技能，请到「项目」选择并预览变更。")
                )
                Spacer(minLength: 0)
                Button {
                    model.libraryError = nil
                    editor = SkillEditorDraft()
                } label: {
                    Label(L10n.tr("新增技能"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("n", modifiers: [.command])
                .accessibilityIdentifier("skills.create")
            }
            HStack(spacing: 8) {
                StatusBadge(text: L10n.tr("\(model.snapshot.catalog.entries.count) 个技能"), tone: .accent)
                StatusBadge(text: L10n.tr("\(model.blockedCount) 个暂不可用"), tone: model.blockedCount > 0 ? .danger : .positive)
                Spacer()
                if model.hiddenSkillCount > 0 {
                    Button(L10n.tr("恢复隐藏条目（\(model.hiddenSkillCount)）")) { model.restoreHiddenSkills() }
                }
            }
            if let error = model.skillRemovalError ?? model.libraryError, editor == nil {
                Text(L10n.text(error)).foregroundStyle(.red).font(AppFont.secondary).textSelection(.enabled)
            }
            HStack(alignment: .top, spacing: AppLayout.columnSpacing) {
                skillList
                    .frame(width: AppLayout.listWidth)
                skillDetail
            }
        }
        .sheet(item: $editor) { draft in
            SkillEditorSheet(model: model, initialDraft: draft)
        }
        .confirmationDialog(L10n.tr("从技能库移除？"), isPresented: Binding(
            get: { !removal.isEmpty }, set: { if !$0 { removal = [] } }
        ), titleVisibility: .visible) {
            Button(L10n.tr("移除"), role: .destructive) {
                let removed = model.removeSkills(removal)
                checkedSkillIDs.subtract(removed)
                removal = []
            }
            Button(L10n.tr("取消"), role: .cancel) { removal = [] }
        } message: {
            Text(L10n.tr("将移除以下技能：") + "\n" + removal.map(\.slug).joined(separator: "、") + "\n\n" + L10n.tr("本机技能从库中移除，历史版本保留；来源技能隐藏，可恢复。来源文件、项目文件和草稿不会改变。"))
        }
        .onChange(of: model.snapshot.catalog.entries.map(\.id)) { _, ids in
            checkedSkillIDs.formIntersection(ids)
        }
        .onChange(of: model.selectedSkillID, initial: true) { _, _ in model.loadSelectedSkillDocument() }
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
                SkillSearchField(model: model)
                HStack {
                    Button(L10n.tr("全选匹配项")) {
                        checkedSkillIDs.formUnion(model.filteredSkills.map(\.id))
                    }
                    .disabled(model.filteredSkills.isEmpty)
                    Button(L10n.tr("清空勾选")) { checkedSkillIDs.removeAll() }
                        .disabled(checkedSkillIDs.isEmpty)
                    Spacer(minLength: 0)
                }
                Button(role: .destructive) {
                    removal = model.snapshot.catalog.entries.filter { checkedSkillIDs.contains($0.id) }
                } label: {
                    Label(L10n.tr("移除勾选项（\(checkedSkillIDs.count)）"), systemImage: "trash")
                }
                .disabled(checkedSkillIDs.isEmpty)
                .accessibilityIdentifier("skills.removeChecked")
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.filteredSkills) { skill in
                            HStack(alignment: .top, spacing: 0) {
                                Toggle(isOn: Binding(
                                    get: { checkedSkillIDs.contains(skill.id) },
                                    set: { checked in
                                        if checked { checkedSkillIDs.insert(skill.id) }
                                        else { checkedSkillIDs.remove(skill.id) }
                                    }
                                )) {
                                    Text(L10n.tr("勾选技能") + " " + skill.slug)
                                }
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                                .padding(.top, 12)
                                .accessibilityIdentifier("skills.check.\(skill.id)")
                                Button {
                                    model.selectedSkillID = skill.id
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(alignment: .top, spacing: 7) {
                                                Text(skill.slug)
                                                    .font(AppFont.body.weight(.semibold))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                    .help(skill.slug)
                                                Spacer(minLength: 0)
                                                if skill.isBlocked {
                                                    StatusBadge(text: L10n.tr("暂不可用"), tone: .danger)
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
                            }
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
                            HStack {
                                Button {
                                    editor = model.editorDraft(for: skill)
                                } label: {
                                    Label(L10n.text(skill.sourceId == SkillLibraryStore.sourceID ? "编辑技能" : "复制并编辑"), systemImage: "square.and.pencil")
                                }
                                .disabled(skill.isBlocked)
                                Button(role: .destructive) { removal = [skill] } label: {
                                    Label(L10n.tr("从技能库移除"), systemImage: "trash")
                                }
                            }
                            if skill.sourceId == SkillLibraryStore.sourceID {
                                Text(L10n.tr("保存在本机。到「项目」选择这个技能，预览变更后再写入项目。"))
                                    .font(AppFont.secondary).foregroundStyle(.secondary)
                            }
                            Divider()
                            KeyValueLine(key: L10n.tr("版本"), value: skill.declaredVersion ?? L10n.tr("未声明"))
                            KeyValueLine(key: L10n.tr("文件大小"), value: L10n.tr("\(skill.fileCount) 文件 · \(L10n.byteCount(Int64(skill.bytes)))"))
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 10) {
                                    KeyValueLine(key: L10n.tr("来源标识"), value: skill.sourceId)
                                    if let origin = model.sourceOrigins[skill.id] {
                                        KeyValueLine(key: L10n.tr("原始仓库"), value: origin.url)
                                        KeyValueLine(key: L10n.tr("来源版本"), value: origin.commit, monospaced: true)
                                        KeyValueLine(key: L10n.tr("仓内路径"), value: origin.path, monospaced: true)
                                    }
                                    KeyValueLine(key: L10n.tr("内容指纹"), value: skill.contentHash, monospaced: true)
                                    Text(L10n.tr("内容指纹用于核对文件、路径和执行权限是否改变。"))
                                        .font(AppFont.secondary).foregroundStyle(.secondary)
                                    KeyValueLine(key: L10n.tr("存储路径"), value: skill.sourceId == SkillLibraryStore.sourceID
                                        ? model.runtimePaths.libraryRoot.appendingPathComponent(skill.path).path : skill.path, monospaced: true)
                                    KeyValueLine(key: L10n.tr("许可"), value: L10n.text(UserFacingText.metadata(skill.licenseReview, field: .licenseReview)))
                                    KeyValueLine(key: L10n.tr("技能信息"), value: L10n.text(UserFacingText.metadata(skill.metadataReview, field: .metadataReview)))
                                    if !skill.excludedPaths.isEmpty {
                                        Text(L10n.tr("排除路径：\(skill.excludedPaths.joined(separator: "、"))"))
                                            .font(AppFont.secondary)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.top, 12)
                            } label: {
                                Text(L10n.tr("详细信息")).font(AppFont.heading)
                            }
                            .accessibilityIdentifier("skills.details")
                        }
                    }
                    SkillContentView(model: model)
                        .id(skill.id + ":" + skill.contentHash)
                    if skill.isBlocked {
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 9) {
                                Label(L10n.tr("暂不可用的原因"), systemImage: "exclamationmark.triangle.fill")
                                    .font(AppFont.heading)
                                    .foregroundStyle(.red)
                                if skill.issues.isEmpty {
                                    Text(L10n.tr("技能文件未通过检查，请核对来源文件后重试。"))
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
                                Text(L10n.tr("请修复来源文件后重新导入，再把技能用于项目。"))
                                    .font(AppFont.secondary)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            EmptyState(icon: "wand.and.stars", title: L10n.tr("没有匹配的技能"), detail: L10n.tr("请清空搜索，或到「技能来源」预览其他仓库。"))
        }
    }
}

