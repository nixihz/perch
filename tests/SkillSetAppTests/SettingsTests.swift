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

    func testThemeTonePersistsAndInvalidValuesReturnToObsidian() throws {
        let suite = "SkillSet.SettingsTests.Theme.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(preferences.theme, .obsidian)
        XCTAssertNil(defaults.string(forKey: PreferenceKey.theme))

        preferences.theme = .terracotta
        XCTAssertEqual(defaults.string(forKey: PreferenceKey.theme), AppTheme.terracotta.rawValue)
        XCTAssertEqual(AppPreferences(defaults: defaults).theme, .terracotta)

        defaults.set("mist", forKey: PreferenceKey.theme)
        XCTAssertEqual(AppPreferences(defaults: defaults).theme, .obsidian)
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

        application.appearance = nil
        let systemScheme: ColorScheme = application.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        try await settle(probe.view)
        let stateID = try XCTUnwrap(colorSchemeProbe(in: probe.view)).stateID
        let opposite: AppAppearance = systemScheme == .dark ? .light : .dark

        for selection in [opposite, .system, .light, .dark, .system] {
            preferences.appearance = selection
            try await settle(probe.view)
            let expected = selection.colorScheme ?? systemScheme
            let current = try XCTUnwrap(colorSchemeProbe(in: probe.view))
            XCTAssertEqual(current.scheme, expected, "\(selection)")
            XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
                           expected == .dark ? .darkAqua : .aqua)
            XCTAssertEqual(current.stateID, stateID, "外观切换应保留页面的局部状态")
            XCTAssertNil(window.appearance, "窗口应始终继承应用外观")
            if selection == .system {
                XCTAssertNil(application.appearance, "跟随系统必须移除应用覆盖")
            }
        }

        // 以应用的继承源模拟系统变化，不修改用户的系统偏好。
        for inheritedAppearance in [NSAppearance.Name.aqua, .darkAqua] {
            application.appearance = NSAppearance(named: inheritedAppearance)
            try await settle(probe.view)
            XCTAssertEqual(colorSchemeProbe(in: probe.view)?.scheme,
                           inheritedAppearance == .darkAqua ? .dark : .light)
        }
    }

    func testAppearanceSelectionReachesExistingSheetsAndNewPanels() async throws {
        let suite = "SkillSet.SettingsTests.Panels.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        let application = NSApplication.shared
        let originalAppearance = application.appearance
        application.appearance = nil
        defer { application.appearance = originalAppearance }
        let systemScheme: ColorScheme = application.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        let opposite: AppAppearance = systemScheme == .dark ? .light : .dark
        let main = NSHostingController(rootView: ColorSchemeProbe().appPreferences(preferences))
        let sheet = NSHostingController(rootView: ColorSchemeProbe())
        let window = NSWindow(contentViewController: main)
        let panel = NSPanel(contentViewController: sheet)
        window.isReleasedWhenClosed = false
        panel.isReleasedWhenClosed = false
        window.orderFront(nil)
        window.beginSheet(panel, completionHandler: nil)
        defer {
            window.endSheet(panel)
            panel.close()
            window.close()
        }
        try await settle(main.view)
        let mainStateID = try XCTUnwrap(colorSchemeProbe(in: main.view)).stateID
        let sheetStateID = try XCTUnwrap(colorSchemeProbe(in: sheet.view)).stateID

        for selection in [opposite, .system, .light, .dark, .system] {
            preferences.appearance = selection
            try await settle(main.view)
            let expected = selection.colorScheme ?? systemScheme
            XCTAssertEqual(colorSchemeProbe(in: main.view)?.scheme, expected)
            XCTAssertEqual(colorSchemeProbe(in: sheet.view)?.scheme, expected, "已打开的 sheet 必须与主窗口一致")
            XCTAssertEqual(colorSchemeProbe(in: main.view)?.stateID, mainStateID)
            XCTAssertEqual(colorSchemeProbe(in: sheet.view)?.stateID, sheetStateID)

            let newPanel = NSOpenPanel()
            XCTAssertEqual(newPanel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
                           expected == .dark ? .darkAqua : .aqua, "新打开的系统面板必须继承应用选择")
            newPanel.close()
            if selection == .system {
                XCTAssertNil(application.appearance, "跟随系统必须清除应用级覆盖")
            }
        }
    }

    func testSavedAppearanceReachesSwiftUISheetAfterWindowReopens() async throws {
        let suite = "SkillSet.SettingsTests.Reopen.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let application = NSApplication.shared
        let originalAppearance = application.appearance
        application.appearance = nil
        defer { application.appearance = originalAppearance }
        let systemIsDark = application.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let savedAppearance: AppAppearance = systemIsDark ? .light : .dark
        defaults.set(savedAppearance.rawValue, forKey: PreferenceKey.appearance)
        let preferences = AppPreferences(defaults: defaults)

        for _ in 0..<2 {
            let controller = NSHostingController(rootView:
                ColorSchemeProbe()
                    .frame(width: 240, height: 120)
                    .sheet(isPresented: .constant(true)) {
                        ColorSchemeProbe().frame(width: 240, height: 120)
                    }
                    .appPreferences(preferences)
            )
            let window = NSWindow(contentViewController: controller)
            window.isReleasedWhenClosed = false
            defer {
                if let sheet = window.attachedSheet { window.endSheet(sheet) }
                window.close()
            }
            window.orderFront(nil)
            try await settle(controller.view)
            let sheet = try XCTUnwrap(window.attachedSheet)
            let sheetContent = try XCTUnwrap(sheet.contentView)
            try await settle(sheetContent)
            XCTAssertEqual(colorSchemeProbe(in: controller.view)?.scheme, savedAppearance.colorScheme)
            XCTAssertEqual(colorSchemeProbe(in: sheetContent)?.scheme, savedAppearance.colorScheme,
                           "重开窗口后 SwiftUI sheet 仍须继承已保存的外观")
            XCTAssertEqual(sheet.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
                           savedAppearance == .dark ? .darkAqua : .aqua)
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
