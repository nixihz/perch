import AppKit
import SwiftUI
import XCTest
@testable import SkillSetApp

@MainActor
final class SettingsTests: XCTestCase {
    func testSystemLanguageChoosesSupportedLanguageAndExplicitChoiceWins() {
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["zh-Hant-TW", "en"]), .chinese)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["en-GB", "zh-Hans"]), .english)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["fr", "zh-Hans"]), .chinese)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["fr"]), .english)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: []), .english)
        XCTAssertEqual(AppLanguage.english.resolved(preferredLanguages: ["zh-Hans"]), .english)
        XCTAssertEqual(AppLanguage.chinese.resolved(preferredLanguages: ["en"]), .chinese)
    }

    func testTranslationsPreserveInterpolatedPathsAndUnknownSourceContent() {
        XCTAssertEqual(L10n.tr("技能库", language: .english), "Skill Library")
        XCTAssertEqual(L10n.tr("\(42) 个匹配", language: .english), "42 matches")
        XCTAssertEqual(L10n.tr("已复制 \("/tmp/100%@-中文")", language: .english), "Copied /tmp/100%@-中文")
        XCTAssertEqual(L10n.text("第三方技能原文", language: .english), "第三方技能原文")
        XCTAssertEqual(L10n.tr("技能库", language: .chinese), "技能库")
    }

    func testPreferencesDefaultToSystemPersistAndRecoverFromInvalidValues() throws {
        let suite = "SkillSet.SettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(preferences.appearance, .system)
        XCTAssertEqual(preferences.language, .system)
        XCTAssertNil(preferences.appearance.colorScheme)
        XCTAssertNil(defaults.string(forKey: PreferenceKey.appearance))
        XCTAssertNil(defaults.string(forKey: PreferenceKey.language))

        preferences.appearance = .dark
        preferences.language = .english
        XCTAssertEqual(defaults.string(forKey: PreferenceKey.appearance), "dark")
        XCTAssertEqual(defaults.string(forKey: PreferenceKey.language), "en")
        let restored = AppPreferences(defaults: defaults)
        XCTAssertEqual(restored.appearance.colorScheme, .dark)
        XCTAssertEqual(restored.language.locale.identifier, "en")
        restored.appearance = .light
        restored.language = .chinese
        let chinese = AppPreferences(defaults: defaults)
        XCTAssertEqual(chinese.appearance.colorScheme, .light)
        XCTAssertEqual(chinese.language.locale.identifier, "zh-Hans")
        chinese.appearance = .system
        chinese.language = .system
        let system = AppPreferences(defaults: defaults)
        XCTAssertNil(system.appearance.colorScheme)
        XCTAssertEqual(system.language, .system)

        defaults.set("unsupported", forKey: PreferenceKey.appearance)
        defaults.set("unsupported", forKey: PreferenceKey.language)
        let recovered = AppPreferences(defaults: defaults)
        XCTAssertNil(recovered.appearance.colorScheme)
        XCTAssertEqual(recovered.language, .system)
    }
}
