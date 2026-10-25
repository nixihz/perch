import Foundation

extension SkillSetService {
    /// 配置来源只保留检出。技能进入库必须单独选择软链或复制，同步不再把来源技能写入库。
    public func synchronizeSourceLibrary(excluding excludedID: UUID? = nil) throws {
        _ = excludedID
    }

    public func removeSource(_ id: UUID) throws {
        let store = SourcePreviewStore(rootURL: paths.previewsRoot)
        let record = try store.load(id)
        let hidden = paths.previewsRoot.appendingPathComponent(".pending-remove-\(id)")
        let directory = paths.previewsRoot.appendingPathComponent(id.uuidString)
        try FileManager.default.moveItem(at: directory, to: hidden)
        do { try synchronizeSourceLibrary() }
        catch {
            try FileManager.default.moveItem(at: hidden, to: directory)
            throw error
        }
        _ = record
        try? FileManager.default.removeItem(at: hidden)
    }
}
