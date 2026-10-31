import SwiftUI
import SkillSetCore

struct TemplateUseSheet: View {
    @Bindable var model: AppModel
    let template: TemplateRecord
    @Environment(\.dismiss) private var dismiss
    @State private var isGlobal = false
    @State private var projectID = ""
    @State private var host: MCPHost = .codex
    @State private var preview: TemplateUsePreview?
    @State private var previewError: String?

    private var target: TemplateUseTarget { isGlobal ? .global(host) : .project(projectID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("使用片段")).font(AppFont.title)
            Text(UserFacingText.templateTitle(template)).font(AppFont.heading)
            AppSegmentedPicker(title: L10n.tr("使用范围"), selection: $isGlobal,
                options: [(false, L10n.tr("项目")), (true, L10n.tr("全局配置"))])
            .accessibilityIdentifier("templates.use.scope")
            if isGlobal {
                AppPicker(title: L10n.tr("AI 工具"), selection: $host, valueLabel: host.displayName) {
                    ForEach(MCPHost.allCases) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("templates.use.host")
                Label(L10n.tr("影响所选 AI 工具的全部项目。"), systemImage: "globe")
                    .font(AppFont.secondary).foregroundStyle(.orange)
            } else if model.projects.isEmpty {
                Text(L10n.tr("请先添加项目目录，再使用片段。"))
                Button(L10n.tr("前往项目")) { model.section = .projects; dismiss() }
            } else {
                AppPicker(title: L10n.tr("目标项目"), selection: $projectID,
                          valueLabel: model.projects.first { $0.id == projectID }?.name ?? "") {
                    ForEach(model.projects) { Text($0.name).tag($0.id) }
                }
                .accessibilityIdentifier("templates.use.project")
                if let project = model.projects.first(where: { $0.id == projectID }) {
                    AppPicker(title: L10n.tr("目标 AI 工具"), selection: Binding(
                        get: { project.editingAgent },
                        set: {
                            model.selectProjectHost($0 == "codex" ? .codex : .claude, projectID: projectID)
                            refresh()
                        }
                    ), valueLabel: project.editingAgentName) {
                        Text("Codex").tag("codex")
                        Text("Claude Code").tag("claude-code")
                    }
                    .accessibilityIdentifier("templates.use.projectHost")
                }
            }
            if let preview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.tr("规则文件")).font(AppFont.heading)
                        ForEach(preview.paths, id: \.self) { Text($0).font(AppFont.code).textSelection(.enabled) }
                        Text(L10n.tr("\(preview.skillCount) 个技能 · \(preview.instructionIDs.count) 个片段"))
                            .font(AppFont.secondary).foregroundStyle(.secondary)
                        Text(L10n.tr("预览包含这份草稿所选技能和全部片段的变更；插件和 MCP 服务需分别预览。"))
                            .font(AppFont.secondary).foregroundStyle(.secondary)
                        Divider()
                        Text(L10n.tr("合成后的规则正文")).font(AppFont.heading)
                        Text(preview.body).font(AppFont.code).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            if let error = model.templateError ?? previewError {
                Text(L10n.text(error)).font(AppFont.secondary).foregroundStyle(.red).textSelection(.enabled)
                    .accessibilityIdentifier("templates.use.error")
            }
            Text(L10n.tr("加入草稿后，核对变更并批准写入。关闭预览会保留草稿，规则文件保持不变。"))
                .font(AppFont.secondary).foregroundStyle(.secondary)
            HStack {
                Button(L10n.tr("取消")) { model.templateError = nil; dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.tr("刷新预览")) { refresh() }
                Button(L10n.tr("加入草稿并预览…")) {
                    if let preview { _ = model.prepareTemplateUse(templateID: template.id, target: target, preview: preview) }
                }
                .buttonStyle(AppButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
                .disabled(preview == nil || model.isWorking)
                .accessibilityIdentifier("templates.use.preview")
            }
        }
        .appControls().padding(24)
        .frame(width: 680, height: 620)
        .onAppear {
            projectID = model.projects.contains(where: { $0.id == model.selectedProjectID })
                ? model.selectedProjectID : model.projects.first?.id ?? ""
            refresh()
        }
        .onChange(of: target) { _, _ in refresh() }
    }

    private func refresh() {
        preview = nil
        previewError = nil
        model.templateError = nil
        guard isGlobal || !projectID.isEmpty else { return }
        do { preview = try model.templateUsePreview(templateID: template.id, target: target) }
        catch TemplateUsePreviewError.noHosts { previewError = "项目草稿尚未选择 AI 工具，请先到项目页选择 Codex 或 Claude Code，再使用片段。" }
        catch { previewError = UserFacingText.error(error) }
    }
}
