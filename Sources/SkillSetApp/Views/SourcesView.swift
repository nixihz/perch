import AppKit
import SwiftUI
import SkillSetCore

struct SourcesView: View {
    @Bindable var model: AppModel
    @State private var sourceURL = "https://github.com/mattpocock/skills"
    @State private var sourceRef = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                eyebrow: "SOURCE REGISTRY",
                title: L10n.tr("来源与快照"),
                detail: L10n.tr("粘贴仓库链接，预览技能和对应版本。预览不运行仓库脚本，也不会收录或启用技能。")
            )

            SurfaceCard {
                HStack(spacing: 10) {
                    TextField("https://github.com/owner/repo", text: $sourceURL)
                        .textFieldStyle(.roundedBorder)
                    TextField(L10n.tr("分支或标签（可选）"), text: $sourceRef)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                    Button(L10n.tr("预览来源")) {
                        model.previewSource(urlString: sourceURL, ref: sourceRef)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColor.accent)
                    .disabled(model.isWorking || sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                HStack(spacing: 8) {
                    if model.isWorking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(AppColor.accentText)
                    }
                    Text(model.isWorking ? L10n.tr("正在下载并扫描技能，不会修改项目。") : sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L10n.tr("请先填写 GitHub 仓库链接。") : L10n.tr("请填写 HTTPS 格式的 GitHub 仓库链接；私有仓库需先通过系统 Git 登录。"))
                        .font(AppFont.secondary)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .top, spacing: AppLayout.columnSpacing) {
                sourceList
                    .frame(width: AppLayout.listWidth)
                sourceDetail
            }
        }
        .task {
            model.refreshSourcePreviews()
        }
    }

    private var sourceList: some View {
        SurfaceCard {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.tr("已登记来源"))
                        .font(AppFont.heading)
                    ForEach(model.snapshot.sources.sources) { source in
                        Button {
                            model.selectedSourceID = source.id
                            model.selectedPreviewID = nil
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: source.id == model.selectedSourceID && model.selectedPreviewID == nil ? "checkmark.seal.fill" : "circle")
                                    .foregroundStyle(source.id == model.selectedSourceID && model.selectedPreviewID == nil ? AppColor.accentText : .secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L10n.text(source.title))
                                        .font(AppFont.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(L10n.text(UserFacingText.metadata(source.kind, field: .sourceKind)))
                                        .font(AppFont.secondary)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                StatusBadge(
                                    text: source.trust == "local-owned" ? L10n.tr("本地") : L10n.tr("待审"),
                                    tone: source.trust == "local-owned" ? .positive : .warning
                                )
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 8)
                            .selectionRow(source.id == model.selectedSourceID && model.selectedPreviewID == nil)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()
                    HStack {
                        Text(L10n.tr("隔离预览"))
                            .font(AppFont.secondary.weight(.semibold))
                        Spacer()
                        Text("\(model.sourcePreviews.count)")
                            .font(AppFont.secondary.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if model.sourcePreviews.isEmpty {
                        Text(L10n.tr("还没有预览。填写上方仓库链接，点击「预览来源」。"))
                            .font(AppFont.secondary)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.sourcePreviews) { preview in
                            Button {
                                model.selectedPreviewID = preview.id
                            } label: {
                                HStack(alignment: .top, spacing: 9) {
                                    Image(systemName: preview.id == model.selectedPreviewID ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(preview.id == model.selectedPreviewID ? AppColor.accentText : .secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(preview.canonicalURL)
                                            .font(AppFont.secondary.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(L10n.tr("\(preview.resolvedCommit.prefix(12)) · \(preview.candidates.count) 候选"))
                                            .font(AppFont.metadata.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .selectionRow(preview.id == model.selectedPreviewID)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider()
                    Text(L10n.tr("研究链接"))
                        .font(AppFont.secondary.weight(.semibold))
                    Text(model.snapshot.matt.url)
                        .font(AppFont.secondary.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxHeight: 620)
        }
    }

    @ViewBuilder
    private var sourceDetail: some View {
        if let preview = model.selectedSourcePreview {
            sourcePreviewDetail(preview)
        } else if let source = model.selectedSource {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SurfaceCard(emphasis: true) {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text(L10n.text(source.title))
                                    .font(AppFont.title.weight(.bold))
                                Spacer()
                                StatusBadge(text: L10n.text(UserFacingText.metadata(source.trust, field: .trust)), tone: source.trust == "local-owned" ? .positive : .warning)
                            }
                            Text(source.origin)
                                .font(AppFont.secondary.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Divider()
                            KeyValueLine(key: L10n.tr("来源类型"), value: L10n.text(UserFacingText.metadata(source.kind, field: .sourceKind)))
                            KeyValueLine(key: L10n.tr("快照路径"), value: source.snapshotPath ?? source.path ?? L10n.tr("未提供"), monospaced: true)
                            KeyValueLine(key: L10n.tr("许可"), value: L10n.text(UserFacingText.metadata(source.licenseReview, field: .licenseReview)))
                        }
                    }
                    if let importedFrom = source.importedFrom {
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 9) {
                                Label(L10n.tr("迁移凭证"), systemImage: "arrow.triangle.2.circlepath")
                                    .font(AppFont.heading)
                                KeyValueLine(key: L10n.tr("原始路径"), value: importedFrom, monospaced: true)
                                KeyValueLine(key: L10n.tr("来源版本"), value: source.sourceCommit ?? L10n.tr("未记录"), monospaced: true)
                                if source.sourceDirty == true {
                                    StatusBadge(text: L10n.tr("原工作区有未提交改动"), tone: .warning)
                                }
                                Text(L10n.tr("这份路径只用于本仓私有迁移凭证；公开导出前需要剥离机器路径和凭据线索。"))
                                    .font(AppFont.secondary)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    mattPreview
                }
            }
        } else {
            EmptyState(icon: "arrow.down.doc", title: L10n.tr("选择一个来源"), detail: L10n.tr("选择左侧来源，查看路径、版本和许可审查状态。"))
        }
    }

    private func sourcePreviewDetail(_ preview: SourcePreviewRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SurfaceCard(emphasis: true) {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preview.canonicalURL)
                                    .font(AppFont.title.weight(.bold))
                                    .textSelection(.enabled)
                                Text(L10n.tr("固定于 \(preview.resolvedCommit.prefix(16))…"))
                                    .font(AppFont.secondary.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            StatusBadge(text: L10n.tr("仅隔离预览"), tone: .warning)
                        }
                        Divider()
                        KeyValueLine(key: L10n.tr("来源标识"), value: preview.namespace, monospaced: true)
                        KeyValueLine(key: L10n.tr("完整版本标识"), value: preview.resolvedCommit, monospaced: true)
                        KeyValueLine(key: L10n.tr("许可线索"), value: L10n.text(UserFacingText.licenseEvidence(preview.licenseEvidence)))
                        KeyValueLine(
                            key: L10n.tr("创建时间"),
                            value: L10n.date(preview.createdAt)
                        )
                        HStack {
                            Button(L10n.tr("在 Finder 中显示隔离区")) {
                                NSWorkspace.shared.activateFileViewerSelecting([
                                    URL(fileURLWithPath: preview.workspacePath, isDirectory: true)
                                ])
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                            Text(L10n.tr("未收录 · 未启用"))
                                .font(AppFont.secondary.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L10n.tr("候选分类"))
                                .font(AppFont.heading)
                            Spacer()
                            Text(L10n.tr("\(preview.candidates.count) 个 SKILL.md"))
                                .font(AppFont.secondary)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(preview.excludedCounts.sorted(by: { $0.key < $1.key }), id: \.key) { state, count in
                            HStack {
                                StatusBadge(text: stateLabel(state), tone: stateTone(state))
                                Spacer()
                                Text("\(count)")
                                    .font(AppFont.secondary.monospaced())
                            }
                        }
                        ForEach(preview.warnings, id: \.self) { warning in
                            Text(L10n.text(UserFacingText.diagnostic(warning, context: .source)))
                                .font(AppFont.secondary)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.tr("读取到的候选"))
                            .font(AppFont.heading)
                        if preview.candidates.isEmpty {
                            EmptyState(
                                icon: "doc.questionmark",
                                title: L10n.tr("没有找到 SKILL.md"),
                                detail: L10n.tr("请检查仓库链接、分支或标签，再重新预览。技能库未改变。")
                            )
                            .frame(minHeight: 180)
                        } else {
                            ForEach(preview.candidates, id: \.path) { candidate in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(candidate.declaredName)
                                            .font(AppFont.body.weight(.semibold))
                                        Text(candidate.id)
                                            .font(AppFont.metadata.monospaced())
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        StatusBadge(text: stateLabel(candidate.state.rawValue), tone: stateTone(candidate.state.rawValue))
                                    }
                                    Text(candidate.path)
                                        .font(AppFont.secondary.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                    if !candidate.description.isEmpty {
                                        Text(candidate.description)
                                            .font(AppFont.secondary)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                    }
                                    HStack {
                                        Text(candidate.contentHash.isEmpty ? L10n.tr("无内容指纹") : String(candidate.contentHash.prefix(16)) + "…")
                                            .font(AppFont.metadata.monospaced())
                                        Text(L10n.tr("· \(candidate.fileCount) 文件 · \(candidate.bytes) 字节"))
                                            .font(AppFont.metadata)
                                        Spacer()
                                    }
                                    .foregroundStyle(.secondary)
                                    ForEach(candidate.issues, id: \.self) { issue in
                                        Text(L10n.text(UserFacingText.diagnostic(issue, context: .candidate)))
                                            .font(AppFont.secondary)
                                            .foregroundStyle(.red)
                                    }
                                }
                                .padding(11)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                            }
                        }
                    }
                }
            }
        }
    }

    private var mattPreview: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.tr("Matt Pocock 固定调研快照"))
                        .font(AppFont.heading)
                    Spacer()
                    StatusBadge(text: L10n.tr("\(model.snapshot.matt.candidates.count) 候选"), tone: .accent)
                }
                KeyValueLine(key: L10n.tr("版本标识"), value: model.snapshot.matt.commit, monospaced: true)
                KeyValueLine(key: L10n.tr("版本"), value: model.snapshot.matt.version)
                KeyValueLine(key: L10n.tr("网络"), value: model.snapshot.matt.network ? L10n.tr("实时") : L10n.tr("未联网"))
                Text(L10n.tr("工程 \(model.snapshot.matt.candidates.filter { $0.category == "engineering" }.count) · 效率 \(model.snapshot.matt.candidates.filter { $0.category == "productivity" }.count) · 杂项 \(model.snapshot.matt.excluded.misc) 条未纳入"))
                    .font(AppFont.secondary)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stateLabel(_ rawValue: String) -> String {
        switch rawValue {
        case "promoted": L10n.tr("已晋级")
        case "in-progress": L10n.tr("进行中")
        case "deprecated": L10n.tr("已弃用")
        case "misc": L10n.tr("杂项")
        default: L10n.tr("其他")
        }
    }

    private func stateTone(_ rawValue: String) -> BadgeTone {
        switch rawValue {
        case "promoted": .positive
        case "in-progress": .accent
        case "deprecated": .warning
        default: .neutral
        }
    }
}
