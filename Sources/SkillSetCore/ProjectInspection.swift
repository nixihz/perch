import Foundation

public struct ProjectInspection: Hashable, Sendable {
    public let observedSkillIDs: [String]
    public let ambiguousSlugs: [String]
    public let driftedSlugs: [String]
    public let ruleBody: String?
    public let ruleBodies: [String: String]
    public let lockStatus: String
    public let issues: [String]

    public init(
        observedSkillIDs: [String],
        ambiguousSlugs: [String],
        driftedSlugs: [String],
        ruleBody: String?,
        ruleBodies: [String: String],
        lockStatus: String,
        issues: [String]
    ) {
        self.observedSkillIDs = observedSkillIDs
        self.ambiguousSlugs = ambiguousSlugs
        self.driftedSlugs = driftedSlugs
        self.ruleBody = ruleBody
        self.ruleBodies = ruleBodies
        self.lockStatus = lockStatus
        self.issues = issues
    }
}

/// 只读取项目受管目录和规则块，不启动宿主、不读取凭据或全量源码。
public enum ProjectInspector {
    public static func inspect(
        projectURL: URL,
        catalog: CatalogDocument,
        ruleBlockID: String = "project-rules",
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
        var observed: Set<String> = []
        var ambiguous: [String] = []
        var drifted: Set<String> = []
        var inspectedRoots: Set<String> = []

        for target in targets where inspectedRoots.insert(target.skillsRoot).inserted {
            let skillsRoot = projectRoot.appendingPathComponent(target.skillsRoot, isDirectory: true)
            guard fileManager.fileExists(atPath: skillsRoot.path) else { continue }
            let children = try fileManager.contentsOfDirectory(
                at: skillsRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            for child in children {
                let slug = child.lastPathComponent
                if (try? fileManager.destinationOfSymbolicLink(atPath: child.path)) != nil {
                    issues.append("\(target.skillsRoot)/\(slug)：部署目标是软链，不参与受管状态推断。")
                    continue
                }
                var childIsDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: child.path, isDirectory: &childIsDirectory),
                      childIsDirectory.boolValue else {
                    issues.append("\(target.skillsRoot)/\(slug)：不是 Skill 目录。")
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
                    if matches.count == 1, let id = matches.first {
                        observed.insert(id)
                    } else if matches.count > 1 {
                        ambiguous.append(slug)
                    } else if !candidates.isEmpty || !lockedSkills.isEmpty {
                        drifted.insert(slug)
                    } else {
                        issues.append("\(target.skillsRoot)/\(slug)：目录存在，但 catalog 和项目锁中没有来源。")
                    }
                } catch {
                    issues.append("\(target.skillsRoot)/\(slug)：无法核对内容指纹（\(error.localizedDescription)）。")
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
            issues: issues.sorted()
        )
    }

    private static func inspectionTargets(
        state: ProjectStateSnapshot,
        ruleBlockID: String
    ) throws -> [ProjectDeploymentTarget] {
        if state.status == "valid", let lock = state.lock {
            return lock.targets
        }
        if let manifest = state.manifest {
            return try AgentDeploymentAdapter.targets(for: manifest)
        }
        return [AgentDeploymentAdapter.target(for: "codex", ruleBlockID: ruleBlockID)!]
    }
}
