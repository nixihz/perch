import SwiftUI
import Observation

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
    var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: PreferenceKey.language) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: PreferenceKey.appearance).flatMap(AppAppearance.init(rawValue:)) ?? .system
        language = defaults.string(forKey: PreferenceKey.language).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }
}

private struct AppPreferencesModifier: ViewModifier {
    let preferences: AppPreferences

    func body(content: Content) -> some View {
        content
            .environment(\.locale, preferences.language.locale)
            .background(WindowAppearancePreference(appearance: preferences.appearance))
    }
}

private struct WindowAppearancePreference: NSViewRepresentable {
    let appearance: AppAppearance

    func makeNSView(context: Context) -> WindowAppearanceView {
        let view = WindowAppearanceView()
        view.selectedAppearance = appearance
        return view
    }

    func updateNSView(_ view: WindowAppearanceView, context: Context) {
        view.selectedAppearance = appearance
    }
}

private final class WindowAppearanceView: NSView {
    var selectedAppearance: AppAppearance = .system {
        didSet { applyAppearance() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAppearance()
    }

    private func applyAppearance() {
        guard let window else { return }
        let override: NSAppearance? = switch selectedAppearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        // 跟随系统时明确移除窗口覆盖，由 AppKit 继承并持续响应系统外观；
        // 保留视图身份，避免切换外观丢失输入、焦点和页面状态。
        if window.appearance != override {
            window.appearance = override
        }
    }
}

extension View {
    func appPreferences(_ preferences: AppPreferences = .shared) -> some View {
        modifier(AppPreferencesModifier(preferences: preferences))
    }
}
