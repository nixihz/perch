import Foundation

public enum DeploymentPlanStoreError: Error, LocalizedError, Equatable, Sendable {
    case planNotFound(String)
    case digestMismatch
    case expired(String)
    case approvalRequired(String)
    case alreadyApplied(String)
    case invalidState(String)
    case corruptRecord(String)

    public var code: String {
        switch self {
        case .planNotFound: "PLAN_NOT_FOUND"
        case .digestMismatch: "PLAN_DIGEST_MISMATCH"
        case .expired: "PLAN_EXPIRED"
        case .approvalRequired: "APPROVAL_REQUIRED"
        case .alreadyApplied: "PLAN_ALREADY_APPLIED"
        case .invalidState: "PLAN_INVALID_STATE"
        case .corruptRecord: "PLAN_RECORD_CORRUPT"
        }
    }

    public var errorDescription: String? {
        switch self {
        case let .planNotFound(id):
            return "找不到变更计划：\(id)"
        case .digestMismatch:
            return "计划内容与提交的 digest 不一致。"
        case let .expired(id):
            return "变更计划已过期，请重新生成：\(id)"
        case let .approvalRequired(id):
            return "变更计划尚未获得本机人工批准：\(id)"
        case let .alreadyApplied(id):
            return "变更计划已经执行，不能重复应用：\(id)"
        case let .invalidState(state):
            return "计划状态不允许当前操作：\(state)"
        case let .corruptRecord(path):
            return "计划记录无法读取：\(path)"
        }
    }
}

public enum DeploymentApprovalState: String, Codable, Hashable, Sendable {
    case pending
    case approved
    case applied
}

public struct StoredDeploymentPlan: Codable, Identifiable, Hashable, Sendable {
    public let schemaVersion: Int
    public let plan: DeploymentPlan
    public let expiresAt: Date
    public let stagingPath: String
    public var approvalState: DeploymentApprovalState
    public var approvedAt: Date?
    public var operationID: UUID?

    public var id: UUID { plan.id }

    public init(
        schemaVersion: Int = 1,
        plan: DeploymentPlan,
        expiresAt: Date,
        stagingPath: String,
        approvalState: DeploymentApprovalState = .pending,
        approvedAt: Date? = nil,
        operationID: UUID? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.plan = plan
        self.expiresAt = expiresAt
        self.stagingPath = stagingPath
        self.approvalState = approvalState
        self.approvedAt = approvedAt
        self.operationID = operationID
    }

    public func isExpired(at date: Date) -> Bool {
        date > expiresAt
    }
}

/// 只负责保存不可变计划与批准状态；文件写入仍由 FileTransactionExecutor 执行。
public struct DeploymentPlanStore {
    public let rootURL: URL

    private let fileManager: FileManager
    private let clock: () -> Date

    public init(
        rootURL: URL,
        fileManager: FileManager = .default,
        clock: @escaping () -> Date = Date.init
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.clock = clock
    }

    public static var defaultRootURL: URL {
        ProjectStore.defaultRootURL.appendingPathComponent("plans", isDirectory: true)
    }

    public func save(
        plan: DeploymentPlan,
        stagingPath: String,
        expiresAt: Date? = nil
    ) throws -> StoredDeploymentPlan {
        let record = StoredDeploymentPlan(
            plan: plan,
            expiresAt: expiresAt ?? clock().addingTimeInterval(10 * 60),
            stagingPath: stagingPath
        )
        try write(record)
        return record
    }

    public func load(_ id: UUID) throws -> StoredDeploymentPlan {
        let url = recordURL(id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw DeploymentPlanStoreError.planNotFound(id.uuidString)
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(StoredDeploymentPlan.self, from: data)
        } catch {
            throw DeploymentPlanStoreError.corruptRecord(url.path)
        }
    }

    public func list() throws -> [StoredDeploymentPlan] {
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return try urls.compactMap { url -> StoredDeploymentPlan? in
            guard url.lastPathComponent != ".DS_Store",
                  let id = UUID(uuidString: url.lastPathComponent) else {
                return nil
            }
            return try load(id)
        }.sorted { $0.plan.createdAt > $1.plan.createdAt }
    }

    @discardableResult
    public func approve(id: UUID, digest: String) throws -> StoredDeploymentPlan {
        var record = try load(id)
        guard record.plan.digest == digest else {
            throw DeploymentPlanStoreError.digestMismatch
        }
        guard !record.isExpired(at: clock()) else {
            throw DeploymentPlanStoreError.expired(id.uuidString)
        }
        guard record.approvalState != .applied else {
            throw DeploymentPlanStoreError.alreadyApplied(id.uuidString)
        }
        if record.approvalState == .approved {
            return record
        }
        record.approvalState = .approved
        record.approvedAt = clock()
        try write(record)
        return record
    }

    @discardableResult
    public func markApplied(id: UUID, digest: String, operationID: UUID) throws -> StoredDeploymentPlan {
        var record = try load(id)
        guard record.plan.digest == digest else {
            throw DeploymentPlanStoreError.digestMismatch
        }
        if record.approvalState == .applied {
            guard record.operationID == operationID else {
                throw DeploymentPlanStoreError.alreadyApplied(id.uuidString)
            }
            return record
        }
        guard record.approvalState == .approved else {
            throw DeploymentPlanStoreError.approvalRequired(id.uuidString)
        }
        guard !record.isExpired(at: clock()) else {
            throw DeploymentPlanStoreError.expired(id.uuidString)
        }
        record.approvalState = .applied
        record.operationID = operationID
        try write(record)
        return record
    }

    /// MCP/CLI 执行前使用同一入口复核批准状态，避免只检查一个布尔参数。
    public func requireApprovedForApply(id: UUID, digest: String) throws -> StoredDeploymentPlan {
        let record = try load(id)
        guard record.plan.digest == digest else {
            throw DeploymentPlanStoreError.digestMismatch
        }
        guard record.approvalState == .approved else {
            if record.approvalState == .applied {
                throw DeploymentPlanStoreError.alreadyApplied(id.uuidString)
            }
            throw DeploymentPlanStoreError.approvalRequired(id.uuidString)
        }
        guard !record.isExpired(at: clock()) else {
            throw DeploymentPlanStoreError.expired(id.uuidString)
        }
        return record
    }

    private func write(_ record: StoredDeploymentPlan) throws {
        let directory = recordURL(record.id).deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(record).write(to: recordURL(record.id), options: .atomic)
    }

    private func recordURL(_ id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
            .appendingPathComponent("plan.json")
    }
}
