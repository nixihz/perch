import Foundation

public enum PluginLifecycleAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case install
    case update
    case enable
    case disable
    case uninstall

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .install: "安装"
        case .update: "更新"
        case .enable: "启用"
        case .disable: "停用"
        case .uninstall: "卸载"
        }
    }
}

public enum PluginLifecycleScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case user
    case project
    case local

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .user: "用户"
        case .project: "项目"
        case .local: "本机项目"
        }
    }
}

public enum PluginLifecycleError: Error, LocalizedError, Equatable, Sendable {
    case invalidPluginID(String)
    case pluginNotFound(String)
    case scopeAmbiguous(String)
    case versionAmbiguous(String)
    case versionNotFound(String, String)
    case manifestDigestInvalid(String)
    case scopeUnsupported(String)
    case projectRootRequired
    case actionUnsupported(String)
    case pluginNotInstalled(String)
    case pluginAlreadyInstalled(String)
    case pluginAlreadyEnabled(String)
    case pluginAlreadyDisabled(String)
    case riskApprovalRequired(String, [String])
    case hostCLIMissing(String)
    case stateChanged(String)
    case stagedCommandInvalid(String)
    case commandLaunchFailed(String)
    case operationNotFound(String)
    case operationCorrupt(String)
    case rollbackUnsupported(String, String)
    case executionFailed(UUID, String, String)
    case executionUncertain(UUID, String)

    public var code: String {
        switch self {
        case .invalidPluginID: "PLUGIN_ID_INVALID"
        case .pluginNotFound: "PLUGIN_NOT_FOUND"
        case .scopeAmbiguous: "PLUGIN_SCOPE_AMBIGUOUS"
        case .versionAmbiguous: "PLUGIN_VERSION_AMBIGUOUS"
        case .versionNotFound: "PLUGIN_VERSION_NOT_FOUND"
        case .manifestDigestInvalid: "PLUGIN_MANIFEST_DIGEST_INVALID"
        case .scopeUnsupported: "PLUGIN_SCOPE_UNSUPPORTED"
        case .projectRootRequired: "PLUGIN_PROJECT_REQUIRED"
        case .actionUnsupported: "PLUGIN_ACTION_UNSUPPORTED"
        case .pluginNotInstalled: "PLUGIN_NOT_INSTALLED"
        case .pluginAlreadyInstalled: "PLUGIN_ALREADY_INSTALLED"
        case .pluginAlreadyEnabled: "PLUGIN_ALREADY_ENABLED"
        case .pluginAlreadyDisabled: "PLUGIN_ALREADY_DISABLED"
        case .riskApprovalRequired: "PLUGIN_RISK_APPROVAL_REQUIRED"
        case .hostCLIMissing: "PLUGIN_HOST_CLI_MISSING"
        case .stateChanged: "PLUGIN_STATE_STALE"
        case .stagedCommandInvalid: "PLUGIN_STAGED_COMMAND_INVALID"
        case .commandLaunchFailed: "PLUGIN_COMMAND_LAUNCH_FAILED"
        case .operationNotFound: "OPERATION_NOT_FOUND"
        case .operationCorrupt: "PLUGIN_OPERATION_CORRUPT"
        case .rollbackUnsupported: "PLUGIN_ROLLBACK_UNSUPPORTED"
        case .executionFailed: "PLUGIN_COMMAND_FAILED"
        case .executionUncertain: "PLUGIN_EXECUTION_UNCERTAIN"
        }
    }

    public var errorDescription: String? {
        switch self {
        case let .invalidPluginID(value):
            return "Plugin id 不安全或格式无效：\(value)"
        case let .pluginNotFound(value):
            return "本机没有该插件的缓存或安装事实，不能凭空执行生命周期命令：\(value)"
        case let .scopeAmbiguous(value):
            return "同名插件存在多个安装范围，请明确选择 scope：\(value)"
        case let .versionAmbiguous(value):
            return "同一范围和插件 id 存在多个缓存版本，请指定 manifestDigest：\(value)"
        case let .versionNotFound(value, digest):
            return "找不到与 manifestDigest \(digest) 匹配的可操作缓存或安装记录：\(value)"
        case let .manifestDigestInvalid(value):
            return "manifestDigest 必须是 64 位 SHA-256 十六进制字符串：\(value)"
        case let .scopeUnsupported(value):
            return "当前宿主不支持这个插件范围：\(value)"
        case .projectRootRequired:
            return "项目和本机项目范围需要先选择已登记项目。"
        case let .actionUnsupported(value):
            return "当前宿主不支持这个 Plugin 生命周期动作：\(value)"
        case let .pluginNotInstalled(value):
            return "插件尚未安装，不能执行该动作：\(value)"
        case let .pluginAlreadyInstalled(value):
            return "插件已经安装：\(value)"
        case let .pluginAlreadyEnabled(value):
            return "插件已经启用：\(value)"
        case let .pluginAlreadyDisabled(value):
            return "插件已经停用：\(value)"
        case let .riskApprovalRequired(value, risks):
            return "插件 \(value) 的此动作需要本机人工确认：\(risks.joined(separator: "、"))。只能由本机 UI 或 CLI 显式确认后生成计划。"
        case let .hostCLIMissing(value):
            return "找不到可执行的宿主 CLI：\(value)"
        case let .stateChanged(value):
            return "插件在生成计划后发生变化，拒绝执行旧计划：\(value)"
        case let .stagedCommandInvalid(path):
            return "计划中的宿主命令描述不完整或已变化：\(path)"
        case let .commandLaunchFailed(path):
            return "宿主命令无法启动：\(path)"
        case let .operationNotFound(id):
            return "找不到操作：\(id)"
        case let .operationCorrupt(path):
            return "Plugin operation journal 无法读取：\(path)"
        case let .rollbackUnsupported(pluginID, action):
            return "Plugin 的 \(action) 没有通用文件回滚；请为 \(pluginID) 生成相反动作的计划。"
        case let .executionFailed(id, state, message):
            return "Plugin 宿主命令失败（operation \(id.uuidString)，state=\(state)）：\(message)"
        case let .executionUncertain(id, message):
            return "Plugin 宿主命令结果不确定，已停止自动重试（operation \(id.uuidString)）：\(message)"
        }
    }
}

public struct PluginLifecycleRequest: Hashable, Sendable {
    public let host: MCPHost
    public let pluginID: String
    public let action: PluginLifecycleAction
    public let scope: PluginLifecycleScope?
    public let expectedManifestDigest: String?
    public let keepData: Bool
    public let acknowledgeExecutableComponents: Bool

    public init(
        host: MCPHost,
        pluginID: String,
        action: PluginLifecycleAction,
        scope: PluginLifecycleScope? = nil,
        expectedManifestDigest: String? = nil,
        keepData: Bool = true,
        acknowledgeExecutableComponents: Bool = false
    ) {
        self.host = host
        self.pluginID = pluginID
        self.action = action
        self.scope = scope
        self.expectedManifestDigest = expectedManifestDigest
        self.keepData = keepData
        self.acknowledgeExecutableComponents = acknowledgeExecutableComponents
    }
}

public struct PluginLifecycleObservation: Codable, Hashable, Sendable {
    public let host: MCPHost
    public let pluginID: String
    public let scope: PluginLifecycleScope
    public let installed: Bool
    public let enabled: Bool?
    public let manifestDigest: String?
    public let sourceRevision: String?
    public let manifestPath: String?
    public let components: [String]
    public let risks: [String]
    public let state: String

    public init(
        host: MCPHost,
        pluginID: String,
        scope: PluginLifecycleScope,
        installed: Bool,
        enabled: Bool?,
        manifestDigest: String?,
        sourceRevision: String?,
        manifestPath: String?,
        components: [String],
        risks: [String],
        state: String
    ) {
        self.host = host
        self.pluginID = pluginID
        self.scope = scope
        self.installed = installed
        self.enabled = enabled
        self.manifestDigest = manifestDigest
        self.sourceRevision = sourceRevision
        self.manifestPath = manifestPath
        self.components = components.sorted()
        self.risks = risks.sorted()
        self.state = state
    }

    public static func absent(
        host: MCPHost,
        pluginID: String,
        scope: PluginLifecycleScope
    ) -> PluginLifecycleObservation {
        PluginLifecycleObservation(
            host: host,
            pluginID: pluginID,
            scope: scope,
            installed: false,
            enabled: nil,
            manifestDigest: nil,
            sourceRevision: nil,
            manifestPath: nil,
            components: [],
            risks: [],
            state: "未发现安装事实"
        )
    }

    public var digest: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(self)) ?? Data()
        return SkillAssetCopier.sha256(data)
    }
}

public struct PluginLifecycleCommand: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let host: MCPHost
    public let pluginID: String
    public let action: PluginLifecycleAction
    public let scope: PluginLifecycleScope
    public let expectedManifestDigest: String?
    public let workingDirectory: String
    public let executablePath: String
    public let arguments: [String]
    public let keepData: Bool
    public let createdAt: Date

    public init(
        schemaVersion: Int = 1,
        host: MCPHost,
        pluginID: String,
        action: PluginLifecycleAction,
        scope: PluginLifecycleScope,
        expectedManifestDigest: String? = nil,
        workingDirectory: String,
        executablePath: String,
        arguments: [String],
        keepData: Bool,
        createdAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.host = host
        self.pluginID = pluginID
        self.action = action
        self.scope = scope
        self.expectedManifestDigest = expectedManifestDigest
        self.workingDirectory = workingDirectory
        self.executablePath = executablePath
        self.arguments = arguments
        self.keepData = keepData
        self.createdAt = createdAt
    }

    public var preview: String {
        ([executablePath] + arguments)
            .map(Self.shellQuoted)
            .joined(separator: " ")
    }

    private static func shellQuoted(_ value: String) -> String {
        if value.range(
            of: #"^[A-Za-z0-9_./:@%+=,-]+$"#,
            options: .regularExpression
        ) != nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public struct PluginCommandOutput: Hashable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool

    public init(exitCode: Int32, stdout: String, stderr: String, timedOut: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

public typealias PluginCommandRunner = (
    _ executable: URL,
    _ arguments: [String],
    _ workingDirectory: URL,
    _ environment: [String: String]
) -> PluginCommandOutput

public struct PluginLifecycleOperation: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let operationID: UUID
    public let planID: UUID
    public let planDigest: String
    public let host: MCPHost
    public let action: PluginLifecycleAction
    public let pluginID: String
    public let scope: PluginLifecycleScope
    public let workingDirectory: String
    public let executablePath: String
    public let arguments: [String]
    public let keepData: Bool
    public let createdAt: Date
    public var finishedAt: Date?
    public var state: String
    public var exitCode: Int32?
    public var timedOut: Bool
    public var before: PluginLifecycleObservation
    public var after: PluginLifecycleObservation?
    public var sanitizedStdout: String
    public var sanitizedStderr: String
    public var outputSHA256: String
    public var message: String

    public init(
        schemaVersion: Int = 1,
        operationID: UUID,
        planID: UUID,
        planDigest: String,
        host: MCPHost,
        action: PluginLifecycleAction,
        pluginID: String,
        scope: PluginLifecycleScope,
        workingDirectory: String,
        executablePath: String,
        arguments: [String],
        keepData: Bool,
        createdAt: Date,
        finishedAt: Date? = nil,
        state: String,
        exitCode: Int32? = nil,
        timedOut: Bool = false,
        before: PluginLifecycleObservation,
        after: PluginLifecycleObservation? = nil,
        sanitizedStdout: String = "",
        sanitizedStderr: String = "",
        outputSHA256: String = "",
        message: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.operationID = operationID
        self.planID = planID
        self.planDigest = planDigest
        self.host = host
        self.action = action
        self.pluginID = pluginID
        self.scope = scope
        self.workingDirectory = workingDirectory
        self.executablePath = executablePath
        self.arguments = arguments
        self.keepData = keepData
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.state = state
        self.exitCode = exitCode
        self.timedOut = timedOut
        self.before = before
        self.after = after
        self.sanitizedStdout = sanitizedStdout
        self.sanitizedStderr = sanitizedStderr
        self.outputSHA256 = outputSHA256
        self.message = message
    }
}

public struct PluginLifecycleExecution: Codable, Hashable, Sendable {
    public let operationID: UUID
    public let journalPath: String
    public let state: String
    public let message: String
    public let planConsumed: Bool
    public let succeeded: Bool

    public init(
        operationID: UUID,
        journalPath: String,
        state: String,
        message: String,
        planConsumed: Bool,
        succeeded: Bool
    ) {
        self.operationID = operationID
        self.journalPath = journalPath
        self.state = state
        self.message = message
        self.planConsumed = planConsumed
        self.succeeded = succeeded
    }
}

public enum OperationKind: String, Codable, Sendable {
    case fileTransaction = "file-transaction"
    case pluginLifecycle = "plugin-lifecycle"
}

public struct OperationInspection: Codable, Hashable, Sendable {
    public let operationID: UUID
    public let kind: OperationKind
    public let state: String
    public let projectPath: String
    public let planID: UUID
    public let planDigest: String
    public let createdAt: Date
    public let steps: [FileTransactionStep]
    public let plugin: PluginLifecycleOperation?

    public init(
        operationID: UUID,
        kind: OperationKind,
        state: String,
        projectPath: String,
        planID: UUID,
        planDigest: String,
        createdAt: Date,
        steps: [FileTransactionStep],
        plugin: PluginLifecycleOperation? = nil
    ) {
        self.operationID = operationID
        self.kind = kind
        self.state = state
        self.projectPath = projectPath
        self.planID = planID
        self.planDigest = planDigest
        self.createdAt = createdAt
        self.steps = steps
        self.plugin = plugin
    }
}

/// 只通过宿主 CLI 执行固定动作；插件内 hooks、commands 和安装器由宿主自行处理，管理器不直接运行它们。
public struct PluginLifecycleManager {
    public let stagingRoot: URL
    public let operationsRoot: URL
    public let homeDirectory: URL

    private let planStore: DeploymentPlanStore
    private let executableOverrides: [MCPHost: URL]
    private let environment: [String: String]
    private let fileManager: FileManager
    private let clock: () -> Date
    private let idGenerator: () -> UUID
    private let commandRunner: PluginCommandRunner

    public init(
        planStore: DeploymentPlanStore,
        stagingRoot: URL,
        operationsRoot: URL,
        homeDirectory: URL = PluginInventoryManager.defaultHomeDirectory,
        executableOverrides: [MCPHost: URL] = [:],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        clock: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> UUID = UUID.init,
        commandRunner: PluginCommandRunner? = nil
    ) {
        self.planStore = planStore
        self.stagingRoot = stagingRoot.standardizedFileURL
        self.operationsRoot = operationsRoot.standardizedFileURL
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.executableOverrides = executableOverrides
        self.environment = environment
        self.fileManager = fileManager
        self.clock = clock
        self.idGenerator = idGenerator
        self.commandRunner = commandRunner ?? Self.runProcess
    }

    public func makePlan(
        request: PluginLifecycleRequest,
        projectRoot: URL?
    ) throws -> StoredDeploymentPlan {
        let pluginID = request.pluginID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pluginID.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._@:/+-]{0,199}$"#,
            options: .regularExpression
        ) != nil else {
            throw PluginLifecycleError.invalidPluginID(pluginID)
        }
        try validateSupport(host: request.host, action: request.action)
        let expectedManifestDigest = try normalizedManifestDigest(
            request.expectedManifestDigest
        )

        let initialSnapshot = PluginInventoryManager(
            projectRoot: nil,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        ).inspect()
        let allMatches = initialSnapshot.records.filter {
            $0.host == request.host && $0.pluginID == pluginID
        }
        guard !allMatches.isEmpty else {
            throw PluginLifecycleError.pluginNotFound(pluginID)
        }
        let scope = try resolvedScope(request: request, records: allMatches)
        let workingDirectory = try workingDirectory(scope: scope, projectRoot: projectRoot)
        let inspectionRoot = scope == .user ? nil : workingDirectory
        let snapshot = PluginInventoryManager(
            projectRoot: inspectionRoot,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        ).inspect()
        let record = try selectRecord(
            pluginID: pluginID,
            host: request.host,
            scope: scope,
            expectedManifestDigest: expectedManifestDigest,
            records: snapshot.records
        )
        try validateTransition(record: record, action: request.action)

        let executableComponents = record.components.filter {
            ["hooks", "commands", "MCP", "LSP", "userConfig"].contains($0)
        }
        if [.install, .update].contains(request.action),
           !request.acknowledgeExecutableComponents {
            throw PluginLifecycleError.riskApprovalRequired(
                pluginID,
                executableComponents.isEmpty
                    ? ["宿主执行时解析的完整包"]
                    : executableComponents
            )
        }

        let executable = try resolveExecutable(host: request.host)
        let command = PluginLifecycleCommand(
            host: request.host,
            pluginID: pluginID,
            action: request.action,
            scope: scope,
            expectedManifestDigest: expectedManifestDigest,
            workingDirectory: workingDirectory.path,
            executablePath: executable.path,
            arguments: try arguments(
                host: request.host,
                action: request.action,
                pluginID: pluginID,
                scope: scope,
                keepData: request.keepData
            ),
            keepData: request.keepData,
            createdAt: clock()
        )
        let before = observation(record: record, pluginID: pluginID, scope: scope)
        let planID = idGenerator()
        let stage = stagingRoot.appendingPathComponent(planID.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: stage.path) {
            try fileManager.removeItem(at: stage)
        }
        try fileManager.createDirectory(at: stage, withIntermediateDirectories: true)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let commandData = try encoder.encode(command)
            let relativePath = "plugins/\(safePathComponent(pluginID))-\(scope.rawValue).json"
            let staged = stage.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: staged.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try commandData.write(to: staged, options: .atomic)

            let change = PlannedChange(
                action: request.action.rawValue,
                relativePath: relativePath,
                beforeHash: before.digest,
                afterHash: SkillAssetCopier.sha256(commandData),
                unifiedDiff: "\(request.action.displayName)：\(command.preview)"
            )
            let argumentsData = try JSONEncoder().encode(command.arguments)
            let metadata = [
                "planType": "plugin-lifecycle",
                "pluginAction": request.action.rawValue,
                "pluginHost": request.host.rawValue,
                "pluginID": pluginID,
                "pluginScope": scope.rawValue,
                "pluginExpectedManifestDigest": expectedManifestDigest ?? "",
                "pluginKeepData": String(request.keepData),
                "pluginRiskAcknowledged": String(request.acknowledgeExecutableComponents),
                "pluginRiskComponents": executableComponents.joined(separator: ","),
                "pluginBeforeDigest": before.digest,
                "pluginWorkingDirectory": workingDirectory.path,
                "pluginExecutable": executable.path,
                "pluginArguments": String(data: argumentsData, encoding: .utf8) ?? "[]",
                "pluginCommandPreview": command.preview
            ]
            let digest = DeploymentPlanner.calculateDigest(
                projectPath: workingDirectory.path,
                changes: [change],
                selectedSkills: [
                    "plugin:\(request.host.rawValue):\(pluginID):\(request.action.rawValue):\(scope.rawValue):\(expectedManifestDigest ?? "any")"
                ],
                metadata: metadata
            )
            let plan = DeploymentPlan(
                id: planID,
                projectPath: workingDirectory.path,
                createdAt: command.createdAt,
                digest: digest,
                changes: [change],
                warnings: warnings(
                    record: record,
                    scope: scope,
                    command: command,
                    executableComponents: executableComponents
                ),
                metadata: metadata
            )
            return try planStore.save(plan: plan, stagingPath: stage.path)
        } catch {
            try? fileManager.removeItem(at: stage)
            throw error
        }
    }

    public func execute(_ planRecord: StoredDeploymentPlan) throws -> PluginLifecycleExecution {
        let command = try stagedCommand(for: planRecord)
        guard command.action.rawValue == planRecord.plan.metadata?["pluginAction"],
              command.host.rawValue == planRecord.plan.metadata?["pluginHost"],
              command.pluginID == planRecord.plan.metadata?["pluginID"],
              command.scope.rawValue == planRecord.plan.metadata?["pluginScope"],
              (command.expectedManifestDigest ?? "")
                == (planRecord.plan.metadata?["pluginExpectedManifestDigest"] ?? ""),
              command.workingDirectory == planRecord.plan.metadata?["pluginWorkingDirectory"],
              command.executablePath == planRecord.plan.metadata?["pluginExecutable"] else {
            throw PluginLifecycleError.stagedCommandInvalid(planRecord.stagingPath)
        }
        let before = try currentObservation(
            host: command.host,
            pluginID: command.pluginID,
            scope: command.scope,
            expectedManifestDigest: command.expectedManifestDigest,
            workingDirectory: URL(fileURLWithPath: command.workingDirectory, isDirectory: true)
        )
        guard before.digest == planRecord.plan.metadata?["pluginBeforeDigest"] else {
            throw PluginLifecycleError.stateChanged(command.pluginID)
        }

        let operationID = idGenerator()
        let operationRoot = operationsRoot.appendingPathComponent(operationID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: operationRoot, withIntermediateDirectories: true)
        var operation = PluginLifecycleOperation(
            operationID: operationID,
            planID: planRecord.id,
            planDigest: planRecord.plan.digest,
            host: command.host,
            action: command.action,
            pluginID: command.pluginID,
            scope: command.scope,
            workingDirectory: command.workingDirectory,
            executablePath: command.executablePath,
            arguments: command.arguments,
            keepData: command.keepData,
            createdAt: clock(),
            state: "applying",
            before: before
        )
        try write(operation)

        let executable = URL(fileURLWithPath: command.executablePath)
        guard fileManager.isExecutableFile(atPath: executable.path) else {
            operation.state = "failed-before-launch"
            operation.finishedAt = clock()
            operation.message = "宿主 CLI 不存在或不可执行。"
            try write(operation)
            throw PluginLifecycleError.commandLaunchFailed(executable.path)
        }
        let output = commandRunner(
            executable,
            command.arguments,
            URL(fileURLWithPath: command.workingDirectory, isDirectory: true),
            processEnvironment(executable: executable)
        )
        let after = try currentObservation(
            host: command.host,
            pluginID: command.pluginID,
            scope: command.scope,
            expectedManifestDigest: command.expectedManifestDigest,
            workingDirectory: URL(fileURLWithPath: command.workingDirectory, isDirectory: true)
        )
        let targetObserved = expectedStateObserved(action: command.action, observation: after)
        let stdout = sanitize(output.stdout)
        let stderr = sanitize(output.stderr)
        let rawOutput = Data((output.stdout + "\n" + output.stderr).utf8)

        operation.finishedAt = clock()
        operation.after = after
        operation.exitCode = output.exitCode
        operation.timedOut = output.timedOut
        operation.sanitizedStdout = stdout
        operation.sanitizedStderr = stderr
        operation.outputSHA256 = SkillAssetCopier.sha256(rawOutput)

        let planConsumed: Bool
        let succeeded: Bool
        if output.timedOut {
            operation.state = "uncertain-interrupted"
            operation.message = "宿主命令超时；不自动重试，请核对插件实际状态。"
            planConsumed = true
            succeeded = false
        } else if output.exitCode == 0, targetObserved {
            operation.state = "applied"
            operation.message = "宿主命令成功，回读已观察到目标状态。"
            planConsumed = true
            succeeded = true
        } else if output.exitCode == 0 {
            operation.state = "applied-verification-pending"
            operation.message = "宿主命令已成功退出，但回读尚未观察到目标状态；可能需要刷新宿主或重启会话。"
            planConsumed = true
            succeeded = true
        } else if targetObserved {
            operation.state = "applied-after-nonzero-exit"
            operation.message = "宿主命令非零退出，但回读已观察到目标状态；保留原始退出码供排查。"
            planConsumed = true
            succeeded = true
        } else {
            operation.state = "failed"
            operation.message = "宿主命令失败，回读未观察到目标状态。"
            planConsumed = false
            succeeded = false
        }
        try write(operation)
        return PluginLifecycleExecution(
            operationID: operationID,
            journalPath: operationURL(operationID).path,
            state: operation.state,
            message: operation.message,
            planConsumed: planConsumed,
            succeeded: succeeded
        )
    }

    public func loadOperation(_ operationID: UUID) throws -> PluginLifecycleOperation {
        let url = operationURL(operationID)
        guard fileManager.fileExists(atPath: url.path) else {
            throw PluginLifecycleError.operationNotFound(operationID.uuidString)
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(PluginLifecycleOperation.self, from: data)
        } catch {
            throw PluginLifecycleError.operationCorrupt(url.path)
        }
    }

    /// 中断只标为不确定，不自动重放宿主命令，因为命令可能已经产生外部副作用。
    public func recoverInterruptedOperations() throws -> [UUID] {
        guard fileManager.fileExists(atPath: operationsRoot.path) else { return [] }
        let directories = try fileManager.contentsOfDirectory(
            at: operationsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var recovered: [UUID] = []
        for directory in directories {
            guard let id = UUID(uuidString: directory.lastPathComponent),
                  var operation = try? loadOperation(id),
                  ["applying", "executing"].contains(operation.state) else {
                continue
            }
            operation.state = "uncertain-interrupted"
            operation.finishedAt = clock()
            operation.message = "应用启动时发现未完成的 Plugin 命令；为避免重复副作用，没有自动重试。"
            try write(operation)
            recovered.append(id)
        }
        return recovered
    }

    private func validateSupport(host: MCPHost, action: PluginLifecycleAction) throws {
        if host == .codex, ![.install, .uninstall].contains(action) {
            throw PluginLifecycleError.actionUnsupported("\(host.displayName) 不提供公开的 \(action.displayName) 命令")
        }
    }

    private func resolvedScope(
        request: PluginLifecycleRequest,
        records: [PluginInventoryRecord]
    ) throws -> PluginLifecycleScope {
        if request.host == .codex {
            if let scope = request.scope, scope != .user {
                throw PluginLifecycleError.scopeUnsupported("Codex Plugin 当前只按用户配置管理")
            }
            return .user
        }
        if let scope = request.scope {
            return scope
        }
        let scopes = Set(records.compactMap { record in
            record.scope.flatMap(PluginLifecycleScope.init(rawValue:))
        })
        if scopes.count > 1 {
            throw PluginLifecycleError.scopeAmbiguous(request.pluginID)
        }
        return scopes.first ?? .user
    }

    private func workingDirectory(
        scope: PluginLifecycleScope,
        projectRoot: URL?
    ) throws -> URL {
        guard scope != .user else {
            return homeDirectory.resolvingSymlinksInPath().standardizedFileURL
        }
        guard let projectRoot else {
            throw PluginLifecycleError.projectRootRequired
        }
        let root = projectRoot.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw PluginLifecycleError.projectRootRequired
        }
        return root
    }

    private func selectRecord(
        pluginID: String,
        host: MCPHost,
        scope: PluginLifecycleScope,
        expectedManifestDigest: String?,
        records: [PluginInventoryRecord]
    ) throws -> PluginInventoryRecord {
        let scopedMatches = records.filter { record in
            guard record.host == host, record.pluginID == pluginID else { return false }
            if host == .codex {
                return true
            }
            if let recordScope = record.scope.flatMap(PluginLifecycleScope.init(rawValue:)) {
                return recordScope == scope
            }
            return !record.installed
        }
        guard !scopedMatches.isEmpty else {
            throw PluginLifecycleError.pluginNotFound(pluginID)
        }
        let installed = scopedMatches.filter(\.installed)
        if let expectedManifestDigest {
            let exactMatches = scopedMatches.filter {
                $0.manifestDigest == expectedManifestDigest
            }
            guard !exactMatches.isEmpty else {
                throw PluginLifecycleError.versionNotFound(pluginID, expectedManifestDigest)
            }
            let exactInstalled = exactMatches.filter(\.installed)
            if exactInstalled.count == 1 {
                return exactInstalled[0]
            }
            if exactInstalled.count > 1 || installed.count > 1 {
                throw PluginLifecycleError.versionAmbiguous(pluginID)
            }
            if installed.count == 1 {
                // 同 id 已安装另一份 manifest 时，不能把未安装缓存伪装成可安装目标。
                throw PluginLifecycleError.versionNotFound(pluginID, expectedManifestDigest)
            }
            guard exactMatches.count == 1 else {
                throw PluginLifecycleError.versionAmbiguous(pluginID)
            }
            return exactMatches[0]
        }
        if installed.count == 1 {
            return installed[0]
        }
        if installed.count > 1 {
            throw PluginLifecycleError.versionAmbiguous(pluginID)
        }
        guard scopedMatches.count == 1 else {
            throw PluginLifecycleError.versionAmbiguous(pluginID)
        }
        return scopedMatches[0]
    }

    private func normalizedManifestDigest(_ value: String?) throws -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.range(
            of: #"^[a-f0-9]{64}$"#,
            options: .regularExpression
        ) != nil else {
            throw PluginLifecycleError.manifestDigestInvalid(value)
        }
        return normalized
    }

    private func validateTransition(
        record: PluginInventoryRecord,
        action: PluginLifecycleAction
    ) throws {
        switch action {
        case .install:
            guard !record.installed else {
                throw PluginLifecycleError.pluginAlreadyInstalled(record.pluginID)
            }
        case .update, .enable, .disable, .uninstall:
            guard record.installed else {
                throw PluginLifecycleError.pluginNotInstalled(record.pluginID)
            }
        }
        switch action {
        case .enable where record.enabled == true:
            throw PluginLifecycleError.pluginAlreadyEnabled(record.pluginID)
        case .disable where record.enabled == false:
            throw PluginLifecycleError.pluginAlreadyDisabled(record.pluginID)
        default:
            break
        }
    }

    private func arguments(
        host: MCPHost,
        action: PluginLifecycleAction,
        pluginID: String,
        scope: PluginLifecycleScope,
        keepData: Bool
    ) throws -> [String] {
        switch (host, action) {
        case (.claudeCode, .install):
            return ["plugin", "install", pluginID, "--scope", scope.rawValue, "--json"]
        case (.claudeCode, .update):
            return ["plugin", "update", pluginID, "--scope", scope.rawValue, "--json"]
        case (.claudeCode, .enable):
            return ["plugin", "enable", pluginID, "--scope", scope.rawValue, "--json"]
        case (.claudeCode, .disable):
            return ["plugin", "disable", pluginID, "--scope", scope.rawValue, "--json"]
        case (.claudeCode, .uninstall):
            var values = ["plugin", "uninstall", pluginID, "--scope", scope.rawValue, "--json"]
            if keepData {
                values.append("--keep-data")
            }
            return values
        case (.codex, .install):
            return ["plugin", "add", pluginID, "--json"]
        case (.codex, .uninstall):
            return ["plugin", "remove", pluginID, "--json"]
        default:
            throw PluginLifecycleError.actionUnsupported(
                "\(host.displayName) 不提供公开的 \(action.displayName) 命令"
            )
        }
    }

    private func resolveExecutable(host: MCPHost) throws -> URL {
        let name = host == .claudeCode ? "claude" : "codex"
        let environmentKey = host == .claudeCode
            ? "SKILLSET_CLAUDE_BIN"
            : "SKILLSET_CODEX_BIN"
        var candidates: [URL] = []
        if let override = executableOverrides[host] {
            candidates.append(override)
        }
        if let configured = environment[environmentKey], !configured.isEmpty {
            candidates.append(URL(fileURLWithPath: configured))
        }
        let pathDirectories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let knownDirectories = [
            homeDirectory.appendingPathComponent(".local/bin", isDirectory: true).path,
            homeDirectory.appendingPathComponent(".npm-global/bin", isDirectory: true).path,
            homeDirectory.appendingPathComponent(".bun/bin", isDirectory: true).path,
            homeDirectory.appendingPathComponent(".volta/bin", isDirectory: true).path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        for directory in Array(Set(pathDirectories + knownDirectories)) {
            candidates.append(URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(name))
        }
        for candidate in candidates {
            let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
            if fileManager.isExecutableFile(atPath: resolved.path) {
                return resolved
            }
        }
        throw PluginLifecycleError.hostCLIMissing(
            "\(name)（可设置 \(environmentKey) 指定绝对路径）"
        )
    }

    private func observation(
        record: PluginInventoryRecord,
        pluginID: String,
        scope: PluginLifecycleScope
    ) -> PluginLifecycleObservation {
        PluginLifecycleObservation(
            host: record.host,
            pluginID: pluginID,
            scope: scope,
            installed: record.installed,
            enabled: record.enabled,
            manifestDigest: record.manifestDigest,
            sourceRevision: record.sourceRevision,
            manifestPath: record.manifestPath,
            components: record.components,
            risks: record.risks,
            state: record.state
        )
    }

    private func currentObservation(
        host: MCPHost,
        pluginID: String,
        scope: PluginLifecycleScope,
        expectedManifestDigest: String?,
        workingDirectory: URL
    ) throws -> PluginLifecycleObservation {
        let snapshot = PluginInventoryManager(
            projectRoot: scope == .user ? nil : workingDirectory,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        ).inspect()
        let scopedMatches = snapshot.records.filter { record in
            guard record.host == host, record.pluginID == pluginID else { return false }
            if host == .codex {
                return true
            }
            if let recordScope = record.scope.flatMap(PluginLifecycleScope.init(rawValue:)) {
                return recordScope == scope
            }
            return !record.installed
        }
        guard !scopedMatches.isEmpty else {
            return .absent(host: host, pluginID: pluginID, scope: scope)
        }
        let installed = scopedMatches.filter(\.installed)
        if let expectedManifestDigest {
            let exactInstalled = installed.filter {
                $0.manifestDigest == expectedManifestDigest
            }
            if exactInstalled.count == 1 {
                return observation(record: exactInstalled[0], pluginID: pluginID, scope: scope)
            }
            if exactInstalled.count > 1 || installed.count > 1 {
                throw PluginLifecycleError.versionAmbiguous(pluginID)
            }
        }
        if let installed = installed.first {
            return observation(record: installed, pluginID: pluginID, scope: scope)
        }
        if let expectedManifestDigest {
            let exactMatches = scopedMatches.filter {
                $0.manifestDigest == expectedManifestDigest
            }
            guard exactMatches.count <= 1 else {
                throw PluginLifecycleError.versionAmbiguous(pluginID)
            }
            guard let exact = exactMatches.first else {
                return .absent(host: host, pluginID: pluginID, scope: scope)
            }
            return observation(record: exact, pluginID: pluginID, scope: scope)
        }
        guard scopedMatches.count == 1 else {
            throw PluginLifecycleError.versionAmbiguous(pluginID)
        }
        return observation(record: scopedMatches[0], pluginID: pluginID, scope: scope)
    }

    private func expectedStateObserved(
        action: PluginLifecycleAction,
        observation: PluginLifecycleObservation
    ) -> Bool {
        switch action {
        case .install, .update:
            return observation.installed
        case .enable:
            return observation.installed && observation.enabled == true
        case .disable:
            return observation.installed && observation.enabled == false
        case .uninstall:
            return !observation.installed
        }
    }

    private func stagedCommand(for record: StoredDeploymentPlan) throws -> PluginLifecycleCommand {
        guard record.plan.metadata?["planType"] == "plugin-lifecycle",
              let change = record.plan.changes.first else {
            throw PluginLifecycleError.stagedCommandInvalid(record.stagingPath)
        }
        let stageRoot = URL(fileURLWithPath: record.stagingPath, isDirectory: true).standardizedFileURL
        guard stageRoot.path.hasPrefix(stagingRoot.path + "/") else {
            throw PluginLifecycleError.stagedCommandInvalid(stageRoot.path)
        }
        let staged = stageRoot.appendingPathComponent(change.relativePath)
        guard staged.standardizedFileURL.path.hasPrefix(stageRoot.path + "/"),
              fileManager.fileExists(atPath: staged.path),
              let data = try? Data(contentsOf: staged),
              SkillAssetCopier.sha256(data) == change.afterHash else {
            throw PluginLifecycleError.stagedCommandInvalid(staged.path)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let command = try? decoder.decode(PluginLifecycleCommand.self, from: data) else {
            throw PluginLifecycleError.stagedCommandInvalid(staged.path)
        }
        let argsData = try JSONEncoder().encode(command.arguments)
        let argsJSON = String(data: argsData, encoding: .utf8) ?? "[]"
        guard argsJSON == record.plan.metadata?["pluginArguments"] else {
            throw PluginLifecycleError.stagedCommandInvalid(staged.path)
        }
        guard (command.expectedManifestDigest ?? "")
            == (record.plan.metadata?["pluginExpectedManifestDigest"] ?? "") else {
            throw PluginLifecycleError.stagedCommandInvalid(staged.path)
        }
        return command
    }

    private func warnings(
        record: PluginInventoryRecord,
        scope: PluginLifecycleScope,
        command: PluginLifecycleCommand,
        executableComponents: [String]
    ) -> [String] {
        var values = [
            "宿主：\(command.host.displayName)；范围：\(scope.displayName)；工作目录：\(command.workingDirectory)",
            "只执行固定白名单宿主命令，不通过 shell，不接受任意附加参数。",
            "执行前会重新读取插件状态；manifest 或安装状态变化会使计划失效。"
        ]
        if !executableComponents.isEmpty {
            values.append("该插件包含需人工核对的组件：\(executableComponents.joined(separator: "、"))。")
        }
        if command.action == .uninstall, command.keepData {
            values.append("卸载会保留宿主持久化插件数据目录。")
        }
        if [.install, .update, .enable].contains(command.action) {
            values.append("宿主可能要求重启会话；回读只证明配置事实，不证明当前会话已加载。")
        }
        if record.risks.contains(where: { $0.contains("hook") }) {
            values.append("禁用或卸载不会撤销已经运行过的 hook 副作用。")
        }
        return values
    }

    private func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(String(scalar)) : "-"
        }
        return String(scalars.prefix(120))
    }

    private func processEnvironment(executable: URL) -> [String: String] {
        var values = environment
        values["HOME"] = homeDirectory.path
        let executableDirectory = executable.deletingLastPathComponent().path
        let path = values["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        values["PATH"] = executableDirectory + ":" + path
        return values
    }

    private func sanitize(_ value: String) -> String {
        let capped = String(value.prefix(32 * 1024))
        let replacements: [(String, String)] = [
            (#"(?i)(authorization|proxy-authorization)\s*[:=]\s*[^\r\n]+"#, "$1: <redacted>"),
            (#"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]+"#, "$1<redacted>"),
            (#"(?i)([?&](?:token|access_token|api_key|key|secret)=)[^&\s]+"#, "$1<redacted>"),
            (#"(https?://)[^/@\s:]+:[^/@\s]+@"#, "$1<redacted>@")
        ]
        var result = capped
        for (pattern, template) in replacements {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: template
            )
        }
        return result
    }

    private func write(_ operation: PluginLifecycleOperation) throws {
        let url = operationURL(operation.operationID)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(operation).write(to: url, options: .atomic)
    }

    private func operationURL(_ id: UUID) -> URL {
        operationsRoot.appendingPathComponent(id.uuidString, isDirectory: true)
            .appendingPathComponent("plugin-operation.json")
    }

    private static func runProcess(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String]
    ) -> PluginCommandOutput {
        let fileManager = FileManager.default
        let outputRoot = fileManager.temporaryDirectory
            .appendingPathComponent("skillset-plugin-\(UUID().uuidString)", isDirectory: true)
        let stdoutURL = outputRoot.appendingPathComponent("stdout.log")
        let stderrURL = outputRoot.appendingPathComponent("stderr.log")
        do {
            try fileManager.createDirectory(at: outputRoot, withIntermediateDirectories: true)
            fileManager.createFile(atPath: stdoutURL.path, contents: nil)
            fileManager.createFile(atPath: stderrURL.path, contents: nil)
            let stdout = try FileHandle(forWritingTo: stdoutURL)
            let stderr = try FileHandle(forWritingTo: stderrURL)
            defer {
                try? stdout.close()
                try? stderr.close()
                try? fileManager.removeItem(at: outputRoot)
            }

            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()

            let processBox = ProcessBox(process)
            let timeoutState = ProcessTimeoutState()
            let timeout = DispatchWorkItem {
                guard processBox.process.isRunning else { return }
                timeoutState.markTimedOut()
                processBox.process.terminate()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 120, execute: timeout)
            process.waitUntilExit()
            timeout.cancel()

            return PluginCommandOutput(
                exitCode: process.terminationStatus,
                stdout: readCapped(stdoutURL, fileManager: fileManager),
                stderr: readCapped(stderrURL, fileManager: fileManager),
                timedOut: timeoutState.timedOut
            )
        } catch {
            try? fileManager.removeItem(at: outputRoot)
            return PluginCommandOutput(
                exitCode: -1,
                stdout: "",
                stderr: error.localizedDescription,
                timedOut: false
            )
        }
    }

    private static func readCapped(_ url: URL, fileManager: FileManager) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "<非 UTF-8 输出>"
    }
}

private final class ProcessBox: @unchecked Sendable {
    let process: Process

    init(_ process: Process) {
        self.process = process
    }
}

private final class ProcessTimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var timedOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func markTimedOut() {
        lock.lock()
        value = true
        lock.unlock()
    }
}
