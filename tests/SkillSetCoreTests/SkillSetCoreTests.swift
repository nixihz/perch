import Testing
import Foundation
@testable import SkillSetCore

struct SkillSetCoreTests {
    @Test
    func snapshotLoadsTheRealCatalogAndPreservesBlockedEntries() {
        let snapshot = AppSnapshot.load()
        #expect(snapshot.catalog.entries.count == 150)
        #expect(snapshot.catalog.entries.contains { $0.id == "workspace/stc" })
        #expect(snapshot.catalog.entries.contains { $0.id == "local-brian/ponytail-review" && $0.isBlocked })
    }

    @Test
    func searchMatchesNamespaceAndDescriptionWithoutChangingTheCatalog() {
        let entries = [
            SkillEntry(
                id: "workspace/stc",
                slug: "stc",
                declaredName: "stc",
                description: "中文技术文稿",
                declaredVersion: nil,
                metadataReview: "reviewed",
                sourceId: "workspace",
                path: "skills/stc",
                contentHash: "abc",
                fileCount: 1,
                bytes: 10,
                integrity: "snapshotted",
                issues: [],
                licenseReview: "required",
                excludedPaths: []
            ),
            SkillEntry(
                id: "local-brian/stc",
                slug: "stc",
                declaredName: "stc",
                description: "另一个来源",
                declaredVersion: nil,
                metadataReview: "reviewed",
                sourceId: "local-brian",
                path: "vendor/local-brian/stc",
                contentHash: "def",
                fileCount: 1,
                bytes: 10,
                integrity: "snapshotted",
                issues: [],
                licenseReview: "required",
                excludedPaths: []
            )
        ]
        #expect(matchingSkills(entries, query: "LOCAL-BRIAN").map(\.id) == ["local-brian/stc"])
        #expect(matchingSkills(entries, query: "中文").map(\.id) == ["workspace/stc"])
        #expect(matchingSkills(entries, query: "").count == 2)
    }

    @Test
    func mcpDraftRejectsSecretsAndIncompleteStdio() {
        let missingCommand = MCPConfigDraft(name: "demo", transport: "stdio")
        #expect(missingCommand.validationIssues().contains("stdio 服务器需要 command。"))

        let secretURL = MCPConfigDraft(
            name: "remote",
            transport: "streamable-http",
            command: "https://user:token@example.test/mcp"
        )
        #expect(secretURL.validationIssues().contains("配置中疑似包含带凭据的 URL，管理器不会接收。"))
    }

    @Test
    func presetsOnlyReferenceKnownCatalogEntries() {
        let snapshot = AppSnapshot.load()
        let ids = Set(snapshot.catalog.entries.map(\.id))
        #expect(snapshot.presets.allSatisfy { Set($0.skills).isSubset(of: ids) })
        #expect(snapshot.templates.map(\.id).sorted() == ["base-zh", "engineering", "ui-craft"])
    }

    @Test
    func managedBlockReplacesOnlyItsOwnBytesAndRejectsMalformedMarkers() throws {
        let original = """
        # 项目约定

        手写内容
        <!-- skillset:begin id=project-rules schema=1 -->
        旧规则
        <!-- skillset:end id=project-rules -->

        尾部内容
        """
        let result = try ManagedBlocks.upsert(original: original, id: "project-rules", body: "新规则")
        #expect(result.content.contains("手写内容"))
        #expect(result.content.contains("尾部内容"))
        #expect(!result.content.contains("旧规则"))
        #expect(result.content.contains("新规则"))

        let duplicate = """
        <!-- skillset:begin id=project-rules schema=1 -->
        a
        <!-- skillset:end id=project-rules -->
        <!-- skillset:begin id=project-rules schema=1 -->
        b
        <!-- skillset:end id=project-rules -->
        """
        #expect(throws: ManagedBlockError.duplicateBegin("project-rules")) {
            try ManagedBlocks.upsert(original: duplicate, id: "project-rules", body: "c")
        }
    }

    @Test
    func projectStoreDeduplicatesCanonicalPathAndRejectsSymlinkEscape() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("skillset-store-\(UUID().uuidString)", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        try fileManager.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let store = ProjectStore(rootURL: root.appendingPathComponent("state"))
        let first = try store.register(path: project, name: "Demo", agents: ["codex"])
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        try fileManager.createSymbolicLink(at: alias, withDestinationURL: project)
        let second = try store.register(path: alias, name: "Other", agents: ["claude-code"])
        #expect(first.id == second.id)
        #expect(second.agents == ["claude-code", "codex"])
        #expect(try store.list().count == 1)

        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("outside-link", isDirectory: true)
        try fileManager.createSymbolicLink(at: link, withDestinationURL: outside)
        let outsideProject = try store.register(path: link, name: "Outside")
        #expect(outsideProject.canonicalPath == outside.path)
        #expect(throws: SkillSetStoreError.self) {
            try store.register(path: root.appendingPathComponent("missing"))
        }
    }

    @Test
    func deploymentAppliesChecksHashesAndRollsBack() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }

        let planner = DeploymentPlanner(
            catalog: fixture.catalog,
            repositoryRoot: fixture.repository,
            stagingRoot: fixture.staging
        )
        let plan = try planner.makePlan(
            projectPath: fixture.project,
            request: DeploymentRequest(skillIDs: ["workspace/demo"], instructionIDs: ["base"], ruleBlockID: "project-rules"),
            fragments: ["base": "只做受管内容"]
        )
        #expect(plan.changes.count == 4)

        let executor = FileTransactionExecutor(operationsRoot: fixture.operations, idGenerator: { fixture.operationID })
        let result = try executor.apply(plan: plan, from: fixture.staging.appendingPathComponent(plan.id.uuidString))
        #expect(result.changedPaths.contains(".agents/skills/demo"))
        let deployed = fixture.project.appendingPathComponent(".agents/skills/demo/SKILL.md")
        #expect(try String(contentsOf: deployed, encoding: .utf8) == "# Demo\n")
        let scriptAttributes = try FileManager.default.attributesOfItem(
            atPath: fixture.project.appendingPathComponent(".agents/skills/demo/scripts/run.sh").path
        )
        let scriptPermissions = (scriptAttributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        #expect(scriptPermissions & 0o111 != 0)
        let inspection = try ProjectInspector.inspect(projectURL: fixture.project, catalog: fixture.catalog, operationsRoot: fixture.operations)
        #expect(inspection.observedSkillIDs == ["workspace/demo"])
        #expect(inspection.ruleBody == "只做受管内容")
        #expect(inspection.lockStatus == "valid")
        #expect(!FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent("skillset.json").path))
        #expect(FileManager.default.fileExists(atPath: fixture.stateStore.manifestURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent("skillset.lock.json").path))
        #expect(FileManager.default.fileExists(atPath: fixture.stateStore.lockURL.path))

        try "用户新编辑".write(to: deployed, atomically: true, encoding: .utf8)
        #expect(throws: FileTransactionError.rollbackConflict(".agents/skills/demo")) {
            try executor.rollback(operationID: fixture.operationID)
        }
    }

    @Test
    func deploymentRejectsStaleBeforeHashWithoutWriting() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let planner = DeploymentPlanner(catalog: fixture.catalog, repositoryRoot: fixture.repository, stagingRoot: fixture.staging)
        let plan = try planner.makePlan(
            projectPath: fixture.project,
            request: DeploymentRequest(skillIDs: ["workspace/demo"]),
            fragments: [:]
        )
        let target = fixture.project.appendingPathComponent(".agents/skills/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try "外部内容".write(to: target.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let executor = FileTransactionExecutor(operationsRoot: fixture.operations)
        #expect(throws: FileTransactionError.staleFile(".agents/skills/demo")) {
            try executor.apply(plan: plan, from: fixture.staging.appendingPathComponent(plan.id.uuidString))
        }
        #expect(try String(contentsOf: target.appendingPathComponent("SKILL.md"), encoding: .utf8) == "外部内容")
    }

    @Test
    func deploymentRejectsUnmanagedDirectoryWithoutChangingIt() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let existing = fixture.project.appendingPathComponent(".agents/skills/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        try "旧版本\n".write(to: existing.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        #expect(throws: DeploymentError.unmanagedSkillConflict(".agents/skills/demo")) {
            try fixture.makePlan()
        }
        #expect(try String(contentsOf: existing.appendingPathComponent("SKILL.md"), encoding: .utf8) == "旧版本\n")
        #expect(!FileManager.default.fileExists(atPath: existing.appendingPathComponent("scripts/run.sh").path))
    }

    @Test
    func plannerRejectsSymlinkAtTheManagedSkillTarget() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let destinationParent = fixture.project.appendingPathComponent(".agents/skills", isDirectory: true)
        let outside = fixture.root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: destinationParent.appendingPathComponent("demo", isDirectory: true),
            withDestinationURL: outside
        )

        #expect(throws: DeploymentError.self) {
            try fixture.makePlan()
        }
    }

    @Test
    func copierMaterializesInsideSymlinksAndKeepsHiddenNestedAssets() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("skillset-copy-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(at: source.appendingPathComponent("assets/tree"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: source.appendingPathComponent("config"), withIntermediateDirectories: true)
        try "# Skill\n".write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "hidden\n".write(to: source.appendingPathComponent("config/.secret"), atomically: true, encoding: .utf8)
        try "nested\n".write(to: source.appendingPathComponent("assets/tree/nested.md"), atomically: true, encoding: .utf8)
        try fileManager.createSymbolicLink(
            atPath: source.appendingPathComponent("alias.md").path,
            withDestinationPath: "assets/tree/nested.md"
        )
        try fileManager.createSymbolicLink(
            atPath: source.appendingPathComponent("linked-tree").path,
            withDestinationPath: "assets/tree"
        )

        let result = try SkillAssetCopier.copy(from: source, to: destination, fileManager: fileManager)
        #expect(result.files == ["SKILL.md", "alias.md", "assets/tree/nested.md", "config/.secret", "linked-tree/nested.md"])
        #expect(try String(contentsOf: destination.appendingPathComponent("alias.md"), encoding: .utf8) == "nested\n")
        #expect(try String(contentsOf: destination.appendingPathComponent("linked-tree/nested.md"), encoding: .utf8) == "nested\n")
        #expect(try destination.appendingPathComponent("alias.md").resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true)
        #expect(try destination.appendingPathComponent("linked-tree").resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true)
    }

    @Test
    func copierRejectsSymlinkThatEscapesTheSkillRoot() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("skillset-escape-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let outside = root.appendingPathComponent("outside.md")
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        try "# Skill\n".write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "outside\n".write(to: outside, atomically: true, encoding: .utf8)
        try fileManager.createSymbolicLink(
            atPath: source.appendingPathComponent("escape.md").path,
            withDestinationPath: outside.path
        )

        #expect(throws: SkillAssetCopyError(path: "escape.md", reason: "软链越出 Skill 根目录")) {
            try SkillAssetCopier.copy(from: source, to: destination, fileManager: fileManager)
        }
    }

    @Test
    func copierRejectsAResourceLinkCycle() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("skillset-cycle-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        try "# Skill\n".write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try fileManager.createSymbolicLink(
            atPath: source.appendingPathComponent("loop").path,
            withDestinationPath: "."
        )

        #expect(throws: SkillAssetCopyError(path: "loop", reason: "软链形成循环")) {
            try SkillAssetCopier.copy(from: source, to: destination, fileManager: fileManager)
        }
    }

    @Test
    func planStoreRequiresExactDigestAndFreshLocalApproval() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let plan = try fixture.makePlan()
        let start = Date(timeIntervalSince1970: 1_000)
        var now = start
        let store = DeploymentPlanStore(rootURL: fixture.root.appendingPathComponent("plans"), clock: { now })
        let saved = try store.save(
            plan: plan,
            stagingPath: fixture.staging.appendingPathComponent(plan.id.uuidString).path,
            expiresAt: start.addingTimeInterval(60)
        )

        #expect(throws: DeploymentPlanStoreError.approvalRequired(plan.id.uuidString)) {
            try store.requireApprovedForApply(id: plan.id, digest: plan.digest)
        }
        #expect(throws: DeploymentPlanStoreError.digestMismatch) {
            try store.approve(id: plan.id, digest: "different")
        }

        let approved = try store.approve(id: plan.id, digest: saved.plan.digest)
        #expect(approved.approvalState == .approved)
        #expect(approved.approvedAt == start)

        now = start.addingTimeInterval(61)
        #expect(throws: DeploymentPlanStoreError.expired(plan.id.uuidString)) {
            try store.requireApprovedForApply(id: plan.id, digest: plan.digest)
        }
    }

    @Test
    func projectDraftStoreRoundTripsNormalizedDesiredState() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("skillset-drafts-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        let projectID = UUID()
        let now = Date(timeIntervalSince1970: 2_000)
        let store = ProjectDraftStore(rootURL: root, clock: { now })

        _ = try store.save(
            projectID: projectID,
            skillIDs: ["workspace/stc", "workspace/stc", " workspace/project-guide "],
            instructionIDs: ["engineering", "base-zh", "engineering"],
            agents: ["codex", "claude-code", "codex"]
        )
        let loaded = try store.load(projectID: projectID)
        #expect(loaded?.skillIDs == ["workspace/project-guide", "workspace/stc"])
        #expect(loaded?.instructionIDs == ["base-zh", "engineering"])
        #expect(loaded?.agents == ["claude-code", "codex"])
        #expect(loaded?.updatedAt == now)

        try store.remove(projectID: projectID)
        #expect(try store.load(projectID: projectID) == nil)
    }

    @Test
    func runtimeDetectionFindsRepositoryFromNestedExecutable() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("skillset-runtime-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("build/nested")
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root.appendingPathComponent("registry"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try "{}".write(to: root.appendingPathComponent("registry/catalog.json"), atomically: true, encoding: .utf8)

        let paths = SkillSetRuntimePaths.detect(
            environment: [:],
            executableURL: nested.appendingPathComponent("skillset"),
            currentDirectoryURL: fileManager.temporaryDirectory,
            applicationSupportRoot: root.appendingPathComponent("state")
        )
        #expect(paths.repositoryRoot?.path == root.path)
        #expect(paths.stagingRoot.lastPathComponent == "staging")
    }

    @Test
    func sourcePreviewParsesOnlyCredentialFreeRepositoryRoots() throws {
        let service = SourcePreviewService(previewsRoot: FileManager.default.temporaryDirectory)
        let parsed = try service.parseSource("https://github.com/mattpocock/skills.git")
        #expect(parsed.canonicalURL == "https://github.com/mattpocock/skills")
        #expect(parsed.namespace == "mattpocock-skills")

        let enterprise = try service.parseSource("https://git.example.com/team/platform/skills.git")
        #expect(enterprise.canonicalURL == "https://git.example.com/team/platform/skills")
        #expect(enterprise.cloneURL == "https://git.example.com/team/platform/skills.git")
        #expect(enterprise.namespace == "team-platform-skills")

        let custom = try service.parseSource("https://git.xiezhi.xin/iamx/skill-set")
        #expect(custom.cloneURL == "https://git.xiezhi.xin/iamx/skill-set.git")
        let ssh = try service.parseSource("ssh://git@git.xiezhi.xin:2222/iamx/skill-set.git")
        #expect(ssh.cloneURL == "ssh://git@git.xiezhi.xin:2222/iamx/skill-set.git")
        let scp = try service.parseSource("git@gitlab.com:team/subgroup/skills.git")
        #expect(scp.cloneURL == "ssh://git@gitlab.com/team/subgroup/skills.git")
        #expect(throws: SourcePreviewError.self) {
            try service.parseSource("https://git.example.com/team/../skills")
        }
        let shorthand = try service.parseSource("mattpocock/skills")
        #expect(shorthand.canonicalURL == "https://github.com/mattpocock/skills")

        #expect(throws: SourcePreviewError.credentialsInURL) {
            try service.parseSource("https://user:token@github.com/mattpocock/skills")
        }
        #expect(throws: SourcePreviewError.invalidURL("https://github.com/mattpocock/skills/tree/main/skills")) {
            try service.parseSource("https://github.com/mattpocock/skills/tree/main/skills")
        }
    }

    @Test
    func rejectedSourceLinksDoNotExposeCredentialsInUserMessages() {
        let service = SourcePreviewService(previewsRoot: FileManager.default.temporaryDirectory)
        for link in [
            "https://user:private-secret@github.com/owner/repo",
            "file:///private-secret/repo",
            "not-a-repository-private-secret"
        ] {
            do {
                _ = try service.parseSource(link)
                Issue.record("含凭据或格式错误的来源不应通过检查")
            } catch {
                #expect(!error.localizedDescription.contains("private-secret"))
                #expect(!error.localizedDescription.contains(link))
                #expect(error.localizedDescription.contains("请"))
            }
        }
    }

    @Test
    func sourcePreviewScansCandidatesWithoutRunningRepositoryScripts() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("skillset-source-\(UUID().uuidString)", isDirectory: true)
        let promoted = root.appendingPathComponent("skills/engineering/alpha", isDirectory: true)
        let deprecated = root.appendingPathComponent("skills/deprecated/old", isDirectory: true)
        let scripts = root.appendingPathComponent("scripts", isDirectory: true)
        let marker = root.appendingPathComponent("script-ran")
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: promoted, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: deprecated, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: scripts, withIntermediateDirectories: true)
        try "MIT License\n".write(to: root.appendingPathComponent("LICENSE"), atomically: true, encoding: .utf8)
        try """
        ---
        name: alpha
        description: Alpha skill
        ---
        # Alpha
        """.write(to: promoted.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try """
        ---
        name: old
        description: Deprecated skill
        ---
        # Old
        """.write(to: deprecated.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "touch \(marker.path)\n".write(
            to: scripts.appendingPathComponent("postinstall.sh"),
            atomically: true,
            encoding: .utf8
        )

        let service = SourcePreviewService(previewsRoot: root.appendingPathComponent("previews"))
        let preview = try service.scan(checkout: root, inputURL: "https://example.test/repo", commit: "abc123")
        #expect(preview.licenseEvidence == "MIT · 仍需逐 skill 审查")
        #expect(preview.candidates.map(\.slug) == ["alpha", "old"])
        #expect(preview.candidates.first?.state == .promoted)
        #expect(preview.candidates.last?.state == .deprecated)
        #expect(preview.candidates.first?.description == "Alpha skill")
        #expect(!fileManager.fileExists(atPath: marker.path))
    }

    @Test
    func projectManifestDigestIsStableAcrossInputOrdering() {
        let first = ProjectManifest(
            agents: ["claude-code", "codex"],
            skills: ["workspace/z", "workspace/a"],
            instructions: ["ui-craft", "base-zh"],
            ruleBlockID: "project-rules"
        )
        let second = ProjectManifest(
            agents: ["codex", "claude-code", "codex"],
            skills: ["workspace/a", "workspace/z"],
            instructions: ["base-zh", "ui-craft"],
            ruleBlockID: "project-rules"
        )
        #expect(first.canonicalData == second.canonicalData)
        #expect(first.digest == second.digest)
        #expect(first.agents == ["claude-code", "codex"])
    }

    @Test
    func projectLockPinsFilesAndRestoresThemFromTheObjectStore() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let plan = try fixture.makePlan()
        let stage = fixture.staging.appendingPathComponent(plan.id.uuidString)
        let manifest = try JSONDecoder().decode(
            ProjectManifest.self,
            from: Data(contentsOf: stage.appendingPathComponent(ProjectLockStore.manifestFileName))
        )
        let lock = try JSONDecoder().decode(
            ProjectLockDocument.self,
            from: Data(contentsOf: stage.appendingPathComponent(ProjectLockStore.lockFileName))
        )
        try lock.validate(against: manifest)
        #expect(lock.skills.count == 1)
        #expect(lock.skills[0].files.map(\.path) == ["SKILL.md", "scripts/run.sh"])
        #expect(lock.skills[0].files[1].executable)

        let store = SkillObjectStore(repositoryRoot: fixture.repository)
        #expect(try store.verify(lock: lock).checkedObjects == 3)
        try FileManager.default.removeItem(at: fixture.repository.appendingPathComponent("skills/demo"))
        let restored = fixture.root.appendingPathComponent("restored", isDirectory: true)
        try store.restore(files: lock.skills[0].files, to: restored)
        let restoredHash = try SkillAssetCopier.analyze(from: restored).contentHash
        #expect(restoredHash == lock.skills[0].contentHash)
    }

    @Test
    func objectManifestAllowsANewProjectToPlanOffline() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        _ = try fixture.makePlan()
        try FileManager.default.removeItem(at: fixture.repository.appendingPathComponent("skills/demo"))

        let offlineProject = fixture.root.appendingPathComponent("offline-project", isDirectory: true)
        try FileManager.default.createDirectory(at: offlineProject, withIntermediateDirectories: true)
        let plan = try DeploymentPlanner(
            catalog: fixture.catalog,
            repositoryRoot: fixture.repository,
            stagingRoot: fixture.staging
        ).makePlan(
            projectPath: offlineProject,
            request: DeploymentRequest(skillIDs: ["workspace/demo"]),
            fragments: [:]
        )
        _ = try FileTransactionExecutor(operationsRoot: fixture.operations)
            .apply(plan: plan, from: fixture.staging.appendingPathComponent(plan.id.uuidString))
        let deployed = offlineProject.appendingPathComponent(".agents/skills/demo/SKILL.md")
        #expect(try String(contentsOf: deployed, encoding: .utf8) == "# Demo\n")
    }

    @Test
    func plannerDeploysOneApprovedRevisionToCodexAndClaude() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let plan = try DeploymentPlanner(
            catalog: fixture.catalog,
            repositoryRoot: fixture.repository,
            stagingRoot: fixture.staging
        ).makePlan(
            projectPath: fixture.project,
            request: DeploymentRequest(
                skillIDs: ["workspace/demo"],
                instructionIDs: ["base"],
                agents: ["codex", "claude-code"]
            ),
            fragments: ["base": "双宿主规则"]
        )
        #expect(Set(plan.changes.map(\.relativePath)) == Set([
            ".agents/skills/demo",
            ".claude/skills/demo",
            "AGENTS.md",
            "CLAUDE.md",
            ProjectLockStore.manifestFileName,
            ProjectLockStore.lockFileName
        ]))
        _ = try FileTransactionExecutor(operationsRoot: fixture.operations)
            .apply(plan: plan, from: fixture.staging.appendingPathComponent(plan.id.uuidString))

        #expect(FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent(".agents/skills/demo/SKILL.md").path))
        #expect(FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent(".claude/skills/demo/SKILL.md").path))
        #expect(try String(contentsOf: fixture.project.appendingPathComponent("AGENTS.md"), encoding: .utf8).contains("双宿主规则"))
        #expect(try String(contentsOf: fixture.project.appendingPathComponent("CLAUDE.md"), encoding: .utf8).contains("双宿主规则"))
        let inspection = try ProjectInspector.inspect(projectURL: fixture.project, catalog: fixture.catalog, operationsRoot: fixture.operations)
        #expect(inspection.observedSkillIDs == ["workspace/demo"])
        #expect(inspection.ruleBodies.keys.sorted() == ["AGENTS.md", "CLAUDE.md"])
    }

    @Test
    func manifestChangeWithoutANewLockIsReportedAsStale() throws {
        let fixture = try DeploymentFixture()
        defer { fixture.cleanup() }
        let plan = try fixture.makePlan()
        _ = try FileTransactionExecutor(operationsRoot: fixture.operations)
            .apply(plan: plan, from: fixture.staging.appendingPathComponent(plan.id.uuidString))

        let manifest = ProjectManifest(
            agents: ["codex"],
            skills: ["workspace/other"],
            instructions: ["base"],
            ruleBlockID: "project-rules"
        )
        try manifest.encodedData.write(
            to: fixture.stateStore.manifestURL,
            options: .atomic
        )
        let state = fixture.stateStore.inspect()
        #expect(state.status == "stale")
        #expect(state.issues.joined().contains("不一致"))
    }

    @Test
    func managedBlockRemovalPreservesTextOutsideTheBlock() throws {
        let original = """
        # 标题

        前文

        <!-- skillset:begin id=project-rules schema=1 -->
        旧规则
        <!-- skillset:end id=project-rules -->

        后文
        """
        let result = try ManagedBlocks.remove(original: original, id: "project-rules")
        #expect(result.changed)
        #expect(result.content.contains("前文"))
        #expect(result.content.contains("后文"))
        #expect(!result.content.contains("旧规则"))
        #expect(!result.content.contains("skillset:begin"))
    }

    @Test
    func claudeMCPConfigPreservesUnknownFieldsAndUsesEnvironmentReferences() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("skillset-mcp-claude-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let config = root.appendingPathComponent(".mcp.json")
        try """
        {
          "theme": "keep-me",
          "mcpServers": {
            "existing": {"type": "stdio", "command": "existing-server"}
          }
        }
        """.write(to: config, atomically: true, encoding: .utf8)

        let manager = MCPConfigurationManager(
            projectRoot: root,
            applicationSupportRoot: root.appendingPathComponent("state"),
            environment: [:],
            homeDirectory: root
        )
        let target = try #require(manager.targets().first {
            $0.host == .claudeCode && $0.scope == .project
        })
        let edit = try manager.makeEdit(
            target: target,
            draft: MCPConfigurationDraft(
                name: "skillset",
                host: .claudeCode,
                scope: .project,
                commandOrURL: "skillset",
                args: ["mcp", "serve"],
                envKeys: ["SKILLSET_TOKEN"]
            )
        )
        let object = try #require(JSONSerialization.jsonObject(with: edit.content) as? [String: Any])
        #expect(object["theme"] as? String == "keep-me")
        let servers = try #require(object["mcpServers"] as? [String: Any])
        #expect(servers["existing"] != nil)
        let added = try #require(servers["skillset"] as? [String: Any])
        #expect((added["env"] as? [String: String])?["SKILLSET_TOKEN"] == "${SKILLSET_TOKEN}")

        #expect(throws: MCPConfigurationError.configConflict("existing")) {
            try manager.makeEdit(
                target: target,
                draft: MCPConfigurationDraft(
                    name: "existing",
                    host: .claudeCode,
                    scope: .project,
                    commandOrURL: "replacement"
                )
            )
        }
    }

    @Test
    func codexMCPConfigOnlyReplacesMarkedBlocks() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("skillset-mcp-codex-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        let config = root.appendingPathComponent(".codex/config.toml")
        try """
        # 用户手动配置
        [mcp_servers.existing]
        command = "existing-server"
        """.write(to: config, atomically: true, encoding: .utf8)

        let manager = MCPConfigurationManager(
            projectRoot: nil,
            applicationSupportRoot: root.appendingPathComponent("state"),
            environment: ["CODEX_HOME": root.appendingPathComponent(".codex").path],
            homeDirectory: root
        )
        let target = try #require(manager.targets().first { $0.host == .codex })
        let first = try manager.makeEdit(
            target: target,
            draft: MCPConfigurationDraft(
                name: "skillset",
                host: .codex,
                scope: .user,
                commandOrURL: "skillset",
                args: ["mcp", "serve"]
            )
        )
        let firstText = String(decoding: first.content, as: UTF8.self)
        #expect(firstText.contains("# 用户手动配置"))
        #expect(firstText.contains("# skillset:begin mcp name=skillset schema=1"))
        try first.content.write(to: config, options: .atomic)

        let second = try manager.makeEdit(
            target: target,
            draft: MCPConfigurationDraft(
                name: "skillset",
                host: .codex,
                scope: .user,
                commandOrURL: "/opt/skillset"
            )
        )
        let secondText = String(decoding: second.content, as: UTF8.self)
        #expect(secondText.contains("command = \"/opt/skillset\""))
        #expect(secondText.contains("command = \"existing-server\""))
        #expect(secondText.components(separatedBy: "# skillset:begin").count == 2)

        #expect(throws: MCPConfigurationError.configConflict("existing")) {
            try manager.makeEdit(
                target: target,
                draft: MCPConfigurationDraft(
                    name: "existing",
                    host: .codex,
                    scope: .user,
                    commandOrURL: "replace"
                )
            )
        }
    }

    @Test
    func mcpConfigurationPlanRequiresApprovalAndRecordsOwnership() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("skillset-mcp-plan-\(UUID().uuidString)", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let state = root.appendingPathComponent("state", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: project, withIntermediateDirectories: true)

        let paths = SkillSetRuntimePaths(
            applicationSupportRoot: state,
            repositoryRoot: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        )
        let service = try SkillSetService(paths: paths)
        let registration = try ProjectStore(rootURL: state).register(path: project, name: "MCP Fixture")
        let record = try service.makeMCPConfigPlan(
            projectID: registration.id,
            draft: MCPConfigurationDraft(
                name: "skillset",
                host: .claudeCode,
                scope: .project,
                commandOrURL: "skillset",
                args: ["mcp", "serve"]
            )
        )
        #expect(record.plan.metadata?["planType"] == "mcp-configuration")
        #expect(!fileManager.fileExists(atPath: project.appendingPathComponent(".mcp.json").path))
        #expect(throws: DeploymentPlanStoreError.approvalRequired(record.id.uuidString)) {
            try service.apply(planID: record.id, digest: record.plan.digest)
        }

        _ = try service.approve(planID: record.id, digest: record.plan.digest)
        _ = try service.apply(planID: record.id, digest: record.plan.digest)
        let inspections = try service.mcpConfigurations(projectID: registration.id)
        let projectConfig = try #require(inspections.first {
            $0.host == .claudeCode && $0.scope == .project
        })
        #expect(projectConfig.servers.map(\.name) == ["skillset"])
        #expect(projectConfig.servers[0].managed)
    }

    @Test
    func pluginInventoryMergesClaudeInstallStateAndDoesNotFollowCacheSymlinks() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("skillset-plugins-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let installPath = home.appendingPathComponent(".claude/plugins/cache/demo/sample/1.2.0", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(
            at: installPath.appendingPathComponent(".claude-plugin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: installPath.appendingPathComponent("hooks", isDirectory: true),
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "name": "sample",
            "version": "1.2.0",
            "description": "fixture",
            "hooks": "./hooks/hooks.json"
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: installPath.appendingPathComponent(".claude-plugin/plugin.json"))
        let installed: [String: Any] = [
            "version": 2,
            "plugins": [
                "sample@demo": [[
                    "scope": "user",
                    "installPath": installPath.path,
                    "version": "1.2.0",
                    "gitCommitSha": String(repeating: "a", count: 40)
                ]]
            ]
        ]
        try JSONSerialization.data(withJSONObject: installed, options: [.sortedKeys])
            .write(to: home.appendingPathComponent(".claude/plugins/installed_plugins.json"))
        try JSONSerialization.data(
            withJSONObject: ["enabledPlugins": ["sample@demo": true]],
            options: [.sortedKeys]
        ).write(to: home.appendingPathComponent(".claude/settings.json"))

        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try fileManager.createDirectory(
            at: outside.appendingPathComponent(".claude-plugin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: ["name": "outside"])
            .write(to: outside.appendingPathComponent(".claude-plugin/plugin.json"))
        try fileManager.createDirectory(
            at: home.appendingPathComponent(".claude/plugins/cache", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createSymbolicLink(
            at: home.appendingPathComponent(".claude/plugins/cache/escape"),
            withDestinationURL: outside
        )

        let snapshot = PluginInventoryManager(projectRoot: nil, homeDirectory: home).inspect()
        #expect(snapshot.records.map(\.pluginID) == ["sample@demo"])
        let sample = try #require(snapshot.records.first)
        #expect(sample.marketplaceID == "demo")
        #expect(sample.installed)
        #expect(sample.enabled == true)
        #expect(sample.sourceRevision == String(repeating: "a", count: 40))
        #expect(sample.components.contains("hooks"))
        #expect(sample.risks.contains("含 hook"))
    }

    @Test
    func pluginInventoryReadsCodexEnabledStateFromConfig() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("skillset-codex-plugin-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let installPath = home.appendingPathComponent(".codex/plugins/cache/demo/sample/1.0.0", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(
            at: installPath.appendingPathComponent(".codex-plugin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: ["name": "sample", "version": "1.0.0"])
            .write(to: installPath.appendingPathComponent(".codex-plugin/plugin.json"))
        try """
        [marketplaces.demo]
        source = "https://example.test/demo.git"

        [plugins."sample@demo"]
        enabled = false
        """.write(to: home.appendingPathComponent(".codex/config.toml"), atomically: true, encoding: .utf8)

        let snapshot = PluginInventoryManager(projectRoot: nil, homeDirectory: home).inspect()
        let sample = try #require(snapshot.records.first)
        #expect(sample.host == .codex)
        #expect(sample.installed)
        #expect(sample.enabled == false)
        #expect(sample.state.contains("已停用"))
    }

    @Test
    func pluginLifecycleRequiresApprovalThenExecutesFixedCommandAndRecordsOperation() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("skillset-plugin-lifecycle-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let state = root.appendingPathComponent("state", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try installPluginFixture(
            home: home,
            enabled: false,
            manifest: ["name": "sample", "version": "1.2.0"]
        )

        var invocations: [[String]] = []
        let planStore = DeploymentPlanStore(rootURL: state.appendingPathComponent("plans", isDirectory: true))
        let manager = PluginLifecycleManager(
            planStore: planStore,
            stagingRoot: state.appendingPathComponent("staging", isDirectory: true),
            operationsRoot: state.appendingPathComponent("operations", isDirectory: true),
            homeDirectory: home,
            executableOverrides: [.claudeCode: URL(fileURLWithPath: "/usr/bin/true")],
            commandRunner: { _, arguments, _, _ in
                invocations.append(arguments)
                try? self.writeClaudeEnabledSettings(home: home, enabled: true)
                return PluginCommandOutput(exitCode: 0, stdout: #"{"ok":true}"#, stderr: "")
            }
        )
        let paths = SkillSetRuntimePaths(
            applicationSupportRoot: state,
            repositoryRoot: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        )
        let service = try SkillSetService(
            paths: paths,
            planStore: planStore,
            pluginLifecycleManager: manager
        )
        let planned = try service.makePluginLifecyclePlan(
            projectID: nil,
            request: PluginLifecycleRequest(
                host: .claudeCode,
                pluginID: "sample@demo",
                action: .enable,
                scope: .user
            )
        )
        #expect(planned.plan.metadata?["planType"] == "plugin-lifecycle")
        #expect(planned.plan.metadata?["pluginCommandPreview"]?.contains("plugin enable sample@demo") == true)
        #expect(planned.approvalState == .pending)
        #expect(throws: DeploymentPlanStoreError.approvalRequired(planned.id.uuidString)) {
            try service.apply(planID: planned.id, digest: planned.plan.digest)
        }
        #expect(invocations.isEmpty)

        _ = try service.approve(planID: planned.id, digest: planned.plan.digest)
        let applied = try service.apply(planID: planned.id, digest: planned.plan.digest)
        #expect(invocations == [[
            "plugin",
            "enable",
            "sample@demo",
            "--scope",
            "user",
            "--json"
        ]])
        #expect(applied.message?.contains("回读已观察到目标状态") == true)
        let operation = try service.pluginOperation(applied.operationID)
        #expect(operation.state == "applied")
        #expect(operation.action == .enable)
        #expect(operation.before.enabled == false)
        #expect(operation.after?.enabled == true)
        #expect(operation.outputSHA256.count == 64)
        #expect(throws: DeploymentPlanStoreError.alreadyApplied(planned.id.uuidString)) {
            try service.apply(planID: planned.id, digest: planned.plan.digest)
        }
    }

    @Test
    func pluginLifecycleRejectsPlanWhenObservedStateChangedBeforeApply() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("skillset-plugin-stale-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let state = root.appendingPathComponent("state", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try installPluginFixture(
            home: home,
            enabled: true,
            manifest: ["name": "sample", "version": "1.2.0"]
        )

        var invocations: [[String]] = []
        let planStore = DeploymentPlanStore(rootURL: state.appendingPathComponent("plans", isDirectory: true))
        let manager = PluginLifecycleManager(
            planStore: planStore,
            stagingRoot: state.appendingPathComponent("staging", isDirectory: true),
            operationsRoot: state.appendingPathComponent("operations", isDirectory: true),
            homeDirectory: home,
            executableOverrides: [.claudeCode: URL(fileURLWithPath: "/usr/bin/true")],
            commandRunner: { _, arguments, _, _ in
                invocations.append(arguments)
                return PluginCommandOutput(exitCode: 0, stdout: "", stderr: "")
            }
        )
        let service = try SkillSetService(
            paths: SkillSetRuntimePaths(
                applicationSupportRoot: state,
                repositoryRoot: URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
            ),
            planStore: planStore,
            pluginLifecycleManager: manager
        )
        let planned = try service.makePluginLifecyclePlan(
            projectID: nil,
            request: PluginLifecycleRequest(
                host: .claudeCode,
                pluginID: "sample@demo",
                action: .disable,
                scope: .user
            )
        )
        try writeClaudeEnabledSettings(home: home, enabled: false)
        _ = try service.approve(planID: planned.id, digest: planned.plan.digest)

        #expect(throws: PluginLifecycleError.stateChanged("sample@demo")) {
            try service.apply(planID: planned.id, digest: planned.plan.digest)
        }
        #expect(invocations.isEmpty)
    }

    @Test
    func pluginLifecycleBlocksRiskyInstallUntilLocalAcknowledgement() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("skillset-plugin-risk-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let state = root.appendingPathComponent("state", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        let installPath = home.appendingPathComponent(
            ".claude/plugins/cache/demo/risky/1.0.0",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: installPath.appendingPathComponent(".claude-plugin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: installPath.appendingPathComponent("hooks", isDirectory: true),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(
            withJSONObject: [
                "name": "risky",
                "version": "1.0.0",
                "hooks": "./hooks/hooks.json"
            ],
            options: [.sortedKeys]
        ).write(to: installPath.appendingPathComponent(".claude-plugin/plugin.json"))

        let planStore = DeploymentPlanStore(rootURL: state.appendingPathComponent("plans", isDirectory: true))
        let manager = PluginLifecycleManager(
            planStore: planStore,
            stagingRoot: state.appendingPathComponent("staging", isDirectory: true),
            operationsRoot: state.appendingPathComponent("operations", isDirectory: true),
            homeDirectory: home,
            executableOverrides: [.claudeCode: URL(fileURLWithPath: "/usr/bin/true")],
            commandRunner: { _, _, _, _ in
                Issue.record("风险确认前或生成计划阶段不能执行宿主命令")
                return PluginCommandOutput(exitCode: 1, stdout: "", stderr: "")
            }
        )
        let service = try SkillSetService(
            paths: SkillSetRuntimePaths(
                applicationSupportRoot: state,
                repositoryRoot: URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
            ),
            planStore: planStore,
            pluginLifecycleManager: manager
        )

        #expect(throws: PluginLifecycleError.riskApprovalRequired("risky@demo", ["hooks"])) {
            try service.makePluginLifecyclePlan(
                projectID: nil,
                request: PluginLifecycleRequest(
                    host: .claudeCode,
                    pluginID: "risky@demo",
                    action: .install,
                    scope: .user
                )
            )
        }
        #expect(try planStore.list().isEmpty)

        let planned = try service.makePluginLifecyclePlan(
            projectID: nil,
            request: PluginLifecycleRequest(
                host: .claudeCode,
                pluginID: "risky@demo",
                action: .install,
                scope: .user,
                acknowledgeExecutableComponents: true
            )
        )
        #expect(planned.plan.metadata?["pluginRiskAcknowledged"] == "true")
        #expect(planned.plan.metadata?["pluginArguments"]?.contains("--yes") == false)
        #expect(planned.plan.metadata?["pluginArguments"]?.contains("-y") == false)
    }

    @Test
    func pluginLifecycleBindsMultipleCacheVersionsByManifestDigest() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("skillset-plugin-versions-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let state = root.appendingPathComponent("state", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        for version in ["1.0.0", "2.0.0"] {
            let installPath = home.appendingPathComponent(
                ".claude/plugins/cache/demo/sample/\(version)",
                isDirectory: true
            )
            try fileManager.createDirectory(
                at: installPath.appendingPathComponent(".claude-plugin", isDirectory: true),
                withIntermediateDirectories: true
            )
            try JSONSerialization.data(
                withJSONObject: ["name": "sample", "version": version],
                options: [.sortedKeys]
            ).write(to: installPath.appendingPathComponent(".claude-plugin/plugin.json"))
        }

        let snapshot = PluginInventoryManager(projectRoot: nil, homeDirectory: home).inspect()
        let records = snapshot.records.filter {
            $0.host == .claudeCode && $0.pluginID == "sample@demo"
        }
        #expect(records.count == 2)
        #expect(Set(records.map(\.manifestDigest)).count == 2)
        let selected = try #require(records.first { $0.version == "1.0.0" })

        var invocations: [[String]] = []
        let planStore = DeploymentPlanStore(rootURL: state.appendingPathComponent("plans", isDirectory: true))
        let manager = PluginLifecycleManager(
            planStore: planStore,
            stagingRoot: state.appendingPathComponent("staging", isDirectory: true),
            operationsRoot: state.appendingPathComponent("operations", isDirectory: true),
            homeDirectory: home,
            executableOverrides: [.claudeCode: URL(fileURLWithPath: "/usr/bin/true")],
            commandRunner: { _, arguments, _, _ in
                invocations.append(arguments)
                let index: [String: Any] = [
                    "version": 2,
                    "plugins": [
                        "sample@demo": [[
                            "scope": "user",
                            "installPath": selected.sourcePath,
                            "version": "1.0.0",
                            "gitCommitSha": String(repeating: "c", count: 40)
                        ]]
                    ]
                ]
                let indexURL = home.appendingPathComponent(".claude/plugins/installed_plugins.json")
                try? fileManager.createDirectory(
                    at: indexURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? JSONSerialization.data(withJSONObject: index, options: [.sortedKeys])
                    .write(to: indexURL)
                try? self.writeClaudeEnabledSettings(home: home, enabled: true)
                return PluginCommandOutput(exitCode: 0, stdout: "", stderr: "")
            }
        )
        let service = try SkillSetService(
            paths: SkillSetRuntimePaths(
                applicationSupportRoot: state,
                repositoryRoot: URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
            ),
            planStore: planStore,
            pluginLifecycleManager: manager
        )

        #expect(throws: PluginLifecycleError.versionAmbiguous("sample@demo")) {
            try service.makePluginLifecyclePlan(
                projectID: nil,
                request: PluginLifecycleRequest(
                    host: .claudeCode,
                    pluginID: "sample@demo",
                    action: .install,
                    scope: .user,
                    acknowledgeExecutableComponents: true
                )
            )
        }

        let missingDigest = String(repeating: "0", count: 64)
        #expect(throws: PluginLifecycleError.versionNotFound("sample@demo", missingDigest)) {
            try service.makePluginLifecyclePlan(
                projectID: nil,
                request: PluginLifecycleRequest(
                    host: .claudeCode,
                    pluginID: "sample@demo",
                    action: .install,
                    scope: .user,
                    expectedManifestDigest: missingDigest,
                    acknowledgeExecutableComponents: true
                )
            )
        }

        let planned = try service.makePluginLifecyclePlan(
            projectID: nil,
            request: PluginLifecycleRequest(
                host: .claudeCode,
                pluginID: "sample@demo",
                action: .install,
                scope: .user,
                expectedManifestDigest: selected.manifestDigest,
                acknowledgeExecutableComponents: true
            )
        )
        #expect(
            planned.plan.metadata?["pluginExpectedManifestDigest"]
                == selected.manifestDigest
        )

        _ = try service.approve(planID: planned.id, digest: planned.plan.digest)
        let applied = try service.apply(planID: planned.id, digest: planned.plan.digest)
        #expect(invocations == [[
            "plugin",
            "install",
            "sample@demo",
            "--scope",
            "user",
            "--json"
        ]])
        let operation = try service.pluginOperation(applied.operationID)
        #expect(operation.state == "applied")
        #expect(operation.before.manifestDigest == selected.manifestDigest)
        #expect(operation.after?.manifestDigest == selected.manifestDigest)
    }

    @Test
    func pluginLifecycleUsesCodexRemoveAndRejectsUnsupportedEnable() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("skillset-codex-plugin-lifecycle-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let state = root.appendingPathComponent("state", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        let installPath = home.appendingPathComponent(
            ".codex/plugins/cache/demo/sample/1.0.0",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: installPath.appendingPathComponent(".codex-plugin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: ["name": "sample", "version": "1.0.0"])
            .write(to: installPath.appendingPathComponent(".codex-plugin/plugin.json"))
        try """
        [plugins."sample@demo"]
        enabled = true
        """.write(
            to: home.appendingPathComponent(".codex/config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let planStore = DeploymentPlanStore(rootURL: state.appendingPathComponent("plans", isDirectory: true))
        let manager = PluginLifecycleManager(
            planStore: planStore,
            stagingRoot: state.appendingPathComponent("staging", isDirectory: true),
            operationsRoot: state.appendingPathComponent("operations", isDirectory: true),
            homeDirectory: home,
            executableOverrides: [.codex: URL(fileURLWithPath: "/usr/bin/true")],
            commandRunner: { _, _, _, _ in
                Issue.record("生成计划不应执行宿主命令")
                return PluginCommandOutput(exitCode: 1, stdout: "", stderr: "")
            }
        )
        let service = try SkillSetService(
            paths: SkillSetRuntimePaths(
                applicationSupportRoot: state,
                repositoryRoot: URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
            ),
            planStore: planStore,
            pluginLifecycleManager: manager
        )
        let planned = try service.makePluginLifecyclePlan(
            projectID: nil,
            request: PluginLifecycleRequest(
                host: .codex,
                pluginID: "sample@demo",
                action: .uninstall
            )
        )
        let arguments = planned.plan.metadata?["pluginArguments"] ?? ""
        #expect(arguments.contains(#""plugin""#))
        #expect(arguments.contains(#""remove""#))
        #expect(arguments.contains(#""sample@demo""#))
        #expect(!arguments.contains(#""enable""#))

        #expect(throws: PluginLifecycleError.actionUnsupported(
            "Codex 不提供公开的 启用 命令"
        )) {
            try service.makePluginLifecyclePlan(
                projectID: nil,
                request: PluginLifecycleRequest(
                    host: .codex,
                    pluginID: "sample@demo",
                    action: .enable
                )
            )
        }
    }

    private func installPluginFixture(
        home: URL,
        enabled: Bool,
        manifest: [String: Any]
    ) throws {
        let fileManager = FileManager.default
        let installPath = home.appendingPathComponent(
            ".claude/plugins/cache/demo/sample/1.2.0",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: installPath.appendingPathComponent(".claude-plugin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: installPath.appendingPathComponent(".claude-plugin/plugin.json"))
        let index: [String: Any] = [
            "version": 2,
            "plugins": [
                "sample@demo": [[
                    "scope": "user",
                    "installPath": installPath.path,
                    "version": manifest["version"] ?? "1.2.0",
                    "gitCommitSha": String(repeating: "b", count: 40)
                ]]
            ]
        ]
        try JSONSerialization.data(withJSONObject: index, options: [.sortedKeys])
            .write(to: home.appendingPathComponent(".claude/plugins/installed_plugins.json"))
        try writeClaudeEnabledSettings(home: home, enabled: enabled)
    }

    private func writeClaudeEnabledSettings(home: URL, enabled: Bool) throws {
        let fileManager = FileManager.default
        let url = home.appendingPathComponent(".claude/settings.json")
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(
            withJSONObject: ["enabledPlugins": ["sample@demo": enabled]],
            options: [.sortedKeys]
        ).write(to: url, options: .atomic)
    }
}

struct DeploymentFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("skillset-deploy-\(UUID().uuidString)", isDirectory: true)
    let operationID = UUID()
    let repository: URL
    let project: URL
    let staging: URL
    let operations: URL
    let catalog: CatalogDocument
    var stateStore: ProjectLockStore { ProjectLockStore(projectRoot: project, stateRoot: root) }

    init() throws {
        repository = root.appendingPathComponent("repo", isDirectory: true)
        project = root.appendingPathComponent("project", isDirectory: true)
        staging = root.appendingPathComponent("staging", isDirectory: true)
        operations = root.appendingPathComponent("operations", isDirectory: true)
        let skill = repository.appendingPathComponent("skills/demo", isDirectory: true)
        for directory in [repository, skill, project, staging, operations] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try "# Demo\n".write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: skill.appendingPathComponent("scripts", isDirectory: true),
            withIntermediateDirectories: true
        )
        let script = skill.appendingPathComponent("scripts/run.sh")
        try "#!/bin/sh\nexit 0\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let skillData = try Data(contentsOf: skill.appendingPathComponent("SKILL.md"))
        let scriptData = try Data(contentsOf: script)
        let manifestBytes = try JSONSerialization.data(
            withJSONObject: [
                ["path": "SKILL.md", "sha256": SkillAssetCopier.sha256(skillData), "executable": false] as [String: Any],
                ["path": "scripts/run.sh", "sha256": SkillAssetCopier.sha256(scriptData), "executable": true] as [String: Any]
            ],
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let expectedHash = SkillAssetCopier.sha256(manifestBytes)
        let entry = SkillEntry(
            id: "workspace/demo",
            slug: "demo",
            declaredName: "demo",
            description: "fixture",
            declaredVersion: nil,
            metadataReview: "reviewed",
            sourceId: "workspace",
            path: "skills/demo",
            contentHash: expectedHash,
            fileCount: 2,
            bytes: skillData.count + scriptData.count,
            integrity: "snapshotted",
            issues: [],
            licenseReview: "required",
            excludedPaths: []
        )
        catalog = CatalogDocument(schemaVersion: 1, hashAlgorithm: "test", entries: [entry])
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    func makePlan(
        skillIDs: [String] = ["workspace/demo"],
        instructionIDs: [String] = ["base"],
        agents: [String] = ["codex"],
        catalogOverride: CatalogDocument? = nil
    ) throws -> DeploymentPlan {
        try DeploymentPlanner(
            catalog: catalogOverride ?? catalog,
            repositoryRoot: repository,
            stagingRoot: staging,
            operationsRoot: operations
        ).makePlan(
            projectPath: project,
            request: DeploymentRequest(skillIDs: skillIDs, instructionIDs: instructionIDs, agents: agents),
            fragments: ["base": "只做受管内容"]
        )
    }
}
