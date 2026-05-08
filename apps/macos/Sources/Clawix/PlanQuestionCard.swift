import SwiftUI
import AppKit

/// Multi-choice card the chat view renders above the composer when the
/// backend has sent an `item/tool/requestUserInput` event for the active
/// chat (plan mode).
///
/// Layout for multi-question planning prompts:
///   • Question header at top.
///   • Numbered options, each with an info icon hosting the option's
///     description tooltip. Up/Down arrow keys move the selection,
///     Return submits, Escape dismisses.
///   • If `isOther` is set on the question, an extra free-text row
///     appears last and switches the card into a text input when picked.
///   • Footer: dismiss-with-Escape pill + submit button.
///
/// All UI mutations call back into `AppState` which then drives
/// `ClawixService.respondToPlanQuestion`. The card never talks to the
/// transport layer directly.
struct PlanQuestionCard: View {
    let pending: PendingPlanQuestion
    @EnvironmentObject var appState: AppState

    @State private var questionIndex: Int = 0
    @State private var selectedOptionIndex: Int = 0
    @State private var otherText: String = ""
    @FocusState private var otherFocused: Bool

    private var currentQuestion: ToolRequestUserInputQuestion {
        pending.questions[questionIndex]
    }

    /// Number of selectable rows including the synthetic free-text row
    /// when the question allows it. The real options come first, the
    /// free-text row is index `options.count`.
    private var rowCount: Int {
        let opts = currentQuestion.options?.count ?? 0
        return opts + (currentQuestion.isOther == true ? 1 : 0)
    }

    /// True when the current selection points at the synthetic free-text row.
    private var isOtherSelected: Bool {
        currentQuestion.isOther == true
            && selectedOptionIndex == (currentQuestion.options?.count ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text(currentQuestion.question)
                    .font(BodyFont.system(size: 14, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                if rowCount > 1 {
                    arrowsHint
                }
            }

            optionsList

            footer
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.085))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 10)
        .background(planCardKeyHandler)
        .onChange(of: pending.itemId) { _, _ in
            // Different question payload arrived (sequenced plan-mode
            // question on the same chat): reset selection state.
            questionIndex = 0
            selectedOptionIndex = 0
            otherText = ""
        }
    }

    // MARK: - Subviews

    private var arrowsHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up")
            Image(systemName: "arrow.down")
        }
        .font(BodyFont.system(size: 11, weight: .regular))
        .foregroundColor(Palette.textSecondary)
    }

    private var optionsList: some View {
        VStack(spacing: 4) {
            if let options = currentQuestion.options {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    PlanOptionRow(
                        index: index + 1,
                        label: option.label,
                        description: option.description,
                        isSelected: selectedOptionIndex == index,
                        onTap: { selectedOptionIndex = index }
                    )
                }
            }
            if currentQuestion.isOther == true {
                let otherIndex = currentQuestion.options?.count ?? 0
                if isOtherSelected {
                    PlanOtherFieldRow(
                        index: otherIndex + 1,
                        text: $otherText,
                        focused: $otherFocused
                    )
                } else {
                    PlanOptionRow(
                        index: otherIndex + 1,
                        label: "No, and tell the agent what to do differently",
                        description: nil,
                        isSelected: false,
                        muted: true,
                        onTap: { selectedOptionIndex = otherIndex }
                    )
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button {
                appState.dismissPlanQuestion(chatId: pending.chatId)
            } label: {
                HStack(spacing: 6) {
                    Text("Ignore")
                        .font(BodyFont.system(size: 12.5, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                    Text("ESC")
                        .font(BodyFont.system(size: 11, wght: 700))
                        .foregroundColor(Color(white: 0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                submitCurrent()
            } label: {
                HStack(spacing: 6) {
                    Text("Send")
                        .font(BodyFont.system(size: 12.5, wght: 700))
                    Image(systemName: "return")
                        .font(BodyFont.system(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.white.opacity(0.18))
                        )
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(canSubmit
                              ? Color(red: 0.34, green: 0.62, blue: 1.0)
                              : Color(red: 0.34, green: 0.62, blue: 1.0).opacity(0.45))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
    }

    // MARK: - Behaviour

    /// Submission is allowed once the user has either picked a regular
    /// option or filled the free-text field with non-whitespace text.
    private var canSubmit: Bool {
        if isOtherSelected {
            return !otherText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return rowCount > 0
    }

    private func submitCurrent() {
        guard canSubmit else { return }
        let answerStrings: [String]
        if isOtherSelected {
            answerStrings = [otherText.trimmingCharacters(in: .whitespacesAndNewlines)]
        } else if let options = currentQuestion.options,
                  options.indices.contains(selectedOptionIndex) {
            answerStrings = [options[selectedOptionIndex].label]
        } else {
            answerStrings = []
        }

        // If the request carried multiple questions, advance to the next
        // one and keep the card open with fresh state. Once we've
        // answered the last question, ship the full answers map back.
        var staged: [String: [String]] = stagedAnswers
        staged[currentQuestion.id] = answerStrings
        if questionIndex + 1 < pending.questions.count {
            stagedAnswers = staged
            questionIndex += 1
            selectedOptionIndex = 0
            otherText = ""
            return
        }
        appState.submitPlanAnswers(chatId: pending.chatId, answers: staged)
    }

    /// Answers accumulated so far when stepping through a multi-question
    /// request. Stored on the view via `@State` so it survives within a
    /// single mount; the wider AppState only sees the final map.
    @State private var stagedAnswers: [String: [String]] = [:]

    /// Hidden NSView that captures arrow key + Return + Escape and
    /// translates them into the same actions the buttons trigger. Sits
    /// behind the card so it doesn't steal mouse hits from real controls.
    private var planCardKeyHandler: some View {
        PlanCardKeyHandler(
            onMove: { delta in
                let count = rowCount
                guard count > 0 else { return }
                selectedOptionIndex = (selectedOptionIndex + delta + count) % count
            },
            onSubmit: { submitCurrent() },
            onCancel: { appState.dismissPlanQuestion(chatId: pending.chatId) }
        )
    }
}

// MARK: - Option row

private struct PlanOptionRow: View {
    let index: Int
    let label: String
    let description: String?
    let isSelected: Bool
    var muted: Bool = false
    let onTap: () -> Void

    @State private var hovered = false
    @State private var infoHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(index).")
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(muted ? Color(white: 0.40) : Color(white: 0.55))
                .frame(width: 18, alignment: .leading)

            Text(label)
                .font(BodyFont.system(size: 13.5, wght: isSelected ? 700 : 500))
                .foregroundColor(muted ? Color(white: 0.55) : Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            if description != nil {
                Image(systemName: "info.circle")
                    .font(BodyFont.system(size: 11, weight: .regular))
                    .foregroundColor(Color(white: 0.45))
                    .help(description ?? "")
                    .onHover { infoHovered = $0 }
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowFill)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { hovered = $0 }
    }

    private var rowFill: Color {
        if isSelected { return Color.white.opacity(0.06) }
        if hovered    { return Color.white.opacity(0.025) }
        return .clear
    }
}

// MARK: - Free-text "other" row

private struct PlanOtherFieldRow: View {
    let index: Int
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(index).")
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Color(white: 0.55))
                .frame(width: 18, alignment: .leading)
            TextField("", text: $text, prompt: Text("Tell the agent what to do instead")
                .foregroundColor(Color(white: 0.42)))
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 13.5, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .focused(focused)
                .onAppear { focused.wrappedValue = true }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}

// MARK: - Key handler

/// Invisible NSView that subscribes to keyDown for ↑/↓/Return/Escape and
/// forwards them as closures. Lives in the SwiftUI tree as the card's
/// background, becomes first responder on attach, and resigns when
/// removed so it doesn't fight the composer for keystrokes.
private struct PlanCardKeyHandler: NSViewRepresentable {
    var onMove: (Int) -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.onMove = onMove
        view.onSubmit = onSubmit
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.onMove = onMove
        nsView.onSubmit = onSubmit
        nsView.onCancel = onCancel
    }

    final class KeyView: NSView {
        var onMove: ((Int) -> Void)?
        var onSubmit: (() -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                if window.firstResponder is NSTextView { return }
                window.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 126: onMove?(-1)         // arrow up
            case 125: onMove?(1)          // arrow down
            case 36, 76: onSubmit?()      // return / numpad return
            case 53: onCancel?()          // escape
            default: super.keyDown(with: event)
            }
        }
    }
}
