import Foundation
import SkillSetCore

enum TemplateUseTarget: Hashable {
    case project(String)
    case global(MCPHost)
}

struct TemplateUseRequest: Identifiable {
    let template: TemplateRecord
    var id: String { template.id }
}

struct TemplateReference: Identifiable {
    let id: String
    let name: String
    let inDraft: Bool
    let isApplied: Bool
    let needsUpdate: Bool
    let target: TemplateUseTarget?
    let presetID: String?
}

struct TemplateUsePreview: Equatable {
    let paths: [String]
    let instructionIDs: [String]
    let body: String
    let skillCount: Int
    let agents: [String]
    let projectDraft: ProjectDraft?
    let globalDraft: GlobalConfigurationDraft?
}

extension AppModel {
    /// 使用位置读取持久化引用；盘点失败时报告未知，不把它显示为未使用。
    func templateReferences(_ id: String) throws -> [TemplateReference] {
        let paths = runtimePaths
        let drafts = ProjectDraftStore(rootURL: paths.applicationSupportRoot)
        var references: [TemplateReference] = []
        for project in try ProjectStore(rootURL: paths.applicationSupportRoot).list() {
            let draft = try drafts.load(projectID: project.id)
            let lockStore = ProjectLockStore(projectRoot: URL(fileURLWithPath: project.canonicalPath),
                                             stateRoot: paths.applicationSupportRoot)
            let manifest = try lockStore.loadManifest()
            let lock = try lockStore.loadLock()
            let currentBody = snapshot.templates.first { $0.id == id }?.body
            let writtenHash = lock?.instructions.first { $0.id == id }?.sha256
            let needsUpdate = currentBody.map { SkillAssetCopier.sha256(Data($0.utf8)) != writtenHash } ?? true
            let inDraft = draft?.instructionIDs.contains(id) == true
            let applied = manifest?.instructions.contains(id) == true
            if inDraft || applied {
                references.append(TemplateReference(id: project.id.uuidString, name: project.name,
                    inDraft: inDraft, isApplied: applied, needsUpdate: applied && needsUpdate, target: .project(project.id.uuidString), presetID: nil))
            }
        }
        let global = GlobalConfigurationManager(paths: paths, locations: globalConfiguration.locations)
        for host in MCPHost.allCases {
            let inDraft = try global.draft(host: host).instructionIDs.contains(id)
            let selection = try global.appliedSelection(host: host)
            let applied = selection.instructionIDs.contains(id)
            let expectedBodies = selection.instructionIDs.compactMap { selectedID in
                snapshot.templates.first { $0.id == selectedID }?.body
            }
            let rulesURL = globalConfiguration.locations.rulesURL(host)
            let text = FileManager.default.fileExists(atPath: rulesURL.path) ? try String(contentsOf: rulesURL, encoding: .utf8) : ""
            let actualBody = try ManagedBlocks.extract(original: text, id: "global-rules")
            let expectedBody = expectedBodies.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let needsUpdate = actualBody != expectedBody || expectedBodies.count != selection.instructionIDs.count
            if inDraft || applied {
                references.append(TemplateReference(id: "global-" + host.rawValue, name: host.displayName,
                    inDraft: inDraft, isApplied: applied, needsUpdate: applied && needsUpdate, target: .global(host), presetID: nil))
            }
        }
        for preset in try PresetStore(rootURL: paths.applicationSupportRoot).list(merging: snapshot.presets)
            where preset.instructionFragments.contains(id) {
            references.append(TemplateReference(id: "preset-" + preset.id, name: preset.name,
                inDraft: false, isApplied: false, needsUpdate: false, target: nil, presetID: preset.id))
        }
        return references
    }

    func showTemplateReference(_ reference: TemplateReference) {
        if let presetID = reference.presetID {
            selectedPresetID = presetID
            section = .presets
        } else if let target = reference.target {
            switch target {
            case .project(let id): selectedProjectID = id; section = .projects
            case .global(let host): globalConfiguration.selectHost(host); section = .globalConfiguration
            }
        }
    }

    func templateUsePreview(templateID: String, target: TemplateUseTarget) throws -> TemplateUsePreview {
        let service = try SkillSetService(paths: runtimePaths, globalLocations: globalConfiguration.locations)
        guard service.snapshot.templates.contains(where: { $0.id == templateID }) else { throw TemplateStoreError.notFound }
        let ids: [String]
        let paths: [String]
        let skills: Int
        let agents: [String]
        var projectDraft: ProjectDraft?
        var globalDraft: GlobalConfigurationDraft?
        switch target {
        case .project(let rawID):
            guard let id = UUID(uuidString: rawID) else { throw ProjectInstallationError.invalidTarget }
            let project = try ProjectStore(rootURL: runtimePaths.applicationSupportRoot).project(id: id)
            let current = try ProjectDraftStore(rootURL: runtimePaths.applicationSupportRoot).load(projectID: id)
            let manifest = try ProjectLockStore(projectRoot: URL(fileURLWithPath: project.canonicalPath),
                stateRoot: runtimePaths.applicationSupportRoot).loadManifest()
            var draft = current ?? ProjectDraft(projectID: id, skillIDs: manifest?.skills ?? [],
                instructionIDs: manifest?.instructions ?? [], agents: manifest?.agents ?? project.agents, updatedAt: .distantPast)
            draft.instructionIDs = Array(Set(draft.instructionIDs + [templateID])).sorted()
            agents = draft.agents
            ids = draft.instructionIDs
            skills = draft.skillIDs.count
            paths = try agents.map {
                guard let adapter = AgentDeploymentAdapter.target(for: $0, ruleBlockID: manifest?.ruleBlockID ?? "project-rules") else {
                    throw ProjectLockError.unsupportedAgent($0)
                }
                return URL(fileURLWithPath: project.canonicalPath).appendingPathComponent(adapter.instructionsFile).path
            }
            projectDraft = draft
        case .global(let host):
            var draft = try service.globalConfiguration.draft(host: host)
            draft.instructionIDs = Array(Set(draft.instructionIDs + [templateID])).sorted()
            globalDraft = draft
            ids = draft.instructionIDs
            skills = draft.skillIDs.count
            agents = [host.rawValue]
            paths = [globalConfiguration.locations.rulesURL(host).path]
        }
        guard !agents.isEmpty else { throw TemplateUsePreviewError.noHosts }
        let body = try ids.map { id in
            guard let template = service.snapshot.templates.first(where: { $0.id == id }) else {
                throw SkillSetServiceError.unknownInstruction(id)
            }
            return template.body
        }.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return TemplateUsePreview(paths: paths, instructionIDs: ids, body: body, skillCount: skills,
                                  agents: agents, projectDraft: projectDraft, globalDraft: globalDraft)
    }
}

enum TemplateUsePreviewError: Error { case noHosts }
