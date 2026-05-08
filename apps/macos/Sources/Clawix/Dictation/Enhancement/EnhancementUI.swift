import SwiftUI
import AppKit

/// Settings entry: a single row that surfaces the master toggle and a
/// Manage button which opens the full provider + prompt + skip-short
/// + timeout configuration sheet. Lives in the Avanzado section per
/// the user's "Avanzados" rule (Enhancement is power-user; default
/// off).
struct EnhancementSummaryRow: View {
    @ObservedObject var library: PromptLibrary
    @AppStorage(EnhancementSettings.enabledKey) private var enabled = false

    @State private var sheetOpen = false

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text("AI Enhancement")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            HStack(spacing: 10) {
                PillToggle(isOn: $enabled)
                Button {
                    sheetOpen = true
                } label: {
                    Text("Manage")
                        .font(BodyFont.system(size: 12, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous).fill(Color(white: 0.165))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $sheetOpen) {
            EnhancementSettingsSheet(library: library, isPresented: $sheetOpen)
        }
    }

    private var detail: LocalizedStringKey {
        if !enabled {
            return "Off. Whisper output is pasted as-is. Enable to clean up grammar / style with an LLM."
        }
        return "On · using \(library.activePrompt().title) prompt"
    }
}

// MARK: - Sheet

struct EnhancementSettingsSheet: View {
    @ObservedObject var library: PromptLibrary
    @Binding var isPresented: Bool

    @AppStorage(EnhancementSettings.providerKey) private var providerRaw = EnhancementProviderID.openai.rawValue
    @AppStorage(EnhancementSettings.skipShortEnabledKey) private var skipShortEnabled = true
    @AppStorage(EnhancementSettings.skipShortMinWordsKey) private var skipShortMinWords = 3
    @AppStorage(EnhancementSettings.timeoutSecondsKey) private var timeoutSeconds = 7
    @AppStorage(EnhancementSettings.timeoutPolicyKey) private var timeoutPolicy = "retry"
    @AppStorage(EnhancementSettings.clipboardContextKey) private var clipboardContext = false
    @AppStorage(EnhancementSettings.screenContextKey) private var screenContext = false

    @State private var apiKeyDraft: String = ""
    @State private var apiKeyVisible: Bool = false
    @State private var modelDraft: String = ""
    @State private var baseURLDraft: String = ""

    private var provider: EnhancementProviderID {
        EnhancementProviderID(rawValue: providerRaw) ?? .openai
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("AI Enhancement")
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
                    providerSection
                    promptSection
                    skipShortSection
                    timeoutSection
                    contextSection
                }
                .padding(20)
            }
            .thinScrollers()
        }
        .frame(width: 660, height: 600)
        .background(Color(white: 0.10))
        .onAppear { reloadDrafts() }
        .onChange(of: providerRaw) { _, _ in reloadDrafts() }
    }

    // MARK: - Sections

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Provider")
            HStack(spacing: 10) {
                Picker("", selection: $providerRaw) {
                    ForEach(EnhancementProviderID.allCases, id: \.rawValue) { id in
                        Text(id.displayName).tag(id.rawValue)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)
                Spacer()
                connectedDot
            }
            if provider.requiresAPIKey {
                HStack(spacing: 8) {
                    Group {
                        if apiKeyVisible {
                            TextField("API key", text: $apiKeyDraft)
                        } else {
                            SecureField("API key", text: $apiKeyDraft)
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(white: 0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                    )
                    Button {
                        apiKeyVisible.toggle()
                    } label: {
                        LucideIcon.auto(apiKeyVisible ? "eye.slash" : "eye", size: 11)
                            .foregroundColor(Palette.textPrimary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color(white: 0.14)))
                    }
                    .buttonStyle(.plain)
                    Button("Save") {
                        EnhancementKeychain.setAPIKey(apiKeyDraft, for: provider)
                    }
                }
            } else if provider == .ollama {
                TextField("Base URL", text: $baseURLDraft)
                    .textFieldStyle(.plain)
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(white: 0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                    )
                    .onChange(of: baseURLDraft) { _, new in
                        UserDefaults.standard.set(
                            new,
                            forKey: EnhancementSettings.baseURLKey(for: provider.rawValue)
                        )
                    }
            }

            HStack(spacing: 10) {
                Text("Model")
                    .font(BodyFont.system(size: 11.5, wght: 600))
                    .foregroundColor(Palette.textSecondary)
                TextField(provider.defaultModels.first ?? "", text: $modelDraft)
                    .textFieldStyle(.plain)
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(white: 0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                    )
                    .onChange(of: modelDraft) { _, new in
                        UserDefaults.standard.set(
                            new,
                            forKey: EnhancementSettings.modelKey(for: provider.rawValue)
                        )
                    }
                Menu {
                    ForEach(provider.defaultModels, id: \.self) { m in
                        Button(m) { modelDraft = m }
                    }
                } label: {
                    LucideIcon(.list, size: 11)
                        .foregroundColor(Palette.textPrimary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color(white: 0.14)))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
            }
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Prompt")
            VStack(spacing: 0) {
                ForEach(library.prompts) { p in
                    PromptListRow(
                        prompt: p,
                        active: library.activePrompt().id == p.id,
                        onTap: { library.setActive(p.id) },
                        onDelete: p.isBuiltIn ? nil : {
                            library.deleteCustom(p.id)
                        }
                    )
                    Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.5)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(white: 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
        }
    }

    private var skipShortSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Skip short transcriptions")
            HStack {
                Text("Skip if shorter than")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                PillToggle(isOn: $skipShortEnabled)
            }
            if skipShortEnabled {
                Picker("Min words", selection: $skipShortMinWords) {
                    ForEach([1, 2, 3, 5, 8, 10, 15], id: \.self) { n in
                        Text("\(n) word\(n == 1 ? "" : "s")").tag(n)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
            }
        }
    }

    private var timeoutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Timeout")
            HStack(spacing: 16) {
                Picker("Timeout", selection: $timeoutSeconds) {
                    ForEach([3, 5, 7, 10, 15, 20, 30, 60], id: \.self) { s in
                        Text("\(s) s").tag(s)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 140)

                Picker("On timeout", selection: $timeoutPolicy) {
                    Text("Fail (paste raw)").tag("fail")
                    Text("Retry up to 3×").tag("retry")
                }
                .labelsHidden()
                .frame(maxWidth: 200)
            }
        }
    }

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Context awareness")
            HStack {
                Text("Send clipboard text alongside transcript")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                PillToggle(isOn: $clipboardContext)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Send screen-capture text (OCR)")
                        .font(BodyFont.system(size: 12.5, wght: 500))
                        .foregroundColor(Palette.textPrimary)
                    Text("Wired but inert until the OCR follow-up ships")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }
                Spacer()
                PillToggle(isOn: $screenContext)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(BodyFont.system(size: 12, wght: 700))
            .foregroundColor(Palette.textSecondary)
            .textCase(.uppercase)
    }

    private var connectedDot: some View {
        let connected = (provider.requiresAPIKey && EnhancementKeychain.hasAPIKey(for: provider))
            || (!provider.requiresAPIKey)
        return HStack(spacing: 6) {
            Circle()
                .fill(connected ? Color(red: 0.27, green: 0.74, blue: 0.42) : Color(white: 0.45))
                .frame(width: 8, height: 8)
            Text(connected ? "Connected" : "Not configured")
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundColor(Palette.textSecondary)
        }
    }

    private func reloadDrafts() {
        apiKeyDraft = EnhancementKeychain.apiKey(for: provider) ?? ""
        modelDraft = UserDefaults.standard.string(
            forKey: EnhancementSettings.modelKey(for: provider.rawValue)
        ) ?? (provider.defaultModels.first ?? "")
        baseURLDraft = UserDefaults.standard.string(
            forKey: EnhancementSettings.baseURLKey(for: provider.rawValue)
        ) ?? "http://localhost:11434"
    }
}

// MARK: - Prompt list row

private struct PromptListRow: View {
    let prompt: EnhancementPrompt
    let active: Bool
    let onTap: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                LucideIcon.auto(active ? "checkmark.circle.fill" : "circle", size: 13)
                    .foregroundColor(active
                        ? Color(red: 0.27, green: 0.74, blue: 0.42)
                        : Palette.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(prompt.title)
                            .font(BodyFont.system(size: 12.5, wght: 600))
                            .foregroundColor(Palette.textPrimary)
                        if prompt.isBuiltIn {
                            Text("BUILT-IN")
                                .font(BodyFont.system(size: 9, wght: 700))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color(white: 0.30))
                                )
                        }
                    }
                    Text(prompt.systemPrompt)
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                Spacer()
                if let onDelete {
                    Button {
                        onDelete()
                    } label: {
                        LucideIcon(.trash2, size: 11)
                            .foregroundColor(Palette.textPrimary)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color(white: 0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Rectangle().fill(active ? Color.white.opacity(0.04) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
