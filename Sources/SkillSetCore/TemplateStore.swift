import Foundation

public enum TemplateStoreError: Error, LocalizedError, SkillSetCodedError {
    case invalid(String)
    case corrupt
    case notFound

    public var code: String {
        switch self {
        case .invalid: "TEMPLATE_INVALID"
        case .corrupt: "TEMPLATE_STORE_CORRUPT"
        case .notFound: "INSTRUCTION_NOT_FOUND"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalid(let reason): reason
        case .corrupt: "本机片段库无法读取，请检查数据文件后重试。"
        case .notFound: "这个片段已删除，请重新选择。"
        }
    }
}

/// 内置片段通过本机覆盖编辑；删除记录防止重启后重新出现，不改动资源和项目。
public struct TemplateStore {
    public let rootURL: URL
    public var documentURL: URL { rootURL.appendingPathComponent("templates.json") }
    public init(rootURL: URL) { self.rootURL = rootURL }

    private struct Document: Codable {
        var schemaVersion = 1
        var records: [TemplateRecord] = []
        var deletedIDs: [String] = []
    }

    private func load() throws -> Document {
        guard FileManager.default.fileExists(atPath: documentURL.path) else { return Document() }
        do {
            let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: documentURL))
            guard document.schemaVersion == 1,
                  Set(document.records.map(\.id)).count == document.records.count,
                  Set(document.deletedIDs).isDisjoint(with: document.records.map(\.id)),
                  document.records.allSatisfy({ $0.isLocal && Self.validationIssue($0) == nil }) else {
                throw TemplateStoreError.corrupt
            }
            return document
        } catch { throw TemplateStoreError.corrupt }
    }

    public func list(merging initial: [TemplateRecord]) throws -> [TemplateRecord] {
        merge(try load(), with: initial)
    }

    private func merge(_ document: Document, with initial: [TemplateRecord]) -> [TemplateRecord] {
        let local = Dictionary(uniqueKeysWithValues: document.records.map { ($0.id, $0) })
        let initialIDs = Set(initial.map(\.id))
        let deleted = Set(document.deletedIDs)
        return initial.filter { !deleted.contains($0.id) }.map { local[$0.id] ?? $0 }
            + document.records.filter { !initialIDs.contains($0.id) }
    }

    public static func validationIssue(_ record: TemplateRecord) -> String? {
        if record.id.isEmpty { return "找不到片段标识，请关闭后重新新建。" }
        let name = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "请填写片段名称。" }
        if name.count > 80 { return "片段名称最多 80 个字符。" }
        if record.purpose.count > 500 { return "片段说明最多 500 个字符。" }
        if record.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写规则正文。" }
        if record.body.utf8.count > 256 * 1024 { return "规则正文不能超过 256 KiB，请精简后保存。" }
        if record.body.contains("skillset:begin") || record.body.contains("skillset:end") {
            return "正文中不用填写起止标记，请移除标记后保存；栖集会在写入时自动添加。"
        }
        return nil
    }

    @discardableResult
    public func save(_ record: TemplateRecord, initial: [TemplateRecord]) throws -> [TemplateRecord] {
        if let issue = Self.validationIssue(record) { throw TemplateStoreError.invalid(issue) }
        var document = try load()
        let name = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if merge(document, with: initial).contains(where: {
            $0.id != record.id && $0.title.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) { throw TemplateStoreError.invalid("已有同名片段，请换一个名称。") }
        let saved = TemplateRecord(id: record.id, title: name, body: record.body,
                                   purpose: record.purpose.trimmingCharacters(in: .whitespacesAndNewlines), isLocal: true)
        document.records.removeAll { $0.id == record.id }
        document.records.append(saved)
        document.deletedIDs.removeAll { $0 == record.id }
        try write(document)
        return merge(document, with: initial)
    }

    @discardableResult
    public func remove(id: String, initial: [TemplateRecord]) throws -> [TemplateRecord] {
        var document = try load()
        guard merge(document, with: initial).contains(where: { $0.id == id }) else { throw TemplateStoreError.notFound }
        document.records.removeAll { $0.id == id }
        if !document.deletedIDs.contains(id) { document.deletedIDs.append(id) }
        try write(document)
        return merge(document, with: initial)
    }

    private func write(_ document: Document) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try encoder.encode(document).write(to: documentURL, options: .atomic)
    }
}
