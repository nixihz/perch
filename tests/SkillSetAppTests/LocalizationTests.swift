import Foundation
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class LocalizationTests: XCTestCase {
    func testBackgroundLoadingAndRetainedResultsHaveEnglishText() {
        for key in ["正在读取配置…", "正在读取技能…", "正在读取使用位置…", "正在读取接入状态…",
                    "正在读取插件内容…", "显示上次读取结果。", "内容是否相同待核对"] {
            let english = L10n.text(key, language: .english)
            XCTAssertFalse(containsChinese(english), english)
            XCTAssertNotEqual(english, key)
        }
    }

    func testGlobalVerificationReasonsTranslateWithoutChangingPaths() {
        let reasons: [GlobalVerificationReason] = [.invalidDraft, .invalidState, .unsupportedSchema, .hostMismatch,
            .skillsPathMismatch, .rulesPathMismatch, .unmanagedPath, .missingReceipt, .invalidRulesEncoding,
            .missingStateStep, .invalidBackup, .invalidRuleMarkers]
        for reason in reasons {
            for path in ["", "/local/项目 100%/record.json"] {
                let source = UserFacingText.error(GlobalConfigurationError.verificationFailed(reason, path: path))
                let english = L10n.text(source, language: .english)
                XCTAssertTrue(english.hasPrefix("Global configuration verification failed:"), english)
                XCTAssertFalse(containsChinese(english.replacingOccurrences(of: path, with: "")), english)
                if !path.isEmpty { XCTAssertTrue(english.contains("File: " + path)) }
                XCTAssertEqual(L10n.text(source, language: .chinese), source)
            }
        }
        let external = "全局配置核验失败：外部程序自报成功。\n文件：/local/file\n已停止当前操作，请核对上述内容后重试。"
        XCTAssertEqual(L10n.text(external, language: .english), external, "未知原因不能被解析成 Core 的核验结论")
    }

    func testPreviouslyStoredStatusCanBeRenderedInEitherLanguageWithoutTranslatingArguments() {
        let skillName = "中文协作"
        let message: LocalizedText = "已登记 \(skillName)；未修改项目文件"
        XCTAssertEqual(L10n.tr(message, language: .english), "Registered 中文协作; project files are unchanged")
        XCTAssertEqual(L10n.tr(message, language: .chinese), "已登记 中文协作；未修改项目文件")
        let preset = LocalizedText(stringLiteral: "日常工程")
        let presetStatus: LocalizedText = "已载入「\(preset)」草稿，尚未写入项目"
        XCTAssertEqual(L10n.tr(presetStatus, language: .english), "Loaded the “Everyday Engineering” draft; project files are unchanged")
        XCTAssertEqual(L10n.tr(presetStatus, language: .chinese), "已载入「日常工程」草稿，尚未写入项目")
    }

    func testAllValidationFailuresHaveEnglishRecoveryTextAndDoNotEchoSecrets() {
        let drafts = [
            MCPConfigurationDraft(),
            MCPConfigurationDraft(name: "bad name", transport: "unknown"),
            MCPConfigurationDraft(name: "valid", commandOrURL: "https://example.com"),
            MCPConfigurationDraft(name: "valid", transport: "streamable-http", commandOrURL: "invalid"),
            MCPConfigurationDraft(name: "valid", transport: "streamable-http", commandOrURL: "https://user:private-token-123@example.com"),
            MCPConfigurationDraft(name: "valid", commandOrURL: "/usr/bin/true", args: ["bad\narg"], envKeys: ["TOKEN=private-token-123"])
        ]
        for draft in drafts {
            let issues = draft.validationIssues()
            XCTAssertFalse(issues.isEmpty)
            let message = L10n.tr(LocalizedText.joining(issues), language: .english)
            XCTAssertFalse(containsChinese(message), message)
            XCTAssertFalse(message.contains("private-token-123"))
            XCTAssertEqual(message.components(separatedBy: "\n").count, issues.count)
        }
    }

    func testServiceNameValidationExplainsLengthAndFirstCharacterRules() {
        let valid = MCPConfigurationDraft(name: String(repeating: "a", count: 64), commandOrURL: "/usr/bin/true")
        XCTAssertTrue(valid.validationIssues().isEmpty)
        for name in ["-service", String(repeating: "a", count: 65)] {
            var draft = valid
            draft.name = name
            let issues = draft.validationIssues()
            XCTAssertEqual(issues.count, 1)
            let message = issues[0]
            XCTAssertTrue(message.contains("64"))
            XCTAssertTrue(message.contains("以字母或数字开头"))
            XCTAssertFalse(containsChinese(L10n.text(message, language: .english)))
        }
    }

    func testCodedAndSystemErrorsHaveTranslatedSafeMessages() {
        let codes = [
            "PLAN_EXPIRED", "APPROVAL_REQUIRED", "PLAN_ALREADY_APPLIED", "PLAN_NO_CHANGES",
            "RECOVERY_REQUIRED", "PROJECT_PATH_MISSING", "PROJECT_ALREADY_REGISTERED",
            "PROJECT_NAME_INVALID", "PROJECT_REGISTRY_CORRUPT", "PROJECT_MANIFEST_CORRUPT",
            "AGENT_UNSUPPORTED", "REPOSITORY_NOT_FOUND", "SKILL_SOURCE_CHANGED", "SKILL_BLOCKED",
            "INSTRUCTION_NOT_FOUND", "SKILL_TARGET_CONFLICT", "SKILL_MANAGED_DRIFT",
            "RULE_TARGET_CONFLICT", "RULE_MANAGED_DRIFT", "SELECTION_LIMIT_EXCEEDED", "SOURCE_INVALID_URL",
            "SOURCE_INVALID_REF", "SOURCE_CREDENTIALS_REJECTED", "SOURCE_GIT_FAILED",
            "SOURCE_IMPORT_CHANGED", "SOURCE_IMPORT_UNAVAILABLE",
            "SOURCE_LIMIT_EXCEEDED", "SOURCE_PREVIEW_CORRUPT", "MCP_CONFIG_CONFLICT",
            "MCP_CONFIG_CORRUPT", "MCP_CONFIG_DRAFT_INVALID", "PLUGIN_RISK_APPROVAL_REQUIRED",
            "PLUGIN_HOST_CLI_MISSING", "PLUGIN_COMMAND_FAILED", "PLUGIN_NOT_FOUND",
            "PLUGIN_SCOPE_AMBIGUOUS", "PLUGIN_ACTION_UNSUPPORTED", "PLUGIN_NOT_INSTALLED",
            "PLUGIN_SOURCE_CHANGED", "PLUGIN_SOURCE_COLLECTED",
            "PATH_OUTSIDE_ROOT", "MANAGED_BLOCK_CONFLICT", "UNKNOWN_ERROR"
        ]
        let errors: [any Error] = codes.map { FixtureError(code: $0) } + [
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError),
            NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError),
            NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError),
            NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        ]
        for error in errors {
            let source = UserFacingText.error(error)
            let english = L10n.text(source, language: .english)
            XCTAssertFalse(containsChinese(english), english)
            XCTAssertNotEqual(english, source)
            XCTAssertFalse(english.contains("private-token"))
        }
    }

    func testStaleTargetMessageExplainsRecoveryWithoutInternalPlanTerms() {
        let message = UserFacingText.message(forCode: "PLAN_STALE")
        XCTAssertFalse(message.contains("计划"), message)
        XCTAssertTrue(message.contains("重新读取当前配置"), message)
        XCTAssertTrue(message.contains("重新保存或审阅"), message)

        let english = L10n.text(message, language: .english)
        XCTAssertFalse(english.contains("plan"), english)
        XCTAssertTrue(english.contains("Reload the current configuration"), english)
    }

    func testBuiltInMetadataIsLocalizedButSkillDescriptionsStayOriginal() {
        let snapshot = AppSnapshot.load()
        for preset in snapshot.presets {
            XCTAssertFalse(containsChinese(L10n.text(preset.name, language: .english)))
            XCTAssertFalse(containsChinese(L10n.text(preset.description, language: .english)))
        }
        for template in snapshot.templates {
            XCTAssertFalse(containsChinese(L10n.text(template.title, language: .english)))
            XCTAssertFalse(containsChinese(L10n.text(template.purpose, language: .english)))
        }
        for source in snapshot.sources.sources {
            XCTAssertFalse(containsChinese(L10n.text(source.title, language: .english)), source.title)
        }
        let skill = snapshot.catalog.entries.first { containsChinese($0.description) }
        XCTAssertNotNil(skill)
        let original = skill?.description ?? ""
        XCTAssertEqual(L10n.text(original, language: .english), original)
    }

    private func containsChinese(_ text: String) -> Bool {
        text.range(of: #"\p{Unified_Ideograph}"#, options: .regularExpression) != nil
    }
}

private struct FixtureError: SkillSetCodedError {
    let code: String
}
