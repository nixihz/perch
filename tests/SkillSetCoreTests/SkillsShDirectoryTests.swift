import Foundation
import Testing
@testable import SkillSetCore

struct SkillsShDirectoryTests {
    @Test func searchUsesPublicEndpointAndParsesStableMetadata() async throws {
        let recorder = SkillsShRequestRecorder()
        let client = SkillsShDirectoryClient { request in
            await recorder.record(request)
            return (Self.searchResponse, 200)
        }

        let hits = try await client.search(query: "  react  ", limit: 3)

        #expect(hits.count == 2)
        #expect(hits[0].id == "vercel-labs/agent-skills/vercel-react-best-practices")
        #expect(hits[0].repositoryURL == "https://github.com/vercel-labs/agent-skills")
        #expect(hits[0].pageURL?.absoluteString == "https://skills.sh/vercel-labs/agent-skills/vercel-react-best-practices")
        #expect(hits[0].installs == 828_545)
        #expect(hits[1].name == "design-review")
        #expect(hits[1].installs == 0)

        let request = try #require(await recorder.lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.url?.path == "/api/search")
        let queryItems = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(queryItems?.first(where: { $0.name == "q" })?.value == "react")
        #expect(queryItems?.first(where: { $0.name == "limit" })?.value == "3")
    }

    @Test func searchReportsHTTPAndDecodeFailuresWithoutHidingThem() async throws {
        let httpFailure = SkillsShDirectoryClient { _ in (Data(), 503) }
        do {
            _ = try await httpFailure.search(query: "react")
            Issue.record("非 200 响应应返回可识别错误")
        } catch let error as SkillsShDirectoryError {
            #expect(error == .searchFailed("HTTP 503"))
        }

        let invalidJSON = SkillsShDirectoryClient { _ in (Data("not-json".utf8), 200) }
        do {
            _ = try await invalidJSON.search(query: "react")
            Issue.record("无法解码的响应应返回可识别错误")
        } catch let error as SkillsShDirectoryError {
            #expect(error == .invalidResponse)
        }
    }

    @Test func matcherRequiresOneUnambiguousCandidate() throws {
        let exact = candidate(id: "fixture/react", path: "skills/react", slug: "react", name: "React")
        #expect(try SkillsShCandidateMatcher.match(hit(skillID: "react"), candidates: [exact]).id == exact.id)

        let sameNameA = candidate(id: "fixture/one", path: "one/react", slug: "one", name: "react")
        let sameNameB = candidate(id: "fixture/two", path: "two/react", slug: "two", name: "react")
        #expect(throws: SkillsShDirectoryError.ambiguousSkill("react")) {
            try SkillsShCandidateMatcher.match(hit(skillID: "react"), candidates: [sameNameA, sameNameB])
        }
        let sharedIDA = candidate(id: "fixture/shared", path: "one/review", slug: "one", name: "review")
        let sharedIDB = candidate(id: "fixture/shared", path: "two/review", slug: "two", name: "review")
        #expect(throws: SkillsShDirectoryError.ambiguousSkill("review")) {
            try SkillsShCandidateMatcher.match(hit(skillID: "review"), candidates: [sharedIDA, sharedIDB])
        }
        #expect(throws: SkillsShDirectoryError.skillNotFound("missing")) {
            try SkillsShCandidateMatcher.match(hit(skillID: "missing"), candidates: [exact])
        }
    }

    @Test func blockedExactIdentityDoesNotFallBackToAnotherImportableSkill() throws {
        let fallback = candidate(id: "fixture/fallback", path: "other/review", slug: "review", name: "another-skill")
        for exact in [
            candidate(id: "fixture/exact", path: "skills/exact", slug: "exact", name: "review", issues: ["包内文件无法安全导入"]),
            candidate(id: "fixture/exact", path: "skills/exact", slug: "exact", name: "review", contentHash: "")
        ] {
            #expect(throws: SourceSkillImportError.unavailable) {
                try SkillsShCandidateMatcher.match(hit(skillID: "review"), candidates: [fallback, exact])
            }
        }
    }

    @Test func blockedDuplicateStillMakesDirectoryIdentityAmbiguous() throws {
        let safe = candidate(id: "fixture/safe", path: "skills/review", slug: "safe", name: "review")
        let blocked = candidate(id: "fixture/blocked", path: "other/review", slug: "blocked", name: "review", issues: ["包内文件无法安全导入"])
        #expect(throws: SkillsShDirectoryError.ambiguousSkill("review")) {
            try SkillsShCandidateMatcher.match(hit(skillID: "review"), candidates: [safe, blocked])
        }
    }

    @Test func nonGitHubDirectoryEntryIsRejectedBeforePreviewing() throws {
        let fixture = try SkillsShInstallFixture(candidates: ["skills/review-demo"])
        defer { fixture.cleanup() }
        let service = try SkillSetService(paths: fixture.paths, globalLocations: .init(home: fixture.root.appendingPathComponent("home"), stateRoot: fixture.paths.applicationSupportRoot))
        let remoteOnly = SkillsShHit(
            id: "example/remote-only", source: "gitlab.com/example/skills",
            skillId: "review-demo", name: "review-demo", installs: 1
        )

        do {
            _ = try service.installDirectorySkill(remoteOnly)
            Issue.record("非 GitHub source 不应进入预览或安装")
        } catch let error as SkillsShDirectoryError {
            #expect(error == .nonGitHubSource("gitlab.com/example/skills"))
        }
        #expect(try SourcePreviewStore(rootURL: fixture.paths.previewsRoot).list().isEmpty)
    }

    @Test func installPinsCommitCopiesCompletePackageAndKeepsSource() throws {
        let fixture = try SkillsShInstallFixture(candidates: ["skills/review-demo"])
        defer { fixture.cleanup() }
        let service = try SkillSetService(paths: fixture.paths, globalLocations: .init(home: fixture.root.appendingPathComponent("home"), stateRoot: fixture.paths.applicationSupportRoot))

        let entry = try service.installDirectorySkill(
            hit(skillID: "review-demo"), previewService: fixture.previewService
        )

        let store = fixture.paths.makeLibraryStore()
        let origin = try #require(store.sourceOrigins()[entry.id])
        let package = try #require(store.sourceURLs()[entry.id])
        #expect(entry.id == "review-demo")
        #expect(origin.url == "https://github.com/fixture/skills")
        #expect(origin.commit == fixture.headCommit)
        #expect(origin.path == "skills/review-demo")
        #expect(try String(contentsOf: package.appendingPathComponent("references/guide.md"), encoding: .utf8) == "# Guide\n")
        #expect(!FileManager.default.fileExists(atPath: fixture.executionMarker.path))
        let previews = SourcePreviewStore(rootURL: fixture.paths.previewsRoot)
        #expect(try previews.list().map(\.canonicalURL) == ["https://github.com/fixture/skills"])
        try store.remove(entry)
        let empty = CatalogDocument(schemaVersion: 1, hashAlgorithm: "sha256:path-content-executable:v1", entries: [])
        #expect(try store.catalog(merging: empty).entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: package.path))
        #expect(try previews.list().map(\.canonicalURL) == ["https://github.com/fixture/skills"])
    }

    @Test func missingOrAmbiguousCandidatePublishesNothing() throws {
        for skillID in ["missing", "react"] {
            let fixture = try SkillsShInstallFixture(
                candidates: ["skills/react-a", "other/react-b"],
                declaredNames: ["skills/react-a": "react", "other/react-b": "react"]
            )
            defer { fixture.cleanup() }
            let service = try SkillSetService(paths: fixture.paths, globalLocations: .init(home: fixture.root.appendingPathComponent("home"), stateRoot: fixture.paths.applicationSupportRoot))

            do {
                _ = try service.installDirectorySkill(
                    hit(skillID: skillID), previewService: fixture.previewService
                )
                Issue.record("\(skillID) 不应猜选候选")
            } catch let error as SkillsShDirectoryError {
                switch (skillID, error) {
                case ("missing", .skillNotFound("missing")), ("react", .ambiguousSkill("react")):
                    break
                default:
                    Issue.record("意外错误：\(error)")
                }
            }
            #expect(try fixture.paths.makeLibraryStore().sourceURLs().isEmpty)
            #expect(try SourcePreviewStore(rootURL: fixture.paths.previewsRoot).list().isEmpty)
        }
    }

    private func hit(skillID: String) -> SkillsShHit {
        SkillsShHit(
            id: "fixture/skills/\(skillID)", source: "fixture/skills",
            skillId: skillID, name: skillID, installs: 42
        )
    }

    private func candidate(id: String, path: String, slug: String, name: String,
                           issues: [String] = [], contentHash: String = "sha256:fixture") -> SourceSkillCandidate {
        SourceSkillCandidate(
            id: id, path: path, slug: slug, declaredName: name, description: "Fixture",
            category: "other", state: .other, contentHash: contentHash, fileCount: 1,
            bytes: 10, issues: issues
        )
    }

    private static let searchResponse = Data(#"""
    {"skills":[
      {"id":"vercel-labs/agent-skills/vercel-react-best-practices","source":"vercel-labs/agent-skills","skillId":"vercel-react-best-practices","name":"vercel-react-best-practices","installs":828545},
      {"id":"fixture/skills/design-review","source":"fixture/skills","skillId":"design-review"}
    ]}
    """#.utf8)
}

private actor SkillsShRequestRecorder {
    private(set) var lastRequest: URLRequest?

    func record(_ request: URLRequest) {
        lastRequest = request
    }
}

private struct SkillsShInstallFixture {
    let root: URL
    let paths: SkillSetRuntimePaths
    let previewService: SourcePreviewService
    let headCommit: String
    let executionMarker: URL

    init(candidates: [String], declaredNames: [String: String] = [:]) throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("skills-sh-install-\(UUID())")
        paths = SkillSetRuntimePaths(
            applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil
        )
        executionMarker = root.appendingPathComponent("script-was-run")
        let remote = root.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try Self.git(["init", "--initial-branch=main"], at: remote)
        for path in candidates {
            let directory = remote.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("references"), withIntermediateDirectories: true)
            let name = declaredNames[path] ?? (path as NSString).lastPathComponent
            try "---\nname: \(name)\ndescription: Fixture skill\n---\n\n# \(name)\n"
                .write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            try "# Guide\n".write(to: directory.appendingPathComponent("references/guide.md"), atomically: true, encoding: .utf8)
            try "#!/bin/sh\nprintf executed > '\(executionMarker.path)'\n"
                .write(to: directory.appendingPathComponent("run.sh"), atomically: true, encoding: .utf8)
        }
        try Self.git(["add", "."], at: remote)
        try Self.git([
            "-c", "user.name=Fixture", "-c", "user.email=fixture@example.test",
            "-c", "commit.gpgsign=false", "commit", "-m", "fixture"
        ], at: remote)
        headCommit = try Self.git(["rev-parse", "HEAD"], at: remote).trimmingCharacters(in: .whitespacesAndNewlines)
        previewService = SourcePreviewService(
            previewsRoot: paths.previewsRoot,
            allowedHosts: ["github.com"],
            gitEnvironment: [
                "GIT_CONFIG_COUNT": "1",
                "GIT_CONFIG_KEY_0": "url.\(remote.absoluteString).insteadOf",
                "GIT_CONFIG_VALUE_0": "https://github.com/fixture/skills.git"
            ]
        )
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    private static func git(_ arguments: [String], at directory: URL) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "core.hooksPath=/dev/null", "-C", directory.path] + arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        #expect(process.terminationStatus == 0)
        return String(decoding: data, as: UTF8.self)
    }
}
