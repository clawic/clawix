import SwiftUI

/// Settings sheet that exposes API keys + base URLs for the cloud
/// transcription backends (#22 cloud variants). Reachable from
/// `DictationSettingsPage` Avanzado section when a cloud backend is
/// selected. Persists keys in the user's encrypted Secrets under the
/// "Clawix System" container; never touches the system Keychain.
struct CloudBackendsSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject private var vault: SecretsManager = .shared

    @State private var groqKey: String = ""
    @State private var deepgramKey: String = ""
    @State private var customBaseURL: String = ""
    @State private var customKey: String = ""
    @State private var customModel: String = ""

    @State private var groqHidden = true
    @State private var deepgramHidden = true
    @State private var customHidden = true
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Cloud transcription backends")
                    .font(BodyFont.system(size: 14, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Cloud Whisper variants take the same audio you'd send to local Whisper and run it on a remote model. Add a key once and switch backends from the Engine picker. Keys live in your encrypted Secrets, never in plaintext on disk.")
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if vault.state != .unlocked {
                        Text("Secrets is locked. Unlock it from Settings → Secrets to manage cloud transcription keys.")
                            .font(BodyFont.system(size: 11.5, wght: 600))
                            .foregroundColor(Color(red: 0.95, green: 0.65, blue: 0.30))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let saveError {
                        Text(saveError)
                            .font(BodyFont.system(size: 11.5, wght: 600))
                            .foregroundColor(Color(red: 0.95, green: 0.65, blue: 0.30))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    section("Groq") {
                        Text("Cloud-hosted transcription. <200 ms typical latency.")
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                        keyRow(
                            placeholder: "Groq API key",
                            value: $groqKey,
                            hidden: $groqHidden,
                            saveAction: {
                                let key = groqKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !key.isEmpty else { return }
                                Task { await saveAPIKey(key, for: .groq) }
                            }
                        )
                    }

                    section("Deepgram") {
                        Text("Cloud transcription with smart formatting for English and 30+ languages.")
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                        keyRow(
                            placeholder: "Deepgram API key",
                            value: $deepgramKey,
                            hidden: $deepgramHidden,
                            saveAction: {
                                let key = deepgramKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !key.isEmpty else { return }
                                Task { await saveAPIKey(key, for: .deepgram) }
                            }
                        )
                    }

                    section("Custom Whisper endpoint") {
                        Text("Any OpenAI-compatible /audio/transcriptions URL. API key optional (some self-hosted gateways skip auth).")
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                        TextField("Base URL (e.g. http://localhost:9000/v1)", text: $customBaseURL)
                            .textFieldStyle(.plain)
                            .font(BodyFont.system(size: 12, wght: 500))
                            .foregroundColor(Palette.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(box)
                            .onChange(of: customBaseURL) { _, new in
                                UserDefaults.standard.set(
                                    new,
                                    forKey: ClawixPersistentSurfaceKeys.dictationCustomBaseURL
                                )
                            }
                        TextField("Model id (default: whisper-1)", text: $customModel)
                            .textFieldStyle(.plain)
                            .font(BodyFont.system(size: 12, wght: 500))
                            .foregroundColor(Palette.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(box)
                            .onChange(of: customModel) { _, new in
                                UserDefaults.standard.set(
                                    new,
                                    forKey: ClawixPersistentSurfaceKeys.dictationCustomModel
                                )
                            }
                        keyRow(
                            placeholder: "API key (optional)",
                            value: $customKey,
                            hidden: $customHidden,
                            saveAction: {
                                let key = customKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !key.isEmpty else { return }
                                Task { await saveAPIKey(key, for: .custom) }
                            }
                        )
                    }
                }
                .padding(20)
            }
            .thinScrollers()
        }
        .frame(width: 600, height: 540)
        .background(Color(white: 0.10))
        .task(id: vault.state) { await loadDrafts() }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(BodyFont.system(size: 12, wght: 700))
                .foregroundColor(Palette.textSecondary)
                .textCase(.uppercase)
            content()
        }
    }

    @ViewBuilder
    private func keyRow(
        placeholder: LocalizedStringKey,
        value: Binding<String>,
        hidden: Binding<Bool>,
        saveAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Group {
                if hidden.wrappedValue {
                    SecureField(placeholder, text: value)
                } else {
                    TextField(placeholder, text: value)
                }
            }
            .textFieldStyle(.plain)
            .font(BodyFont.system(size: 12, wght: 500))
            .foregroundColor(Palette.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(box)
            Button {
                hidden.wrappedValue.toggle()
            } label: {
                LucideIcon.auto(hidden.wrappedValue ? "eye.slash" : "eye", size: 11)
                    .foregroundColor(Palette.textPrimary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color(white: 0.14)))
            }
            .buttonStyle(.plain)
            Button("Save", action: saveAction)
        }
    }

    private var box: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(white: 0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
    }

    private func loadDrafts() async {
        groqKey = ""
        deepgramKey = ""
        customKey = ""
        customBaseURL = UserDefaults.standard.string(
            forKey: ClawixPersistentSurfaceKeys.dictationCustomBaseURL
        ) ?? ""
        customModel = UserDefaults.standard.string(
            forKey: ClawixPersistentSurfaceKeys.dictationCustomModel
        ) ?? "whisper-1"
    }

    private func saveAPIKey(_ key: String, for provider: CloudTranscriptionProvider) async {
        saveError = nil
        do {
            try await CloudTranscriptionSecrets.setAPIKey(key, for: provider)
        } catch {
            saveError = error.localizedDescription
        }
    }
}
