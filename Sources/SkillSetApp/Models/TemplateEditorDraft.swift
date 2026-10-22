import Foundation
import SkillSetCore

struct TemplateEditorDraft: Identifiable, Equatable {
    let id: String
    let isEditing: Bool
    var title: String
    var purpose: String
    var body: String

    @MainActor
    init(template: TemplateRecord? = nil) {
        id = template?.id ?? UUID().uuidString.lowercased()
        isEditing = template != nil
        title = template.map { UserFacingText.templateTitle($0) } ?? ""
        purpose = template.map { UserFacingText.templatePurpose($0) } ?? ""
        body = template?.body ?? ""
    }

    var record: TemplateRecord { TemplateRecord(id: id, title: title, body: body, purpose: purpose, isLocal: true) }
}
