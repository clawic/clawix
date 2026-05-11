import Foundation
import SwiftUI

final class DummyContactsBackend: ContactsBackend, @unchecked Sendable {

    let isReadOnly: Bool = false

    private struct Storage {
        var accounts: [ContactsAccount]
        var groups: [ContactsGroup]
        var contacts: [Contact]
    }

    private var storage = Storage(accounts: [], groups: [], contacts: [])
    private let lock = NSLock()

    init() {
        seed()
    }

    func requestAccess() async -> ContactsAccessResult { .granted }

    func loadAccounts() async -> [ContactsAccount] {
        lock.lock(); defer { lock.unlock() }
        return storage.accounts
    }

    func loadGroups() async -> [ContactsGroup] {
        lock.lock(); defer { lock.unlock() }
        return storage.groups
    }

    func loadContacts() async -> [Contact] {
        lock.lock(); defer { lock.unlock() }
        return storage.contacts
    }

    func save(_ contact: Contact) async -> Result<Contact, Error> {
        lock.lock(); defer { lock.unlock() }
        if let idx = storage.contacts.firstIndex(where: { $0.id == contact.id }) {
            storage.contacts[idx] = contact
        } else {
            storage.contacts.append(contact)
        }
        return .success(contact)
    }

    func delete(_ contactID: String) async -> Result<Void, Error> {
        lock.lock(); defer { lock.unlock() }
        storage.contacts.removeAll(where: { $0.id == contactID })
        return .success(())
    }

    func merge(_ contactIDs: [String]) async -> Result<Contact, Error> {
        lock.lock(); defer { lock.unlock() }
        let targets = storage.contacts.filter { contactIDs.contains($0.id) }
        guard let primary = targets.first else { return .failure(BackendError.notFound) }
        var merged = primary
        for other in targets.dropFirst() {
            if merged.organization == nil, let o = other.organization { merged.organization = o }
            if merged.jobTitle == nil, let j = other.jobTitle { merged.jobTitle = j }
            if merged.note == nil, let n = other.note { merged.note = n }
            if merged.photoData == nil, let p = other.photoData { merged.photoData = p }
            for f in other.fields where !merged.fields.contains(where: { $0.kind == f.kind && $0.value == f.value }) {
                merged.fields.append(f)
            }
            merged.groupIDs.formUnion(other.groupIDs)
        }
        storage.contacts.removeAll(where: { contactIDs.contains($0.id) && $0.id != primary.id })
        if let idx = storage.contacts.firstIndex(where: { $0.id == primary.id }) {
            storage.contacts[idx] = merged
        }
        return .success(merged)
    }

    func saveGroup(_ group: ContactsGroup) async -> Result<ContactsGroup, Error> {
        lock.lock(); defer { lock.unlock() }
        if let idx = storage.groups.firstIndex(where: { $0.id == group.id }) {
            storage.groups[idx] = group
        } else {
            storage.groups.append(group)
        }
        return .success(group)
    }

    func deleteGroup(_ groupID: String) async -> Result<Void, Error> {
        lock.lock(); defer { lock.unlock() }
        storage.groups.removeAll(where: { $0.id == groupID })
        for i in storage.contacts.indices {
            storage.contacts[i].groupIDs.remove(groupID)
        }
        return .success(())
    }

    func toggleMembership(contactID: String, groupID: String, included: Bool) async -> Result<Void, Error> {
        lock.lock(); defer { lock.unlock() }
        guard let idx = storage.contacts.firstIndex(where: { $0.id == contactID }) else {
            return .failure(BackendError.notFound)
        }
        if included { storage.contacts[idx].groupIDs.insert(groupID) }
        else { storage.contacts[idx].groupIDs.remove(groupID) }
        return .success(())
    }

    enum BackendError: LocalizedError {
        case notFound
        var errorDescription: String? { "Contact not found." }
    }

    private func seed() {
        let acctPersonal = ContactsAccount(id: "acct-personal", title: "Personal")
        let acctWork = ContactsAccount(id: "acct-work", title: "Work")
        storage.accounts = [acctPersonal, acctWork]

        let g1 = ContactsGroup(id: "grp-team",   accountID: "acct-work",     title: "Team",
                               color: ContactsTokens.Accent.primary,  kind: .normal, smartRule: nil)
        let g2 = ContactsGroup(id: "grp-family", accountID: "acct-personal", title: "Family",
                               color: ContactsTokens.AvatarPalette.colors[2], kind: .normal, smartRule: nil)
        let g3 = ContactsGroup(id: "grp-friends", accountID: "acct-personal", title: "Friends",
                               color: ContactsTokens.AvatarPalette.colors[3], kind: .normal, smartRule: nil)
        let smart = ContactsGroup(
            id: "smart-engineers",
            accountID: "acct-work",
            title: "Engineers",
            color: ContactsTokens.Accent.smart,
            kind: .smart,
            smartRule: SmartGroupRule(matchAll: true, conditions: [
                SmartGroupRule.Condition(id: UUID().uuidString, field: .jobTitle,
                                         op: .contains, value: "Engineer")
            ])
        )
        storage.groups = [g1, g2, g3, smart]

        let now = Date()
        let day: TimeInterval = 86_400

        func mk(_ id: String, _ given: String, _ family: String,
                org: String? = nil, title: String? = nil,
                phone: String, email: String,
                groups: [String] = [], account: String = "acct-personal",
                favorite: Bool = false, daysAgo: Int = 30,
                addr: String? = nil, url: String? = nil) -> Contact {
            var fields: [ContactField] = [
                ContactField(id: "\(id)-p", kind: .phone, label: "mobile", value: phone),
                ContactField(id: "\(id)-e", kind: .email, label: "home", value: email)
            ]
            if let a = addr { fields.append(ContactField(id: "\(id)-a", kind: .address, label: "home", value: a)) }
            if let u = url { fields.append(ContactField(id: "\(id)-u", kind: .url, label: "homepage", value: u)) }
            return Contact(
                id: id,
                givenName: given,
                familyName: family,
                organization: org,
                jobTitle: title,
                photoData: nil,
                fields: fields,
                groupIDs: Set(groups),
                accountID: account,
                isFavorite: favorite,
                dateAdded: now.addingTimeInterval(-day * Double(daysAgo)),
                note: nil
            )
        }

        storage.contacts = [
            mk("c-1", "Ana", "Garcia", org: "Northwind", title: "Senior Engineer",
               phone: "+34 555 010 234", email: "ana.garcia@example.com",
               groups: ["grp-team"], account: "acct-work", favorite: true, daysAgo: 2,
               addr: "Calle Mayor 1\n28013 Madrid\nSpain",
               url: "https://example.com/ana"),
            mk("c-2", "Bob", "Hill",
               phone: "+1 555 020 100", email: "bob.hill@example.com",
               groups: ["grp-friends"], daysAgo: 5),
            mk("c-3", "Carol", "Martinez", org: "Contoso", title: "Design Lead",
               phone: "+34 555 030 088", email: "carol.m@example.com",
               groups: ["grp-team"], account: "acct-work", daysAgo: 9),
            mk("c-4", "Daniel", "Owen",
               phone: "+1 555 040 717", email: "daniel.owen@example.com",
               groups: ["grp-family"], favorite: true, daysAgo: 21),
            mk("c-5", "Elena", "Pereira", org: "Northwind", title: "Junior Engineer",
               phone: "+34 555 050 411", email: "elena.p@example.com",
               groups: ["grp-team"], account: "acct-work", daysAgo: 35),
            mk("c-6", "Frank", "Quinn",
               phone: "+1 555 060 919", email: "frank.q@example.com",
               groups: ["grp-friends"], daysAgo: 60),
            mk("c-7", "Greta", "Romano", org: "Adventure Works", title: "Product Manager",
               phone: "+34 555 070 322", email: "greta.r@example.com",
               groups: ["grp-team"], account: "acct-work", daysAgo: 90),
            mk("c-8", "Hugo", "Silva",
               phone: "+34 555 080 504", email: "hugo.silva@example.com",
               groups: ["grp-family"], daysAgo: 1),
            mk("c-9", "Iris", "Tanaka", org: "Fabrikam", title: "Engineer",
               phone: "+1 555 090 213", email: "iris.t@example.com",
               groups: ["grp-team"], account: "acct-work", daysAgo: 14),
            mk("c-10", "Julio", "Vega",
               phone: "+34 555 100 668", email: "julio.v@example.com",
               groups: ["grp-friends"], daysAgo: 120),
            mk("c-11", "Kasia", "Walsh", org: "Tailspin", title: "Engineer",
               phone: "+1 555 110 781", email: "kasia.w@example.com",
               groups: ["grp-team"], account: "acct-work", daysAgo: 7),
            mk("c-12", "Luis", "Ximenez",
               phone: "+34 555 120 902", email: "luis.x@example.com",
               groups: ["grp-family"], daysAgo: 240)
        ]
    }
}
