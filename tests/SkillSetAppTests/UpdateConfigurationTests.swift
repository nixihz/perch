import Foundation
import XCTest
@testable import SkillSetApp

final class UpdateConfigurationTests: XCTestCase {
    // RFC 8032 测试向量，仅用于验证配置解析。
    private let publicKey = "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="

    func testValidConfigurationPreservesFeedAndDecodesVerificationKey() throws {
        let configuration = try XCTUnwrap(UpdateConfiguration(info: [
            "SUFeedURL": "https://updates.example.com/perch/appcast.xml",
            "SUPublicEDKey": publicKey
        ]))
        XCTAssertEqual(configuration.feedURL.host, "updates.example.com")
        XCTAssertEqual(configuration.feedURL.path, "/perch/appcast.xml")
        XCTAssertEqual(configuration.publicKey.map { String(format: "%02x", $0) }.joined(),
                       "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
    }

    func testMissingPartialAndUnsafeConfigurationCannotEnableUpdater() {
        for info: [String: Any] in [[:], ["SUFeedURL": "https://example.com/appcast.xml"], ["SUPublicEDKey": publicKey]] {
            XCTAssertNil(UpdateConfiguration(info: info))
        }
        for feed in ["", "$(PERCH_SPARKLE_FEED_URL)", "http://example.com/appcast.xml",
                     "file:///tmp/appcast.xml", "https:///", "https://user:secret@example.com/appcast.xml",
                     "https://example.com/appcast.xml#fragment", "https://example.com/app cast.xml"] {
            XCTAssertNil(UpdateConfiguration(info: ["SUFeedURL": feed, "SUPublicEDKey": publicKey]), feed)
        }
        for key in ["", "$(PERCH_SPARKLE_PUBLIC_KEY)", "not-base64", "YWJj", publicKey + "!"] {
            XCTAssertNil(UpdateConfiguration(info: ["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": key]))
        }
    }

    @MainActor
    func testUnconfiguredBuildShowsVersionAndKeepsUpdateActionsUnavailable() {
        let updates = AppUpdates(info: ["CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "42"])
        XCTAssertEqual(updates.version, "1.2.3 (42)")
        XCTAssertEqual(updates.unavailableReason, "此版本尚未开启在线更新。")
        updates.checkForUpdates()
        updates.setAutomaticallyChecksForUpdates(true)
        XCTAssertFalse(updates.isReady)
        XCTAssertFalse(updates.canCheckForUpdates)
        XCTAssertFalse(updates.automaticallyChecksForUpdates)
    }
}
