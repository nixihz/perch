import SwiftUI

struct AIAccessView: View {
    @Bindable var model: AppModel

    private var tools: [MCPToolPresentation] { [
        MCPToolPresentation(name: "projects_list", purpose: L10n.tr("列出已登记项目"), access: L10n.tr("只读")),
        MCPToolPresentation(name: "skills_search", purpose: L10n.tr("按来源、内容指纹和完整性搜索"), access: L10n.tr("只读")),
        MCPToolPresentation(name: "sources_list", purpose: L10n.tr("列出已保存的隔离预览"), access: L10n.tr("只读")),
        MCPToolPresentation(name: "sources_preview", purpose: L10n.tr("隔离读取 GitHub 来源并固定 commit"), access: L10n.tr("本机缓存")),
        MCPToolPresentation(name: "projects_inspect", purpose: L10n.tr("查看 desired / observed / inherited"), access: L10n.tr("只读")),
        MCPToolPresentation(name: "deployment_plan", purpose: L10n.tr("生成可审阅变更单"), access: L10n.tr("生成本机计划")),
        MCPToolPresentation(name: "deployment_apply", purpose: L10n.tr("执行已批准计划"), access: L10n.tr("写入 · 人工批准")),
        MCPToolPresentation(name: "plans_pending", purpose: L10n.tr("列出待本机审批的计划"), access: L10n.tr("只读")),
        MCPToolPresentation(name: "operations_get", purpose: L10n.tr("查询操作、备份和恢复"), access: L10n.tr("只读")),
        MCPToolPresentation(name: "objects_verify", purpose: L10n.tr("核验项目锁引用的离线对象"), access: L10n.tr("只读")),
        MCPToolPresentation(name: "mcp_servers_list", purpose: L10n.tr("读取宿主 MCP 配置，不返回凭据"), access: L10n.tr("只读")),
        MCPToolPresentation(name: "mcp_config_plan", purpose: L10n.tr("生成 MCP 配置变更计划"), access: L10n.tr("生成本机计划"))
    ] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    eyebrow: "AI ACCESS",
                    title: L10n.tr("本应用提供的 MCP"),
                    detail: L10n.tr("这里是管理器自己的 stdio MCP，不等于宿主里的 MCP Servers。AI 可以快速准备计划，但不能凭工具参数伪造用户授权。")
                )
                HStack(alignment: .top, spacing: 18) {
                    SurfaceCard(emphasis: true) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(AppFont.title)
                                    .foregroundStyle(AppColor.accentText)
                                Text("Perch MCP")
                                    .font(AppFont.heading.weight(.bold))
                                Spacer()
                                StatusBadge(text: L10n.tr("stdio · 可用"), tone: .positive)
                            }
                            Text(L10n.tr("由本应用的 skillset 二进制按需启动；stdout 只输出 JSON-RPC，不监听 HTTP 端口。"))
                                .font(AppFont.body)
                                .foregroundStyle(.secondary)
                            Divider()
                            KeyValueLine(key: L10n.tr("连接方式"), value: "stdio")
                            KeyValueLine(key: L10n.tr("协议"), value: L10n.tr("legacy 2025-11-25 首发；modern 单独验收"))
                            KeyValueLine(key: L10n.tr("启动"), value: "skillset mcp serve --transport stdio", monospaced: true)
                            KeyValueLine(key: L10n.tr("审批"), value: L10n.tr("MCP 没有 approve 工具；必须在 App 或 CLI 批准"))
                        }
                    }
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(L10n.tr("授权链"), systemImage: "lock.shield.fill")
                                .font(AppFont.heading)
                            Text(L10n.tr("AI 请求 plan → 用户在本机 App 或 CLI 批准同一 plan digest → AI 才可调用 apply → 核心复核并写入。"))
                                .font(AppFont.secondary)
                                .foregroundStyle(.secondary)
                            Text(L10n.tr("confirmed=true、tool annotation 或自然语言“用户同意了”都不构成审批。"))
                                .font(AppFont.secondary.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L10n.tr("工具契约"))
                                .font(AppFont.heading)
                            Spacer()
                            Text(L10n.tr("\(tools.count) 个"))
                                .font(AppFont.secondary)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(tools) { tool in
                            toolRow(tool)
                        }
                    }
                }
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 9) {
                        Label(L10n.tr("兼容性边界"), systemImage: "checkmark.seal")
                            .font(AppFont.heading)
                        Text(L10n.tr("当前只实测 legacy stdio；modern、HTTP、OAuth 注册、Cross-process lock 和宿主 trust 策略仍待验证。Plugin 生命周期只调用宿主 CLI，不证明当前会话已加载或 hooks 已安全。"))
                            .font(AppFont.secondary)
                            .foregroundStyle(.secondary)
                        Button(L10n.tr("查看 MCP / Plugin 调研")) {
                            model.report("调研文件：docs/research/mcp-plugins.md")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func toolRow(_ tool: MCPToolPresentation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: tool.access == L10n.tr("只读") ? "eye" : "pencil.line")
                    .foregroundStyle(tool.access == L10n.tr("只读") ? AppColor.accentText : .orange)
                    .frame(width: 18)
                Text(tool.name)
                    .font(AppFont.secondary.monospaced())
                    .frame(width: 170, alignment: .leading)
                Text(tool.purpose)
                    .font(AppFont.secondary)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(tool.access)
                    .font(AppFont.metadata)
                    .foregroundStyle(tool.access == L10n.tr("只读") ? Color.secondary : Color.orange)
            }
            .padding(.vertical, 5)
            Divider()
        }
    }
}

private struct MCPToolPresentation: Identifiable {
    let name: String
    let purpose: String
    let access: String

    var id: String { name }
}

