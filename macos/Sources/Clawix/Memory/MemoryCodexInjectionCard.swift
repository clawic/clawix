import SwiftUI

/// Mirrors `SecretsCodexInjectionCard` but for the Memory service.
/// Toggles the `<!-- clawix:memory-begin -->` block in
/// `~/.codex/AGENTS.md` so any agent that reads that file learns how to
/// call `claw memory save / search / get / conclude`.
struct MemoryCodexInjectionCard: View {
    @State private var isInjected: Bool = false
    @State private var bodyText: String = CodexMemoryBlock.defaultBody
    @State private var savedBody: String = CodexMemoryBlock.defaultBody
    @State private var error: String?
    @State private var didLoad = false

    private var isDirty: Bool { isInjected && bodyText != savedBody }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Memory → Codex")
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text("Inject a paragraph into ~/.codex/AGENTS.md teaching agents how to use `claw memory`. The block is delimited by sentinel comments so flipping the toggle off removes only this block.")
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .padding(.bottom, 14)

            HStack(alignment: .top, spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { isInjected },
                    set: { newValue in toggle(newValue: newValue) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                VStack(alignment: .leading, spacing: 2) {
                    Text(isInjected ? "Codex injection is on" : "Codex injection is off")
                        .font(BodyFont.system(size: 12, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Text(isInjected
                         ? "Codex sees the memory paragraph at the top of every conversation."
                         : "Turn on to teach Codex how to call `claw memory`.")
                        .font(BodyFont.system(size: 11))
                        .foregroundColor(Palette.textSecondary)
                }
                Spacer()
                if isInjected {
                    Button { resetToDefault() } label: {
                        Text("Reset to default")
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 14)

            if isInjected {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(white: 0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                    TextEditor(text: $bodyText)
                        .font(BodyFont.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .frame(height: 220)

                HStack(spacing: 10) {
                    if let error {
                        Text(error)
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.55))
                    } else if isDirty {
                        Text("Unsaved changes")
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                    }
                    Spacer()
                    Button { saveBody() } label: {
                        Text("Save paragraph")
                            .font(BodyFont.system(size: 12, wght: 600))
                            .foregroundColor(isDirty ? Palette.textPrimary : Palette.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(isDirty ? 0.12 : 0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isDirty)
                }
                .padding(.top, 10)
            }
        }
        .onAppear { load() }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        do {
            if let body = try CodexInstructionsFile.sentinelBlockBody(id: CodexMemoryBlock.id) {
                self.isInjected = true
                self.bodyText = body
                self.savedBody = body
            } else {
                self.isInjected = false
                self.bodyText = CodexMemoryBlock.defaultBody
                self.savedBody = CodexMemoryBlock.defaultBody
            }
            self.error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    private func toggle(newValue: Bool) {
        do {
            if newValue {
                let bodyToWrite = bodyText.isEmpty ? CodexMemoryBlock.defaultBody : bodyText
                try CodexInstructionsFile.replaceSentinelBlock(id: CodexMemoryBlock.id, body: bodyToWrite)
                self.bodyText = bodyToWrite
                self.savedBody = bodyToWrite
                self.isInjected = true
            } else {
                try CodexInstructionsFile.removeSentinelBlock(id: CodexMemoryBlock.id)
                self.isInjected = false
            }
            self.error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    private func saveBody() {
        do {
            try CodexInstructionsFile.replaceSentinelBlock(id: CodexMemoryBlock.id, body: bodyText)
            savedBody = bodyText
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    private func resetToDefault() {
        bodyText = CodexMemoryBlock.defaultBody
        if isInjected {
            saveBody()
        }
    }
}
