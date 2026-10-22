import Foundation

public struct ProjectSkillObservation: Codable, Hashable, Sendable {
    public let agent: String
    public let relativePath: String
    public let skillID: String?
    public let ownership: String
    public let status: String
}

public struct ProjectInspection: Hashable, Sendable {
    public let observedSkillIDs: [String]
    public let ambiguousSlugs: [String]
    public let driftedSlugs: [String]
    public let ruleBody: String?
    public let ruleBodies: [String: String]
    public let lockStatus: String
    public let issues: [String]
    public let skillObservations: [ProjectSkillObservation]

    public init(
        observedSkillIDs: [String],
        ambiguousSlugs: [String],
        driftedSlugs: [String],
        ruleBody: String?,
        ruleBodies: [String: String],
        lockStatus: String,
        issues: [String],
        skillObservations: [ProjectSkillObservation] = []
    ) {
        self.observedSkillIDs = observedSkillIDs
        self.ambiguousSlugs = ambiguousSlugs
        self.driftedSlugs = driftedSlugs
        self.ruleBody = ruleBody
        self.ruleBodies = ruleBodies
        self.lockStatus = lockStatus
        self.issues = issues
        self.skillObservations = skillObservations
    }
}

/// 只读取项目受管目录和规则块，不启动宿主、不读取凭据或全量源码。
public enum ProjectInspector {
    public static func inspect(
        projectURL: URL,
        catalog: CatalogDocument,
        ruleBlockID: String = "project-rules",
        operationsRoot: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> ProjectInspection {
        let projectRoot = projectURL.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: projectRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw DeploymentError.projectNotFound(projectRoot.path)
        }

        let state = ProjectLockStore(projectRoot: projectRoot, fileManager: fileManager).inspect()
        var issues = state.status == "valid" || state.status == "absent" ? [] : state.issues
        let targets = try inspectionTargets(state: state, ruleBlockID: ruleBlockID)
        let lockedSkills = state.status == "valid" ? (state.lock?.skills ?? []) : []
        let ownedSkills = state.status == "valid"
            ? try ProjectOwnershipReader.skills(projectRoot: projectRoot, operationsRoot: operationsRoot, fileManager: fileManager)
            : [:]
        var skillObservations: [ProjectSkillObservation] = []
        var observed: Set<String> = []
        var ambiguous: [String] = []
        var drifted: Set<String> = []
        var inspectedRoots: Set<String> = []

        for target in targets where inspectedRoots.insert(target.skillsRoot).inserted {
            let skillsRoot = projectRoot.appendingPathComponent(target.skillsRoot, isDirectory: true)
            // 不经链接进入项目外目录；尚未受管的链接只记录节点事实。
            let components = target.skillsRoot.split(separator: "/")
            var prefix = projectRoot
            var linkedParent = false
            for component in components {
                prefix.appendPathComponent(String(component))
                if (try? fileManager.destinationOfSymbolicLink(atPath: prefix.path)) != nil {
                    issues.append("\(target.skillsRoot)：父目录是软链，未扫描。")
                    linkedParent = true
                    break
                }
            }
            if linkedParent { continue }
            guard fileManager.fileExists(atPath: skillsRoot.path) else { continue }
            let children = try fileManager.contentsOfDirectory(
                at: skillsRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            for child in children {
                let slug = child.lastPathComponent
                let path = "\(target.skillsRoot)/\(slug)"
                let owner = ownedSkills[path] == nil ? "existing" : "managed"
                if (try? fileManager.destinationOfSymbolicLink(atPath: child.path)) != nil {
                    issues.append("\(target.skillsRoot)/\(slug)：部署目标是软链，不参与受管状态推断。")
                    skillObservations.append(ProjectSkillObservation(agent: target.agent, relativePath: path, skillID: nil, ownership: owner, status: "symlink"))
                    continue
                }
                var childIsDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: child.path, isDirectory: &childIsDirectory),
                      childIsDirectory.boolValue else {
                    issues.append("\(target.skillsRoot)/\(slug)：不是 Skill 目录。")
                    skillObservations.append(ProjectSkillObservation(agent: target.agent, relativePath: path, skillID: nil, ownership: owner, status: "unknown"))
                    continue
                }
                do {
                    let actualHash = try SkillAssetCopier.analyze(from: child, fileManager: fileManager).contentHash
                    let lockedMatches = lockedSkills.filter { skill in
                        (skill.id.split(separator: "/").last.map(String.init) ?? "") == slug
                            && skill.contentHash == actualHash
                    }
                    let candidates = catalog.entries.filter { $0.slug == slug && !$0.isBlocked }
                    let catalogMatches = candidates.filter { $0.contentHash == actualHash }
                    let matches = lockedMatches.count == 1 ? lockedMatches.map(\.id) : catalogMatches.map(\.id)
                    let status = ownedSkills[path].map { $0 == actualHash ? "matching" : "drifted" }
                        ?? (matches.isEmpty ? "unknown" : "matching")
                    skillObservations.append(ProjectSkillObservation(
                        agent: target.agent, relativePath: path,
                        skillID: matches.count == 1 ? matches.first : nil, ownership: owner, status: status
                    ))
                    if matches.count == 1, let id = matches.first {
                        observed.insert(id)
                    } else if matches.count > 1 {
                        ambiguous.append(slug)
                    } else if !candidates.isEmpty || lockedSkills.contains(where: { $0.id.split(separator: "/").last.map(String.init) == slug }) {
                        drifted.insert(slug)
                    } else {
                        issues.append("\(target.skillsRoot)/\(slug)：目录存在，但 catalog 和项目锁中没有来源。")
                    }
                } catch {
                    issues.append("\(target.skillsRoot)/\(slug)：无法核对内容指纹（\(error.localizedDescription)）。")
                    skillObservations.append(ProjectSkillObservation(agent: target.agent, relativePath: path, skillID: nil, ownership: owner, status: "unknown"))
                }
            }
        }

        var ruleBody: String?
        var ruleBodies: [String: String] = [:]
        for target in targets.sorted(by: { $0.instructionsFile < $1.instructionsFile }) {
            let instructionsURL = projectRoot.appendingPathComponent(target.instructionsFile)
            guard fileManager.fileExists(atPath: instructionsURL.path) else { continue }
            if (try? fileManager.destinationOfSymbolicLink(atPath: instructionsURL.path)) != nil {
                issues.append("\(target.instructionsFile)：文件是软链，不读取受管块。")
                continue
            }
            do {
                let text = try String(contentsOf: instructionsURL, encoding: .utf8)
                if let body = try ManagedBlocks.extract(original: text, id: target.ruleBlockID) {
                    ruleBodies[target.instructionsFile] = body
                    if target.instructionsFile == "AGENTS.md" {
                        ruleBody = body
                    }
                }
            } catch {
                issues.append("\(target.instructionsFile)：受管块无法解析（\(error.localizedDescription)）。")
            }
        }
        if ruleBody == nil, ruleBodies.count == 1 {
            ruleBody = ruleBodies.values.first
        }

        return ProjectInspection(
            observedSkillIDs: observed.sorted(),
            ambiguousSlugs: ambiguous.sorted(),
            driftedSlugs: drifted.sorted(),
            ruleBody: ruleBody,
            ruleBodies: ruleBodies,
            lockStatus: state.status,
            issues: issues.sorted(),
            skillObservations: skillObservations.sorted { $0.relativePath < $1.relativePath }
        )
    }

    private static func inspectionTargets(
        state: ProjectStateSnapshot,
        ruleBlockID: String
    ) throws -> [ProjectDeploymentTarget] {
        let configured = state.status == "valid" ? state.lock?.targets : nil
        let fallback = try state.manifest.map { try AgentDeploymentAdapter.targets(for: $0) } ?? []
        var targets = configured ?? fallback
        for agent in AgentDeploymentAdapter.supportedAgents where !targets.contains(where: { $0.agent == agent }) {
            if let target = AgentDeploymentAdapter.target(for: agent, ruleBlockID: ruleBlockID) { targets.append(target) }
        }
        return targets
    }
}
