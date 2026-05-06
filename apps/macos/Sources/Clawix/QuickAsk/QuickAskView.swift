import SwiftUI
import AppKit

/// Floating composer rendered inside `QuickAskPanel`. Pure presentation
/// for now — buttons are non-functional placeholders until the wiring
/// to the agent backend lands. `onSubmit` and `onClose` close the panel
/// so the controller can hide it.
struct QuickAskView: View {

    let onSubmit: (String) -> Void
    let onClose: () -> Void

    @State private var prompt: String = ""
    @FocusState private var inputFocused: Bool

    private let cornerRadius: CGFloat = 28

    var body: some View {
        ZStack {
            // Single squircle filled with a frosted-glass background and
            // a thin hairline; rendering the shape itself (vs. clipping
            // a separate background view) avoids the phantom rectangular
            // edge AppKit was painting around the previous structure.
            // The shadow lives on the same shape so it stays anchored
            // to the visible silhouette.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
                )
                .shadow(color: Color.black.opacity(0.55), radius: 28, x: 0, y: 14)

            VStack(alignment: .leading, spacing: 10) {
                promptField
                controlsRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
        }
        .padding(10)
        .onAppear { inputFocused = true }
    }


    private var promptField: some View {
        TextField("", text: $prompt, prompt: Text("Pregunta lo que quieras")
            .foregroundColor(Color(white: 0.55))
        )
        .textFieldStyle(.plain)
        .font(.system(size: 17, weight: .regular))
        .foregroundColor(.white)
        .focused($inputFocused)
        .onSubmit {
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            onSubmit(trimmed)
            prompt = ""
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 14) {
            iconButton(systemName: "plus", weight: .regular)
            iconButton(systemName: "globe", weight: .regular)
            iconButton(systemName: "rectangle.dashed.and.paperclip", weight: .regular)
            iconButton(systemName: "a.circle", weight: .regular)

            Text("5.5 Instant")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(white: 0.78))
                .padding(.leading, 2)

            Spacer(minLength: 0)

            iconButton(systemName: "record.circle", weight: .regular)
            iconButton(systemName: "mic", weight: .regular)
            sendButton
        }
    }

    private func iconButton(systemName: String, weight: Font.Weight) -> some View {
        QuickAskIconButton(systemName: systemName, weight: weight) {
            // Placeholder: hooks land alongside the agent wiring.
        }
    }

    private var sendButton: some View {
        Button {
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            onSubmit(trimmed)
            prompt = ""
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(Color(white: 0.32))
                )
        }
        .buttonStyle(.plain)
    }
}

/// Round, plain-style icon button matching the chrome in the
/// reference screenshot: ~18pt SF Symbol, no background fill, soft
/// hover highlight.
private struct QuickAskIconButton: View {
    let systemName: String
    let weight: Font.Weight
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: weight))
                .foregroundColor(Color(white: hovered ? 0.95 : 0.78))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
