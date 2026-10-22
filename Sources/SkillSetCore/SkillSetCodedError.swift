import Foundation

public protocol SkillSetCodedError: Error {
    var code: String { get }
}

extension DeploymentError: SkillSetCodedError {}
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
extension PluginLifecycleError: SkillSetCodedError {}
