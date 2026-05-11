import Foundation

struct SmartGroupRule: Equatable, Hashable {
    var matchAll: Bool
    var conditions: [Condition]

    struct Condition: Identifiable, Equatable, Hashable {
        let id: String
        var field: Field
        var op: Op
        var value: String
    }

    enum Field: String, CaseIterable, Identifiable, Hashable {
        case givenName, familyName, organization, jobTitle
        case phone, email, address
        case groupTitle, accountTitle, note, birthday

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .givenName:    return "Given name"
            case .familyName:   return "Family name"
            case .organization: return "Organization"
            case .jobTitle:     return "Job title"
            case .phone:        return "Phone"
            case .email:        return "Email"
            case .address:      return "Address"
            case .groupTitle:   return "Group"
            case .accountTitle: return "Account"
            case .note:         return "Note"
            case .birthday:     return "Birthday"
            }
        }
    }

    enum Op: String, CaseIterable, Identifiable, Hashable {
        case contains, doesNotContain, beginsWith, endsWith, equals, notEqual, isSet, isNotSet

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .contains:       return "contains"
            case .doesNotContain: return "does not contain"
            case .beginsWith:     return "begins with"
            case .endsWith:       return "ends with"
            case .equals:         return "is"
            case .notEqual:       return "is not"
            case .isSet:          return "is set"
            case .isNotSet:       return "is not set"
            }
        }

        var needsValue: Bool {
            switch self {
            case .isSet, .isNotSet: return false
            default: return true
            }
        }
    }

    func evaluate(_ contact: Contact,
                  groupsByID: [String: ContactsGroup],
                  accountsByID: [String: ContactsAccount]) -> Bool {
        let results = conditions.map { match(condition: $0, against: contact,
                                             groupsByID: groupsByID,
                                             accountsByID: accountsByID) }
        if results.isEmpty { return false }
        return matchAll ? results.allSatisfy { $0 } : results.contains(true)
    }

    private func match(condition: Condition, against contact: Contact,
                       groupsByID: [String: ContactsGroup],
                       accountsByID: [String: ContactsAccount]) -> Bool {
        let candidates = fieldValues(for: condition.field, contact: contact,
                                     groupsByID: groupsByID, accountsByID: accountsByID)
        switch condition.op {
        case .isSet:    return candidates.contains { !$0.isEmpty }
        case .isNotSet: return candidates.allSatisfy { $0.isEmpty }
        default:
            let needle = condition.value.lowercased()
            return candidates.contains { haystack in
                let h = haystack.lowercased()
                switch condition.op {
                case .contains:       return h.contains(needle)
                case .doesNotContain: return !h.contains(needle) && !h.isEmpty
                case .beginsWith:     return h.hasPrefix(needle)
                case .endsWith:       return h.hasSuffix(needle)
                case .equals:         return h == needle
                case .notEqual:       return h != needle && !h.isEmpty
                case .isSet, .isNotSet: return false
                }
            }
        }
    }

    private func fieldValues(for field: Field, contact: Contact,
                             groupsByID: [String: ContactsGroup],
                             accountsByID: [String: ContactsAccount]) -> [String] {
        switch field {
        case .givenName:    return [contact.givenName]
        case .familyName:   return [contact.familyName]
        case .organization: return [contact.organization ?? ""]
        case .jobTitle:     return [contact.jobTitle ?? ""]
        case .phone:        return contact.fields.filter { $0.kind == .phone }.map { $0.value }
        case .email:        return contact.fields.filter { $0.kind == .email }.map { $0.value }
        case .address:      return contact.fields.filter { $0.kind == .address }.map { $0.value }
        case .groupTitle:   return contact.groupIDs.compactMap { groupsByID[$0]?.title }
        case .accountTitle: return [accountsByID[contact.accountID]?.title ?? ""]
        case .note:         return [contact.note ?? ""]
        case .birthday:
            if let d = contact.birthday {
                return [ISO8601DateFormatter().string(from: d)]
            }
            return [""]
        }
    }
}
