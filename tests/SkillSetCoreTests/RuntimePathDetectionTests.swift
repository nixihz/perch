import Foundation
import Testing
@testable import SkillSetCore

struct RuntimePathDetectionTests {
    @Test
    func packagedAppFindsLibraryInsideBundleResources() throws {
        let root = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .appendingPathComponent("runtime-paths-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("栖集.app/Contents/Resources")
        let library = resources.appendingPathComponent("SkillSetLibrary")
        try FileManager.default.createDirectory(at: library.appendingPathComponent("registry"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: library.appendingPathComponent("registry/catalog.json"))

        let paths = SkillSetRuntimePaths.detect(
            environment: [:],
            executableURL: root.appendingPathComponent("栖集.app/Contents/MacOS/SkillSet"),
            currentDirectoryURL: root.appendingPathComponent("empty-working-directory"),
            bundleResourceURL: resources,
            applicationSupportRoot: root.appendingPathComponent("state")
        )

        #expect(paths.repositoryRoot == library.resolvingSymlinksInPath().standardizedFileURL)
    }
}
