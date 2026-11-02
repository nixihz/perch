import Foundation

public enum DeploymentPlanStoreError: Error, LocalizedError, Equatable, Sendable {
    case planNotFound(String)
    case digestMismatch
    case expired(String)
    case approvalRequired(String)
    case alreadyApplied(String)
    case idempotencyKeyInvalid
    case idempotencyKeyMismatch(String)
    case recoveryRequired(String)
    case invalidState(String)
    case corruptRecord(String)

    public var code: String {
        switch self {
        case .planNotFound: "PLAN_NOT_FOUND"
        case .digestMismatch: "PLAN_DIGEST_MISMATCH"
        case .expired: "PLAN_EXPIRED"
        case .approvalRequired: "APPROVAL_REQUIRED"
        case .alreadyApplied: "PLAN_ALREADY_APPLIED"
        case .idempotencyKeyInvalid: "IDEMPOTENCY_KEY_INVALID"
        case .idempotencyKeyMismatch: "IDEMPOTENCY_KEY_MISMATCH"
        case .recoveryRequired: "RECOVERY_REQUIRED"
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
        case .idempotencyKeyInvalid:
            return "幂等键不能为空，且不能包含控制字符。"
        case let .idempotencyKeyMismatch(id):
            return "计划已绑定其他幂等键，不能用不同请求重试：\(id)"
        case let .recoveryRequired(id):
            return "计划对应的 operation 结果不确定，需要先检查或恢复：\(id)"
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

public struct ApplyReceipt: Codable, Hashable, Sendable {
    public let operationID: UUID
    public let changedPaths: [String]
    public let journalPath: String
    public let message: String?

    public init(operationID: UUID, changedPaths: [String], journalPath: String, message: String? = nil) {
        self.operationID = operationID
        self.changedPaths = changedPaths
        self.journalPath = journalPath
        self.message = message
    }
}

public struct StoredDeploymentPlan: Codable, Identifiable, Hashable, Sendable {
    public let schemaVersion: Int
    public let plan: DeploymentPlan
    public let expiresAt: Date
    public let stagingPath: String
    public var state: OperationState
    public var approvedAt: Date?
    public var operationID: UUID?
    public var idempotencyKey: String?
    public var applyReceipt: ApplyReceipt?

    public var id: UUID { plan.id }

    public var approvalState: DeploymentApprovalState {
        get { state.approvalState }
        set {
            state = switch newValue {
            case .pending: .pending
            case .approved: .approved
            case .applied: .applied
            }
        }
    }

    public init(
        schemaVersion: Int = 1,
        plan: DeploymentPlan,
        expiresAt: Date,
        stagingPath: String,
        approvalState: DeploymentApprovalState = .pending,
        approvedAt: Date? = nil,
        operationID: UUID? = nil,
        state: OperationState? = nil,
        idempotencyKey: String? = nil,
        applyReceipt: ApplyReceipt? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.plan = plan
        self.expiresAt = expiresAt
        self.stagingPath = stagingPath
        self.state = state ?? {
            switch approvalState {
            case .pending: .pending
            case .approved: .approved
            case .applied: .applied
            }
        }()
        self.approvedAt = approvedAt
        self.operationID = operationID
        self.idempotencyKey = idempotencyKey
        self.applyReceipt = applyReceipt
    }

    public func isExpired(at date: Date) -> Bool {
        date > expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case plan
        case expiresAt
        case stagingPath
        case state
        case approvalState
        case approvedAt
        case operationID
        case idempotencyKey
        case applyReceipt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        plan = try container.decode(DeploymentPlan.self, forKey: .plan)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        stagingPath = try container.decode(String.self, forKey: .stagingPath)
        if let state = try container.decodeIfPresent(OperationState.self, forKey: .state) {
            self.state = state
        } else {
            let legacy = try container.decodeIfPresent(DeploymentApprovalState.self, forKey: .approvalState) ?? .pending
            self.state = switch legacy {
            case .pending: .pending
            case .approved: .approved
            case .applied: .applied
            }
        }
        approvedAt = try container.decodeIfPresent(Date.self, forKey: .approvedAt)
        operationID = try container.decodeIfPresent(UUID.self, forKey: .operationID)
        idempotencyKey = try container.decodeIfPresent(String.self, forKey: .idempotencyKey)
        applyReceipt = try container.decodeIfPresent(ApplyReceipt.self, forKey: .applyReceipt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(plan, forKey: .plan)
        try container.encode(expiresAt, forKey: .expiresAt)
        try container.encode(stagingPath, forKey: .stagingPath)
        try container.encode(state, forKey: .state)
        try container.encode(approvalState, forKey: .approvalState)
        try container.encodeIfPresent(approvedAt, forKey: .approvedAt)
        try container.encodeIfPresent(operationID, forKey: .operationID)
        try container.encodeIfPresent(idempotencyKey, forKey: .idempotencyKey)
        try container.encodeIfPresent(applyReceipt, forKey: .applyReceipt)
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

    @discardableResult
    public func beginApply(
        id: UUID,
        digest: String,
        operationID: UUID,
        idempotencyKey: String?
    ) throws -> StoredDeploymentPlan {
        var record = try load(id)
        try validateIdempotencyKey(idempotencyKey)
        guard record.plan.digest == digest else {
            throw DeploymentPlanStoreError.digestMismatch
        }
        guard !record.isExpired(at: clock()) else {
            throw DeploymentPlanStoreError.expired(id.uuidString)
        }
        if record.state.isApplied {
            if let idempotencyKey,
               record.idempotencyKey == idempotencyKey,
               let receipt = record.applyReceipt {
                record.operationID = receipt.operationID
                return record
            }
            throw DeploymentPlanStoreError.alreadyApplied(id.uuidString)
        }
        if record.state.requiresRecovery {
            throw DeploymentPlanStoreError.recoveryRequired(id.uuidString)
        }
        if record.state == .pending {
            throw DeploymentPlanStoreError.approvalRequired(id.uuidString)
        }
        guard record.state == .approved || record.state.isRetryable else {
            throw DeploymentPlanStoreError.invalidState(record.state.rawValue)
        }
        try verifyIdempotencyKey(idempotencyKey, record: record)
        if record.idempotencyKey == nil {
            record.idempotencyKey = idempotencyKey
        }
        record.state = .applying
        record.operationID = operationID
        record.applyReceipt = nil
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
        guard !record.state.isApplied else {
            throw DeploymentPlanStoreError.alreadyApplied(id.uuidString)
        }
        guard record.state == .pending || record.state.isRetryable else {
            throw DeploymentPlanStoreError.invalidState(record.state.rawValue)
        }
        if record.state == .approved {
            return record
        }
        record.state = .approved
        record.approvedAt = clock()
        try write(record)
        return record
    }

    @discardableResult
    public func markApplied(
        id: UUID,
        digest: String,
        operationID: UUID,
        receipt: ApplyReceipt? = nil,
        state: OperationState = .applied
    ) throws -> StoredDeploymentPlan {
        var record = try load(id)
        guard record.plan.digest == digest else {
            throw DeploymentPlanStoreError.digestMismatch
        }
        if record.state.isApplied {
            guard record.operationID == operationID else {
                throw DeploymentPlanStoreError.alreadyApplied(id.uuidString)
            }
            return record
        }
        guard record.state == .applying || record.state == .approved else {
            throw DeploymentPlanStoreError.approvalRequired(id.uuidString)
        }
        guard !record.isExpired(at: clock()) else {
            throw DeploymentPlanStoreError.expired(id.uuidString)
        }
        record.state = state
        record.operationID = operationID
        record.applyReceipt = receipt
        try write(record)
        return record
    }

    @discardableResult
    public func markFailed(id: UUID, digest: String, operationID: UUID) throws -> StoredDeploymentPlan {
        try markState(id: id, digest: digest, operationID: operationID, state: .failed)
    }

    @discardableResult
    public func markRecoveryRequired(id: UUID, digest: String, operationID: UUID) throws -> StoredDeploymentPlan {
        try markState(id: id, digest: digest, operationID: operationID, state: .recoveryRequired)
    }

    @discardableResult
    public func markUncertain(id: UUID, digest: String, operationID: UUID) throws -> StoredDeploymentPlan {
        try markState(id: id, digest: digest, operationID: operationID, state: .uncertainInterrupted)
    }

    @discardableResult
    public func markRetryable(id: UUID, digest: String) throws -> StoredDeploymentPlan {
        var record = try load(id)
        guard record.plan.digest == digest else {
            throw DeploymentPlanStoreError.digestMismatch
        }
        guard !record.state.isApplied else {
            throw DeploymentPlanStoreError.alreadyApplied(id.uuidString)
        }
        record.state = .failed
        record.applyReceipt = nil
        try write(record)
        return record
    }

    private func markState(id: UUID, digest: String, operationID: UUID, state: OperationState) throws -> StoredDeploymentPlan {
        var record = try load(id)
        guard record.plan.digest == digest else {
            throw DeploymentPlanStoreError.digestMismatch
        }
        guard record.operationID == operationID else {
            throw DeploymentPlanStoreError.invalidState(record.state.rawValue)
        }
        record.state = state
        try write(record)
        return record
    }

    /// MCP/CLI 执行前使用同一入口复核批准状态，避免只检查一个布尔参数。
    public func requireApprovedForApply(id: UUID, digest: String) throws -> StoredDeploymentPlan {
        let record = try load(id)
        guard record.plan.digest == digest else {
            throw DeploymentPlanStoreError.digestMismatch
        }
        guard record.state == .approved || record.state.isRetryable else {
            if record.state.isApplied {
                throw DeploymentPlanStoreError.alreadyApplied(id.uuidString)
            }
            if record.state.requiresRecovery {
                throw DeploymentPlanStoreError.recoveryRequired(id.uuidString)
            }
            throw DeploymentPlanStoreError.approvalRequired(id.uuidString)
        }
        guard !record.isExpired(at: clock()) else {
            throw DeploymentPlanStoreError.expired(id.uuidString)
        }
        return record
    }

    private func validateIdempotencyKey(_ key: String?) throws {
        guard let key else { return }
        guard !key.isEmpty, key.count <= 256,
              key.unicodeScalars.allSatisfy({
                  String($0).rangeOfCharacter(from: .controlCharacters) == nil
              }) else {
            throw DeploymentPlanStoreError.idempotencyKeyInvalid
        }
    }

    private func verifyIdempotencyKey(_ key: String?, record: StoredDeploymentPlan) throws {
        guard let existing = record.idempotencyKey else { return }
        guard key == existing else {
            throw DeploymentPlanStoreError.idempotencyKeyMismatch(record.id.uuidString)
        }
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
