import Foundation
import XCTest
import SkillSetCore
@testable import SkillSetApp

@MainActor
final class SkillInvocationMetadataTests: XCTestCase {
    func testSkillLibraryToggleWritesCodexAndClaudeInvocationMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skill-invocation-(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let skill = try paths.makeLibraryStore().save(
            SkillEditorDraft(slug: "manual-only", document: "---\nname: manual-only\ndescription: 元信息测试\n---\n正文\n"),
            repositoryRoot: nil
        )
        let model = AppModel(runtimePaths: paths)

        XCTAssertTrue(model.setImplicitInvocation(skill, allowed: false), model.skillMetadataError ?? "")
        let current = try XCTUnwrap(model.snapshot.catalog.entries.first { $0.id == skill.id })
        let source = try XCTUnwrap(paths.makeLibraryStore().sourceURLs()[current.id])
        XCTAssertTrue(try String(contentsOf: source.appendingPathComponent("agents/openai.yaml"), encoding: .utf8)
            .contains("allow_implicit_invocation: false"))

        XCTAssertTrue(try String(contentsOf: source.appendingPathComponent("SKILL.md"), encoding: .utf8)
            .contains("disable-model-invocation: true"))
        XCTAssertEqual(model.invocationPolicy(for: try XCTUnwrap(model.snapshot.catalog.entries.first { $0.id == skill.id })),
                       SkillInvocationPolicy(codexManualOnly: true, claudeManualOnly: true))

        XCTAssertTrue(model.setImplicitInvocation(current, allowed: true), model.skillMetadataError ?? "")
        XCTAssertFalse(try String(contentsOf: source.appendingPathComponent("agents/openai.yaml"), encoding: .utf8)
            .contains("allow_implicit_invocation: false"))
        XCTAssertFalse(try String(contentsOf: source.appendingPathComponent("SKILL.md"), encoding: .utf8)
            .contains("disable-model-invocation: true"))
    }
}
