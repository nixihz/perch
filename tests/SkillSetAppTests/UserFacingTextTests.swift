import Foundation
import Darwin
import XCTest
import SkillSetCore
@testable import SkillSetApp

final class UserFacingTextTests: XCTestCase {
    func testLinkedFolderErrorsNameTheAffectedToolAndKeepInternalPathsOutOfTheMessage() {
        for (path, tool) in [("/local/project/.claude/skills", "Claude Code"), ("/local/project/.agents/skills", "Codex")] {
            let message = UserFacingText.error(DeploymentError.symlinkDetected(path))
            XCTAssertTrue(message.contains(tool))
            XCTAssertTrue(message.contains("独立文件夹"))
            XCTAssertFalse(message.contains("安全检查"))
            XCTAssertFalse(message.contains(path))
        }
        XCTAssertTrue(UserFacingText.error(DeploymentError.symlinkDetected("/local/project/.agents/skills/demo"))
            .contains("先移走这个链接"))
        XCTAssertTrue(UserFacingText.isInformationalProjectNote(".claude/skills：父目录是软链，未扫描。"))
        XCTAssertFalse(UserFacingText.isInformationalProjectNote(".claude/skills：读取失败。"))
        XCTAssertTrue(UserFacingText.diagnostic(".claude/skills：父目录是软链，未扫描。", context: .project).contains("Claude Code"))
    }

    func testMissingPlanPointsBackToPreviewWithoutShowingInternalIdentifier() {
        let error = DeploymentPlanStoreError.planNotFound("private-plan-123")
        let message = UserFacingText.error(error)
        XCTAssertTrue(message.contains("重新预览"))
        XCTAssertFalse(message.contains("private-plan-123"))
        XCTAssertFalse(message.contains("PLAN_NOT_FOUND"))
    }

    func testMissingOrCorruptSavedSkillOffersSourceRecoveryWithoutEchoingDetails() {
        let errors: [SkillObjectStoreError] = [
            .objectMissing("private-digest-123"),
            .objectCorrupt("private-digest-123")
        ]
        for error in errors {
            let message = UserFacingText.error(error)
            XCTAssertTrue(message.contains("技能版本"))
            XCTAssertTrue(message.contains("从来源重新加入"))
            XCTAssertFalse(message.contains("private-digest-123"))
            XCTAssertFalse(message.contains("OFFLINE_OBJECT"))
        }
    }

    @MainActor
    func testPlanSummariesExplainChangesWithoutRewritingActualDiffsOrPaths() {
        let previousLanguage = AppPreferences.shared.language
        AppPreferences.shared.language = .chinese
        defer { AppPreferences.shared.language = previousLanguage }

        let summaries = PlannedChange(
            action: "update", relativePath: "AGENTS.md", beforeHash: "old", afterHash: "new",
            unifiedDiff: "替换受管块 project-rules\n移除未漂移的受管技能 .agents/skills/review；操作备份可用于撤销"
        )
        let presented = UserFacingText.planSummary(summaries)
        XCTAssertTrue(presented.contains("更新栖集维护的规则 project-rules"))
        XCTAssertTrue(presented.contains(".agents/skills/review"))
        XCTAssertTrue(presented.contains("操作备份恢复"))
        XCTAssertFalse(presented.contains("受管"))

        let rawDiff = "--- a/AGENTS.md\n+++ b/AGENTS.md\n-用户原文：受管块\n+用户原文：受管块 100% 保留"
        let actualChange = PlannedChange(
            action: "update", relativePath: "AGENTS.md", beforeHash: "old", afterHash: "new",
            unifiedDiff: rawDiff
        )
        XCTAssertEqual(UserFacingText.planSummary(actualChange), rawDiff)
    }

    func testGlobalVerificationShowsSpecificReasonAndFile() {
        let error = GlobalConfigurationError.verificationFailed(.missingReceipt, path: "/local/global/codex.json")
        let message = UserFacingText.error(error)
        XCTAssertTrue(message.contains("找不到与当前管理记录内容指纹匹配的已完成操作凭证"))
        XCTAssertTrue(message.contains("/local/global/codex.json"))
        XCTAssertFalse(message.contains("已有文件保持不变"))
    }

    func testMCPStatusKeepsOwnershipSeparateFromLoadingAndRejectsUnknownInput() {
        let managed = UserFacingText.mcpState("管理器受管")
        let existing = UserFacingText.mcpState("仅观察")
        XCTAssertTrue(managed.contains("栖集"))
        XCTAssertFalse(managed.contains("已加载"))
        XCTAssertTrue(existing.contains("已有配置"))
        XCTAssertFalse(existing.contains("栖集"))

        let unknown = UserFacingText.mcpState("loaded successfully private-token-123")
        XCTAssertTrue(unknown.contains("待检查"))
        XCTAssertFalse(unknown.contains("private-token"))
        XCTAssertFalse(unknown.contains("已加载"))
    }

    func testSystemErrorsOfferRecoveryWithoutEchoingUnderlyingText() {
        let secret = "private-token-123"
        let denied = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoPermissionError,
            userInfo: [NSLocalizedDescriptionKey: "Permission denied \(secret)"]
        )
        let diskFull = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteOutOfSpaceError,
            userInfo: [NSLocalizedDescriptionKey: "No space left \(secret)"]
        )
        let unknown = NSError(domain: "ThirdPartySDK", code: 123,
                              userInfo: [NSLocalizedDescriptionKey: "HTTP 500 \(secret)"])
        XCTAssertTrue(UserFacingText.error(denied).contains("权限"))
        XCTAssertTrue(UserFacingText.error(diskFull).contains("空间"))
        for error in [denied, diskFull, unknown] {
            let message = UserFacingText.error(error)
            XCTAssertFalse(message.contains(secret))
            XCTAssertFalse(message.contains(error.localizedDescription))
            XCTAssertTrue(message.contains("请"))
        }
    }

    func testRejectedRepositoryInputIsPresentedWithoutExternalDetails() {
        let service = SourcePreviewService(previewsRoot: FileManager.default.temporaryDirectory)
        do {
            _ = try service.parseSource("https://user:private-token-123@github.com/owner/repo")
            XCTFail("含凭据的链接不应通过检查")
        } catch {
            let message = UserFacingText.error(error)
            XCTAssertTrue(message.contains("移除"))
            XCTAssertFalse(message.contains("private-token-123"))
            XCTAssertFalse(message.contains("SOURCE_"))
        }
        let failedCommand = SourcePreviewError.gitFailed("fatal: authentication failed private-token-123")
        XCTAssertTrue(UserFacingText.error(failedCommand).contains("访问权限"))
        XCTAssertFalse(UserFacingText.error(failedCommand).contains("fatal"))
    }

    func testPOSIXAndNetworkFailuresKeepUsefulRecoveryAdvice() {
        let denied = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES),
                             userInfo: [NSLocalizedDescriptionKey: "private-token"])
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet,
                              userInfo: [NSLocalizedDescriptionKey: "private-token"])
        XCTAssertTrue(UserFacingText.error(denied).contains("权限"))
        XCTAssertTrue(UserFacingText.error(offline).contains("网络"))
        XCTAssertFalse(UserFacingText.error(denied).contains("private-token"))
        XCTAssertFalse(UserFacingText.error(offline).contains("private-token"))
    }

    func testOldLicenseNoticesDisappearWhileUnrelatedWarningsRemainVisible() {
        XCTAssertTrue(UserFacingText.isInformationalPlanNote("demo 仍处于 snapshotted；许可审查为 required。"))
        XCTAssertFalse(UserFacingText.isInformationalPlanNote("检测到受管技能已被删除，批准后将从技能库重新创建。"))
        XCTAssertFalse(UserFacingText.isInformationalPlanNote("demo 仍处于 snapshotted；许可审查为 required。\n文件冲突"))
        for evidence in ["MIT", "MIT · 仍需逐 skill 审查"] {
            XCTAssertEqual(UserFacingText.licenseEvidence(evidence), "MIT")
        }
        XCTAssertEqual(UserFacingText.licenseEvidence("GPL 迹象 · 需合规审查"), "GPL")
        XCTAssertEqual(UserFacingText.licenseEvidence("private-token"), "未记录许可信息")
    }

    func testKnownMetadataHasChineseLabelsAndUnknownValuesNeverPassThrough() {
        let examples: [(UserFacingText.MetadataField, String)] = [
            (.sourceKind, "local-snapshot"), (.trust, "review-required"),
            (.metadataReview, "not-schema-validated"),
            (.integrity, "snapshotted"),
            (.presetStatus, "draft"), (.mergePolicy, "explicit-selection"),
            (.component, "hooks"), (.scope, "user")
        ]
        for (field, value) in examples {
            let label = UserFacingText.metadata(value, field: field)
            XCTAssertNotEqual(label, value)
            XCTAssertFalse(label.contains("未识别"))
        }
        for field in UserFacingText.MetadataField.allCases {
            let label = UserFacingText.metadata("unexpected-error-private-token", field: field)
            XCTAssertFalse(label.contains("unexpected"))
            XCTAssertTrue(label.contains("核对"))
        }
    }

    func testDiagnosticsDoNotEchoSystemErrorsOrClaimUnknownRisksAreSafe() {
        let external = "manifest decode failed: private-token-123"
        for context: UserFacingText.DiagnosticContext in [.project, .plugin, .source, .plan, .candidate] {
            let message = UserFacingText.diagnostic(external, context: context)
            XCTAssertFalse(message.contains("private-token"))
            XCTAssertFalse(message.contains("decode"))
        }
        XCTAssertTrue(UserFacingText.diagnostic(external, context: .plan).contains("暂不批准"))
        XCTAssertTrue(UserFacingText.pluginRisk(external).contains("未识别"))
        XCTAssertFalse(UserFacingText.pluginRisk("未发现可执行副作用").contains("已通过"))
        XCTAssertTrue(UserFacingText.catalogIssue(CatalogIssue(reason: "broken-or-cyclic-link")).contains("链接"))
        XCTAssertFalse(UserFacingText.catalogIssue(CatalogIssue(message: external)).contains(external))
    }

    func testUnverifiedExecutionDoesNotBecomeSuccessInPresentation() {
        let pending = UserFacingText.applyResult("宿主命令已成功退出，但回读尚未观察到目标状态；可能需要刷新宿主或重启会话。")
        XCTAssertTrue(pending.contains("尚未确认"))
        let unknown = UserFacingText.applyResult("HTTP 500 private-token-123")
        XCTAssertFalse(unknown.contains("private-token"))
        XCTAssertTrue(unknown.contains("不要重复执行"))
    }

    func testPluginStateUsesObservedFactsRatherThanDisplayText() {
        func record(installed: Bool, enabled: Bool?) -> PluginInventoryRecord {
            PluginInventoryRecord(
                host: .codex, pluginID: "demo", name: "Demo", marketplaceID: nil,
                version: nil, sourceRevision: nil, scope: nil, installed: installed,
                enabled: enabled, description: "", manifestPath: "/tmp/demo/manifest.json",
                sourcePath: "/tmp/demo", manifestDigest: "abc", components: [],
                dependencyCount: 0, license: nil, risks: [],
                state: "Installed successfully private-token-123"
            )
        }
        XCTAssertTrue(UserFacingText.pluginState(record(installed: false, enabled: true)).contains("未确认安装"))
        XCTAssertTrue(UserFacingText.pluginState(record(installed: true, enabled: nil)).contains("待确认"))
        XCTAssertTrue(UserFacingText.pluginState(record(installed: true, enabled: false)).contains("已停用"))
        XCTAssertFalse(UserFacingText.pluginState(record(installed: true, enabled: true)).contains("private-token"))
    }
}
