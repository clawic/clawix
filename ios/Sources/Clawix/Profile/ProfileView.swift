import SwiftUI

struct ProfileView: View {
    @ObservedObject var store: ProfileStore
    @State private var pasteLink: String = ""
    @State private var pairedHandle: ProfileClient.Handle?

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    if let me = store.me {
                        LabeledContent("Alias") { Text("@" + me.handle.alias).foregroundStyle(Palette.textPrimary) }
                        LabeledContent("Fingerprint") {
                            Text(me.handle.fingerprint)
                                .font(.system(size: 13, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    } else {
                        Text("No profile yet").foregroundStyle(Palette.textSecondary)
                    }
                }

                Section("Pair with a peer") {
                    TextEditor(text: $pasteLink)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 80)
                    Button("Resolve and add") {
                        Task { pairedHandle = await store.pair(link: pasteLink) }
                    }
                    .disabled(pasteLink.isEmpty)
                    if let handle = pairedHandle {
                        Text("Paired with @\(handle.alias)")
                            .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                    }
                }

                Section("Audience tiers") {
                    ForEach(["public", "audience", "friends", "family", "inner-circle"], id: \.self) { tier in
                        Text(tier)
                    }
                }

                Section("Recovery") {
                    Button("Reveal mnemonic") {
                        // Reveal flow lives behind a biometric prompt in the daemon.
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Profile")
        }
    }
}
