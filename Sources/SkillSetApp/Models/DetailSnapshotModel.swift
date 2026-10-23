import Foundation
import Observation

/// 同一条目刷新失败时保留上次结果；切换条目后不沿用旧条目的详情。
@MainActor
@Observable
final class DetailSnapshotModel<Key: Equatable, Snapshot> {
    private(set) var key: Key?
    private(set) var snapshot: Snapshot?
    private(set) var error: String?
    private(set) var isLoading = false
    private var requestID = UUID()

    func load(
        for key: Key,
        errorMessage: (Error) -> String = UserFacingText.error,
        operation: @MainActor () async throws -> Snapshot
    ) async {
        guard !Task.isCancelled else { return }
        let request = UUID()
        requestID = request
        if self.key != key {
            self.key = key
            snapshot = nil
        }
        error = nil
        isLoading = true
        defer {
            if requestID == request { isLoading = false }
        }
        do {
            let result = try await operation()
            guard requestID == request, !Task.isCancelled else { return }
            snapshot = result
        } catch is CancellationError {
            return
        } catch {
            guard requestID == request, !Task.isCancelled else { return }
            self.error = errorMessage(error)
        }
    }

    func reset() {
        requestID = UUID()
        key = nil
        snapshot = nil
        error = nil
        isLoading = false
    }
}
