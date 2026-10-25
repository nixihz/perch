import Foundation

public protocol SkillSetCodedError: Error {
    var code: String { get }
}

/// 只携带稳定错误码的错误。批量结果里的失败原因用它交给界面层翻译。
public struct SkillSetCodedFailure: Error, SkillSetCodedError, Sendable {
    public let code: String

    public init(code: String) {
        self.code = code
    }
}

extension DeploymentError: SkillSetCodedError {}
extension SkillObjectStoreError: SkillSetCodedError {}
extension ProjectLockError: SkillSetCodedError {}
extension SkillAssetCopyError: SkillSetCodedError {
    public var code: String { "SKILL_ASSET_UNSAFE" }
}
extension SkillSetStoreError: SkillSetCodedError {}
extension ManagedBlockError: SkillSetCodedError {}
extension FileTransactionError: SkillSetCodedError {}
extension DeploymentPlanStoreError: SkillSetCodedError {}
extension ProjectDraftStoreError: SkillSetCodedError {}
extension SkillSetServiceError: SkillSetCodedError {}
extension SourcePreviewError: SkillSetCodedError {}
extension SkillsShDirectoryError: SkillSetCodedError {}
extension PluginLifecycleError: SkillSetCodedError {}
