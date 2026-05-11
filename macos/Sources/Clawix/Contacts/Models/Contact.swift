import Foundation
import SwiftUI

struct Contact: Identifiable, Equatable {
    let id: String
    var givenName: String
    var familyName: String
    var organization: String?
    var jobTitle: String?
    var photoData: Data?
    var fields: [ContactField]
    var groupIDs: Set<String>
    var accountID: String
    var isFavorite: Bool
    var dateAdded: Date
    var note: String?

    var fullName: String {
        let parts = [givenName, familyName].filter { !$0.isEmpty }
        if parts.isEmpty { return organization ?? "No Name" }
        return parts.joined(separator: " ")
    }

    var initials: String {
        let first = givenName.first.map(String.init) ?? ""
        let last = familyName.first.map(String.init) ?? ""
        let combined = (first + last).uppercased()
        if !combined.isEmpty { return combined }
        if let org = organization, let c = org.first { return String(c).uppercased() }
        return "?"
    }

    var primaryPhone: String? {
        fields.first(where: { $0.kind == .phone })?.value
    }

    var primaryEmail: String? {
        fields.first(where: { $0.kind == .email })?.value
    }

    var birthday: Date? {
        for f in fields where f.kind == .birthday {
            if let d = ISO8601DateFormatter().date(from: f.value) { return d }
        }
        return nil
    }

    static func == (lhs: Contact, rhs: Contact) -> Bool {
        lhs.id == rhs.id
            && lhs.givenName == rhs.givenName
            && lhs.familyName == rhs.familyName
            && lhs.organization == rhs.organization
            && lhs.jobTitle == rhs.jobTitle
            && lhs.fields == rhs.fields
            && lhs.groupIDs == rhs.groupIDs
            && lhs.accountID == rhs.accountID
            && lhs.isFavorite == rhs.isFavorite
            && lhs.dateAdded == rhs.dateAdded
            && lhs.note == rhs.note
    }
}
