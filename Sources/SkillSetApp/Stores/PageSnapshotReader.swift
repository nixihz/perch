import Foundation
import SkillSetCore

/// 只读页面数据；不构造会初始化整个技能库的服务，也不执行写入计划。
enum PageSnapshotReader {
    static func mcpConfigurations(paths: SkillSetRuntimePaths, locations: GlobalConfigurationLocations,
                                  projectID: String) throws -> [MCPConfigurationInspection] {
        let projectRoot: URL?
        if let id = UUID(uuidString: projectID) {
            let registration = try ProjectStore(rootURL: paths.applicationSupportRoot).project(id: id)
            projectRoot = URL(fileURLWithPath: registration.canonicalPath, isDirectory: true)
        } else {
            projectRoot = nil
        }
        return MCPConfigurationManager(projectRoot: projectRoot, applicationSupportRoot: paths.applicationSupportRoot,
            environment: ["CODEX_HOME": locations.codexRoot.path], homeDirectory: locations.home).inspectAll()
    }

    static func pendingPlans(paths: SkillSetRuntimePaths) throws -> [StoredDeploymentPlan] {
        let now = Date()
        return try DeploymentPlanStore(rootURL: paths.plansRoot).list().filter {
            $0.approvalState != .applied && !$0.isExpired(at: now)
        }
    }
}
