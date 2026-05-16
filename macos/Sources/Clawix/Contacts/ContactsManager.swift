import Foundation
import SwiftUI

protocol ContactsBackend: Sendable {
    var isReadOnly: Bool { get }
    func requestAccess() async -> ContactsAccessResult
    func loadAccounts() async -> [ContactsAccount]
    func loadGroups() async -> [ContactsGroup]
    func loadContacts() async -> [Contact]
    func save(_ contact: Contact) async -> Result<Contact, Error>
    func delete(_ contactID: String) async -> Result<Void, Error>
    func merge(_ contactIDs: [String]) async -> Result<Contact, Error>
    func saveGroup(_ group: ContactsGroup) async -> Result<ContactsGroup, Error>
    func deleteGroup(_ groupID: String) async -> Result<Void, Error>
    func toggleMembership(contactID: String, groupID: String, included: Bool) async -> Result<Void, Error>
}

enum ContactsAccessResult: Equatable {
    case granted
    case denied(String)
    case unavailable
}

enum ContactsSelection: Equatable {
    case allContacts
    case account(String)
    case group(String)
    case recentlyAdded
    case birthdays
    case favorites
}

enum ContactsSortKey: String, CaseIterable, Identifiable {
    case lastName, firstName, recent

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .lastName:  return "Last Name"
        case .firstName: return "First Name"
        case .recent:    return "Recently Added"
        }
    }
}

@MainActor
final class ContactsManager: ObservableObject {

    enum AccessState: Equatable {
        case unknown
        case requesting
        case granted
        case denied(String)
        case unavailable
    }

    @Published private(set) var access: AccessState = .unknown
    @Published private(set) var accounts: [ContactsAccount] = []
    @Published private(set) var groups: [ContactsGroup] = []
    @Published private(set) var contacts: [Contact] = []
    @Published var selection: ContactsSelection = .allContacts
    @Published var selectedContactID: String? = nil
    @Published var searchQuery: String = ""
    @Published var sortKey: ContactsSortKey = .lastName
    @Published var isEditing: Bool = false
    @Published var isCreating: Bool = false
    @Published var mergeCandidateIDs: Set<String> = []
    @Published var isMergeOpen: Bool = false
    @Published var editingSmartGroupID: String? = nil

    let backend: ContactsBackend

    init(backend: ContactsBackend? = nil) {
        self.backend = backend ?? ContactsManager.makeDefaultBackend()
    }

    private static func makeDefaultBackend() -> ContactsBackend {
        let env = ProcessInfo.processInfo.environment
        if env["CLAWIX_DISABLE_BACKEND"] == "1" || env["CLAWIX_DUMMY_MODE"] == "1" {
            return DummyContactsBackend()
        }
        return ContactsKitBackend()
    }

    var isReadOnly: Bool { backend.isReadOnly }

    func bootstrap() async {
        guard access == .unknown else { return }
        access = .requesting
        let result = await backend.requestAccess()
        switch result {
        case .granted:
            access = .granted
            await reload()
        case .denied(let reason):
            access = .denied(reason)
        case .unavailable:
            access = .unavailable
        }
    }

    func reload() async {
        async let a = backend.loadAccounts()
        async let g = backend.loadGroups()
        async let c = backend.loadContacts()
        let (loadedAccounts, loadedGroups, loadedContacts) = await (a, g, c)
        self.accounts = loadedAccounts
        self.groups = loadedGroups
        self.contacts = loadedContacts
        if selectedContactID == nil, let first = filteredContacts.first {
            selectedContactID = first.id
        }
    }

    var accountsByID: [String: ContactsAccount] {
        Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
    }

    var groupsByID: [String: ContactsGroup] {
        Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
    }

    var contactsByID: [String: Contact] {
        Dictionary(uniqueKeysWithValues: contacts.map { ($0.id, $0) })
    }

    var selectedContact: Contact? {
        guard let id = selectedContactID else { return nil }
        return contactsByID[id]
    }

    func selectionTitle() -> String {
        switch selection {
        case .allContacts:    return "All Contacts"
        case .account(let id): return accountsByID[id]?.title ?? "Account"
        case .group(let id):  return groupsByID[id]?.title ?? "Group"
        case .recentlyAdded:  return "Recently Added"
        case .birthdays:      return "Birthdays"
        case .favorites:      return "Favorites"
        }
    }

    var filteredContacts: [Contact] {
        let base: [Contact]
        switch selection {
        case .allContacts:
            base = contacts
        case .account(let accountID):
            base = contacts.filter { $0.accountID == accountID }
        case .group(let id):
            if let g = groupsByID[id], g.kind == .smart, let rule = g.smartRule {
                base = contacts.filter { rule.evaluate($0,
                                                      groupsByID: groupsByID,
                                                      accountsByID: accountsByID) }
            } else {
                base = contacts.filter { $0.groupIDs.contains(id) }
            }
        case .recentlyAdded:
            let cutoff = Date().addingTimeInterval(-30 * 86_400)
            base = contacts.filter { $0.dateAdded >= cutoff }
        case .birthdays:
            base = contacts.filter { $0.birthday != nil }
        case .favorites:
            base = contacts.filter { $0.isFavorite }
        }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = query.isEmpty ? base : base.filter { match($0, query: query) }
        return sort(filtered)
    }

    private func sort(_ items: [Contact]) -> [Contact] {
        switch sortKey {
        case .lastName:
            return items.sorted { lhs, rhs in
                let l = (lhs.familyName.isEmpty ? lhs.givenName : lhs.familyName)
                let r = (rhs.familyName.isEmpty ? rhs.givenName : rhs.familyName)
                return l.localizedCaseInsensitiveCompare(r) == .orderedAscending
            }
        case .firstName:
            return items.sorted { lhs, rhs in
                lhs.givenName.localizedCaseInsensitiveCompare(rhs.givenName) == .orderedAscending
            }
        case .recent:
            return items.sorted { $0.dateAdded > $1.dateAdded }
        }
    }

    private func match(_ c: Contact, query: String) -> Bool {
        if c.fullName.lowercased().contains(query) { return true }
        if let org = c.organization, org.lowercased().contains(query) { return true }
        if let job = c.jobTitle, job.lowercased().contains(query) { return true }
        for f in c.fields where f.value.lowercased().contains(query) { return true }
        return false
    }

    func sectionedContacts() -> [SectionedContacts] {
        let items = filteredContacts
        switch sortKey {
        case .recent:
            return [SectionedContacts(id: "all", header: nil, contacts: items)]
        case .firstName, .lastName:
            var groupsMap: [String: [Contact]] = [:]
            for c in items {
                let key = sectionKey(for: c)
                groupsMap[key, default: []].append(c)
            }
            return groupsMap.keys.sorted().map { key in
                SectionedContacts(id: key, header: key, contacts: groupsMap[key] ?? [])
            }
        }
    }

    private func sectionKey(for contact: Contact) -> String {
        let name: String
        switch sortKey {
        case .firstName: name = contact.givenName.isEmpty ? contact.familyName : contact.givenName
        default:         name = contact.familyName.isEmpty ? contact.givenName : contact.familyName
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "#" }
        if first.isLetter { return String(first).uppercased() }
        return "#"
    }

    func selectContact(_ id: String?) {
        selectedContactID = id
        isEditing = false
    }

    func startEdit() {
        guard !isReadOnly, selectedContactID != nil else { return }
        withAnimation(ContactsTokens.Motion.editToggle) { isEditing = true }
    }

    func cancelEdit() {
        withAnimation(ContactsTokens.Motion.editToggle) { isEditing = false }
    }

    func startCreate() {
        guard !isReadOnly else { return }
        isCreating = true
    }

    func endCreate() { isCreating = false }

    func newContactDraft() -> Contact {
        Contact(
            id: "draft-\(UUID().uuidString)",
            givenName: "",
            familyName: "",
            organization: nil,
            jobTitle: nil,
            photoData: nil,
            fields: [
                ContactField(id: UUID().uuidString, kind: .phone, label: "mobile", value: ""),
                ContactField(id: UUID().uuidString, kind: .email, label: "home", value: "")
            ],
            groupIDs: [],
            accountID: accounts.first?.id ?? "local",
            isFavorite: false,
            dateAdded: Date(),
            note: nil
        )
    }

    func commit(_ contact: Contact) async {
        guard !isReadOnly else { return }
        _ = await backend.save(contact)
        await reload()
        selectedContactID = contact.id
        isEditing = false
    }

    func delete(_ contactID: String) async {
        guard !isReadOnly else { return }
        _ = await backend.delete(contactID)
        if selectedContactID == contactID { selectedContactID = nil }
        await reload()
    }

    func toggleFavorite(_ contactID: String) async {
        guard !isReadOnly else { return }
        guard var c = contactsByID[contactID] else { return }
        c.isFavorite.toggle()
        await commit(c)
    }

    func toggleMerge(_ contactID: String) {
        if mergeCandidateIDs.contains(contactID) { mergeCandidateIDs.remove(contactID) }
        else { mergeCandidateIDs.insert(contactID) }
    }

    func performMerge() async {
        guard !isReadOnly, mergeCandidateIDs.count >= 2 else { return }
        _ = await backend.merge(Array(mergeCandidateIDs))
        mergeCandidateIDs.removeAll()
        isMergeOpen = false
        await reload()
    }

    func toggleGroupMembership(contactID: String, groupID: String) async {
        guard !isReadOnly else { return }
        guard let c = contactsByID[contactID] else { return }
        let included = !c.groupIDs.contains(groupID)
        _ = await backend.toggleMembership(contactID: contactID, groupID: groupID, included: included)
        await reload()
    }

    func saveSmartGroup(_ group: ContactsGroup) async {
        guard !isReadOnly else { return }
        _ = await backend.saveGroup(group)
        editingSmartGroupID = nil
        await reload()
    }

    func deleteGroup(_ groupID: String) async {
        guard !isReadOnly else { return }
        _ = await backend.deleteGroup(groupID)
        if case .group(let id) = selection, id == groupID { selection = .allContacts }
        await reload()
    }

    func encodeVCard(for contact: Contact) -> Data? {
        var lines: [String] = ["BEGIN:VCARD", "VERSION:3.0"]
        lines.append("N:\(contact.familyName);\(contact.givenName);;;")
        lines.append("FN:\(contact.fullName)")
        if let org = contact.organization { lines.append("ORG:\(org)") }
        if let job = contact.jobTitle { lines.append("TITLE:\(job)") }
        for f in contact.fields {
            switch f.kind {
            case .phone:   lines.append("TEL;TYPE=\(f.label.uppercased()):\(f.value)")
            case .email:   lines.append("EMAIL;TYPE=\(f.label.uppercased()):\(f.value)")
            case .url:     lines.append("URL:\(f.value)")
            case .address: lines.append("ADR;TYPE=\(f.label.uppercased()):;;\(f.value.replacingOccurrences(of: "\n", with: ", "));;;;")
            case .social:  lines.append("X-SOCIALPROFILE;TYPE=\(f.label):\(f.value)")
            case .birthday:
                if let d = ISO8601DateFormatter().date(from: f.value) {
                    let fmt = DateFormatter()
                    fmt.dateFormat = "yyyy-MM-dd"
                    lines.append("BDAY:\(fmt.string(from: d))")
                }
            case .note:    lines.append("NOTE:\(f.value)")
            case .related: lines.append("X-RELATED;TYPE=\(f.label):\(f.value)")
            }
        }
        if let note = contact.note, !note.isEmpty { lines.append("NOTE:\(note)") }
        lines.append("END:VCARD")
        return lines.joined(separator: "\r\n").data(using: .utf8)
    }

    func upcomingBirthdays(within days: Int = 60) -> [Contact] {
        let cal = Foundation.Calendar.current
        let today = Date()
        return contacts.compactMap { c -> (Contact, Int)? in
            guard let bday = c.birthday else { return nil }
            var comps = cal.dateComponents([.month, .day], from: bday)
            comps.year = cal.component(.year, from: today)
            guard var next = cal.date(from: comps) else { return nil }
            if next < cal.startOfDay(for: today) {
                next = cal.date(byAdding: .year, value: 1, to: next) ?? next
            }
            let diff = cal.dateComponents([.day], from: today, to: next).day ?? Int.max
            guard diff >= 0, diff <= days else { return nil }
            return (c, diff)
        }
        .sorted { $0.1 < $1.1 }
        .map { $0.0 }
    }
}

struct SectionedContacts: Identifiable {
    let id: String
    let header: String?
    let contacts: [Contact]
}
