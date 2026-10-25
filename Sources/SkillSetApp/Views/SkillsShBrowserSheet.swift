import SwiftUI
import SkillSetCore

struct SkillsShBrowserSheet: View {
    @Bindable var model: AppModel
    @State private var pendingUninstall: SkillsShHit?
    @Environment(\.dismiss) private var dismiss

    private var trimmedQuery: String {
        model.skillsShQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("浏览 skills.sh"))
                        .font(AppFont.title)
                    Text(L10n.tr("搜索第三方技能，加入时从原 GitHub 仓库复制当前版本，不运行脚本。用于项目前还需选择并预览。"))
                        .font(AppFont.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button(L10n.tr("完成")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isWorking)
            }

            HStack(spacing: 10) {
                AppSearchField(
                    query: $model.skillsShQuery,
                    prompt: L10n.tr("搜索 skills.sh"),
                    label: L10n.tr("搜索 skills.sh"),
                    identifier: "skills.sh.search"
                )
                .onSubmit { Task { await model.searchSkillsSh() } }
                Button(L10n.tr("搜索")) {
                    Task { await model.searchSkillsSh() }
                }
                .buttonStyle(AppButtonStyle(kind: .primary))
                .disabled(trimmedQuery.count < 2 || model.isSearchingSkillsSh)
                .accessibilityIdentifier("skills.sh.submit")
            }
            Text(trimmedQuery.count < 2
                ? L10n.tr("至少输入 2 个字符。搜索结果来自第三方目录，安装前仍会核对来源仓库和内容指纹。")
                : L10n.tr("加入后可在「技能库」查看和编辑；用于项目前还需选择并预览。"))
                .font(AppFont.secondary)
                .foregroundStyle(.secondary)

            if model.isSearchingSkillsSh {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.tr("正在搜索 skills.sh…"))
                        .font(AppFont.secondary)
                        .foregroundStyle(.secondary)
                }
            }
            if let error = model.skillsShError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(AppFont.secondary)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack {
                Text(L10n.tr("目录结果"))
                    .font(AppFont.heading)
                Spacer()
                if !model.skillsShResults.isEmpty {
                    Text(L10n.tr("\(model.skillsShResults.count) 个结果"))
                        .font(AppFont.secondary.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            resultList
        }
        .appControls()
        .padding(26)
        .frame(minWidth: 720, idealWidth: 820, minHeight: 560, idealHeight: 680)
        .interactiveDismissDisabled(model.isWorking)
        .confirmationDialog(
            L10n.tr("从技能库移除 \(pendingUninstall?.name ?? "")？"),
            isPresented: Binding(
                get: { pendingUninstall != nil },
                set: { if !$0 { pendingUninstall = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingUninstall
        ) { hit in
            Button(L10n.tr("移除"), role: .destructive) {
                model.uninstallSkillsSh(hit)
                pendingUninstall = nil
            }
            Button(L10n.tr("先不移除"), role: .cancel) { pendingUninstall = nil }
        } message: { _ in
            Text(L10n.tr("技能将从技能库移除；历史版本、来源记录和已写入项目的文件会保留。"))
        }
    }

    @ViewBuilder
    private var resultList: some View {
        if model.skillsShResults.isEmpty && !model.isSearchingSkillsSh {
            EmptyState(
                icon: "sparkle.magnifyingglass",
                title: trimmedQuery.count < 2 ? L10n.tr("搜索技能目录") : L10n.tr("没有匹配的技能"),
                detail: trimmedQuery.count < 2
                    ? L10n.tr("输入技能名称或关键词，例如 react、review、design。")
                    : L10n.tr("换一个关键词，或到 skills.sh 查看完整目录。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.skillsShResults) { hit in
                        resultRow(hit)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func resultRow(_ hit: SkillsShHit) -> some View {
        let installed = model.installedSkillsShEntry(for: hit)
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(hit.name)
                        .font(AppFont.body.weight(.semibold))
                        .lineLimit(1)
                    if installed != nil {
                        StatusBadge(text: L10n.tr("已在技能库"), tone: .positive)
                    }
                    if hit.repositoryURL == nil {
                        StatusBadge(text: L10n.tr("仅目录展示"), tone: .warning)
                    }
                }
                Text(hit.source)
                    .font(AppFont.metadata.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Text(L10n.tr("\(hit.installs) 次安装"))
                        .font(AppFont.metadata)
                    if let url = hit.pageURL {
                        Link(destination: url) {
                            Label(L10n.tr("在 skills.sh 查看"), systemImage: "arrow.up.right.square")
                                .font(AppFont.secondary)
                        }
                        .accessibilityIdentifier("skills.sh.page.\(hit.id)")
                    }
                }
                .foregroundStyle(.secondary)
                if hit.repositoryURL == nil {
                    Text(L10n.tr("目录没有提供可用的 GitHub 仓库；请前往 skills.sh 查看安装说明。"))
                        .font(AppFont.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            resultActions(hit, installed: installed)
                .frame(minWidth: 150, alignment: .trailing)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(AppColor.border, lineWidth: 1)
        }
        .accessibilityIdentifier("skills.sh.result.\(hit.id)")
    }

    @ViewBuilder
    private func resultActions(_ hit: SkillsShHit, installed: SkillEntry?) -> some View {
        if let installed {
            HStack(spacing: 8) {
                Button(L10n.tr("在技能库查看")) {
                    dismiss()
                    model.showLibrarySkill(installed.id)
                }
                .disabled(model.isWorking)
                Button(L10n.tr("移除"), role: .destructive) {
                    pendingUninstall = hit
                }
                .disabled(model.isWorking)
                .accessibilityIdentifier("skills.sh.uninstall.\(hit.id)")
            }
        } else if hit.repositoryURL != nil {
            VStack(alignment: .trailing, spacing: 7) {
                Button {
                    Task { _ = await model.installSkillsSh(hit) }
                } label: {
                    if model.installingSkillsShID == hit.id {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(L10n.tr("正在加入技能库…"))
                        }
                    } else {
                        Label(L10n.tr("加入技能库"), systemImage: "arrow.down.to.line")
                    }
                }
                .buttonStyle(AppButtonStyle(kind: .primary))
                .disabled(model.isWorking)
                .accessibilityIdentifier("skills.sh.install.\(hit.id)")
                Text(L10n.tr("复制来源的当前版本"))
                    .font(AppFont.metadata)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(L10n.tr("需在 skills.sh 查看安装方式"))
                .font(AppFont.secondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
