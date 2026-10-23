import SwiftUI
import SkillSetCore

struct SkillsView: View {
    @Bindable var model: AppModel
    @State private var editor: SkillEditorDraft?
    @State private var removal: [SkillEntry] = []
    @State private var installing = false
    @State private var scanning = false
    @State private var checkedSkillIDs: Set<String> = []

    @State private var filter: SkillLibraryFilter = .all
    @State private var sourceID = ""

    private var libraryIndex: SkillLibraryIndex { SkillLibraryIndex(entries: model.snapshot.catalog.entries) }
    private var sourceLabels: [String: String] {
        Dictionary(grouping: model.snapshot.catalog.entries, by: \.sourceId).mapValues { entries in
            let id = entries[0].sourceId
            return SkillSourceLabel.title(
                sourceID: id,
                origin: entries.compactMap { model.sourceOrigins[$0.id]?.url }.sorted().first,
                registeredTitle: model.snapshot.sources.sources.first { $0.id == id }?.title
            )
        }
    }
    private var visibleSkills: [SkillEntry] {
        let index = libraryIndex
        return model.filteredSkills.filter {
            (sourceID.isEmpty || $0.sourceId == sourceID) && index.matches($0, filter: filter)
        }
    }

    private func reconcileSelection() {
        if !visibleSkills.contains(where: { $0.id == model.selectedSkillID }) {
            model.selectedSkillID = visibleSkills.first?.id
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageActionHeader(
                eyebrow: "SKILL CATALOG",
                title: L10n.tr("技能库"),
                detail: L10n.tr("搜索、阅读和编辑技能。要让 AI 在项目中使用技能，请到「项目」选择并预览变更。")
            ) {
                Button(L10n.tr("扫描已安装技能…")) { scanning = true }
                    .accessibilityIdentifier("skills.scan-installed")
                Button {
                    model.libraryError = nil
                    editor = SkillEditorDraft()
                } label: {
                    Label(L10n.tr("新增技能"), systemImage: "plus")
                }
                .buttonStyle(AppButtonStyle(kind: .primary))
                .keyboardShortcut("n", modifiers: [.command])
                .accessibilityIdentifier("skills.create")
            }
            HStack(spacing: 8) {
                StatusBadge(text: L10n.tr("\(model.snapshot.catalog.entries.count) 个技能"), tone: .accent)
                StatusBadge(text: L10n.tr("\(model.blockedCount) 个暂不可用"), tone: model.blockedCount > 0 ? .danger : .positive)
                Spacer()
                Button(L10n.tr("启用到 AI 工具…")) { installing = true }
                    .disabled(checkedSkillIDs.isEmpty || model.isWorking)
                    .accessibilityIdentifier("skills.install-user")
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
        .sheet(isPresented: $scanning) {
            InstalledSkillScanSheet(model: model)
        }
        .sheet(isPresented: $installing) {
            UserSkillInstallSheet(model: model, skillIDs: checkedSkillIDs.sorted())
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
        .onChange(of: visibleSkills.map(\.id), initial: true) { _, _ in reconcileSelection() }
        .onChange(of: model.selectedSkillID) { _, _ in reconcileSelection() }
        .task(id: model.selectedSkill.map { $0.id + ":" + $0.contentHash }) {
            await model.loadSelectedSkillDocumentInBackground()
        }
    }

    private var skillList: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.tr("技能列表"))
                        .font(AppFont.heading)
                    Spacer()
                    Text(L10n.tr("\(visibleSkills.count) 个匹配"))
                        .font(AppFont.secondary)
                        .foregroundStyle(.secondary)
                }
                SkillSearchField(model: model)
                HStack(spacing: 8) {
                    AppPicker(title: L10n.tr("筛选技能"), selection: $filter, valueLabel: L10n.text(filter.title), showsLabel: false) {
                        ForEach(SkillLibraryFilter.allCases, id: \.self) { option in
                            Text(L10n.text(option.title)).tag(option)
                        }
                    }
                    .accessibilityIdentifier("skills.filter")
                    AppPicker(title: L10n.tr("技能来源"), selection: $sourceID,
                              valueLabel: sourceID.isEmpty ? L10n.tr("全部来源") : (sourceLabels[sourceID] ?? sourceID), showsLabel: false) {
                        Text(L10n.tr("全部来源")).tag("")
                        ForEach(Set(model.snapshot.catalog.entries.map(\.sourceId)).sorted(), id: \.self) { source in
                            Text(sourceLabels[source] ?? source).tag(source)
                        }
                    }
                    .accessibilityIdentifier("skills.sourceFilter")
                }
                if filter != .all || !sourceID.isEmpty || !model.query.isEmpty {
                    Button(L10n.tr("清空筛选")) {
                        filter = .all; sourceID = ""; model.updateQuery("")
                    }
                    .accessibilityIdentifier("skills.clearFilters")
                }
                if visibleSkills.isEmpty {
                    Text(L10n.tr("没有匹配的技能，请清空筛选或调整搜索。"))
                        .font(AppFont.secondary).foregroundStyle(.secondary)
                }
                HStack {
                    Button(L10n.tr("全选匹配项")) {
                        checkedSkillIDs.formUnion(visibleSkills.map(\.id))
                    }
                    .disabled(visibleSkills.isEmpty)
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
                        ForEach(visibleSkills) { skill in
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
                                            Text(SkillSourceLabel.title(
                                                sourceID: skill.sourceId,
                                                origin: model.sourceOrigins[skill.id]?.url,
                                                registeredTitle: model.snapshot.sources.sources.first { $0.id == skill.sourceId }?.title
                                            ))
                                                .font(AppFont.metadata.monospaced())
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .help(model.sourceOrigins[skill.id]?.url ?? skill.sourceId)
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
                            let namesakes = libraryIndex.namesakes(of: skill)
                            if !namesakes.isEmpty {
                                DisclosureGroup(L10n.tr("同名条目（\(namesakes.count)）")) {
                                    Text(L10n.tr("按 SKILL.md 名称比较，忽略大小写及首尾空格；未声明名称时使用目录名。重名不代表内容相同。"))
                                        .font(AppFont.secondary).foregroundStyle(.secondary)
                                    ForEach(namesakes) { other in
                                        Button {
                                            filter = .all; sourceID = ""; model.updateQuery("")
                                            model.selectedSkillID = other.id
                                        } label: {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(other.id)
                                                if let sameContent = SkillLibraryIndex.hasSameContent(other, skill) {
                                                    Text(sameContent ? L10n.tr("内容相同") : L10n.tr("内容不同"))
                                                        .font(AppFont.secondary)
                                                } else {
                                                    Text(L10n.tr("内容是否相同待核对"))
                                                        .font(AppFont.secondary)
                                                }
                                            }
                                        }
                                    }
                                }
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
                                    KeyValueLine(key: L10n.tr("存储路径"), value: (skill.sourceId == SkillLibraryStore.sourceID || skill.sourceId.hasPrefix("source-"))
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
            EmptyState(icon: "wand.and.stars", title: L10n.tr("没有匹配的技能"), detail: L10n.tr("请清空筛选，或到「技能来源」预览其他仓库。"))
        }
    }
}



private struct UserSkillInstallSheet: View {
    @Bindable var model: AppModel
    let skillIDs: [String]
    @State private var host = "codex"
    @State private var method: SkillInstallMethod = .symlink
    @State private var adoptExisting = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("用户级启用技能")).font(AppFont.title)
            Text(L10n.tr("用户级技能会影响所选 AI 工具的全部项目。已有受管技能会保留；安装方式也会应用于它们。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            AppPicker(title: L10n.tr("目标 AI 工具"), selection: $host,
                      valueLabel: host == "codex" ? "Codex · ~/.agents/skills" : "Claude Code · ~/.claude/skills") {
                Text("Codex · ~/.agents/skills").tag("codex")
                Text("Claude Code · ~/.claude/skills").tag("claude-code")
            }
            Picker(L10n.tr("技能安装方式"), selection: $method) {
                Text(L10n.tr("软链接（推荐）")).tag(SkillInstallMethod.symlink)
                Text(L10n.tr("复制独立文件")).tag(SkillInstallMethod.copy)
            }.pickerStyle(.segmented)
            Text(model.runtimePaths.versionsRoot.path).font(AppFont.metadata.monospaced()).textSelection(.enabled)
            Toggle(L10n.tr("迁移同内容的现有目录（先备份，再替换）"), isOn: $adoptExisting)
            Text(L10n.tr("迁移前可把现有 skills 目录添加为本地来源，完整复制到栖集。内容不同的同名技能会阻止安装。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(L10n.tr("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("预览变更")) {
                    model.libraryError = nil
                    dismiss()
                    model.prepareUserSkillPlan(skillIDs: skillIDs, agents: [host], method: method, adoptExisting: adoptExisting)
                }
                .keyboardShortcut(.defaultAction).buttonStyle(AppButtonStyle(kind: .primary))
            }
        }.appControls().padding(26).frame(width: 600)
    }
}
