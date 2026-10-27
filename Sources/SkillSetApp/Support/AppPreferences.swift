import SwiftUI
import Observation
import Foundation

enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case obsidian
    case snow
    case mist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .obsidian: "黑曜"
        case .snow: "雪白"
        case .mist: "雾灰"
        }
    }

    var detail: String {
        switch self {
        case .obsidian: "深墨与柔和高光"
        case .snow: "纸面与细边界"
        case .mist: "中性灰与低对比"
        }
    }

    var symbolName: String {
        switch self {
        case .obsidian: "circle.fill"
        case .snow: "circle"
        case .mist: "circle.lefthalf.filled"
        }
    }

    var swatch: Color {
        switch self {
        case .obsidian: Color(red: 0.12, green: 0.12, blue: 0.12)
        case .snow: Color(red: 0.96, green: 0.96, blue: 0.96)
        case .mist: Color(red: 0.55, green: 0.55, blue: 0.55)
        }
    }
}

/// 颜色提供器在绘制时读取当前主题，避免把浅色或深色结果缓存到静态 token 中。
final class AppThemeRuntime: @unchecked Sendable {
    static let shared = AppThemeRuntime()

    private let lock = NSLock()
    private var value: AppTheme = .obsidian

    func update(_ theme: AppTheme) {
        lock.lock()
        value = theme
        lock.unlock()
    }

    func current() -> AppTheme {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var nativeAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, chinese = "zh-Hans", english = "en"

    var id: String { rawValue }

    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        // 仅在应用支持的语言中选择，其他系统语言回退到英文。
        let supported = preferredLanguages.first { $0.hasPrefix("zh") || $0.hasPrefix("en") }
        return supported.map { $0.hasPrefix("zh") ? .chinese : .english } ?? .english
    }

    var locale: Locale {
        self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }
}

enum PreferenceKey {
    static let appearance = "app.appearance"
    static let theme = "app.theme"
    static let language = "app.language"
}

@MainActor
@Observable
final class AppPreferences {
    static let shared = AppPreferences()

    @ObservationIgnored private let defaults: UserDefaults
    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: PreferenceKey.appearance) }
    }
    var theme: AppTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: PreferenceKey.theme)
            AppThemeRuntime.shared.update(theme)
        }
    }
    var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: PreferenceKey.language) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: PreferenceKey.appearance).flatMap(AppAppearance.init(rawValue:)) ?? .system
        theme = defaults.string(forKey: PreferenceKey.theme).flatMap(AppTheme.init(rawValue:)) ?? .obsidian
        language = defaults.string(forKey: PreferenceKey.language).flatMap(AppLanguage.init(rawValue:)) ?? .system
        AppThemeRuntime.shared.update(theme)
    }
}

private struct AppPreferencesModifier: ViewModifier {
    let preferences: AppPreferences

    func body(content: Content) -> some View {
        let theme = preferences.theme
        content
            .environment(\.locale, preferences.language.locale)
            .environment(\.appTheme, theme)
            // 让静态颜色 token 在主题改变后重新绘制，同时不重建页面状态。
            .onChange(of: theme, initial: true) { _, selection in
                AppThemeRuntime.shared.update(selection)
            }
            .onChange(of: preferences.appearance, initial: true) { _, selection in
                // 由应用统一外观，保证 sheet 和系统面板也继承同一选择；
                // nil 恢复系统继承，不把当前系统模式固化为手动选择。
                NSApplication.shared.appearance = selection.nativeAppearance
            }
    }
}

private struct AppThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppTheme.obsidian
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeEnvironmentKey.self] }
        set { self[AppThemeEnvironmentKey.self] = newValue }
    }
}

extension View {
    func appPreferences(_ preferences: AppPreferences = .shared) -> some View {
        modifier(AppPreferencesModifier(preferences: preferences))
    }
}
