import Foundation

extension GlobalConfigurationManager {
    public func makeUndoPlan(host: SkillConfigurationTarget, operationID: UUID) throws -> StoredDeploymentPlan {
        _ = try loadState(host)
        guard let operation = try history(host: host).first(where: { $0.id == operationID }), operation.canUndo else {
            throw GlobalConfigurationError.staleOperation
        }
        let journal = operation.journal
        let root = locations.transactionRoot(host)
        let statePath = relative(locations.stateURL(host), root: root)
        guard let stateStep = journal.steps.first(where: { $0.relativePath == statePath }) else {
            throw GlobalConfigurationError.verificationFailed(.missingStateStep, path: paths.operationsRoot.appendingPathComponent(operationID.uuidString + "/journal.json").path)
        }
        let operationRoot = paths.operationsRoot.appendingPathComponent(operationID.uuidString)
        let previous: GlobalConfigurationState
        if let beforeHash = stateStep.beforeHash {
            let backup = operationRoot.appendingPathComponent("backup/\(statePath)")
            guard try hash(backup) == beforeHash else { throw GlobalConfigurationError.baselineMissing }
            do {
                let decoded = try JSONDecoder().decode(GlobalConfigurationState.self, from: Data(contentsOf: backup))
                previous = try canonicalState(decoded, host: host, path: backup.path)
            }
            catch { throw GlobalConfigurationError.verificationFailed(.invalidBackup, path: backup.path) }
        } else {
            previous = GlobalConfigurationState(host: host, skillsPath: locations.skillsRoot(host).path,
                rulesPath: (locations.rulesURL(for: host)?.path ?? ""), selection: GlobalConfigurationDraft(), managed: [:])
        }
        let builder = try GlobalPlanBuilder(manager: self, host: host, action: "undo")
        defer { builder.cleanup() }
        guard builder.observations[statePath]?.contentHash == stateStep.afterHash else {
            throw GlobalConfigurationError.staleOperation
        }
        for step in journal.steps where step.relativePath != statePath {
            let target = root.appendingPathComponent(step.relativePath)
            guard allowedResource(target, host: host) else { throw DeploymentError.invalidPlan }
            let actual = try builder.observe(target)
            let backup = operationRoot.appendingPathComponent("backup/\(step.relativePath)")
            if let expected = step.beforeHash, try hash(backup) != expected { throw GlobalConfigurationError.baselineMissing }
            if target == locations.rulesURL(for: host) {
                // 保存的 staging 是该操作写入后的字节，用于只比较规则块并保留块外编辑。
                let record = try DeploymentPlanStore(rootURL: paths.plansRoot).load(journal.planID)
                let stage = URL(fileURLWithPath: record.stagingPath).standardizedFileURL
                guard stage.path.hasPrefix(paths.stagingRoot.standardizedFileURL.path + "/") else { throw DeploymentError.invalidPlan }
                let after = stage.appendingPathComponent(step.relativePath)
                if let expected = step.afterHash, try hash(after) != expected { throw GlobalConfigurationError.baselineMissing }
                let written = step.afterHash == nil ? Data() : try Data(contentsOf: after)
                let original = step.beforeHash == nil ? nil : try Data(contentsOf: backup)
                let restored = try GlobalRuleEditing.restore(current: try dataIfPresent(target) ?? Data(), written: written, original: original, path: target.path)
                try builder.write(restored, to: target, summary: "撤销此次规则变更，保留块外编辑")
            } else {
                guard actual == step.afterHash else { throw FileTransactionError.rollbackConflict(target.path) }
                if step.beforeHash != nil {
                    try fileManager.createDirectory(at: builder.staged(target).deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fileManager.copyItem(at: backup, to: builder.staged(target))
                }
                builder.append(target, before: actual, after: step.beforeHash, summary: "撤销此次全局技能变更")
            }
        }
        // 停止管理只改变本机状态；撤销停止管理前仍需复核将重新接管的内容。
        for (path, resource) in previous.managed where !journal.steps.contains(where: { $0.relativePath == relative(URL(fileURLWithPath: path), root: root) }) {
            let target = URL(fileURLWithPath: path)
            guard allowedResource(target, host: host) else { throw DeploymentError.invalidPlan }
            let actual = try builder.observe(target)
            if target == locations.rulesURL(for: host) {
                guard let data = try dataIfPresent(target),
                      try ruleBody(data, path: target.path).map({ SkillAssetCopier.sha256(Data($0.utf8)) }) == resource.hash else {
                    throw DeploymentError.managedRuleDrift(path)
                }
            } else if actual != resource.hash { throw DeploymentError.managedSkillDrift(path) }
        }
        return try builder.finish(state: previous)
    }

    private func canonicalState(_ state: GlobalConfigurationState, host: SkillConfigurationTarget, path: String) throws -> GlobalConfigurationState {
        guard state.skillsPath == locations.skillsRoot(host).path,
              state.rulesPath == (locations.rulesURL(for: host)?.path ?? "") else {
            return try canonicalizeStatePaths(state, host: host, path: path)
        }
        return state
    }
}
