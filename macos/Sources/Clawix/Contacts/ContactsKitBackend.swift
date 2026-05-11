import Foundation
import SwiftUI
import Contacts

final class ContactsKitBackend: ContactsBackend, @unchecked Sendable {

    let isReadOnly: Bool = true
    private let store = CNContactStore()

    func requestAccess() async -> ContactsAccessResult {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized:
            return .granted
        case .denied:
            return .denied("Contacts access denied in System Settings.")
        case .restricted:
            return .denied("Contacts access is restricted on this device.")
        case .notDetermined:
            do {
                let granted = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
                    store.requestAccess(for: .contacts) { ok, err in
                        if let err = err { cont.resume(throwing: err) }
                        else { cont.resume(returning: ok) }
                    }
                }
                return granted ? .granted : .denied("Permission not granted.")
            } catch {
                return .denied(error.localizedDescription)
            }
        @unknown default:
            return .unavailable
        }
    }

    func loadAccounts() async -> [ContactsAccount] {
        do {
            let containers = try store.containers(matching: nil)
            return containers.map { c in
                ContactsAccount(id: c.identifier, title: c.name.isEmpty ? "Account" : c.name)
            }
        } catch {
            return []
        }
    }

    func loadGroups() async -> [ContactsGroup] {
        do {
            let groups = try store.groups(matching: nil)
            return groups.map { g in
                ContactsGroup(
                    id: g.identifier,
                    accountID: containerID(for: g) ?? "local",
                    title: g.name,
                    color: ContactsTokens.Accent.primary,
                    kind: .normal,
                    smartRule: nil
                )
            }
        } catch {
            return []
        }
    }

    func loadContacts() async -> [Contact] {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey,
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactOrganizationNameKey,
            CNContactJobTitleKey,
            CNContactImageDataKey,
            CNContactThumbnailImageDataKey,
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey,
            CNContactPostalAddressesKey,
            CNContactUrlAddressesKey,
            CNContactSocialProfilesKey,
            CNContactBirthdayKey,
            CNContactNoteKey
        ] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var contacts: [Contact] = []
        do {
            try store.enumerateContacts(with: request) { raw, _ in
                contacts.append(self.adapt(raw))
            }
        } catch {
            return []
        }
        return contacts
    }

    func save(_ contact: Contact) async -> Result<Contact, Error> {
        .failure(BackendError.readOnly)
    }

    func delete(_ contactID: String) async -> Result<Void, Error> {
        .failure(BackendError.readOnly)
    }

    func merge(_ contactIDs: [String]) async -> Result<Contact, Error> {
        .failure(BackendError.readOnly)
    }

    func saveGroup(_ group: ContactsGroup) async -> Result<ContactsGroup, Error> {
        .failure(BackendError.readOnly)
    }

    func deleteGroup(_ groupID: String) async -> Result<Void, Error> {
        .failure(BackendError.readOnly)
    }

    func toggleMembership(contactID: String, groupID: String, included: Bool) async -> Result<Void, Error> {
        .failure(BackendError.readOnly)
    }

    enum BackendError: LocalizedError {
        case readOnly
        var errorDescription: String? { "Read-only backend." }
    }

    private func containerID(for group: CNGroup) -> String? {
        let predicate = CNContainer.predicateForContainerOfGroup(withIdentifier: group.identifier)
        return (try? store.containers(matching: predicate))?.first?.identifier
    }

    private func adapt(_ raw: CNContact) -> Contact {
        var fields: [ContactField] = []
        for p in raw.phoneNumbers {
            fields.append(ContactField(
                id: "phone-\(p.identifier)",
                kind: .phone,
                label: CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: p.label ?? ""),
                value: p.value.stringValue
            ))
        }
        for e in raw.emailAddresses {
            fields.append(ContactField(
                id: "email-\(e.identifier)",
                kind: .email,
                label: CNLabeledValue<NSString>.localizedString(forLabel: e.label ?? ""),
                value: e.value as String
            ))
        }
        for a in raw.postalAddresses {
            fields.append(ContactField(
                id: "addr-\(a.identifier)",
                kind: .address,
                label: CNLabeledValue<CNPostalAddress>.localizedString(forLabel: a.label ?? ""),
                value: CNPostalAddressFormatter.string(from: a.value, style: .mailingAddress)
            ))
        }
        for u in raw.urlAddresses {
            fields.append(ContactField(
                id: "url-\(u.identifier)",
                kind: .url,
                label: CNLabeledValue<NSString>.localizedString(forLabel: u.label ?? ""),
                value: u.value as String
            ))
        }
        for s in raw.socialProfiles {
            fields.append(ContactField(
                id: "social-\(s.identifier)",
                kind: .social,
                label: s.value.service,
                value: s.value.username
            ))
        }
        if let bday = raw.birthday, let d = Foundation.Calendar(identifier: .gregorian).date(from: bday) {
            fields.append(ContactField(
                id: "bday-\(raw.identifier)",
                kind: .birthday,
                label: "birthday",
                value: ISO8601DateFormatter().string(from: d)
            ))
        }
        let photo = raw.imageData ?? raw.thumbnailImageData
        return Contact(
            id: raw.identifier,
            givenName: raw.givenName,
            familyName: raw.familyName,
            organization: raw.organizationName.isEmpty ? nil : raw.organizationName,
            jobTitle: raw.jobTitle.isEmpty ? nil : raw.jobTitle,
            photoData: photo,
            fields: fields,
            groupIDs: [],
            accountID: "local",
            isFavorite: false,
            dateAdded: Date(),
            note: nil
        )
    }
}
