import Foundation
import XCTest
@testable import SkillSetApp

@MainActor
final class DetailSnapshotModelTests: XCTestCase {
    func testFailedRefreshKeepsPublishedContentAndRetryReadsRecoveredFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try "first snapshot".write(to: root, atomically: true, encoding: .utf8)
        let model = DetailSnapshotModel<String, String>()
        await model.load(for: "source") { try String(contentsOf: root, encoding: .utf8) }
        XCTAssertEqual(model.snapshot, "first snapshot")

        try FileManager.default.removeItem(at: root)
        await model.load(for: "source") { try String(contentsOf: root, encoding: .utf8) }
        XCTAssertEqual(model.snapshot, "first snapshot", "读取失败保留同一条目的上次结果")
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.isLoading)

        try "recovered snapshot".write(to: root, atomically: true, encoding: .utf8)
        await model.load(for: "source") { try String(contentsOf: root, encoding: .utf8) }
        XCTAssertEqual(model.snapshot, "recovered snapshot")
        XCTAssertNil(model.error)
        XCTAssertFalse(model.isLoading)
    }

    func testSwitchingItemsClearsOldContentAndRejectsLateResult() async {
        let model = DetailSnapshotModel<String, String>()
        await model.load(for: "first") { "first snapshot" }
        let gate = ReadGate()
        let stale = Task { await model.load(for: "first") { await gate.read() } }
        await gate.waitUntilStarted()
        XCTAssertTrue(model.isLoading)
        XCTAssertEqual(model.snapshot, "first snapshot")

        await model.load(for: "second") {
            XCTAssertNil(model.snapshot, "切换条目后不得展示前一条目的详情")
            return "second snapshot"
        }
        gate.finish("late first snapshot")
        await stale.value
        XCTAssertEqual(model.key, "second")
        XCTAssertEqual(model.snapshot, "second snapshot")
        XCTAssertFalse(model.isLoading)
    }

    func testCancellationFinishesLoadingWithoutPublishingAndAllowsRetry() async {
        let model = DetailSnapshotModel<String, String>()
        await model.load(for: "item") { "saved snapshot" }
        let gate = ReadGate()
        let cancelled = Task { await model.load(for: "item") { await gate.read() } }
        await gate.waitUntilStarted()
        cancelled.cancel()
        gate.finish("cancelled snapshot")
        await cancelled.value
        XCTAssertEqual(model.snapshot, "saved snapshot")
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.error)
        await model.load(for: "item") { "new snapshot" }
        XCTAssertEqual(model.snapshot, "new snapshot")
    }
}

@MainActor
private final class ReadGate {
    private var continuation: CheckedContinuation<String, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func read() async -> String {
        await withCheckedContinuation {
            continuation = $0
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish(_ value: String) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
