import Foundation

/// 计划和 operation 共用的持久化状态，旧字符串值保持兼容。
public enum OperationState: String, Codable, Hashable, Sendable {
    case pending
    case approved
    case applying
    case executing
    case applied
    case appliedVerificationPending = "applied-verification-pending"
    case appliedAfterNonzeroExit = "applied-after-nonzero-exit"
    case failedBeforeLaunch = "failed-before-launch"
    case failed
    case uncertainInterrupted = "uncertain-interrupted"
    case recoveryRequired = "recovery-required"
    case rollingBack = "rolling-back"
    case restoring
    case rolledBack = "rolled-back"
    case failedRolledBack = "failed-rolled-back"

    public var isApplied: Bool {
        switch self {
        case .applied, .appliedVerificationPending, .appliedAfterNonzeroExit:
            return true
        default:
            return false
        }
    }

    public var requiresRecovery: Bool {
        switch self {
        case .uncertainInterrupted, .recoveryRequired:
            return true
        default:
            return false
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .approved, .failed, .failedBeforeLaunch:
            return true
        default:
            return false
        }
    }

    public var approvalState: DeploymentApprovalState {
        isApplied ? .applied : (self == .pending ? .pending : .approved)
    }

    public var isIncompleteFileTransaction: Bool {
        switch self {
        case .applying, .rollingBack:
            return true
        default:
            return false
        }
    }
}
