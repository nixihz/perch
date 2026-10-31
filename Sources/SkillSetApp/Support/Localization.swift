import Foundation
import SkillSetCore

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
        joining(keys.map { LocalizedText(stringLiteral: $0) })
    }

    /// 每条原因单独翻译后再拼接，名称和来源保持原文。
    static func joining(_ parts: [LocalizedText], separator: String = "\n") -> LocalizedText {
        guard let first = parts.first else { return "" }
        if parts.count == 1 { return first }
        var interpolation = StringInterpolation(literalCapacity: separator.count * parts.count, interpolationCount: parts.count)
        interpolation.appendInterpolation(first)
        for part in parts.dropFirst() {
            interpolation.appendLiteral(separator)
            interpolation.appendInterpolation(part)
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
        guard selected.resolved() == .english else { return key }
        return english[key] ?? translatedVerificationFailure(key) ?? translatedSnapshotRepairMessage(key) ?? key
    }

    private static func translatedVerificationFailure(_ message: String) -> String? {
        let prefix = "全局配置核验失败："
        let suffix = "\n已停止当前操作，请核对上述内容后重试。"
        guard message.hasPrefix(prefix), message.hasSuffix(suffix) else { return nil }
        let detail = String(message.dropFirst(prefix.count).dropLast(suffix.count))
        guard let separator = detail.range(of: "。") else { return nil }
        let reason = String(detail[..<separator.lowerBound])
        // 仅翻译 Core 已定义的原因；不猜测外部异常，也不翻译用户路径。
        guard GlobalVerificationReason(rawValue: reason) != nil else { return nil }
        let pathLine = String(detail[separator.upperBound...])
        if pathLine.isEmpty {
            return tr("全局配置核验失败：\(LocalizedText(stringLiteral: reason))。\n已停止当前操作，请核对上述内容后重试。", language: .english)
        }
        guard pathLine.hasPrefix("\n文件：") else { return nil }
        let path = String(pathLine.dropFirst("\n文件：".count))
        return tr("全局配置核验失败：\(LocalizedText(stringLiteral: reason))。\n文件：\(path)\n已停止当前操作，请核对上述内容后重试。", language: .english)
    }

    private static func translatedSnapshotRepairMessage(_ message: String) -> String? {
        let prefix = "技能快照内容与目录指纹不一致，当前操作已停止。\n文件："
        let suffix = "\n请先修复技能快照，再重新预览。"
        guard message.hasPrefix(prefix), message.hasSuffix(suffix) else { return nil }
        let path = String(message.dropFirst(prefix.count).dropLast(suffix.count))
        return tr("技能快照内容与目录指纹不一致，当前操作已停止。\n文件：\(LocalizedText(stringLiteral: path))\n请先修复技能快照，再重新预览。", language: .english)
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
