import Foundation
import XCTest
import CucumberSwift
import SkillSetCore

extension Cucumber: @retroactive StepImplementation {
    public var bundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        class ThisBundle {}
        return Bundle(for: ThisBundle.self)
        #endif
    }

    public func setupSteps() {
        var world: BDDWorld?

        BeforeScenario { _ in
            do {
                world = try BDDWorld()
            } catch {
                XCTFail("无法创建隔离场景：\(error.localizedDescription)")
                world = nil
            }
        }

        AfterScenario { _ in
            world?.cleanup()
            world = nil
        }

        Given("使用当前仓库作为能力库存") { _, _ in
            let current = try XCTUnwrap(world)
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: current.repositoryRoot.appendingPathComponent("registry/catalog.json").path
                )
            )
        }

        Given("本机状态写入隔离的临时目录") { _, _ in
            let current = try XCTUnwrap(world)
            XCTAssertFalse(current.applicationSupportRoot.path.hasPrefix(current.repositoryRoot.path + "/"))
        }

        Given("已登记项目 {string}") { match, _ in
            let name: String = try match.first(\.string)
            try XCTUnwrap(world).registerProject(named: name)
        }

        Given("草稿选择 Skill {string}") { match, _ in
            let id: String = try match.first(\.string)
            try XCTUnwrap(world).selectSkill(id)
        }

        Given("目标 agent 为 {string}") { match, _ in
            let agent: String = try match.first(\.string)
            try XCTUnwrap(world).selectAgent(agent)
        }

        Given("宿主 {string} 单独选择技能 {string}") { match, _ in
            try XCTUnwrap(world).selectHarnessSkill(agent: match[\.string, index: 0], skillID: match[\.string, index: 1])
        }

        When("生成独立宿主部署计划") { _, _ in
            try XCTUnwrap(world).makeIndependentHarnessPlan()
        }

        When("仅预览宿主 {string} 的变更") { match, _ in
            try XCTUnwrap(world).makeSingleHarnessPlan(match.first(\.string))
        }

        When("清空宿主 {string} 的技能选择") { match, _ in
            try XCTUnwrap(world).clearHarness(match.first(\.string))
        }

        When("记录项目文件 {string} 的内容") { match, _ in
            try XCTUnwrap(world).recordProjectFile(match.first(\.string))
        }

        Then("项目文件 {string} 保持已记录的内容") { match, _ in
            XCTAssertTrue(try XCTUnwrap(world).recordedProjectFileUnchanged(match.first(\.string)))
        }

        Given("项目文件 {string} 内容为 {string}") { match, _ in
            let path = match[\.string, index: 0]
            let content = match[\.string, index: 1]
            try XCTUnwrap(world).writeProjectFile(path, content: content)
        }

        Given("远端来源不可访问") { _, _ in
            try XCTUnwrap(world).configureMissingRemote()
        }

        Given("已准备两版本地 Git 来源") { _, _ in
            try XCTUnwrap(world).createLocalSourceFixture()
        }

        Given("已记录库存与项目快照") { _, _ in
            let current = try XCTUnwrap(world)
            try current.captureInventorySnapshot()
            try current.captureProjectSnapshot()
        }

        Given("Claude 项目 MCP 配置包含未知字段") { _, _ in
            try XCTUnwrap(world).writeClaudeMCPConfigurationWithUnknownFields()
        }

        Given("本机只有含 hook 的 Claude Plugin 缓存 {string}") { match, _ in
            let pluginID = try match.first(\.string)
            XCTAssertEqual(pluginID, "risky@demo")
            try XCTUnwrap(world).createCachedRiskyClaudePlugin()
        }

        Given("本机已安装并启用 Claude Plugin {string}") { match, _ in
            let pluginID = try match.first(\.string)
            XCTAssertEqual(pluginID, "sample@demo")
            try XCTUnwrap(world).createInstalledClaudePlugin(enabled: true)
        }

        Given("本机已安装并停用 Claude Plugin {string}") { match, _ in
            let pluginID = try match.first(\.string)
            XCTAssertEqual(pluginID, "sample@demo")
            try XCTUnwrap(world).createInstalledClaudePlugin(enabled: false)
        }

        Given("原生界面已准备含 hook 的 Plugin 缓存") { _, _ in
            try XCTUnwrap(world).prepareNativeUIPluginFixture()
        }

        Given("项目受管 skills 目录不可读") { _, _ in
            try XCTUnwrap(world).restrictProjectSkillsDirectory()
        }

        Given("原生界面已启动") { _, _ in
            guard NativeUIHarness.canRunInCurrentEnvironment else {
                throw XCTSkip(NativeUIHarness.unavailableReason)
            }
            try XCTUnwrap(world).launchNativeUI()
        }

        When("生成部署计划") { _, _ in
            try XCTUnwrap(world).makePlan()
        }

        When("尝试生成部署计划") { _, _ in
            try XCTUnwrap(world).attemptMakePlan()
        }

        When("批准当前计划") { _, _ in
            try XCTUnwrap(world).approvePlan()
        }

        When("执行部署计划") { _, _ in
            try XCTUnwrap(world).applyPlan()
        }

        When("在未批准时执行计划") { _, _ in
            try XCTUnwrap(world).attemptApplyPlan()
        }

        When("在已批准时执行计划") { _, _ in
            try XCTUnwrap(world).attemptApplyPlan()
        }

        When("修改项目文件 {string} 为 {string}") { match, _ in
            let path = match[\.string, index: 0]
            let content = match[\.string, index: 1]
            try XCTUnwrap(world).writeProjectFile(path, content: content)
        }

        When("预览来源 {string}") { match, _ in
            let url = try match.first(\.string)
            try XCTUnwrap(world).preview(urlString: url)
        }

        When("尝试预览来源 {string}") { match, _ in
            let url = try match.first(\.string)
            try XCTUnwrap(world).attemptPreview(urlString: url)
        }

        When("以 ref {string} 预览来源 {string}") { match, _ in
            let ref = match[\.string, index: 0]
            let url = match[\.string, index: 1]
            try XCTUnwrap(world).preview(urlString: url, ref: ref)
        }

        When("将标签 {string} 移到第二版") { match, _ in
            let tag = try match.first(\.string)
            XCTAssertEqual(tag, "v1")
            try XCTUnwrap(world).moveSourceTagToSecondCommit()
        }

        When("尝试以 URL {string} 生成 MCP 配置计划") { match, _ in
            let url = try match.first(\.string)
            try XCTUnwrap(world).attemptMakeMCPConfigPlan(
                name: "remote",
                transport: "streamable-http",
                commandOrURL: url
            )
        }

        When("尝试以环境变量名称 {string} 生成 MCP 配置计划") { match, _ in
            let key = try match.first(\.string)
            try XCTUnwrap(world).attemptMakeMCPConfigPlan(
                name: "skillset",
                commandOrURL: "skillset",
                envKeys: [key]
            )
        }

        When("生成项目 MCP 配置计划，名称为 {string}，使用环境变量 {string}") { match, _ in
            let name = match[\.string, index: 0]
            let key = match[\.string, index: 1]
            try XCTUnwrap(world).makeMCPConfigPlan(
                name: name,
                commandOrURL: "/opt/skillset",
                args: ["mcp", "serve"],
                envKeys: [key]
            )
        }

        When("生成 Plugin {string} 的 {string} 计划") { match, _ in
            let pluginID = match[\.string, index: 0]
            let action = match[\.string, index: 1]
            try XCTUnwrap(world).makePluginLifecyclePlan(
                pluginID: pluginID,
                action: action
            )
        }

        When("尝试生成 Plugin {string} 的 {string} 计划") { match, _ in
            let pluginID = match[\.string, index: 0]
            let action = match[\.string, index: 1]
            try XCTUnwrap(world).attemptMakePluginLifecyclePlan(
                pluginID: pluginID,
                action: action
            )
        }

        When("在计划后停用 Plugin {string}") { match, _ in
            let pluginID = try match.first(\.string)
            XCTAssertEqual(pluginID, "sample@demo")
            try XCTUnwrap(world).changeInstalledPluginEnabledState(false)
        }

        When("聚焦侧栏并按向下方向键") { _, _ in
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            try nativeUI.focusSidebar()
            try nativeUI.pressDownArrow()
        }

        When("按 Command-3") { _, _ in
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            try nativeUI.pressCommandThree()
        }

        When("按 Command-2") { _, _ in
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            try nativeUI.pressCommandTwo()
        }

        When("在原生界面预览变更") { _, _ in
            try XCTUnwrap(world).previewNativeUIPlan()
        }

        When("按 Escape 取消原生界面的计划") { _, _ in
            try XCTUnwrap(world).cancelNativeUIPlan()
        }

        When("在原生界面选择 {string}") { match, _ in
            let title = try match.first(\.string)
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            try nativeUI.selectSidebarItem(title)
        }

        When("在原生界面点击按钮 {string}") { match, _ in
            let label = try match.first(\.string)
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            try nativeUI.pressButton(label)
        }

        When("在原生界面点击标题文字 {string}") { match, _ in
            let title = try match.first(\.string)
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            try nativeUI.clickDisclosureLabel(title: title, identifier: "skills.details")
        }

        When("在原生界面点击技能详情标题右侧的空白") { _, _ in
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            try nativeUI.clickDisclosureWhitespace(title: "详细信息", identifier: "skills.details")
        }

        When("在原生界面搜索 {string}") { match, _ in
            let query = try match.first(\.string)
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            try nativeUI.setText(fieldMatching: "搜索技能", to: query)
        }

        When("在原生界面展开 {string}") { match, _ in
            try XCTUnwrap(world?.nativeUI).expandDisclosure(match.first(\.string))
        }

        When("在原生界面打开 MCP 配置表单") { _, _ in
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            try nativeUI.pressButton("添加 MCP 服务")
            try nativeUI.waitForStaticText("编辑 MCP 服务")
        }

        When("在原生界面填写 MCP 字段 {string} 为 {string}") { match, _ in
            let field = match[\.string, index: 0]
            let value = match[\.string, index: 1]
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            try nativeUI.setText(fieldMatching: field, to: value)
        }

        When("提交原生 MCP 配置表单") { _, _ in
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            try nativeUI.pressButton("保存到配置库")
        }

        When("勾选原生界面的复选框 {string}") { match, _ in
            let text = try match.first(\.string)
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            try nativeUI.toggleCheckbox(containing: text)
        }

        When("在原生界面生成 Plugin 安装计划") { _, _ in
            try XCTUnwrap(world).generateNativeUIPluginPlan()
        }

        When("在原生界面请求批准") { _, _ in
            try XCTUnwrap(world).requestNativeUIPlanApproval()
        }

        When("在原生界面按 Escape 返回审阅") { _, _ in
            try XCTUnwrap(world).returnToNativeUIReview()
        }

        Then("计划状态为 {string}") { match, _ in
            let expected: String = try match.first(\.string)
            XCTAssertEqual(try XCTUnwrap(world).planStatusLabel(), expected)
        }

        Then("操作失败，错误码为 {string}") { match, _ in
            let expected: String = try match.first(\.string)
            XCTAssertEqual(try XCTUnwrap(world).actionErrorCode(), expected)
        }

        Then("错误信息不包含 {string}") { match, _ in
            let forbidden = try match.first(\.string)
            XCTAssertFalse(try XCTUnwrap(world).actionErrorMessage().contains(forbidden))
        }

        Then("项目路径 {string} 存在") { match, _ in
            let path: String = try match.first(\.string)
            XCTAssertTrue(try XCTUnwrap(world).projectPathExists(path))
        }

        Then("项目路径 {string} 不存在") { match, _ in
            let path: String = try match.first(\.string)
            XCTAssertFalse(try XCTUnwrap(world).projectPathExists(path))
        }

        Then("项目文件 {string} 内容为 {string}") { match, _ in
            let path = match[\.string, index: 0]
            let expected = match[\.string, index: 1]
            XCTAssertEqual(try XCTUnwrap(world).projectFileContent(path), expected)
        }

        Then("项目文件 {string} 包含受管块") { match, _ in
            let path: String = try match.first(\.string)
            XCTAssertTrue(
                try XCTUnwrap(world).projectFileContent(path)
                    .contains(ManagedBlocks.beginMarker(id: "project-rules"))
            )
        }

        Then("项目锁状态为 {string}") { match, _ in
            let expected: String = try match.first(\.string)
            XCTAssertEqual(try XCTUnwrap(world).projectLockStatus(), expected)
        }

        Then("保存的来源预览为 {int} 个") { match, _ in
            let expected = try match.first(\.int)
            XCTAssertEqual(try XCTUnwrap(world).savedPreviewCount(), expected)
        }

        Then("隔离预览目录为 {int} 个") { match, _ in
            let expected = try match.first(\.int)
            XCTAssertEqual(try XCTUnwrap(world).previewDirectoryCount(), expected)
        }

        Then("预览候选为 {int} 个") { match, _ in
            let expected = try match.first(\.int)
            XCTAssertEqual(try XCTUnwrap(world).previewCandidateCount(), expected)
        }

        Then("预览 commit 等于第一版 commit") { _, _ in
            let current = try XCTUnwrap(world)
            XCTAssertEqual(
                try current.previewResolvedCommit(),
                try XCTUnwrap(current.firstSourceCommit)
            )
        }

        Then("隔离区文件 {string} 包含 {string}") { match, _ in
            let path = match[\.string, index: 0]
            let expected = match[\.string, index: 1]
            XCTAssertTrue(
                try XCTUnwrap(world).previewWorkspaceContent(path).contains(expected)
            )
        }

        Then("重新读取的来源预览 commit 仍等于第一版 commit") { _, _ in
            let current = try XCTUnwrap(world)
            XCTAssertEqual(
                try current.savedPreviewResolvedCommit(),
                try XCTUnwrap(current.firstSourceCommit)
            )
        }

        Then("重新读取的隔离区文件 {string} 包含 {string}") { match, _ in
            let path = match[\.string, index: 0]
            let expected = match[\.string, index: 1]
            XCTAssertTrue(
                try XCTUnwrap(world).savedPreviewWorkspaceContent(path).contains(expected)
            )
        }

        Then("隔离预览目录位于应用隔离数据") { _, _ in
            XCTAssertTrue(try XCTUnwrap(world).previewWorkspaceIsIsolated())
        }

        Then("库存快照未改变") { _, _ in
            XCTAssertTrue(try XCTUnwrap(world).inventoryUnchanged())
        }

        Then("新来源未进入 catalog") { _, _ in
            XCTAssertFalse(try XCTUnwrap(world).catalogContains("bdd-owner-skills/alpha"))
        }

        Then("项目目录未改变") { _, _ in
            XCTAssertTrue(try XCTUnwrap(world).projectDirectoryUnchanged())
        }

        Then("已保存的 MCP 配置计划为 {int} 个") { match, _ in
            let expected = try match.first(\.int)
            XCTAssertEqual(try XCTUnwrap(world).mcpConfigPlanCount(), expected)
        }

        Then("MCP Server {string} 存在") { match, _ in
            let name = try match.first(\.string)
            XCTAssertTrue(try XCTUnwrap(world).mcpServerExists(name))
        }

        Then("MCP 配置保留外部未知字段") { _, _ in
            XCTAssertTrue(try XCTUnwrap(world).mcpConfigurationPreservesUnknownFields())
        }

        Then("MCP Server {string} 的环境变量 {string} 使用引用") { match, _ in
            let server = match[\.string, index: 0]
            let key = match[\.string, index: 1]
            XCTAssertEqual(
                try XCTUnwrap(world).mcpEnvironmentReference(server: server, key: key),
                "${\(key)}"
            )
        }

        Then("Plugin 生命周期计划为 {int} 个") { match, _ in
            let expected = try match.first(\.int)
            XCTAssertEqual(try XCTUnwrap(world).pluginLifecyclePlanCount(), expected)
        }

        Then("Plugin 操作记录为 {int} 个") { match, _ in
            let expected = try match.first(\.int)
            XCTAssertEqual(try XCTUnwrap(world).pluginOperationCount(), expected)
        }

        Then("宿主进程调用为 {int} 次") { match, _ in
            let expected = try match.first(\.int)
            XCTAssertEqual(try XCTUnwrap(world).pluginHostInvocationCount(), expected)
        }

        Then("当前侧栏选中 {string}") { match, _ in
            let expected = try match.first(\.string)
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            XCTAssertTrue(
                try nativeUI.sidebarSelection().hasPrefix(expected),
                "当前侧栏选中项不是 \(expected)"
            )
        }

        Then("原生界面显示展开入口 {string}") { match, _ in
            let title = try match.first(\.string)
            try XCTUnwrap(world?.nativeUI).waitForDisclosure(title)
        }

        Then("原生界面尚未写入 Codex MCP 配置") { _, _ in
            XCTAssertFalse(try XCTUnwrap(world?.nativeUI).hasCodexMCPConfiguration())
        }

        Then("原生界面显示文案 {string}") { match, _ in
            let expected = try match.first(\.string)
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            try nativeUI.waitForStaticText(expected)
            XCTAssertTrue(try nativeUI.hasStaticText(expected), "缺少文案：\(expected)")
        }

        Then("原生界面显示标题 {string}") { match, _ in
            let expected = try match.first(\.string)
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            try nativeUI.waitForStaticText(expected)
            XCTAssertTrue(try nativeUI.hasStaticText(expected), "缺少标题：\(expected)")
        }

        Then("原生界面显示含文案 {string}") { match, _ in
            let expected = try match.first(\.string)
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            try nativeUI.waitForStaticText(containing: expected)
        }

        Then("原生界面不显示文案 {string}") { match, _ in
            let forbidden = try match.first(\.string)
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            XCTAssertFalse(try nativeUI.hasStaticText(forbidden), "不应显示文案：\(forbidden)")
        }

        Then("搜索字段提示为 {string}") { match, _ in
            let expected = try match.first(\.string)
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            XCTAssertEqual(try nativeUI.searchPlaceholder(), expected)
        }

        Then("原生界面显示可用按钮 {string}") { match, _ in
            let expected = try match.first(\.string)
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            XCTAssertTrue(
                try nativeUI.hasEnabledButton(expected),
                "缺少可用按钮：\(expected)"
            )
        }

        Then("原生界面显示不可用按钮 {string}") { match, _ in
            let expected = try match.first(\.string)
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            XCTAssertFalse(
                try nativeUI.buttonIsEnabled(expected),
                "按钮不应可用：\(expected)"
            )
        }

        Then("原生界面的复选框 {string} 未勾选") { match, _ in
            let text = try match.first(\.string)
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            XCTAssertFalse(try nativeUI.checkboxIsChecked(containing: text))
        }

        Then("原生界面的复选框 {string} 已勾选") { match, _ in
            let text = try match.first(\.string)
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            XCTAssertTrue(try nativeUI.checkboxIsChecked(containing: text))
        }

        Then("原生界面显示确认对话框 {string}") { match, _ in
            let title = try match.first(\.string)
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            XCTAssertTrue(try nativeUI.confirmationAlertPresent(), "缺少二次确认对话框")
            try nativeUI.waitForStaticText(title)
        }

        Then("原生确认说明包含当前计划的项目路径") { _, _ in
            let current = try XCTUnwrap(world)
            let path = try XCTUnwrap(current.currentPlan).plan.projectPath
            XCTAssertTrue(
                try XCTUnwrap(current.nativeUI).nonEditableTextContains(path),
                "二次确认没有说明项目路径"
            )
        }

        Then("原生确认说明包含当前计划的变更数量") { _, _ in
            let current = try XCTUnwrap(world)
            let count = try XCTUnwrap(current.currentPlan).plan.changes.count
            XCTAssertTrue(
                try XCTUnwrap(current.nativeUI).nonEditableTextContains("\(count) 项内容"),
                "二次确认没有说明变更数量"
            )
        }

        Then("原生界面显示当前计划的项目路径") { _, _ in
            let current = try XCTUnwrap(world)
            let record = try XCTUnwrap(current.currentPlan)
            XCTAssertTrue(
                try XCTUnwrap(current.nativeUI).hasStaticText(record.plan.projectPath),
                "计划 sheet 没有显示项目路径"
            )
        }

        Then("原生界面显示当前计划 digest") { _, _ in
            let current = try XCTUnwrap(world)
            let record = try XCTUnwrap(current.currentPlan)
            XCTAssertTrue(
                try XCTUnwrap(current.nativeUI).hasStaticText(record.plan.digest),
                "计划 sheet 没有显示完整 digest"
            )
        }

        Then("原生界面显示当前计划的第一项变更明细") { _, _ in
            let current = try XCTUnwrap(world)
            let change = try XCTUnwrap(try XCTUnwrap(current.currentPlan).plan.changes.first)
            let nativeUI = try XCTUnwrap(current.nativeUI)
            XCTAssertTrue(try nativeUI.hasStaticText(change.relativePath), "缺少变更路径")
            XCTAssertTrue(
                try nativeUI.hasStaticText(
                    "旧 \(change.beforeHash ?? "不存在") · 新 \(change.afterHash ?? "删除")"
                ),
                "缺少第一项变更的旧/新 hash"
            )
        }

        Then("原生界面已关闭变更计划 sheet") { _, _ in
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            try nativeUI.waitForNoSheet()
            XCTAssertFalse(try nativeUI.sheetPresent())
        }

        Then("原生界面已关闭确认对话框") { _, _ in
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            XCTAssertFalse(try nativeUI.confirmationAlertPresent())
        }

        Then("原生界面仍显示变更计划 sheet") { _, _ in
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            XCTAssertTrue(try nativeUI.sheetPresent())
            XCTAssertTrue(try nativeUI.hasStaticText("变更计划"))
        }

        Then("原生界面焦点仍在侧栏") { _, _ in
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            XCTAssertTrue(try nativeUI.focusIsSidebar())
        }

        Then("原生界面保存的部署计划为 {int} 个") { match, _ in
            let expected = try match.first(\.int)
            XCTAssertEqual(try XCTUnwrap(world).nativeUIPlanCount(), expected)
        }

        Then("原生界面登记的项目为 {int} 个") { match, _ in
            let expected = try match.first(\.int)
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            XCTAssertEqual(try ProjectStore(rootURL: nativeUI.applicationSupportRoot).list().count, expected)
        }

        Then("原生界面的计划 digest 未改变") { _, _ in
            XCTAssertTrue(try XCTUnwrap(world).nativeUIPlanDigestUnchanged())
        }

        Then("原生界面的非编辑文本不包含 {string}") { match, _ in
            let forbidden = try match.first(\.string)
            let nativeUI = try XCTUnwrap(try XCTUnwrap(world).nativeUI)
            XCTAssertFalse(
                try nativeUI.nonEditableTextContains(forbidden),
                "非编辑文本泄露了凭据值"
            )
        }

        Then("原生界面保存的 MCP 配置计划为 {int} 个") { match, _ in
            let expected = try match.first(\.int)
            XCTAssertEqual(
                try XCTUnwrap(world).nativeUIPlanCount(type: "mcp-configuration"),
                expected
            )
        }

        Then("原生界面保存的 Plugin 计划为 {int} 个") { match, _ in
            let expected = try match.first(\.int)
            XCTAssertEqual(
                try XCTUnwrap(world).nativeUIPlanCount(type: "plugin-lifecycle"),
                expected
            )
        }

        Then("原生界面宿主进程调用为 {int} 次") { match, _ in
            let expected = try match.first(\.int)
            XCTAssertEqual(
                try XCTUnwrap(world).nativeUIPluginHostInvocationCount(),
                expected
            )
        }
    }
}
