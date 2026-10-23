import Foundation
import Darwin
import Testing
@testable import SkillSetCore

struct RootTransactionPathTests {
    @Test(arguments: [false, true])
    func filesystemRootPlanRejectsReplacedParentWithoutWriting(useSymlink: Bool) throws {
        let fm = FileManager.default
        // Foundation 会将 /private/var 归一成 /var；这里需要实际无软链路径。
        let temporaryPath = try #require(realpath(fm.temporaryDirectory.path, nil))
        defer { free(temporaryPath) }
        let fixture = URL(fileURLWithPath: String(cString: temporaryPath))
            .appendingPathComponent("root-transaction-\(UUID())")
        defer { try? fm.removeItem(at: fixture) }
        let project = fixture.appendingPathComponent("project")
        let outside = fixture.appendingPathComponent("outside")
        let staging = fixture.appendingPathComponent("staging")
        let destination = project.appendingPathComponent(".codex/config.toml")
        // 使用 / 作为事务根复现跨卷计划；所有实际读写仍限制在临时目录中。
        let relativePath = String(destination.path.dropFirst())
        let staged = staging.appendingPathComponent(relativePath)
        for directory in [project, outside, staged.deletingLastPathComponent()] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let content = "[mcp_servers.docs]\ncommand = \"docs\"\n"
        try content.write(to: staged, atomically: true, encoding: .utf8)
        let change = PlannedChange(action: "add", relativePath: relativePath, beforeHash: nil,
            afterHash: try SkillAssetCopier.sha256(fileAt: staged), unifiedDiff: "新增项目 MCP")
        let plan = DeploymentPlan(projectPath: "/", createdAt: Date(),
            digest: DeploymentPlanner.calculateDigest(projectPath: "/", changes: [change], selectedSkills: []),
            changes: [change], warnings: [])
        let executor = FileTransactionExecutor(operationsRoot: fixture.appendingPathComponent("operations"))
        if useSymlink {
            try fm.createSymbolicLink(at: destination.deletingLastPathComponent(), withDestinationURL: outside)
            #expect(throws: FileTransactionError.self) { try executor.apply(plan: plan, from: staging) }
            #expect(!fm.fileExists(atPath: outside.appendingPathComponent("config.toml").path))
        } else {
            _ = try executor.apply(plan: plan, from: staging)
            #expect(try String(contentsOf: destination, encoding: .utf8) == content)
        }
    }
}
