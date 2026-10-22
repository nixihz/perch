import SwiftUI

/// 把领域关系变成可导航的说明；数字只来自当前本机库，不推断宿主加载状态。
struct ConfigurationMapSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                PageHeader(eyebrow: "YOUR CONFIGURATION", title: L10n.tr("每一份配置，都有来处与去处"),
                    detail: L10n.tr("从内容来源，到 AI 工具读取的文件。点击任意入口，继续完成你的配置。"))
                Spacer(minLength: 0)
                Button(L10n.tr("完成")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            Text(L10n.tr("来源 → 能力库 → 配置范围 → AI 工具"))
                .font(AppFont.body.weight(.semibold)).foregroundStyle(AppColor.accentText)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    layer("01", title: "来源", detail: "内容从哪里来", icon: "tray.and.arrow.down") {
                        destination(.sources, detail: "Git 仓库与本地技能目录")
                        destination(.plugins, detail: "完整插件包与来源记录")
                    }
                    connector("同步或收录 · 不会自动启用")
                    layer("02", title: "能力库", detail: "保存可复用的内容", icon: "square.stack") {
                        destination(.skills, detail: "\(model.snapshot.catalog.entries.count) 个技能")
                        destination(.templates, detail: "\(model.snapshot.templates.count) 个片段")
                        destination(.mcp, detail: "\(model.mcpLibrary.entries.count) 个连接配置")
                    }
                    connector("选择内容 · 保存为草稿")
                    layer("03", title: "配置", detail: "决定谁用、在哪里用", icon: "slider.horizontal.3") {
                        destination(.globalConfiguration, detail: "所选 AI 工具的全部项目")
                        destination(.projects, detail: "只配置指定项目")
                        destination(.presets, detail: "可重复载入的组合")
                    }
                    connector("预览变更 → 本机批准 → 写入文件")
                    SurfaceCard {
                        HStack(alignment: .top, spacing: 14) {
                            Text("04").font(AppFont.code).foregroundStyle(AppColor.accentText)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Codex / Claude Code").font(AppFont.heading)
                                Text(L10n.tr("技能、规则、MCP 连接和插件由所选 AI 工具读取。文件写入后，仍需在工具中确认加载。"))
                                    .font(AppFont.secondary).foregroundStyle(.secondary)
                            }
                        }
                    }
                    SurfaceCard(emphasis: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(L10n.tr("MCP 的两个方向"), systemImage: "arrow.left.arrow.right")
                                .font(AppFont.heading)
                            Text(L10n.tr("MCP 服务：AI 工具 → 外部服务。库中保存的是连接配置。"))
                            Text(L10n.tr("AI 接入：AI 工具 → 栖集。让 AI 查询能力、准备计划。"))
                            HStack {
                                Text(L10n.tr("AI 可以准备计划；批准始终由你完成。"))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(L10n.tr("配置 AI 接入")) { navigate(.aiAccess) }
                            }
                        }.font(AppFont.secondary)
                    }
                    Text(L10n.tr("插件是组合包，可包含技能、MCP、命令、Agent 和自动运行脚本；在目标配置中单独审阅。"))
                        .font(AppFont.metadata).foregroundStyle(.secondary).padding(.horizontal, 20)
                }
                .padding(2)
            }
        }
        .padding(26)
        .frame(width: 760, height: 640)
        .appControls()
        .accessibilityIdentifier("configuration.map")
    }

    private func layer<Content: View>(_ number: String, title: LocalizedText, detail: LocalizedText,
                                      icon: String, @ViewBuilder content: () -> Content) -> some View {
        SurfaceCard {
            HStack(spacing: 12) {
                Text(number).font(AppFont.code).foregroundStyle(AppColor.accentText)
                Label(L10n.tr(title), systemImage: icon).font(AppFont.heading)
                Text(L10n.tr(detail)).font(AppFont.secondary).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 10, content: content)
        }
    }

    private func destination(_ item: NavigationItem, detail: LocalizedText) -> some View {
        Button { navigate(item) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.title).font(AppFont.body.weight(.semibold))
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right").font(AppFont.metadata)
                }
                Text(L10n.tr(detail)).font(AppFont.metadata).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(10)
            .background(AppColor.controlSurface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityIdentifier("configuration.map.\(item.rawValue)")
    }

    private func connector(_ text: LocalizedText) -> some View {
        Label(L10n.tr(text), systemImage: "arrow.down")
            .font(AppFont.metadata).foregroundStyle(.secondary).padding(.leading, 20)
    }

    private func navigate(_ item: NavigationItem) {
        model.section = item
        dismiss()
    }
}
