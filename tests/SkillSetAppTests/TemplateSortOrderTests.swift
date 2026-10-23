import XCTest
import SkillSetCore
@testable import SkillSetApp

final class TemplateSortOrderTests: XCTestCase {
    func testNaturalTitleOrderAndDefaultOrderKeepRecordsIntact() {
        let templates = [
            TemplateRecord(id: "z", title: "规则 10", body: "十"),
            TemplateRecord(id: "b", title: "规则 2", body: "二"),
            TemplateRecord(id: "a", title: "规则 2", body: "同名")
        ]
        XCTAssertEqual(TemplateSortOrder.original.sorted(templates).map(\.id), ["z", "b", "a"])
        XCTAssertEqual(TemplateSortOrder.titleAscending.sorted(templates).map(\.id), ["a", "b", "z"])
        XCTAssertEqual(TemplateSortOrder.titleDescending.sorted(templates).map(\.id), ["z", "a", "b"])
        XCTAssertEqual(Set(TemplateSortOrder.titleAscending.sorted(templates)), Set(templates))
        XCTAssertTrue(TemplateSortOrder.titleAscending.sorted([]).isEmpty)
    }

    func testSortUsesDisplayedTitleAndSupportsFilteredSubset() {
        let templates = [
            TemplateRecord(id: "one", title: "Alpha", body: "a"),
            TemplateRecord(id: "two", title: "Beta", body: "b"),
            TemplateRecord(id: "three", title: "Gamma", body: "c")
        ]
        let displayNames = ["one": "Zebra", "two": "Apple", "three": "Middle"]
        XCTAssertEqual(TemplateSortOrder.titleAscending.sorted(templates) { displayNames[$0.id]! }.map(\.id),
                       ["two", "three", "one"])
        let filtered = templates.filter { $0.id != "three" }
        XCTAssertEqual(TemplateSortOrder.titleDescending.sorted(filtered).map(\.id), ["two", "one"])
        XCTAssertEqual(templates.first?.body, "a", "排序不能修改规则正文或原始顺序")
    }
}
