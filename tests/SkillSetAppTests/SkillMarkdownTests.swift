import AppKit
import SwiftUI
import XCTest
@testable import SkillSetCore
@testable import SkillSetApp

@MainActor
final class SkillMarkdownTests: XCTestCase {
    func testFrontmatterAndGFMBlocksKeepContentAndFormatting() throws {
        let source = """
        ---
        name: demo
        description: 保留原始说明
        ---

        # 使用说明

        这段有 **重点** 和 `inline`。

        3. 首项
        4. 次项

        - [x] 已核对
        - [ ] 待核对

        > 先核对条件。

        | 项目 | 结果 |
        | --- | --- |
        | 预览 | 通过 |

        ```bash
        echo "<token>"
        ```
        """
        let parsed = SkillMarkdownDocument(source: source)
        XCTAssertEqual(parsed.metadata, "name: demo\ndescription: 保留原始说明")
        guard case let .heading(level, title) = parsed.blocks[0],
              case let .paragraph(paragraph) = parsed.blocks[1],
              case let .list(ordered) = parsed.blocks[2],
              case let .list(checks) = parsed.blocks[3],
              case let .quote(quote) = parsed.blocks[4],
              case let .table(header, rows) = parsed.blocks[5],
              case let .code(language, code) = parsed.blocks[6] else {
            return XCTFail("GFM 结构未按标题、段落、列表、引用、表格与代码块解析")
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(String(title.characters), "使用说明")
        XCTAssertEqual(String(paragraph.characters), "这段有 重点 和 inline。")
        XCTAssertTrue(paragraph.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        XCTAssertTrue(paragraph.runs.contains { String(paragraph[$0.range].characters) == "inline" && $0.font != nil })
        XCTAssertEqual(ordered.map(\.marker), ["3.", "4."])
        XCTAssertEqual(checks.map(\.marker), ["☑", "☐"])
        guard case let .paragraph(quotedText) = quote.first else { return XCTFail("引用正文丢失") }
        XCTAssertEqual(String(quotedText.characters), "先核对条件。")
        XCTAssertEqual(header.map { String($0.characters) }, ["项目", "结果"])
        XCTAssertEqual(rows.map { $0.map { String($0.characters) } }, [["预览", "通过"]])
        XCTAssertEqual(language, "bash")
        XCTAssertEqual(code, "echo \"<token>\"\n")
    }

    func testUnclosedFrontmatterAndNonFrontmatterAreNotHidden() {
        XCTAssertNil(SkillMarkdownDocument(source: "---\nname: unfinished\n# 正文").metadata)
        XCTAssertNil(SkillMarkdownDocument(source: "# 标题\n\n---\n\n后续内容").metadata)
        let crlf = SkillMarkdownDocument(source: "---\r\nname: demo\r\n---\r\n# 标题\r\n")
        XCTAssertEqual(crlf.metadata, "name: demo")
        guard case let .heading(_, title) = crlf.blocks.first else { return XCTFail("CRLF 正文丢失") }
        XCTAssertEqual(String(title.characters), "标题")
    }

    func testPreviewKeepsRawHTMLAsTextAndFiltersLinkDestinations() throws {
        let source = """
        <script>alert('不执行')</script>

        [文档](https://example.com/guide) [危险](javascript:alert(1)) [本机](file:///tmp/private)

        ![示意图](https://example.com/image.png)
        """
        let parsed = SkillMarkdownDocument(source: source)
        guard case let .literal(html) = parsed.blocks[0],
              case let .paragraph(links) = parsed.blocks[1],
              case let .paragraph(image) = parsed.blocks[2] else { return XCTFail("原始内容丢失") }
        XCTAssertEqual(html.trimmingCharacters(in: .newlines), "<script>alert('不执行')</script>")
        XCTAssertEqual(links.runs.compactMap(\.link).map(\.absoluteString), ["https://example.com/guide"])
        XCTAssertEqual(String(image.characters), "[示意图]")
        for destination in ["javascript:alert(1)", "file:///tmp/private", "data:text/html,bad", "../secret", "x-custom://open"] {
            XCTAssertNil(SkillMarkdownDocument.allowedLink(destination), destination)
        }
        XCTAssertEqual(SkillMarkdownDocument.allowedLink("mailto:hello@example.com")?.scheme, "mailto")
    }

    func testEditorPreviewKeepsUnsavedInputForNewAndExistingSkills() async throws {
        try await withModel { model, _ in
            for original in [nil, model.selectedSkill] {
                let draft = SkillEditorDraft(slug: "preview-demo", document: "---\nname: preview-demo\ndescription: 演示\n---\n\n# 初始正文\n", original: original)
                let controller = NSHostingController(rootView: SkillEditorSheet(model: model, initialDraft: draft))
                let window = makeWindow(controller, size: NSSize(width: 720, height: 620))
                defer { window.close() }
                try await settle(controller.view)
                let input = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSTextView }.first)
                let changed = draft.document + "\n## 未保存段落\n\n| 项目 | 状态 |\n| --- | --- |\n| 输入 | 保留 |\n"
                input.insertText(changed, replacementRange: NSRange(location: 0, length: input.string.utf16.count))
                try await settle(controller.view)
                let modes = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSSegmentedControl }.first)
                modes.selectedSegment = 1
                _ = modes.sendAction(modes.action, to: modes.target)
                try await settle(controller.view)
                XCTAssertTrue(descendants(controller.view).compactMap { $0 as? NSTextView }.isEmpty)
                XCTAssertLessThanOrEqual(controller.view.fittingSize.width, 721)
                XCTAssertLessThanOrEqual(controller.view.fittingSize.height, 621)
                try screenshot(controller.view, name: original == nil ? "new-preview" : "edit-preview")
                modes.selectedSegment = 0
                _ = modes.sendAction(modes.action, to: modes.target)
                try await settle(controller.view)
                let restored = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSTextView }.first)
                XCTAssertEqual(restored.string, changed, "切换预览不能替换草稿")
                XCTAssertFalse(model.selectedSkillDocument.contains("未保存段落"), "预览不能提前保存技能")
            }
        }
    }

    func testDetailDefaultsToPreviewAndRawSourceRemainsCompleteInBothAppearances() async throws {
        try await withModel { model, _ in
            model.section = .skills
            let controller = NSHostingController(rootView: ContentView(model: model))
            let window = makeWindow(controller, size: NSSize(width: 1080, height: 700))
            defer { window.close() }
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: appearance)
                model.selectedSkillID = model.snapshot.catalog.entries.first { $0.slug == "first-demo" }?.id
                try await settle(controller.view)
                let modes = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSSegmentedControl }.first {
                    $0.segmentCount == 2 && $0.label(forSegment: 1) == L10n.tr("原文")
                })
                XCTAssertEqual(modes.selectedSegment, 0)
                XCTAssertLessThanOrEqual(controller.view.fittingSize.width, 1081)
                XCTAssertLessThanOrEqual(controller.view.fittingSize.height, 701)
                try screenshot(controller.view, name: appearance == .aqua ? "detail-light" : "detail-dark")
                modes.selectedSegment = 1
                _ = modes.sendAction(modes.action, to: modes.target)
                try await settle(controller.view)
                XCTAssertEqual(modes.selectedSegment, 1)
                XCTAssertTrue(model.selectedSkillDocument.hasPrefix("---\nname:"))
                let second = try XCTUnwrap(model.snapshot.catalog.entries.first { $0.slug == "second-demo" })
                model.selectedSkillID = second.id
                try await settle(controller.view)
                let reset = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSSegmentedControl }.first {
                    $0.segmentCount == 2 && $0.label(forSegment: 1) == L10n.tr("原文")
                })
                XCTAssertEqual(reset.selectedSegment, 0, "切换技能应恢复预览")
            }
        }
    }

    private func withModel(_ body: (AppModel, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("markdown-ui-\(UUID())")
        let variables = ["CFFIXED_USER_HOME", "SKILLSET_HOME", "CODEX_HOME"]
        let saved = ProcessInfo.processInfo.environment
        for variable in variables { setenv(variable, root.appendingPathComponent(variable).path, 1) }
        defer {
            for variable in variables {
                if let value = saved[variable] { setenv(variable, value, 1) } else { unsetenv(variable) }
            }
            try? FileManager.default.removeItem(at: root)
        }
        let paths = SkillSetRuntimePaths(applicationSupportRoot: root.appendingPathComponent("state"), repositoryRoot: nil)
        let model = AppModel(runtimePaths: paths)
        for slug in ["first-demo", "second-demo"] {
            XCTAssertTrue(model.saveSkill(SkillEditorDraft(slug: slug, document: "---\nname: \(slug)\ndescription: Markdown 演示\n---\n\n# 技能预览\n\n## 使用步骤\n\n1. 核对 `输入`。\n2. 执行 **任务**。\n\n> 保留原始内容。\n\n```bash\necho preview\n```\n")))
        }
        model.selectedSkillID = model.snapshot.catalog.entries.first { $0.slug == "first-demo" }?.id
        model.loadSelectedSkillDocument()
        try await body(model, root)
    }

    private func makeWindow(_ controller: NSViewController, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        return window
    }

    private func settle(_ view: NSView) async throws {
        try await Task.sleep(for: .milliseconds(160))
        view.layoutSubtreeIfNeeded()
    }

    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }

    private func screenshot(_ view: NSView, name: String) throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SKILLSET_MARKDOWN_SCREENSHOT_DIR"] ?? "/tmp/skillset-markdown-ui")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: root.appendingPathComponent(name + ".png"))
    }
}
