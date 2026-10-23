import Foundation
import Observation
import SkillSetCore

@MainActor
@Observable
final class InstalledSkillScanModel {
    private(set) var items: [InstalledSkillObservation] = []
    var selected: Set<String> = []
    private(set) var error: String?
    private(set) var scanning = false

    func scan(paths: SkillSetRuntimePaths, locations: GlobalConfigurationLocations, roots: [URL]) async {
        guard !scanning else { return }
        scanning = true
        error = nil
        defer { scanning = false }
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try SkillSetService(paths: paths, globalLocations: locations).scanInstalledSkills(additionalRoots: roots)
            }.value
            items = result
            selected.formIntersection(result.filter(\.canImport).map(\.id))
        } catch {
            // 临时读取失败不能抹掉上次结果；只有成功重扫才重新核对勾选项。
            self.error = UserFacingText.error(error)
        }
    }
}
