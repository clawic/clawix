import SwiftUI

struct BrowserUsagePage: View {
    @AppStorage(BrowserPermissionPolicy.approvalStorageKey) private var approval: String = BrowserPermissionPolicy.Approval.alwaysAsk.rawValue
    @AppStorage("clawix.browser.historyApproval") private var history: String = BrowserPermissionPolicy.Approval.alwaysAsk.rawValue
    @State private var browsingData: BrowserPermissionPolicy.BrowsingDataKind = .all
    @State private var clearStatus: String?
    @State private var clearingBrowsingData = false
    @State private var blockedDomains: [String] = []
    @State private var allowedDomains: [String] = []

    private var browsingDataOptions: [(BrowserPermissionPolicy.BrowsingDataKind, String)] {
        [
            (.all, "Clear all browsing data"),
            (.cache, "Clear cache"),
            (.cookies, "Clear cookies")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Browser usage")

            /*
            Text("Plugins")
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(Palette.textPrimary)
                .padding(.bottom, 14)

            SettingsCard {
                BrowserPluginRow(title: "Browser Use",
                                 detail: "Control the in-app browser with Clawix")
            }
            */

            SectionLabel(title: "Browser")
            SettingsCard {
                SettingsRow {
                    RowLabel(
                        title: "Browsing data",
                        detail: "Clear site data and the cache of the in-app browser"
                    )
                } trailing: {
                    HStack(spacing: 8) {
                        SettingsDropdown(
                            options: browsingDataOptions,
                            selection: $browsingData,
                            minWidth: 190
                        )
                        Button(clearingBrowsingData ? "Clearing…" : "Clear") {
                            clearSelectedBrowsingData()
                        }
                        .buttonStyle(.borderless)
                        .font(BodyFont.system(size: 11.5, wght: 600))
                        .foregroundColor(clearingBrowsingData ? Palette.textSecondary : Palette.textPrimary)
                        .disabled(clearingBrowsingData)
                    }
                }
                .liftWhenSettingsDropdownOpen()
            }
            if let clearStatus {
                InfoBanner(text: clearStatus, kind: .ok)
                    .padding(.top, 10)
            }

            SectionLabel(title: "Permissions")
            SettingsCard {
                DropdownRow(
                    title: "Approval",
                    detail: "Choose whether Clawix asks for permission before opening websites",
                    options: [
                        (BrowserPermissionPolicy.Approval.alwaysAsk.rawValue, "Always ask"),
                        (BrowserPermissionPolicy.Approval.alwaysAllow.rawValue, "Always allow"),
                        (BrowserPermissionPolicy.Approval.alwaysBlock.rawValue, "Always block")
                    ],
                    selection: $approval
                )
                CardDivider()
                DropdownRow(
                    title: "History",
                    detail: "Choose whether Clawix asks for approval before accessing your history",
                    options: [
                        (BrowserPermissionPolicy.Approval.alwaysAsk.rawValue, "Always ask"),
                        (BrowserPermissionPolicy.Approval.alwaysAllow.rawValue, "Always allow"),
                        (BrowserPermissionPolicy.Approval.alwaysBlock.rawValue, "Always block")
                    ],
                    selection: $history
                )
            }

            DomainListSection(title: "Blocked domains",
                              subtitle: "Clawix will never open these sites",
                              emptyText: "No blocked domains",
                              domains: $blockedDomains,
                              list: .blocked,
                              onChanged: reloadDomains)
                .padding(.top, 28)

            DomainListSection(title: "Allowed domains",
                              subtitle: "Domains that open without prompting",
                              emptyText: "No allowed domains",
                              domains: $allowedDomains,
                              list: .allowed,
                              onChanged: reloadDomains)
                .padding(.top, 28)
        }
        .onAppear {
            normalizeBrowserPermissionValues()
            reloadDomains()
        }
    }

    private func normalizeBrowserPermissionValues() {
        let valid = [
            BrowserPermissionPolicy.Approval.alwaysAsk.rawValue,
            BrowserPermissionPolicy.Approval.alwaysAllow.rawValue,
            BrowserPermissionPolicy.Approval.alwaysBlock.rawValue,
        ]
        if !valid.contains(approval) { approval = BrowserPermissionPolicy.Approval.alwaysAsk.rawValue }
        if !valid.contains(history) { history = BrowserPermissionPolicy.Approval.alwaysAsk.rawValue }
    }

    private func reloadDomains() {
        blockedDomains = BrowserPermissionPolicy.blockedDomains
        allowedDomains = BrowserPermissionPolicy.allowedDomains
    }

    private func clearSelectedBrowsingData() {
        clearingBrowsingData = true
        clearStatus = nil
        let selected = browsingData
        BrowserPermissionPolicy.clearBrowsingData(selected) {
            clearingBrowsingData = false
            clearStatus = "\(selected.rawValue) completed."
            ToastCenter.shared.show(clearStatus ?? "Browsing data cleared")
        }
    }
}

struct BrowserPluginRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.12, green: 0.20, blue: 0.36),
                                     Color(red: 0.06, green: 0.10, blue: 0.20)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 36, height: 36)
                LucideIcon(.send, size: 14)
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(-12))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer(minLength: 12)
            CheckIcon(size: 13)
                .foregroundColor(Palette.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct DomainListSection: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let emptyText: LocalizedStringKey
    @Binding var domains: [String]
    let list: BrowserPermissionPolicy.DomainList
    let onChanged: () -> Void

    @State private var draft = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(title)
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button {
                    addDomain()
                } label: {
                    HStack(spacing: 5) {
                        LucideIcon(.plus, size: 11)
                        Text("Add")
                            .font(BodyFont.system(size: 12, wght: 600))
                    }
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(subtitle)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Palette.textSecondary)
                    .padding(.top, 4)
                    .padding(.bottom, 10)

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    TextField("example.com", text: $draft)
                        .textFieldStyle(.plain)
                        .font(BodyFont.system(size: 12.5))
                        .foregroundColor(Palette.textPrimary)
                        .onSubmit(addDomain)
                    Button("Add") {
                        addDomain()
                    }
                    .buttonStyle(.borderless)
                    .font(BodyFont.system(size: 11.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                if let error {
                    CardDivider()
                    Text(error)
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }

                if domains.isEmpty {
                    CardDivider()
                    HStack {
                        Spacer()
                        Text(emptyText)
                            .font(BodyFont.system(size: 12, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 18)
                } else {
                    ForEach(domains, id: \.self) { domain in
                        CardDivider()
                        HStack(spacing: 10) {
                            Text(verbatim: domain)
                                .font(BodyFont.system(size: 12.5, wght: 500))
                                .foregroundColor(Palette.textPrimary)
                            Spacer()
                            Button("Remove") {
                                BrowserPermissionPolicy.removeDomain(domain, from: list)
                                onChanged()
                            }
                            .buttonStyle(.borderless)
                            .font(BodyFont.system(size: 11.5, wght: 600))
                            .foregroundColor(Palette.textSecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(white: 0.085))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
        }
    }

    private func addDomain() {
        guard let domain = BrowserPermissionPolicy.addDomain(draft, to: list) else {
            error = "Enter a valid domain such as example.com."
            return
        }
        error = nil
        draft = ""
        switch list {
        case .blocked:
            domains = BrowserPermissionPolicy.blockedDomains
        case .allowed:
            domains = BrowserPermissionPolicy.allowedDomains
        }
        onChanged()
        ToastCenter.shared.show("Added \(domain)")
    }
}
