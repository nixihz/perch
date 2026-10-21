import Foundation
import Darwin
import XCTest
import SkillSetCore
@testable import SkillSetApp

final class UserFacingTextTests: XCTestCase {
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

    func testKnownMetadataHasChineseLabelsAndUnknownValuesNeverPassThrough() {
        let examples: [(UserFacingText.MetadataField, String)] = [
            (.sourceKind, "local-snapshot"), (.trust, "review-required"),
            (.licenseReview, "required"), (.metadataReview, "not-schema-validated"),
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
