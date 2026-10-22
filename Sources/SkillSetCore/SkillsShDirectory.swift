import Foundation

public enum SkillsShDirectoryError: Error, LocalizedError, Equatable, Sendable {
    case queryTooShort
    case searchFailed(String)
    case invalidResponse
    case invalidSkillID
    case nonGitHubSource(String)
    case skillNotFound(String)
    case ambiguousSkill(String)

    public var code: String {
        switch self {
        case .queryTooShort: "SKILLS_SH_QUERY_TOO_SHORT"
        case .searchFailed: "SKILLS_SH_SEARCH_FAILED"
        case .invalidResponse: "SKILLS_SH_RESPONSE_INVALID"
        case .invalidSkillID: "SKILLS_SH_SKILL_ID_INVALID"
        case .nonGitHubSource: "SKILLS_SH_INVALID_SOURCE"
        case .skillNotFound: "SKILLS_SH_SKILL_NOT_FOUND"
        case .ambiguousSkill: "SKILLS_SH_AMBIGUOUS_SKILL"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .queryTooShort:
            return "请至少输入 2 个字符，再搜索 skills.sh。"
        case let .searchFailed(detail):
            return "skills.sh 搜索失败（\(detail)），请稍后重试。"
        case .invalidResponse:
            return "skills.sh 返回了无法识别的响应，请稍后重试。"
        case .invalidSkillID:
            return "这个目录条目缺少可用的技能标识，无法安装。"
        case .nonGitHubSource:
            return "这个目录条目没有可用的 GitHub 仓库，请到 skills.sh 查看安装说明。"
        case let .skillNotFound(skillID):
            return "在来源仓库的固定提交中没有找到技能 \(skillID)，请到 skills.sh 核对条目。"
        case let .ambiguousSkill(skillID):
            return "来源仓库中有多个候选匹配技能 \(skillID)，请换一个目录条目。"
        }
    }
}

public struct SkillsShHit: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let source: String
    public let skillId: String
    public let name: String
    public let installs: Int

    public init(id: String, source: String, skillId: String, name: String, installs: Int) {
        self.id = id
        self.source = source
        self.skillId = skillId
        self.name = name
        self.installs = installs
    }

    /// 只从目录记录的规范标识生成页面地址，不接受外部传入的任意 URL。
    public var pageURL: URL? {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        guard !encoded.isEmpty else { return nil }
        return URL(string: "https://skills.sh/\(encoded)")
    }

    /// skills.sh 的 source 字段通常是 `owner/repo`；其他形式只展示，不走 Git 安装。
    public var repositoryURL: String? {
        let parts = source.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              parts.allSatisfy({
                  $0.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
              }) else { return nil }
        return "https://github.com/\(source)"
    }

    public var librarySlug: String {
        SkillsShCandidateMatcher.normalizedIdentifier(skillId)
    }
}

public struct SkillsShDirectoryClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)

    private let baseURL: URL
    private let transport: Transport

    public init(
        baseURL: URL = URL(string: "https://skills.sh")!,
        transport: Transport? = nil
    ) {
        self.baseURL = baseURL
        self.transport = transport ?? Self.liveTransport
    }

    public func search(query: String, limit: Int = 20) async throws -> [SkillsShHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { throw SkillsShDirectoryError.queryTooShort }
        let safeLimit = min(max(limit, 1), 50)
        let endpoint = baseURL
            .appendingPathComponent("api", isDirectory: true)
            .appendingPathComponent("search", isDirectory: false)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw SkillsShDirectoryError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "limit", value: String(safeLimit))
        ]
        guard let url = components.url else { throw SkillsShDirectoryError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, status) = try await transport(request)
        guard status == 200 else {
            throw SkillsShDirectoryError.searchFailed("HTTP \(status)")
        }
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw SkillsShDirectoryError.invalidResponse
        }
        return response.skills.compactMap { item in
            let id = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let source = item.source.trimmingCharacters(in: .whitespacesAndNewlines)
            let skillID = item.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !source.isEmpty, !skillID.isEmpty else { return nil }
            let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return SkillsShHit(
                id: id,
                source: source,
                skillId: skillID,
                name: name.isEmpty ? skillID : name,
                installs: max(item.installs ?? 0, 0)
            )
        }
    }

    private struct Response: Decodable {
        let skills: [Item]
    }

    private struct Item: Decodable {
        let id: String
        let source: String
        let skillId: String
        let name: String?
        let installs: Int?
    }

    private static func liveTransport(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SkillsShDirectoryError.invalidResponse
        }
        return (data, http.statusCode)
    }
}

public enum SkillsShCandidateMatcher {
    /// 先按原值，再按规范化标识和路径末段匹配；每一层都必须唯一，避免猜选同名技能。
    public static func match(_ hit: SkillsShHit, candidates: [SourceSkillCandidate]) throws -> SourceSkillCandidate {
        let skillID = hit.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalizedIdentifier(skillID)
        guard !normalized.isEmpty else { throw SkillsShDirectoryError.invalidSkillID }
        // 先确定目录条目指向谁，再校验能否导入；过滤阻塞项会把身份匹配错误地降级到其他技能。
        let stages: [[SourceSkillCandidate]] = [
            candidates.filter { $0.declaredName.caseInsensitiveCompare(skillID) == .orderedSame },
            candidates.filter { $0.slug.caseInsensitiveCompare(skillID) == .orderedSame },
            candidates.filter { pathLeaf($0.path).caseInsensitiveCompare(skillID) == .orderedSame },
            candidates.filter { normalizedIdentifier($0.declaredName) == normalized },
            candidates.filter { normalizedIdentifier($0.slug) == normalized },
            candidates.filter { normalizedIdentifier(pathLeaf($0.path)) == normalized }
        ]
        for stage in stages {
            // 仓库内不同目录可能得到相同候选 id；按路径去重，避免把两个技能误判成唯一候选。
            let unique = Dictionary(grouping: stage, by: \.path).compactMap(\.value.first)
            guard !unique.isEmpty else { continue }
            guard unique.count == 1 else { throw SkillsShDirectoryError.ambiguousSkill(skillID) }
            let candidate = unique[0]
            guard candidate.issues.isEmpty, !candidate.contentHash.isEmpty else {
                throw SourceSkillImportError.unavailable
            }
            return candidate
        }
        throw SkillsShDirectoryError.skillNotFound(skillID)
    }

    public static func normalizedIdentifier(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func pathLeaf(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? ""
    }
}
