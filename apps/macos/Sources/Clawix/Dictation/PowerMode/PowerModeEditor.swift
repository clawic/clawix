import SwiftUI
import ClawixEngine

struct PowerModeEditor: View {
    @Binding var config: PowerModeConfig
    let onDelete: () -> Void

    @State private var bundleDraft: String = ""
    @State private var urlDraft: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                triggersSection
                transcriptionSection
                outputSection
                behaviorSection
                enhancementSection
            }
            .padding(20)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            TextField("Emoji", text: $config.emoji)
                .textFieldStyle(.plain)
                .font(.system(size: 22))
                .frame(width: 44, height: 44)
                .background(editorFieldBackground(radius: 8))
                .multilineTextAlignment(.center)
            TextField("Name", text: $config.name)
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 14, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(editorFieldBackground(radius: 8))
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.94, green: 0.45, blue: 0.45))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color(white: 0.14)))
            }
            .buttonStyle(.plain)
        }
    }

    private var triggersSection: some View {
        EditorSection(title: "Triggers") {
            EditorTagList(
                title: "Bundle IDs",
                placeholder: "com.tinyspeck.slackmacgap",
                draft: $bundleDraft,
                items: $config.triggerBundleIds
            )
            EditorTagList(
                title: "URL hosts (browsers)",
                placeholder: "github.com",
                draft: $urlDraft,
                items: $config.triggerURLHosts
            )
        }
    }

    private var transcriptionSection: some View {
        EditorSection(title: "Transcription overrides") {
            EditorRow {
                EditorLabel(text: "Language")
                Picker("", selection: Binding(
                    get: { config.languageOverride ?? "" },
                    set: { config.languageOverride = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Use global").tag("")
                    Text("Auto-detect").tag("auto")
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang.whisperLanguageCode)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }
            EditorRow {
                EditorLabel(text: "Whisper prompt override")
                TextEditor(text: Binding(
                    get: { config.whisperPromptOverride ?? "" },
                    set: { config.whisperPromptOverride = $0.isEmpty ? nil : $0 }
                ))
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 70)
                .background(editorFieldBackground(radius: 6))
            }
        }
    }

    private var outputSection: some View {
        EditorSection(title: "Output overrides") {
            EditorRow {
                EditorLabel(text: "Auto-send")
                Picker("", selection: Binding(
                    get: { config.autoSendKeyOverride ?? "" },
                    set: { config.autoSendKeyOverride = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Use global").tag("")
                    ForEach(DictationAutoSendKey.allCases, id: \.self) { key in
                        Text(key.displayName).tag(key.rawValue)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
            }
        }
    }

    private var behaviorSection: some View {
        EditorSection(title: "Behavior") {
            EditorRow {
                EditorLabel(text: "Enabled")
                Spacer()
                PillToggle(isOn: $config.enabled)
            }
            EditorRow {
                EditorLabel(text: "Use as default profile (fallback)")
                Spacer()
                PillToggle(isOn: $config.isDefault)
            }
        }
    }

    private var enhancementSection: some View {
        EditorSection(title: "Enhancement (coming soon)") {
            Text("AI Enhancement integration is wired in the data model but not active yet. Toggling here only persists the value; nothing fires until the Enhancement module ships.")
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            EditorRow {
                EditorLabel(text: "Enhance transcripts")
                Spacer()
                PillToggle(isOn: $config.enhancementEnabled)
            }
            EditorRow {
                EditorLabel(text: "Bundle clipboard + screen context")
                Spacer()
                PillToggle(isOn: $config.contextAwareness)
            }
        }
    }
}
