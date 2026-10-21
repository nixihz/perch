import Foundation

struct LocalizedText: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    let key: String
    let arguments: [Argument]

    indirect enum Argument {
        case raw(String)
        case localized(LocalizedText)
    }

    init(stringLiteral value: String) {
        key = value
        arguments = []
    }

    init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key
        arguments = stringInterpolation.arguments
    }

    static func joining(_ keys: [String]) -> LocalizedText {
        var interpolation = StringInterpolation(literalCapacity: 0, interpolationCount: keys.count)
        for (index, key) in keys.enumerated() {
            if index > 0 { interpolation.appendLiteral("\n") }
            interpolation.appendInterpolation(LocalizedText(stringLiteral: key))
        }
        return LocalizedText(stringInterpolation: interpolation)
    }

    struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [Argument] = []

        init(literalCapacity: Int, interpolationCount: Int) {}

        mutating func appendLiteral(_ literal: String) { key += literal }

        mutating func appendInterpolation<T>(_ value: T) {
            key += "%@"
            arguments.append(.raw(String(describing: value)))
        }

        mutating func appendInterpolation(_ value: LocalizedText) {
            key += "%@"
            arguments.append(.localized(value))
        }
    }
}

@MainActor
enum L10n {
    private static let english: [String: String] = {
        guard let url = Bundle.module.url(forResource: "English", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return table
    }()

    static func text(_ key: String, language: AppLanguage? = nil) -> String {
        let selected = language ?? AppPreferences.shared.language
        return selected.resolved() == .english ? english[key] ?? key : key
    }

    static func tr(_ value: LocalizedText, language: AppLanguage? = nil) -> String {
        let template = text(value.key, language: language)
        // 只替换模板占位符，不把路径或用户输入中的百分号当作格式指令。
        let parts = template.components(separatedBy: "%@")
        guard parts.count == value.arguments.count + 1 else { return value.key }
        let arguments = value.arguments.map { argument in
            switch argument {
            case let .raw(text): text
            case let .localized(message): tr(message, language: language)
            }
        }
        return zip(parts.dropLast(), arguments).map { $0 + $1 }.joined() + (parts.last ?? "")
    }

    static var locale: Locale {
        Locale(identifier: AppPreferences.shared.language.resolved().rawValue)
    }

    static func date(_ value: Date) -> String {
        value.formatted(.dateTime.year().month(.abbreviated).day().hour().minute().locale(locale))
    }

    static func byteCount(_ value: Int64) -> String {
        ByteCountFormatStyle(style: .file, locale: locale).format(value)
    }
}
