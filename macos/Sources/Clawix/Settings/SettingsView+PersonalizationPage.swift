import SwiftUI

struct PersonalizationPage: View {
    @EnvironmentObject var flags: FeatureFlags
    @EnvironmentObject var appState: AppState
    @State private var expanded: Bool = false
    @State private var instructions: String = ""
    @State private var savedSnapshot: String = ""
    @State private var loadError: String? = nil
    @State private var saveError: String? = nil
    @State private var didLoad: Bool = false

    private var isDirty: Bool { instructions != savedSnapshot }

    private func localizedPersonalityLabel(_ personality: Personality) -> String {
        switch personality {
        case .friendly: return L10n.t("Friendly")
        case .pragmatic: return L10n.t("Pragmatic")
        }
    }

    private func localizedPersonalityBlurb(_ personality: Personality) -> String {
        switch personality {
        case .friendly: return L10n.t("Warm, collaborative, and helpful")
        case .pragmatic: return L10n.t("Concise, task-focused, and direct")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Personalization")

            SettingsCard {
                DropdownRow(
                    title: "Personality",
                    detail: "Choose a default tone for Clawix's responses",
                    options: Personality.allCases.map { ($0.rawValue, localizedPersonalityLabel($0)) },
                    selection: Binding(
                        get: { appState.personality.rawValue },
                        set: { newValue in
                            if let next = Personality(rawValue: newValue) {
                                appState.personality = next
                            }
                        }
                    ),
                    descriptionForOption: { key in
                        Personality(rawValue: key).map { localizedPersonalityBlurb($0) }
                    }
                )
            }
            .padding(.bottom, 28)

            Text("Custom instructions")
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text("Give Codex extra instructions and context for your project. Learn more")
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .padding(.bottom, 14)

            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(white: 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                InstructionsTextEditor(
                    text: $instructions,
                    isEditable: didLoad || loadError != nil
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                ExpandIconButton { expanded = true }
                    .padding(8)
            }
            .frame(height: 240)

            HStack(spacing: 10) {
                if let loadError {
                    Text("Could not load AGENTS.md: \(loadError)")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.55))
                } else if let saveError {
                    Text("Save failed: \(saveError)")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.55))
                } else if isDirty {
                    Text("Unsaved changes")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }
                Spacer()
                Button { save() } label: {
                    Text("Save")
                        .font(BodyFont.system(size: 12, wght: 600))
                        .foregroundColor(isDirty ? Palette.textPrimary : Palette.textSecondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(isDirty ? 0.12 : 0.06))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isDirty)
            }
            .padding(.top, 14)

            if flags.isVisible(.secrets) {
                SecretsCodexInjectionCard()
                    .padding(.top, 28)
            }
        }
        .onAppear { load() }
        .sheet(isPresented: $expanded) {
            InstructionsExpandedSheet(text: $instructions, isPresented: $expanded)
        }
    }

    private func load() {
        do {
            let text = try CodexInstructionsFile.read()
            instructions = text
            savedSnapshot = text
            loadError = nil
            didLoad = true
        } catch {
            loadError = error.localizedDescription
            didLoad = false
        }
    }

    private func save() {
        do {
            try CodexInstructionsFile.write(instructions)
            savedSnapshot = instructions
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}

struct InstructionsTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.scrollerInsets = NSEdgeInsets(top: 40, left: 0, bottom: 8, right: 0)

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let bigSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        let textContainer = NSTextContainer(size: bigSize)
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 4
        layoutManager.addTextContainer(textContainer)

        let textView = InstructionsNSTextView(frame: .zero, textContainer: textContainer)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = NSColor.white
        textView.insertionPointColor = NSColor.white
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.usesFindPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 12)
        textView.string = text
        textView.isEditable = isEditable

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEditable
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: InstructionsTextEditor
        init(_ parent: InstructionsTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let snapshot = textView.string
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.parent.text != snapshot {
                    self.parent.text = snapshot
                }
            }
        }
    }
}

struct ExpandIconButton: View {
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            CornerBracketsIcon(size: 12, variant: .expanded, lineWidth: 1.5)
                .foregroundColor(Color(white: hovered ? 0.95 : 0.78))
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(hovered ? 0.10 : 0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .hoverHint(L10n.t("Edit in large view"))
    }
}

final class InstructionsNSTextView: NSTextView {
    /// Square corner reserved for the overlay button, in screen-stable
    /// (visibleRect) coordinates. Matches `ExpandIconButton.padding(8)`
    /// plus its content size with a couple of pixels of slack.
    private let pointerCornerSize: CGFloat = 40

    private var pointerCornerRect: NSRect {
        let visible = visibleRect
        let s = pointerCornerSize
        return NSRect(x: visible.maxX - s, y: visible.minY, width: s, height: s)
    }

    override func cursorUpdate(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if pointerCornerRect.contains(p) {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if pointerCornerRect.contains(p) {
            NSCursor.pointingHand.set()
            return
        }
        super.mouseMoved(with: event)
    }
}

struct InstructionsExpandedSheet: View {
    @Binding var text: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Custom instructions")
                    .font(BodyFont.system(size: 14, wght: 700))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button { isPresented = false } label: {
                    LucideIcon(.x, size: 11)
                        .foregroundColor(Color(white: 0.78))
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            TextEditor(text: $text)
                .font(BodyFont.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(18)
                .background(Color(white: 0.06))

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            HStack {
                Spacer()
                Button { isPresented = false } label: {
                    Text("Done")
                        .font(BodyFont.system(size: 12, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.10))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 820, idealWidth: 980, maxWidth: 1200,
               minHeight: 600, idealHeight: 720, maxHeight: 900)
        .background(Color(white: 0.07))
    }
}
