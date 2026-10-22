import Foundation
import SkillSetCore

struct RuleFilePreview: Identifiable {
    let id: String
    let before: String?
    let after: String?
    let diff: String

    static func load(record: StoredDeploymentPlan, change: PlannedChange) throws -> RuleFilePreview {
        let path = change.relativePath
        guard change.scope != "project-state", !path.hasPrefix("/"),
              !path.split(separator: "/").contains(".."),
              ["AGENTS.md", "CLAUDE.md"].contains(URL(fileURLWithPath: path).lastPathComponent) else {
            throw DeploymentError.invalidPlan
        }
        let before = try read(path: path, root: URL(fileURLWithPath: record.plan.projectPath), hash: change.beforeHash)
        let after = try read(path: path, root: URL(fileURLWithPath: record.stagingPath), hash: change.afterHash)
        return RuleFilePreview(id: path, before: before, after: after,
                               diff: difference(before: before ?? "", after: after ?? ""))
    }

    private static func read(path: String, root: URL, hash: String?) throws -> String? {
        let url = root.appendingPathComponent(path).standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        guard url.path.hasPrefix(rootPath == "/" ? "/" : rootPath + "/") else { throw DeploymentError.invalidPlan }
        var cursor = url
        while cursor.path != root.standardizedFileURL.path {
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: cursor.path)) != nil {
                throw DeploymentError.symlinkDetected(cursor.path)
            }
            cursor.deleteLastPathComponent()
        }
        let exists = FileManager.default.fileExists(atPath: url.path)
        guard let hash else {
            // 删除操作没有 staging；新增操作则必须确认目标仍不存在。
            guard !exists else { throw RulePreviewError.changed }
            return nil
        }
        guard exists else { throw RulePreviewError.changed }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 1024 * 1024 else { throw RulePreviewError.tooLarge }
        let data = try Data(contentsOf: url)
        guard SkillAssetCopier.sha256(data) == hash else { throw RulePreviewError.changed }
        guard let text = String(data: data, encoding: .utf8) else { throw RulePreviewError.unreadable }
        return text
    }

    /// 以共同前后缀界定一个替换区间，线性构造行差异，避免长规则的二次方比较。
    static func difference(before: String, after: String) -> String {
        guard before != after else { return "" }
        let old = before.isEmpty ? [] : before.components(separatedBy: "\n")
        let new = after.isEmpty ? [] : after.components(separatedBy: "\n")
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix,
              old[old.count - suffix - 1] == new[new.count - suffix - 1] { suffix += 1 }
        let start = max(0, prefix - 3)
        let contextEnd = min(suffix, 3)
        let oldCount = old.count - suffix - start + contextEnd
        let newCount = new.count - suffix - start + contextEnd
        var lines = ["@@ -\(oldCount == 0 ? start : start + 1),\(oldCount) +\(newCount == 0 ? start : start + 1),\(newCount) @@"]
        lines += old[start..<prefix].map { " " + $0 }
        lines += old[prefix..<(old.count - suffix)].map { "-" + $0 }
        lines += new[prefix..<(new.count - suffix)].map { "+" + $0 }
        lines += old[(old.count - suffix)..<(old.count - suffix + contextEnd)].map { " " + $0 }
        return lines.joined(separator: "\n")
    }
}

enum RulePreviewError: Error {
    case changed, tooLarge, unreadable
}
