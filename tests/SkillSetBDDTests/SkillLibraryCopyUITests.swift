import Foundation
import XCTest
import SkillSetCore

/// 技能库页面的文案回归：开关留在详情里，页面不再重复解释用法。
@MainActor
final class SkillLibraryCopyUITests: XCTestCase {
    func testSkillDetailKeepsInvocationSwitchWithoutRedundantCopy() throws {
        try XCTSkipUnless(NativeUIHarness.canRunInCurrentEnvironment, NativeUIHarness.unavailableReason)
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("perch-skill-copy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let harness = try NativeUIHarness(
            repositoryRoot: try Self.locateRepositoryRoot(),
            temporaryRoot: temporaryRoot,
            projectURL: nil,
            projectName: nil,
            skillIDs: [],
            instructionIDs: [],
            agents: ["codex"],
            librarySkillDocuments: [
                "copy-check": "---\nname: copy-check\ndescription: 文案回归用的技能\n---\n正文\n"
            ]
        )
        defer { harness.stop() }

        try harness.selectSidebarItem("技能库")
        try harness.waitForStaticText("copy-check")

        XCTAssertTrue(try harness.hasElement(label: "允许模型隐式调用"),
                      "详情里必须保留调用开关，用户才知道在这里改调用方式")
        XCTAssertFalse(try harness.hasStaticText("在技能详情中调整“允许模型隐式调用”。关闭后会同时更新 Codex 和 Claude Code 的调用元信息，只能由用户显式触发。"),
                       "页面顶部不再常驻解释开关用法")
        XCTAssertFalse(try harness.hasStaticText("保存在本机。到「项目」选择这个技能，预览变更后再写入项目。"),
                       "存储位置和写入步骤由页面标题区说明一次即可")
    }

    private static func locateRepositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while true {
            let candidate = directory.appendingPathComponent("registry/catalog.json")
            if FileManager.default.fileExists(atPath: candidate.path) { return directory }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                throw XCTSkip("找不到包含 registry/catalog.json 的仓库根目录")
            }
            directory = parent
        }
    }
}
