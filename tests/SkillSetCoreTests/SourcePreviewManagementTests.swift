import Foundation
import Testing
@testable import SkillSetCore

struct SourcePreviewManagementTests {
    @Test
    func editingReplacesOnlyAfterNewRevisionIsSavedAndKeepsRequestedRef() throws {
        let fixture = try PreviewManagementFixture()
        defer { fixture.cleanup() }
        let original = try fixture.service.preview(urlString: fixture.url, ref: "v1")
        let revised = try fixture.service.preview(urlString: fixture.url, ref: "v2", replacing: original.id)
        let saved = try fixture.store.list()
        #expect(saved.map(\.id) == [revised.id])
        #expect(saved.first?.requestedRef == "v2")
        #expect(revised.resolvedCommit != original.resolvedCommit)
        #expect(!FileManager.default.fileExists(atPath: original.workspacePath))
        #expect(try String(contentsOf: URL(fileURLWithPath: revised.workspacePath).appendingPathComponent("SKILL.md"), encoding: .utf8).contains("Second revision"))
    }

    @Test
    func failedEditKeepsOriginalRecordAndCheckout() throws {
        let fixture = try PreviewManagementFixture()
        defer { fixture.cleanup() }
        let original = try fixture.service.preview(urlString: fixture.url, ref: "v1")
        #expect(throws: SourcePreviewError.self) {
            try fixture.service.preview(urlString: fixture.url, ref: "missing-ref", replacing: original.id)
        }
        #expect(try fixture.store.list().map(\.id) == [original.id])
        #expect(try fixture.store.load(original.id).resolvedCommit == original.resolvedCommit)
        #expect(try String(contentsOf: URL(fileURLWithPath: original.workspacePath).appendingPathComponent("SKILL.md"), encoding: .utf8).contains("First revision"))
        let directories = try FileManager.default.contentsOfDirectory(atPath: fixture.store.rootURL.path)
        #expect(directories == [original.id.uuidString])
    }

    @Test
    func removalIgnoresUntrustedWorkspacePathAndPreservesOtherPreviews() throws {
        let fixture = try PreviewManagementFixture()
        defer { fixture.cleanup() }
        let original = try fixture.service.preview(urlString: fixture.url, ref: "v1")
        let other = try fixture.service.preview(urlString: fixture.url, ref: "v2")
        let outside = fixture.root.appendingPathComponent("unrelated.txt")
        try "keep".write(to: outside, atomically: true, encoding: .utf8)
        let recordURL = fixture.store.rootURL.appendingPathComponent(original.id.uuidString).appendingPathComponent("preview.json")
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: recordURL)) as? [String: Any])
        json["workspacePath"] = outside.path
        try JSONSerialization.data(withJSONObject: json).write(to: recordURL)

        try fixture.store.remove(original.id)
        #expect(try fixture.store.list().map(\.id) == [other.id])
        #expect(try String(contentsOf: outside, encoding: .utf8) == "keep")
        #expect(FileManager.default.fileExists(atPath: other.workspacePath))
        #expect(throws: (any Error).self) { try fixture.store.remove(original.id) }
        #expect(try fixture.store.load(other.id).resolvedCommit == other.resolvedCommit)
    }

    @Test
    func recordsWithoutRequestedRefStillLoad() throws {
        let fixture = try PreviewManagementFixture()
        defer { fixture.cleanup() }
        let original = try fixture.service.preview(urlString: fixture.url, ref: "v1")
        let recordURL = fixture.store.rootURL.appendingPathComponent(original.id.uuidString).appendingPathComponent("preview.json")
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: recordURL)) as? [String: Any])
        json.removeValue(forKey: "requestedRef")
        try JSONSerialization.data(withJSONObject: json).write(to: recordURL)
        let loaded = try fixture.store.load(original.id)
        #expect(loaded.requestedRef == nil)
        #expect(loaded.resolvedCommit == original.resolvedCommit)
        #expect(loaded.candidates == original.candidates)
    }
}

private struct PreviewManagementFixture {
    let root: URL
    let url = "https://github.com/fixture/skills"
    let service: SourcePreviewService
    let store: SourcePreviewStore

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let remote = root.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        let previews = root.appendingPathComponent("previews")
        store = SourcePreviewStore(rootURL: previews)
        service = SourcePreviewService(previewsRoot: previews, gitEnvironment: [
            "GIT_CONFIG_COUNT": "1",
            "GIT_CONFIG_KEY_0": "url.\(remote.absoluteString).insteadOf",
            "GIT_CONFIG_VALUE_0": "https://github.com/fixture/skills.git"
        ])
        try git(["init", "--initial-branch=main"], at: remote)
        for (tag, content) in [("v1", "First revision"), ("v2", "Second revision")] {
            try "---\nname: fixture\ndescription: \(content)\n---\n\(content)\n".write(
                to: remote.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
            )
            try git(["add", "SKILL.md"], at: remote)
            try git(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.test", "-c", "commit.gpgsign=false", "commit", "-m", tag], at: remote)
            try git(["tag", tag], at: remote)
        }
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }

    private func git(_ arguments: [String], at directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "core.hooksPath=/dev/null", "-C", directory.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
