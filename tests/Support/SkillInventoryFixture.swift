import Foundation
import SkillSetCore

/// 公共仓库不分发个人技能，测试自己创建有真实内容指纹的隔离库存。
public enum SkillInventoryFixture {
    public static func create(at root: URL) throws {
        let manager = FileManager.default
        let registry = root.appendingPathComponent("registry")
        try manager.createDirectory(at: registry, withIntermediateDirectories: true)
        var entries: [[String: Any]] = []
        for slug in ["stc", "humanizer-zh", "likec4-dsl", "collaboration-style", "project-guide"] {
            let path = "skills/\(slug)"
            let package = root.appendingPathComponent(path)
            try manager.createDirectory(at: package, withIntermediateDirectories: true)
            let document = "---\nname: \(slug)\ndescription: 隔离测试技能 \(slug)\n---\n# \(slug)\n仅供行为测试使用。\n"
            try document.write(to: package.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            let analysis = try SkillAssetCopier.analyze(from: package)
            entries.append([
                "id": "workspace/\(slug)", "slug": slug, "declaredName": slug,
                "description": "隔离测试技能 \(slug)", "metadataReview": "reviewed",
                "sourceId": "workspace", "path": path, "contentHash": analysis.contentHash,
                "fileCount": analysis.files.count, "bytes": analysis.bytes,
                "integrity": "snapshotted", "issues": [], "excludedPaths": []
            ])
        }
        let catalog: [String: Any] = [
            "schemaVersion": 1, "hashAlgorithm": "sha256:path-content-executable:v1", "entries": entries
        ]
        try JSONSerialization.data(withJSONObject: catalog, options: [.sortedKeys])
            .write(to: registry.appendingPathComponent("catalog.json"))
    }
}
