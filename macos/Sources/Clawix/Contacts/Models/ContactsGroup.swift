import Foundation
import SwiftUI

struct ContactsGroup: Identifiable, Equatable, Hashable {
    let id: String
    var accountID: String
    var title: String
    var color: Color
    var kind: Kind
    var smartRule: SmartGroupRule?

    enum Kind: String, Equatable, Hashable {
        case normal
        case smart
        case system
    }

    static func == (lhs: ContactsGroup, rhs: ContactsGroup) -> Bool {
        lhs.id == rhs.id
            && lhs.accountID == rhs.accountID
            && lhs.title == rhs.title
            && lhs.kind == rhs.kind
            && lhs.smartRule == rhs.smartRule
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct ContactsAccount: Identifiable, Equatable, Hashable {
    let id: String
    var title: String

    static func == (lhs: ContactsAccount, rhs: ContactsAccount) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title
    }
}
