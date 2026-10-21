import Foundation

public enum SourcePreviewError: Error, LocalizedError, Equatable, Sendable {
    case invalidURL(String)
    case invalidRef(String)
    case credentialsInURL
    case unsupportedHost(String)
    case gitFailed(String)
    case workspaceLimitExceeded(String)
    case corruptPreview(String)

    public var code: String {
        switch self {
        case .invalidURL: "SOURCE_INVALID_URL"
        case .invalidRef: "SOURCE_INVALID_REF"
        case .credentialsInURL: "SOURCE_CREDENTIALS_REJECTED"
        case .unsupportedHost: "SOURCE_HOST_NOT_ALLOWED"
        case .gitFailed: "SOURCE_GIT_FAILED"
        case .workspaceLimitExceeded: "SOURCE_LIMIT_EXCEEDED"
        case .corruptPreview: "SOURCE_PREVIEW_CORRUPT"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "仓库链接格式不对，请填写 https://github.com/owner/repo 格式的链接。"
        case .invalidRef:
            return "分支或标签格式不对，请检查后重试，也可以留空使用默认分支。"
        case .credentialsInURL:
            return "请移除链接中的用户名和密钥。私有仓库请先通过系统 Git 登录。"
        case .unsupportedHost:
            return "暂不支持这个来源，请使用 HTTPS 格式的 GitHub 仓库链接。"
        case .gitFailed:
            return "仓库读取失败，请检查网络、仓库访问权限和分支名称，再重新预览。"
        case let .workspaceLimitExceeded(message):
            return "来源超出隔离预览限制：\(message)"
        case let .corruptPreview(path):
            return "来源预览记录无法读取：\(path)"
        }
    }
}

public enum SourceCandidateState: String, Codable, Hashable, Sendable {
    case promoted
    case inProgress = "in-progress"
    case deprecated
    case misc
    case other
}

public struct SourceSkillCandidate: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let path: String
    public let slug: String
    public let declaredName: String
    public let description: String
    public let category: String
    public let state: SourceCandidateState
    public let contentHash: String
    public let fileCount: Int
    public let bytes: Int
    public let issues: [String]

    public init(
        id: String,
        path: String,
        slug: String,
        declaredName: String,
        description: String,
        category: String,
        state: SourceCandidateState,
        contentHash: String,
        fileCount: Int,
        bytes: Int,
        issues: [String]
    ) {
        self.id = id
        self.path = path
        self.slug = slug
        self.declaredName = declaredName
        self.description = description
        self.category = category
        self.state = state
        self.contentHash = contentHash
        self.fileCount = fileCount
        self.bytes = bytes
        self.issues = issues
    }
}

public struct SourcePreviewRecord: Codable, Identifiable, Hashable, Sendable {
    public let schemaVersion: Int
    public let id: UUID
    public let inputURL: String
    public let canonicalURL: String
    public let namespace: String
    public let resolvedCommit: String
    public let createdAt: Date
    public let workspacePath: String
    public let licenseEvidence: String
    public let candidates: [SourceSkillCandidate]
    public let excludedCounts: [String: Int]
    public let warnings: [String]

    public init(
        schemaVersion: Int = 1,
        id: UUID,
        inputURL: String,
        canonicalURL: String,
        namespace: String,
        resolvedCommit: String,
        createdAt: Date,
        workspacePath: String,
        licenseEvidence: String,
        candidates: [SourceSkillCandidate],
        excludedCounts: [String: Int],
        warnings: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.inputURL = inputURL
        self.canonicalURL = canonicalURL
        self.namespace = namespace
        self.resolvedCommit = resolvedCommit
        self.createdAt = createdAt
        self.workspacePath = workspacePath
        self.licenseEvidence = licenseEvidence
        self.candidates = candidates
        self.excludedCounts = excludedCounts
        self.warnings = warnings
    }
}

public struct SourcePreviewStore {
    public let rootURL: URL

    private let fileManager: FileManager

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    public func save(_ record: SourcePreviewRecord) throws {
        let directory = rootURL.appendingPathComponent(record.id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(record).write(
            to: directory.appendingPathComponent("preview.json"),
            options: .atomic
        )
    }

    public func load(_ id: UUID) throws -> SourcePreviewRecord {
        let url = rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
            .appendingPathComponent("preview.json")
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SourcePreviewRecord.self, from: data)
        } catch {
            throw SourcePreviewError.corruptPreview(url.path)
        }
    }

    public func list() throws -> [SourcePreviewRecord] {
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        let directories = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return try directories.compactMap { directory in
            guard let id = UUID(uuidString: directory.lastPathComponent) else { return nil }
            return try load(id)
        }.sorted { $0.createdAt > $1.createdAt }
    }
}

public struct SourcePreviewService {
    public let previewsRoot: URL
    public let allowedHosts: Set<String>

    private let fileManager: FileManager
    private let clock: () -> Date
    private let idGenerator: () -> UUID
    private let gitEnvironment: [String: String]

    public init(
        previewsRoot: URL = ProjectStore.defaultRootURL.appendingPathComponent("previews", isDirectory: true),
        allowedHosts: Set<String> = ["github.com"],
        fileManager: FileManager = .default,
        clock: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> UUID = UUID.init,
        gitEnvironment: [String: String] = [:]
    ) {
        self.previewsRoot = previewsRoot
        self.allowedHosts = allowedHosts
        self.fileManager = fileManager
        self.clock = clock
        self.idGenerator = idGenerator
        self.gitEnvironment = gitEnvironment
    }

    public func preview(urlString: String, ref: String? = nil) throws -> SourcePreviewRecord {
        let source = try parseSource(urlString)
        let validatedRef = try validateRef(ref)
        let previewID = idGenerator()
        let previewRoot = previewsRoot.appendingPathComponent(previewID.uuidString, isDirectory: true)
        let checkout = previewRoot.appendingPathComponent("checkout", isDirectory: true)
        try fileManager.createDirectory(at: previewRoot, withIntermediateDirectories: true)

        do {
            var arguments = [
                "-c", "core.hooksPath=/dev/null",
                "-c", "core.fsmonitor=false",
                "-c", "submodule.recurse=false",
                "clone", "--depth", "1", "--no-tags", "--single-branch",
                "--no-recurse-submodules"
            ]
            arguments += [source.cloneURL, checkout.path]
            let clone = try runProcess(
                executable: "/usr/bin/git",
                arguments: arguments,
                currentDirectoryURL: nil,
                timeout: 180
            )
            guard clone.status == 0 else {
                throw SourcePreviewError.gitFailed(trimmedGitMessage(clone.output))
            }
            if let validatedRef {
                let fetched = try runProcess(
                    executable: "/usr/bin/git",
                    arguments: [
                        "-C", checkout.path,
                        "fetch", "--depth", "1", "origin", validatedRef
                    ],
                    currentDirectoryURL: nil,
                    timeout: 180
                )
                guard fetched.status == 0 else {
                    throw SourcePreviewError.gitFailed(trimmedGitMessage(fetched.output))
                }
                let checkedOut = try runProcess(
                    executable: "/usr/bin/git",
                    arguments: ["-C", checkout.path, "checkout", "--detach", "FETCH_HEAD"],
                    currentDirectoryURL: nil,
                    timeout: 60
                )
                guard checkedOut.status == 0 else {
                    throw SourcePreviewError.gitFailed(trimmedGitMessage(checkedOut.output))
                }
            }
            let revision = try runProcess(
                executable: "/usr/bin/git",
                arguments: ["-C", checkout.path, "rev-parse", "HEAD"],
                currentDirectoryURL: nil,
                timeout: 30
            )
            guard revision.status == 0 else {
                throw SourcePreviewError.gitFailed(trimmedGitMessage(revision.output))
            }
            let commit = revision.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let record = try scan(
                checkout: checkout,
                previewID: previewID,
                inputURL: urlString,
                source: source,
                commit: commit
            )
            try SourcePreviewStore(rootURL: previewsRoot, fileManager: fileManager).save(record)
            return record
        } catch {
            try? fileManager.removeItem(at: previewRoot)
            throw error
        }
    }

    public func scan(
        checkout: URL,
        previewID: UUID = UUID(),
        inputURL: String,
        source: ParsedSource? = nil,
        commit: String
    ) throws -> SourcePreviewRecord {
        let root = checkout.resolvingSymlinksInPath().standardizedFileURL
        let parsed = source ?? ParsedSource(
            canonicalURL: inputURL,
            cloneURL: inputURL,
            namespace: "source"
        )
        let total = try workspaceUsage(root)
        guard total.files <= 12_000, total.bytes <= 512 * 1024 * 1024 else {
            throw SourcePreviewError.workspaceLimitExceeded(
                "\(total.files) 个文件 / \(total.bytes) 字节"
            )
        }

        var candidates: [SourceSkillCandidate] = []
        var queue: [(URL, String)] = [(root, "")]
        var visitedDirectories = Set<String>()
        while let (directory, relative) = queue.popLast() {
            let resolved = directory.resolvingSymlinksInPath().standardizedFileURL
            guard !visitedDirectories.contains(resolved.path) else { continue }
            visitedDirectories.insert(resolved.path)
            let children = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            let hasSkill = children.contains { $0.lastPathComponent == "SKILL.md" && fileManager.fileExists(atPath: $0.path) }
            if hasSkill {
                let slug = directory.lastPathComponent
                let relativePath = relative.isEmpty ? "." : relative
                let (category, state) = classify(relativePath)
                let metadata = readMetadata(directory.appendingPathComponent("SKILL.md"))
                do {
                    let analysis = try SkillAssetCopier.analyze(from: directory, fileManager: fileManager)
                    candidates.append(SourceSkillCandidate(
                        id: "\(parsed.namespace)/\(slug)",
                        path: relativePath,
                        slug: slug,
                        declaredName: metadata.name,
                        description: metadata.description,
                        category: category,
                        state: state,
                        contentHash: analysis.contentHash,
                        fileCount: analysis.files.count,
                        bytes: analysis.bytes,
                        issues: []
                    ))
                } catch {
                    candidates.append(SourceSkillCandidate(
                        id: "\(parsed.namespace)/\(slug)",
                        path: relativePath,
                        slug: slug,
                        declaredName: metadata.name,
                        description: metadata.description,
                        category: category,
                        state: state,
                        contentHash: "",
                        fileCount: 0,
                        bytes: 0,
                        issues: [error.localizedDescription]
                    ))
                }
            }

            for child in children where child.lastPathComponent != ".git" {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: child.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }
                let resolvedChild = child.resolvingSymlinksInPath().standardizedFileURL
                guard resolvedChild.path == root.path || resolvedChild.path.hasPrefix(root.path + "/") else {
                    continue
                }
                let childRelative = relative.isEmpty ? child.lastPathComponent : "\(relative)/\(child.lastPathComponent)"
                queue.append((child, childRelative))
            }
        }

        candidates.sort {
            let left = candidateRank($0.state)
            let right = candidateRank($1.state)
            return left == right ? $0.path < $1.path : left < right
        }
        let excludedCounts = Dictionary(grouping: candidates, by: \.state.rawValue).mapValues(\.count)
        let license = detectLicense(root)
        return SourcePreviewRecord(
            id: previewID,
            inputURL: inputURL,
            canonicalURL: parsed.canonicalURL,
            namespace: parsed.namespace,
            resolvedCommit: commit,
            createdAt: clock(),
            workspacePath: root.path,
            licenseEvidence: license,
            candidates: candidates,
            excludedCounts: excludedCounts,
            warnings: [
                "预览只 clone 固定提交并读取文本，不执行仓库脚本、hooks、postinstall 或子模块。",
                "内容指纹与许可提示不等于安全、合规或模型行为审核。"
            ]
        )
    }

    public struct ParsedSource: Hashable, Sendable {
        public let canonicalURL: String
        public let cloneURL: String
        public let namespace: String
    }

    public func parseSource(_ value: String) throws -> ParsedSource {
        guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased() else {
            throw SourcePreviewError.invalidURL(value)
        }
        guard components.user == nil, components.password == nil else {
            throw SourcePreviewError.credentialsInURL
        }
        guard allowedHosts.contains(host) else {
            throw SourcePreviewError.unsupportedHost(host)
        }
        let pathComponents = components.path.split(separator: "/").map(String.init)
        guard pathComponents.count == 2 else {
            throw SourcePreviewError.invalidURL("首版请输入仓库根链接，例如 https://github.com/owner/repo")
        }
        var repository = pathComponents[1]
        if repository.hasSuffix(".git") {
            repository.removeLast(4)
        }
        guard !pathComponents[0].isEmpty, !repository.isEmpty else {
            throw SourcePreviewError.invalidURL(value)
        }
        let owner = sanitizeNamespacePart(pathComponents[0])
        let repo = sanitizeNamespacePart(repository)
        return ParsedSource(
            canonicalURL: "https://\(host)/\(pathComponents[0])/\(repository)",
            cloneURL: "https://\(host)/\(pathComponents[0])/\(repository).git",
            namespace: "\(owner)-\(repo)"
        )
    }

    private func validateRef(_ ref: String?) throws -> String? {
        guard let ref else { return nil }
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let forbidden = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet.controlCharacters)
            .union(CharacterSet(charactersIn: "~^:?*[\\"))
        guard !trimmed.hasPrefix("-"),
              trimmed.rangeOfCharacter(from: forbidden) == nil,
              !trimmed.contains(".."),
              !trimmed.contains("@{") else {
            throw SourcePreviewError.invalidRef(ref)
        }
        return trimmed
    }

    private func workspaceUsage(_ root: URL) throws -> (files: Int, bytes: Int) {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return (0, 0) }
        var files = 0
        var bytes = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true {
                files += 1
                bytes += values.fileSize ?? 0
            }
            if files > 12_000 || bytes > 512 * 1024 * 1024 {
                break
            }
        }
        return (files, bytes)
    }

    private func classify(_ path: String) -> (String, SourceCandidateState) {
        let parts = path.split(separator: "/").map(String.init)
        if let index = parts.firstIndex(of: "skills"), parts.indices.contains(index + 1) {
            let category = parts[index + 1]
            switch category {
            case "engineering", "productivity":
                return (category, .promoted)
            case "in-progress":
                return (category, .inProgress)
            case "deprecated":
                return (category, .deprecated)
            case "misc":
                return (category, .misc)
            default:
                return (category, .other)
            }
        }
        return ("other", .other)
    }

    private func candidateRank(_ state: SourceCandidateState) -> Int {
        switch state {
        case .promoted: 0
        case .inProgress: 1
        case .other: 2
        case .misc: 3
        case .deprecated: 4
        }
    }

    private func readMetadata(_ url: URL) -> (name: String, description: String) {
        let fallback = url.deletingLastPathComponent().lastPathComponent
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return (fallback, "")
        }
        let lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---",
              let end = lines.dropFirst().firstIndex(where: {
                  $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---"
              }) else {
            return (fallback, "")
        }
        var values: [String: String] = [:]
        for line in lines[1..<end] {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            values[key] = value
        }
        return (
            values["name"]?.isEmpty == false ? values["name"]! : fallback,
            values["description"] ?? ""
        )
    }

    private func detectLicense(_ root: URL) -> String {
        let names = ["LICENSE", "LICENSE.md", "LICENSE.txt", "COPYING"]
        for name in names {
            let url = root.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8).prefix(8_192) else { continue }
            let upper = text.uppercased()
            if upper.contains("MIT LICENSE") { return "MIT · 仍需逐 skill 审查" }
            if upper.contains("APACHE LICENSE") { return "Apache-2.0 迹象 · 仍需逐 skill 审查" }
            if upper.contains("GNU GENERAL PUBLIC LICENSE") { return "GPL 迹象 · 需合规审查" }
            return "检测到许可文件 · 未自动判定"
        }
        return "未检测到根许可文件 · 禁止默认再分发"
    }

    private func sanitizeNamespacePart(_ value: String) -> String {
        value.lowercased().map { character in
            character.isLetter || character.isNumber || character == "-" ? character : "-"
        }.reduce(into: "") { output, character in
            if character == "-", output.last == "-" { return }
            output.append(character)
        }.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        currentDirectoryURL: URL?,
        timeout: TimeInterval
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        var environment = ProcessInfo.processInfo.environment
        // 允许调用方注入 Git 传输映射；安全相关变量在合并后固定覆盖。
        environment.merge(gitEnvironment) { _, injected in injected }
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_LFS_SKIP_SMUDGE"] = "1"
        environment["GIT_HTTP_LOW_SPEED_LIMIT"] = "1"
        environment["GIT_HTTP_LOW_SPEED_TIME"] = "30"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let timer = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()
        return (
            process.terminationStatus,
            String(data: data, encoding: .utf8) ?? ""
        )
    }

    private func trimmedGitMessage(_ output: String) -> String {
        let lines = output.split(separator: "\n").map(String.init)
        return lines.suffix(8).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
