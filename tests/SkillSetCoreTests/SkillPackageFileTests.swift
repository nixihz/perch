import Foundation
import Testing
@testable import SkillSetCore

struct SkillPackageFileTests {
    @Test func listsRelativePathsAndReadsRawTextWithoutRunningScripts() throws {
        let fixture = try PackageFixture()
        defer { fixture.cleanup() }
        try fixture.write("README.md", "# 使用说明\n")
        try fixture.write("references/README.md", "<script>doNotRun()</script>\n")
        let sentinel = fixture.root.appendingPathComponent("executed")
        try fixture.write("scripts/run.sh", "#!/bin/sh\ntouch '\(sentinel.path)'\n")
        let files = try fixture.store.attachedFiles(for: fixture.entry(), repositoryRoot: fixture.root)
        #expect(files.map(\.path) == ["README.md", "references/README.md", "scripts/run.sh"])
        #expect(files.map(\.name) == ["README.md", "README.md", "run.sh"])
        #expect(files[1].directory == "references")
        #expect(try fixture.preview("references/README.md") == .text("<script>doNotRun()</script>\n"))
        #expect(try fixture.preview("scripts/run.sh") == .text("#!/bin/sh\ntouch '\(sentinel.path)'\n"))
        #expect(!FileManager.default.fileExists(atPath: sentinel.path))
        #expect(try String(contentsOf: fixture.package.appendingPathComponent("README.md"), encoding: .utf8) == "# 使用说明\n")
    }

    @Test func binaryEmptyAndOversizedFilesHaveExplicitPreviewStates() throws {
        let fixture = try PackageFixture()
        defer { fixture.cleanup() }
        try Data([0x89, 0x50, 0, 0xff]).write(to: fixture.package.appendingPathComponent("image.png"))
        try fixture.write("empty.md", "")
        try fixture.write("control.bin", "binary\u{01}data")
        let limit = SkillLibraryStore.previewByteLimit
        try Data(repeating: 65, count: limit).write(to: fixture.package.appendingPathComponent("large.txt"))
        #expect(try fixture.preview("large.txt") == .text(String(repeating: "A", count: limit)))
        let handle = try FileHandle(forWritingTo: fixture.package.appendingPathComponent("large.txt"))
        try handle.truncate(atOffset: UInt64(limit + 1))
        try handle.close()
        #expect(try fixture.preview("large.txt") == .tooLarge)
        #expect(try fixture.preview("image.png") == .unsupported)
        #expect(try fixture.preview("control.bin") == .unsupported)
        #expect(try fixture.preview("empty.md") == .text(""))
    }

    @Test func excludedFilesCannotBeListedOrOpenedDirectly() throws {
        let fixture = try PackageFixture()
        defer { fixture.cleanup() }
        try fixture.write("references/visible.md", "可读")
        try fixture.write("cache/private.md", "已排除")
        let entry = fixture.entry(excluded: ["cache"])
        #expect(try fixture.store.attachedFiles(for: entry, repositoryRoot: fixture.root).map(\.path) == ["references/visible.md"])
        #expect(throws: SkillLibraryError.unsafePath) {
            try fixture.store.previewAttachedFile("cache/private.md", for: entry, repositoryRoot: fixture.root)
        }
    }

    @Test func traversalDirectoriesAndSymlinkReplacementAreRejected() throws {
        let fixture = try PackageFixture()
        defer { fixture.cleanup() }
        try fixture.write("references/guide.md", "原文")
        let entry = fixture.entry()
        #expect(try fixture.store.attachedFiles(for: entry, repositoryRoot: fixture.root).count == 1)
        for path in ["../outside.md", "/etc/passwd", "references/../SKILL.md", "references//guide.md", "references"] {
            #expect(throws: SkillLibraryError.unsafePath) { try fixture.preview(path) }
        }
        let outside = fixture.root.appendingPathComponent("outside.md")
        try "不应读取".write(to: outside, atomically: true, encoding: .utf8)
        let guide = fixture.package.appendingPathComponent("references/guide.md")
        try FileManager.default.removeItem(at: guide)
        try FileManager.default.createSymbolicLink(at: guide, withDestinationURL: outside)
        #expect(throws: SkillLibraryError.unsafePath) { try fixture.preview("references/guide.md") }
        #expect(throws: SkillLibraryError.unsafePath) {
            try fixture.store.attachedFileURL("references/guide.md", for: entry, repositoryRoot: fixture.root)
        }
        #expect(throws: SkillLibraryError.unsafePath) {
            try fixture.store.attachedFiles(for: entry, repositoryRoot: fixture.root)
        }
        #expect(try String(contentsOf: outside, encoding: .utf8) == "不应读取")
    }

    @Test func personalPackagesAreReadableAndMissingFilesFail() throws {
        let fixture = try PackageFixture()
        defer { fixture.cleanup() }
        let entry = try fixture.store.save(SkillEditorDraft(slug: "demo", document: "---\nname: demo\ndescription: 演示\n---\n正文"), repositoryRoot: nil)
        #expect(try fixture.store.attachedFiles(for: entry, repositoryRoot: nil).isEmpty)
        let package = try #require(fixture.store.sourceURLs()[entry.id])
        try "本地附属文件".write(to: package.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        #expect(try fixture.store.previewAttachedFile("README.md", for: entry, repositoryRoot: nil) == .text("本地附属文件"))
        try FileManager.default.removeItem(at: package.appendingPathComponent("README.md"))
        #expect(throws: (any Error).self) { try fixture.store.previewAttachedFile("README.md", for: entry, repositoryRoot: nil) }
    }
}

private struct PackageFixture {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("package-reader-\(UUID())")
    var package: URL { root.appendingPathComponent("skills/demo") }
    var store: SkillLibraryStore { SkillLibraryStore(rootURL: root.appendingPathComponent("library")) }

    init() throws { try write("SKILL.md", "---\nname: demo\ndescription: 演示\n---\n正文") }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
    func write(_ path: String, _ text: String) throws {
        let url = package.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    func preview(_ path: String) throws -> SkillFilePreview {
        try store.previewAttachedFile(path, for: entry(), repositoryRoot: root)
    }
    func entry(excluded: [String] = []) -> SkillEntry {
        SkillEntry(id: "workspace/demo", slug: "demo", declaredName: "demo", description: "文件预览",
                   declaredVersion: nil, metadataReview: "not-schema-validated", sourceId: "workspace",
                   path: "skills/demo", contentHash: "fixture", fileCount: 1, bytes: 0,
                   integrity: "snapshotted", issues: [], licenseReview: "required", excludedPaths: excluded)
    }
}
