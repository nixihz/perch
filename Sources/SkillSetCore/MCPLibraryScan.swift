import Foundation

public struct MCPLibraryScanCandidate: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let source: String
    public let entry: MCPLibraryEntry?
    public let issue: String?
}

/// 扫描入库与界面摘要共用检测规则，避免同一参数在不同入口暴露凭据。
public enum MCPConnectionSafety {
    public static func containsCredential(_ values: [String]) -> Bool {
        values.contains { value in
            let lower = value.lowercased()
            if ["token", "secret", "password", "api_key", "api-key", "apikey", "authorization", "bearer", "credential"].contains(where: lower.contains) { return true }
            if value.range(of: #"(sk-[A-Za-z0-9_-]{12,}|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)"#, options: .regularExpression) != nil { return true }
            // 同时识别独立 URL 和 --url=https://… 这类参数值，参数名本身不是 URL。
            var urlValues = [value]
            if let separator = value.firstIndex(of: "=") {
                urlValues.append(String(value[value.index(after: separator)...]))
            }
            return urlValues.contains { candidate in
                guard let url = URLComponents(string: candidate),
                      ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
                return url.user != nil || url.password != nil || url.query != nil || url.fragment != nil
            }
        }
    }
}

/// 只支持字符串参数数组；拒绝推测复杂 TOML，避免悄悄丢失启动参数。
enum MCPTOMLArguments {
    static func parse(_ text: String) throws -> [String] {
        let chars = Array(text)
        var index = 0
        func skip() {
            while index < chars.count {
                if chars[index].isWhitespace || chars[index] == "," { index += 1 }
                else if chars[index] == "#" { while index < chars.count && chars[index] != "\n" { index += 1 } }
                else { break }
            }
        }
        skip()
        guard index < chars.count, chars[index] == "[" else { throw MCPConfigurationError.invalidDraft("") }
        index += 1
        var result: [String] = []
        while true {
            skip()
            guard index < chars.count else { throw MCPConfigurationError.invalidDraft("") }
            if chars[index] == "]" { return result }
            let quote = chars[index]
            guard quote == "\"" || quote == "'" else { throw MCPConfigurationError.invalidDraft("") }
            let start = index
            index += 1
            while index < chars.count && chars[index] != quote {
                if quote == "\"" && chars[index] == "\\" { index += 1 }
                index += 1
            }
            guard index < chars.count else { throw MCPConfigurationError.invalidDraft("") }
            let value: String
            if quote == "'" { value = String(chars[(start + 1)..<index]) }
            else { value = try JSONDecoder().decode(String.self, from: Data(String(chars[start...index]).utf8)) }
            result.append(value)
            index += 1
            while index < chars.count && chars[index].isWhitespace { index += 1 }
            guard index < chars.count, [",", "]", "#"].contains(chars[index]) else { throw MCPConfigurationError.invalidDraft("") }
        }
    }
}

extension SkillSetService {
    public func scanMCPLibrary() throws -> [MCPLibraryScanCandidate] {
        var candidates = MCPConfigurationManager(projectRoot: nil, applicationSupportRoot: paths.applicationSupportRoot,
            environment: ["CODEX_HOME": globalConfiguration.locations.codexRoot.path], homeDirectory: globalConfiguration.locations.home).libraryScanCandidates()
        for project in try ProjectStore(rootURL: paths.applicationSupportRoot).list() {
            candidates += MCPConfigurationManager(projectRoot: URL(fileURLWithPath: project.canonicalPath),
                applicationSupportRoot: paths.applicationSupportRoot,
                environment: ["CODEX_HOME": globalConfiguration.locations.codexRoot.path], homeDirectory: globalConfiguration.locations.home).libraryScanCandidates().filter { $0.source.contains(project.canonicalPath) }
        }
        return candidates
    }
}
