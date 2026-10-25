import Foundation

extension GlobalConfigurationManager {
    public func makeDeploymentPlan(
        host: MCPHost, selection: GlobalConfigurationDraft, catalog: CatalogDocument,
        sourceURLs: [String: URL], fragments: [String: String], takeOverExisting: Bool = false,
        installMethod: SkillInstallMethod = .copy
    ) throws -> StoredDeploymentPlan {
        guard selection.skillIDs.count <= 200 else { throw SkillSetServiceError.tooManySelections(selection.skillIDs.count) }
        let current = try loadState(host)
        var next = current ?? GlobalConfigurationState(host: host,
            skillsPath: locations.skillsRoot(host).path, rulesPath: locations.rulesURL(host).path,
            selection: GlobalConfigurationDraft(), managed: [:])
        next.selection = selection
        let builder = try GlobalPlanBuilder(manager: self, host: host, action: "deploy")
        defer { builder.cleanup() }
        try builder.requireState(current)
        var desired: Set<String> = []
        var slugs: Set<String> = []
        let skillsByID = skillLookup(catalog.entries)
        for id in selection.skillIDs {
            guard let entry = skillsByID[id] else { throw DeploymentError.skillNotFound(id) }
            guard !entry.isBlocked else { throw DeploymentError.skillBlocked(id) }
            let target = locations.skillsRoot(host).appendingPathComponent(entry.slug)
            guard allowedResource(target, host: host), slugs.insert(entry.slug).inserted else { throw DeploymentError.invalidPlan }
            desired.insert(target.path)
            let actual = try builder.observe(target)
            // 私有库存归栖集自己所有，宿主安装目标不能落在库存里。
            guard !target.standardizedFileURL.path.hasPrefix(paths.libraryDirectoryURL.standardizedFileURL.path + "/") else {
                throw DeploymentError.pathOutsideRoot(target.path)
            }
            let old = current?.managed[target.path]
            if let old, actual != old.hash, actual != nil {
                // 外部修改保留在原地；本次计划只重新登记实际指纹，避免阻塞其他全局配置。
                next.managed[target.path] = GlobalManagedResource(hash: actual!, baselineID: old.baselineID,
                    baselineHash: old.baselineHash, originalRules: old.originalRules, writtenRules: old.writtenRules)
                builder.warnings.append("检测到外部修改，保留当前技能文件并更新管理指纹：\(target.path)")
                continue
            }
            if old != nil, actual == nil {
                builder.warnings.append("检测到受管技能已被删除，批准后将从技能库重新创建：\(target.path)")
            }
            if actual != nil, old == nil, !takeOverExisting {
                if actual == entry.contentHash { continue }
                throw DeploymentError.unmanagedSkillConflict(target.path)
            }
            let source: URL
            if let local = sourceURLs[id] { source = local }
            else if let repository = paths.repositoryRoot { source = repository.appendingPathComponent(entry.path) }
            else { throw SkillSetServiceError.repositoryNotFound }
            let destination = builder.staged(target)
            guard try SkillAssetCopier.analyze(from: source).contentHash == entry.contentHash else { throw DeploymentError.skillSourceChanged(source.path) }
            let installedHash: String
            if installMethod == .symlink {
                let linkTarget = try ManagedSkillLink.prepare(source: source, contentHash: entry.contentHash, root: paths.versionsRoot)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.createSymbolicLink(at: destination, withDestinationURL: linkTarget)
                installedHash = try ManagedSkillLink.hash(
                    destination, versionsRoot: paths.versionsRoot,
                    libraryRoot: paths.libraryDirectoryURL, sourcesRoot: paths.sourcesRoot
                )!
            } else {
                let result = try SkillAssetCopier.copy(from: source, to: destination)
                guard result.contentHash == entry.contentHash else { throw DeploymentError.skillSourceChanged(source.path) }
                installedHash = result.contentHash
            }
            let baseline: UUID?
            if let old { baseline = old.baselineID }
            else if actual != nil {
                let id = UUID()
                let url = baselineURL(id)
                try check(url, root: locations.stateRoot)
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: target, to: url)
                guard try hash(url) == actual else { throw GlobalConfigurationError.baselineMissing }
                builder.newBaselines.append(url)
                baseline = id
            } else { baseline = nil }
            next.managed[target.path] = GlobalManagedResource(hash: installedHash, baselineID: baseline,
                baselineHash: old?.baselineHash ?? actual, originalRules: nil, writtenRules: nil)
            builder.append(target, before: actual, after: installedHash,
                summary: actual != nil && old == nil ? "接管全局技能并保留原始备份" : (installMethod == .symlink ? "软链接到栖集固定版本" : "复制全局技能完整包"))
        }

        let bodies = try selection.instructionIDs.map { id in
            guard let body = fragments[id] else { throw SkillSetServiceError.unknownInstruction(id) }
            return body
        }
        let body = bodies.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let rules = locations.rulesURL(host)
        if !body.isEmpty {
            desired.insert(rules.path)
            _ = try builder.observe(rules)
            let original = try dataIfPresent(rules)
            let observedBody = try original.flatMap { try ruleBody($0, path: rules.path) }
            let old = current?.managed[rules.path]
            let observedHash = observedBody.map { SkillAssetCopier.sha256(Data($0.utf8)) }
            if let old, observedHash != old.hash, observedBody != nil {
                // 保留用户修改，只更新管理记录；下次计划仍可继续处理其他内容。
                next.managed[rules.path] = GlobalManagedResource(hash: observedHash!, baselineID: old.baselineID,
                    baselineHash: old.baselineHash, originalRules: old.originalRules, writtenRules: old.writtenRules)
                builder.warnings.append("检测到外部修改，保留当前规则文件并更新管理指纹：\(rules.path)")
            } else if old == nil, observedBody != nil, !takeOverExisting {
                guard observedBody == body else { throw DeploymentError.unmanagedRuleConflict(rules.path) }
            } else {
                let text = original.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let updated = try ManagedBlocks.upsert(original: text, id: Self.blockID, body: body).content
                let data = Data(updated.utf8)
                let baselineRules = old == nil ? original : old?.originalRules
                let baselineText = baselineRules.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                // 还原比较基于最初的块外正文；更新前已有的块外编辑同样需要保留。
                let baselineWritten = try ManagedBlocks.upsert(original: baselineText, id: Self.blockID, body: body).content
                next.managed[rules.path] = GlobalManagedResource(hash: SkillAssetCopier.sha256(Data(body.utf8)),
                    baselineID: nil, baselineHash: nil, originalRules: baselineRules,
                    writtenRules: Data(baselineWritten.utf8))
                try builder.write(data, to: rules, summary: "更新全局规则，保留标记外内容")
            }
        }

        for (path, resource) in current?.managed ?? [:] where !desired.contains(path) {
            try restore(resource, at: URL(fileURLWithPath: path), host: host, builder: builder)
            next.managed.removeValue(forKey: path)
        }
        guard !builder.changes.isEmpty || current?.selection != next.selection || current?.managed != next.managed else {
            throw DeploymentError.noChanges
        }
        next.revision = UUID()
        return try builder.finish(state: next)
    }

    public func makeRestorePlan(host: MCPHost, mode: GlobalRestoreMode) throws -> StoredDeploymentPlan {
        guard let current = try loadState(host) else { throw DeploymentError.noChanges }
        let builder = try GlobalPlanBuilder(manager: self, host: host, action: mode.rawValue)
        defer { builder.cleanup() }
        try builder.requireState(current)
        if mode == .baseline {
            for (path, resource) in current.managed.sorted(by: { $0.key < $1.key }) {
                try restore(resource, at: URL(fileURLWithPath: path), host: host, builder: builder)
            }
        }
        // 留下独立的空状态修订，让退出管理本身也可撤销且不会误认旧归属。
        let next = GlobalConfigurationState(host: host, skillsPath: current.skillsPath,
            rulesPath: current.rulesPath, selection: GlobalConfigurationDraft(), managed: [:])
        guard !current.managed.isEmpty || !current.selection.skillIDs.isEmpty || !current.selection.instructionIDs.isEmpty else {
            throw DeploymentError.noChanges
        }
        return try builder.finish(state: next)
    }

    func baselineURL(_ id: UUID) -> URL { locations.stateRoot.appendingPathComponent("global-baselines/\(id.uuidString)") }

    func restore(_ resource: GlobalManagedResource, at target: URL, host: MCPHost, builder: GlobalPlanBuilder) throws {
        let actual = try builder.observe(target)
        if target == locations.rulesURL(host) {
            let current = try dataIfPresent(target)
            guard current != nil else {
                if builder.action == "deploy" { builder.warnings.append("原规则文件已删除，跳过恢复并清理管理记录：\(target.path)") }
                return
            }
            let observedHash = try current.flatMap { try ruleBody($0, path: target.path) }
                .map { SkillAssetCopier.sha256(Data($0.utf8)) }
            if observedHash != resource.hash {
                if builder.action == "deploy" { return }
                throw DeploymentError.managedRuleDrift(target.path)
            }
            guard let current, try ruleBody(current, path: target.path).map({ SkillAssetCopier.sha256(Data($0.utf8)) }) == resource.hash,
                  let written = resource.writtenRules else { throw DeploymentError.managedRuleDrift(target.path) }
            let restored = try GlobalRuleEditing.restore(current: current, written: written, original: resource.originalRules, path: target.path)
            try builder.write(restored, to: target, summary: "恢复接管前规则，保留后续块外编辑")
        } else {
            if actual == nil {
                if builder.action == "deploy" { builder.warnings.append("原技能目录已删除，跳过恢复并清理管理记录：\(target.path)") }
                return
            }
            if actual != resource.hash {
                if builder.action == "deploy" { return }
                throw DeploymentError.managedSkillDrift(target.path)
            }
            if let id = resource.baselineID {
                let baseline = baselineURL(id)
                guard try hash(baseline) == resource.baselineHash, resource.baselineHash != nil else {
                    throw GlobalConfigurationError.baselineMissing
                }
                try fileManager.createDirectory(at: builder.staged(target).deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: baseline, to: builder.staged(target))
                builder.append(target, before: actual, after: resource.baselineHash, summary: "恢复接管前的原始技能包")
            } else {
                builder.append(target, before: actual, after: nil, summary: "移除栖集新增的全局技能，保留其他内容")
            }
        }
    }
}

final class GlobalPlanBuilder {
    let manager: GlobalConfigurationManager
    let host: MCPHost
    let action: String
    let id = UUID()
    let root: URL
    let stage: URL
    var changes: [PlannedChange] = []
    var warnings: [String] = []
    var observations: [String: PlannedObservation] = [:]
    var newBaselines: [URL] = []
    var saved = false

    init(manager: GlobalConfigurationManager, host: MCPHost, action: String) throws {
        self.manager = manager
        self.host = host
        self.action = action
        try manager.validateSkillsRoot(host)
        root = manager.locations.transactionRoot(host)
        stage = manager.paths.stagingRoot.appendingPathComponent(id.uuidString)
        try manager.fileManager.createDirectory(at: stage, withIntermediateDirectories: true)
        _ = try observe(manager.locations.stateURL(host))
    }

    func staged(_ url: URL) -> URL { stage.appendingPathComponent(manager.relative(url, root: root)) }
    func requireState(_ state: GlobalConfigurationState?) throws {
        let path = manager.relative(manager.locations.stateURL(host), root: root)
        let expected = try state.map { SkillAssetCopier.sha256(try manager.encode($0)) }
        if state?.didRepairPaths == true {
            // 旧状态的 JSON 仍需以历史收据为准；路径迁移只改变内存中的目标映射。
            guard let actual = observations[path]?.contentHash,
                  manager.hasStateReceipt(actual, host: host, journals: try manager.journals(host)) else {
                throw FileTransactionError.staleFile(path)
            }
        } else {
            guard observations[path]?.contentHash == expected else { throw FileTransactionError.staleFile(path) }
        }
    }
    @discardableResult
    func observe(_ url: URL) throws -> String? {
        try manager.check(url, root: root)
        let hash = try manager.hash(url)
        let path = manager.relative(url, root: root)
        if let previous = observations[path], previous.contentHash != hash { throw FileTransactionError.staleFile(path) }
        observations[path] = PlannedObservation(relativePath: path, contentHash: hash)
        return hash
    }
    func append(_ url: URL, before: String?, after: String?, summary: String) {
        guard before != after else { return }
        changes.append(PlannedChange(action: after == nil ? "remove" : (before == nil ? "add" : "update"),
            relativePath: manager.relative(url, root: root), beforeHash: before, afterHash: after, unifiedDiff: summary))
    }
    func write(_ data: Data?, to url: URL, summary: String) throws {
        let before = try observe(url)
        if let data {
            let target = staged(url)
            try manager.fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
            if before != nil {
                let permissions = try manager.fileManager.attributesOfItem(atPath: url.path)[.posixPermissions]
                if let permissions { try manager.fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path) }
            }
        }
        append(url, before: before, after: data.map(SkillAssetCopier.sha256), summary: summary)
    }
    func finish(state: GlobalConfigurationState) throws -> StoredDeploymentPlan {
        try write(manager.encode(state), to: manager.locations.stateURL(host), summary: "保存全局配置与本机管理归属")
        let metadata = ["planType": "global-configuration", "globalHost": host.rawValue,
                        "globalAction": action, "globalSkillsRoot": state.skillsPath]
        let dependencies = observations.values.sorted { $0.relativePath < $1.relativePath }
        let digest = DeploymentPlanner.calculateDigest(projectPath: root.path, changes: changes,
            selectedSkills: [], metadata: metadata, observations: dependencies)
        let plan = DeploymentPlan(id: id, projectPath: root.path, createdAt: Date(), digest: digest,
            changes: changes, warnings: ["此操作影响当前用户在该 AI 工具中的全部项目。"] + warnings,
            metadata: metadata, observations: dependencies)
        try manager.validate(plan: plan)
        let stored = try DeploymentPlanStore(rootURL: manager.paths.plansRoot).save(plan: plan, stagingPath: stage.path)
        saved = true
        return stored
    }
    func cleanup() {
        if !saved {
            try? manager.fileManager.removeItem(at: stage)
            for url in newBaselines { try? manager.fileManager.removeItem(at: url) }
        }
    }
}

enum GlobalRuleEditing {
    static func body(in text: String, path: String) throws -> String? {
        do { return try ManagedBlocks.extract(original: text, id: GlobalConfigurationManager.blockID) }
        catch is ManagedBlockError {
            throw GlobalConfigurationError.verificationFailed(.invalidRuleMarkers, path: path)
        }
    }

    static func restore(current: Data, written: Data, original: Data?, path: String = "") throws -> Data? {
        if current == written { return original }
        guard let text = String(data: current, encoding: .utf8),
              let expected = String(data: written, encoding: .utf8),
              original == nil || String(data: original!, encoding: .utf8) != nil else { throw GlobalConfigurationError.verificationFailed(.invalidRulesEncoding, path: path) }
        let currentBody = try body(in: text, path: path)
        let expectedBody = try body(in: expected, path: path)
        guard currentBody == expectedBody else { throw DeploymentError.managedRuleDrift("global-rules") }
        let originalText = original.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        // 按原始标记范围替换，保留块外的空白和新增内容。
        let originalBlock = try blockRange(originalText, path: path).map { Data(originalText.utf8).subdata(in: $0) } ?? Data()
        if let range = try blockRange(text, path: path) {
            var restored = current
            restored.replaceSubrange(range, with: originalBlock)
            return restored
        }
        if originalBlock.isEmpty { return current }
        var restored = current
        if !text.isEmpty && !text.hasSuffix("\n") { restored.append(contentsOf: [0x0a]) }
        restored.append(originalBlock)
        return restored
    }

    private static func blockRange(_ text: String, path: String) throws -> Range<Int>? {
        let id = GlobalConfigurationManager.blockID
        guard try body(in: text, path: path) != nil else { return nil }
        var start: Int?
        var cursor = 0
        for line in text.components(separatedBy: "\n") {
            // CRLF 在 Swift 中是一个 Character；按 UTF-8 字节定位，避免越过规则块破坏用户正文。
            let end = cursor + line.utf8.count
            if line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<!-- skillset:begin id=\(id) schema=") { start = cursor }
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == ManagedBlocks.endMarker(id: id), let start { return start..<end }
            cursor = end + 1
        }
        throw GlobalConfigurationError.verificationFailed(.invalidRuleMarkers, path: path)
    }
}
