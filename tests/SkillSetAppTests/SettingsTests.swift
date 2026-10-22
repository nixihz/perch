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

    func testSystemAppearanceRestoresCurrentSystemSchemeAfterExplicitOverride() async throws {
        let suite = "SkillSet.SettingsTests.Appearance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        let application = NSApplication.shared
        let originalAppearance = application.appearance
        defer { application.appearance = originalAppearance }
        let probe = NSHostingController(rootView: ColorSchemeProbe().appPreferences(preferences))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = probe
        defer { window.close() }

        for systemAppearance in [NSAppearance.Name.darkAqua, .aqua] {
            application.appearance = NSAppearance(named: systemAppearance)
            preferences.appearance = .system
            try await settle(probe.view)
            let initial = try XCTUnwrap(colorSchemeProbe(in: probe.view))
            let stateID = initial.stateID
            let systemScheme: ColorScheme = systemAppearance == .darkAqua ? .dark : .light
            let opposite: AppAppearance = systemScheme == .dark ? .light : .dark
            let matching: AppAppearance = systemScheme == .dark ? .dark : .light

            for selection in [opposite, .system, matching, opposite, .system] {
                preferences.appearance = selection
                try await settle(probe.view)
                let expected = selection.colorScheme ?? systemScheme
                let current = try XCTUnwrap(colorSchemeProbe(in: probe.view))
                XCTAssertEqual(current.scheme, expected, "\(systemAppearance) / \(selection)")
                XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
                               expected == .dark ? .darkAqua : .aqua)
                XCTAssertEqual(current.stateID, stateID, "外观切换应保留页面的局部状态")
                if selection == .system {
                    XCTAssertNil(window.appearance, "跟随系统必须移除窗口覆盖")
                }
            }

            // 以应用级外观模拟系统变化，不修改用户的系统偏好。
            application.appearance = NSAppearance(named: systemAppearance == .darkAqua ? .aqua : .darkAqua)
            try await settle(probe.view)
            XCTAssertEqual(colorSchemeProbe(in: probe.view)?.scheme, systemScheme == .dark ? .light : .dark)

            preferences.appearance = .light
            try await settle(probe.view)
            application.appearance = NSAppearance(named: systemAppearance)
            try await settle(probe.view)
            XCTAssertEqual(colorSchemeProbe(in: probe.view)?.scheme, .light, "显式选择不随系统变化")
        }
    }

    private struct ColorSchemeProbe: View {
        @Environment(\.colorScheme) private var scheme
        @State private var stateID = UUID()

        var body: some View { ProbeRepresentable(scheme: scheme, stateID: stateID) }
    }

    private struct ProbeRepresentable: NSViewRepresentable {
        let scheme: ColorScheme
        let stateID: UUID

        func makeNSView(context: Context) -> ProbeView { ProbeView() }

        func updateNSView(_ view: ProbeView, context: Context) {
            view.scheme = scheme
            view.stateID = stateID
        }
    }

    private final class ProbeView: NSView {
        var scheme: ColorScheme?
        var stateID: UUID?
    }

    private func colorSchemeProbe(in view: NSView) -> ProbeView? {
        if let probe = view as? ProbeView { return probe }
        return view.subviews.lazy.compactMap { self.colorSchemeProbe(in: $0) }.first
    }

    private func settle(_ view: NSView) async throws {
        try await Task.sleep(for: .milliseconds(80))
        view.layoutSubtreeIfNeeded()
    }
}
