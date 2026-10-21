import Foundation

public enum ManagedBlockError: Error, LocalizedError, Equatable, Sendable {
    case duplicateBegin(String)
    case duplicateEnd(String)
    case endWithoutBegin(String)
    case mismatchedEnd(expected: String, actual: String)
    case nestedBegin(String)
    case missingEnd(String)
    case nestedMarkerInBody

    public var code: String {
        switch self {
        case .duplicateBegin: "MANAGED_BLOCK_DUPLICATE"
        case .duplicateEnd: "MANAGED_BLOCK_DUPLICATE"
        case .endWithoutBegin: "MANAGED_BLOCK_UNBALANCED"
        case .mismatchedEnd: "MANAGED_BLOCK_MISMATCH"
        case .nestedBegin: "MANAGED_BLOCK_NESTED"
        case .missingEnd: "MANAGED_BLOCK_MISSING_END"
        case .nestedMarkerInBody: "MANAGED_BLOCK_NESTED"
        }
    }

    public var errorDescription: String? {
        switch self {
        case let .duplicateBegin(id):
            return "受管块 \(id) 出现重复起始标记。"
        case let .duplicateEnd(id):
            return "受管块 \(id) 出现重复结束标记。"
        case let .endWithoutBegin(id):
            return "受管块 \(id) 出现没有起始标记的结束标记。"
        case let .mismatchedEnd(expected, actual):
            return "受管块结束标记不匹配：需要 \(expected)，实际是 \(actual)。"
        case let .nestedBegin(id):
            return "受管块 \(id) 出现嵌套起始标记。"
        case let .missingEnd(id):
            return "受管块 \(id) 缺少结束标记。"
        case .nestedMarkerInBody:
            return "受管块正文不能包含受管标记。"
        }
    }
}

public struct ManagedBlockChange: Hashable, Sendable {
    public let content: String
    public let changed: Bool
    public let wasInserted: Bool

    public init(content: String, changed: Bool, wasInserted: Bool) {
        self.content = content
        self.changed = changed
        self.wasInserted = wasInserted
    }
}

public enum ManagedBlocks {
    public static func beginMarker(id: String, schema: Int = 1) -> String {
        "<!-- skillset:begin id=\(id) schema=\(schema) -->"
    }

    public static func endMarker(id: String) -> String {
        "<!-- skillset:end id=\(id) -->"
    }

    /// 只替换指定受管块；块外文本通过逐行拼接保留，避免全量重写用户文件。
    public static func upsert(
        original: String,
        id: String,
        body: String,
        schema: Int = 1
    ) throws -> ManagedBlockChange {
        guard !body.contains("skillset:begin"), !body.contains("skillset:end") else {
            throw ManagedBlockError.nestedMarkerInBody
        }

        let begin = beginMarker(id: id, schema: schema)
        let end = endMarker(id: id)
        let lines = original.components(separatedBy: "\n")
        let blocks = try validatedBlocks(in: lines)

        let block = [begin] + body.components(separatedBy: "\n") + [end]
        guard let existing = blocks.first(where: { $0.id == id }) else {
            let suffix = original.isEmpty || original.hasSuffix("\n") ? "" : "\n"
            return ManagedBlockChange(
                content: original + suffix + block.joined(separator: "\n"),
                changed: true,
                wasInserted: true
            )
        }

        var updated = lines
        updated.replaceSubrange(existing.begin...existing.end, with: block)
        let content = updated.joined(separator: "\n")
        return ManagedBlockChange(
            content: content,
            changed: content != original,
            wasInserted: false
        )
    }

    public static func extract(original: String, id: String, schema: Int = 1) throws -> String? {
        let lines = original.components(separatedBy: "\n")
        let blocks = try validatedBlocks(in: lines)
        guard let block = blocks.first(where: { $0.id == id }) else { return nil }
        return lines[(block.begin + 1)..<block.end].joined(separator: "\n")
    }

    /// 只移除指定受管块及其相邻空行，块外正文保持不变。
    public static func remove(original: String, id: String, schema: Int = 1) throws -> ManagedBlockChange {
        let lines = original.components(separatedBy: "\n")
        let blocks = try validatedBlocks(in: lines)
        guard let block = blocks.first(where: { $0.id == id }) else {
            return ManagedBlockChange(content: original, changed: false, wasInserted: false)
        }

        var updated = lines
        updated.removeSubrange(block.begin...block.end)
        if block.begin < updated.count,
           updated[block.begin].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.remove(at: block.begin)
        } else if block.begin > 0,
                  updated[block.begin - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.remove(at: block.begin - 1)
        }
        let content = updated.joined(separator: "\n")
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : content
        return ManagedBlockChange(content: normalized, changed: normalized != original, wasInserted: false)
    }

    private struct BeginMarker {
        let id: String
    }

    private struct EndMarker {
        let id: String
    }

    private struct BlockRange {
        let id: String
        let begin: Int
        let end: Int
    }

    private static func validatedBlocks(in lines: [String]) throws -> [BlockRange] {
        var blocks: [BlockRange] = []
        var active: (id: String, start: Int)?
        var seenIDs: Set<String> = []

        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if let marker = parseBegin(line) {
                guard active == nil else {
                    throw ManagedBlockError.nestedBegin(marker.id)
                }
                guard !seenIDs.contains(marker.id) else {
                    throw ManagedBlockError.duplicateBegin(marker.id)
                }
                active = (marker.id, index)
                continue
            }
            if let marker = parseEnd(line) {
                guard let current = active else {
                    throw ManagedBlockError.endWithoutBegin(marker.id)
                }
                guard marker.id == current.id else {
                    throw ManagedBlockError.mismatchedEnd(expected: current.id, actual: marker.id)
                }
                blocks.append(BlockRange(id: current.id, begin: current.start, end: index))
                seenIDs.insert(current.id)
                active = nil
            }
        }

        if let active {
            throw ManagedBlockError.missingEnd(active.id)
        }
        return blocks
    }

    private static func parseBegin(_ line: String) -> BeginMarker? {
        let prefix = "<!-- skillset:begin id="
        guard line.hasPrefix(prefix), line.hasSuffix(" -->") else { return nil }
        let value = String(line.dropFirst(prefix.count).dropLast(4))
        guard let separator = value.range(of: " schema=") else { return nil }
        let id = String(value[..<separator.lowerBound])
        return id.isEmpty ? nil : BeginMarker(id: id)
    }

    private static func parseEnd(_ line: String) -> EndMarker? {
        let prefix = "<!-- skillset:end id="
        guard line.hasPrefix(prefix), line.hasSuffix(" -->") else { return nil }
        let id = String(line.dropFirst(prefix.count).dropLast(4))
        return id.isEmpty ? nil : EndMarker(id: id)
    }
}
