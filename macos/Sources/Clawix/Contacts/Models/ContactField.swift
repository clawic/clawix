import Foundation

struct ContactField: Identifiable, Equatable {
    let id: String
    var kind: Kind
    var label: String
    var value: String

    enum Kind: String, CaseIterable, Identifiable {
        case phone, email, address, url, social, birthday, note, related

        var id: String { rawValue }

        var defaultLabel: String {
            switch self {
            case .phone:    return "mobile"
            case .email:    return "home"
            case .address:  return "home"
            case .url:      return "homepage"
            case .social:   return "username"
            case .birthday: return "birthday"
            case .note:     return "note"
            case .related:  return "related"
            }
        }

        var displayName: String {
            switch self {
            case .phone:    return "Phone"
            case .email:    return "Email"
            case .address:  return "Address"
            case .url:      return "URL"
            case .social:   return "Social"
            case .birthday: return "Birthday"
            case .note:     return "Note"
            case .related:  return "Related"
            }
        }

        static let availableLabels: [Kind: [String]] = [
            .phone:   ["mobile", "home", "work", "iPhone", "main", "other"],
            .email:   ["home", "work", "school", "other"],
            .address: ["home", "work", "other"],
            .url:     ["homepage", "home", "work", "blog", "other"],
            .social:  ["Twitter", "LinkedIn", "Instagram", "GitHub", "other"],
            .birthday: ["birthday"],
            .note:    ["note"],
            .related: ["mother", "father", "partner", "child", "friend", "assistant", "other"]
        ]
    }
}
