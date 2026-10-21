import AppKit
import SwiftUI
import XCTest
@testable import SkillSetApp

@MainActor
final class ThemeContrastTests: XCTestCase {
    func testNativeAccentAssetHasDistinctReadableAppearanceVariants() throws {
        let light = try XCTUnwrap(NSAppearance(named: .aqua))
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))
        XCTAssertGreaterThan(
            try luminance(AppColor.accent, appearance: dark),
            try luminance(AppColor.accent, appearance: light)
        )
        for appearance in [light, dark] {
            XCTAssertGreaterThanOrEqual(
                try contrast(AppColor.accent, AppColor.surface, appearance: appearance),
                3,
                "原生强调色资源必须能加载，并与控件所在表面保持区分"
            )
        }
    }

    func testContentAndAccentTextRemainReadableOnBothCardSurfaces() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            XCTAssertGreaterThanOrEqual(
                try contrast(AppColor.onSelection, AppColor.selection, appearance: appearance), 4.5,
                "侧栏选中后的标题与副标题仍须可读"
            )
            for background in [AppColor.surface, AppColor.accentSoft] {
                for foreground in [AppColor.ink, AppColor.accentText, AppColor.positive] {
                    let ratio = try contrast(foreground, background, appearance: appearance)
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name.rawValue) 卡片文字对比度不足")
                }
            }
        }
    }

    func testDarkEmphasisCardDoesNotBecomeALightPanel() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let surface = try luminance(AppColor.surface, appearance: appearance)
        let emphasis = try luminance(AppColor.accentSoft, appearance: appearance)
        XCTAssertLessThan(emphasis, 0.08, "深色详情卡不应使用浅色底")
        XCTAssertLessThan(abs(emphasis - surface), 0.03, "强调应来自色相而非大面积亮度跳变")
    }

    private func contrast(_ foreground: Color, _ background: Color, appearance: NSAppearance) throws -> Double {
        let first = try luminance(foreground, appearance: appearance)
        let second = try luminance(background, appearance: appearance)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private func luminance(_ color: Color, appearance: NSAppearance) throws -> Double {
        var components: [CGFloat]?
        appearance.performAsCurrentDrawingAppearance {
            if let rgb = NSColor(color).usingColorSpace(.sRGB) {
                components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
            }
        }
        let rgb = try XCTUnwrap(components)
        func linear(_ value: CGFloat) -> Double {
            let value = Double(value)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb[0])
            + 0.7152 * linear(rgb[1])
            + 0.0722 * linear(rgb[2])
    }
}
