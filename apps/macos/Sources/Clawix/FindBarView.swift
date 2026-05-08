import SwiftUI
import AppKit

/// Floating ⌘F find bar pinned to the top-trailing corner of the chat
/// view. Black HUD-style pill: lupa + query field + spinner while the
/// debounced search is in flight + close (×). Once the user types, a
/// second row appears below the divider with ↑ / ↓ navigation and the
/// match counter ("3 / 12 results"). When `findQuery` is non-empty
/// `AppState` populates `findMatches` and the chat renderer paints
/// every hit with a yellow highlight; the current match drives
/// `proxy.scrollTo` from `ChatView`.
struct FindBarView: View {
    @EnvironmentObject var appState: AppState
    @FocusState private var fieldFocused: Bool
    /// Decoupled from `appState.isFinding` so the spinner only takes
    /// over the trailing slot once a search has been running for long
    /// enough to feel like real work. Quick searches over a tiny
    /// transcript finish well before the threshold and the spinner
    /// never appears at all, mirroring how the sidebar's row spinner
    /// only paints when there's something genuinely loading.
    @State private var spinnerVisible: Bool = false

    private let cornerRadius: CGFloat = 16
    private let rowVerticalPadding: CGFloat = 10
    private let horizontalPadding: CGFloat = 14
    /// How long `appState.isFinding` must stay true before the spinner
    /// is allowed to flip on. Long enough that typing fast on a small
    /// chat shows nothing; short enough that a heavy chat (or a slow
    /// debounce flush) still gets visible feedback.
    private let spinnerRevealDelayMs: UInt64 = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            if !appState.findQuery.isEmpty {
                Divider()
                    .overlay(Color.white.opacity(0.08))
                bottomRow
            }
        }
        .background(barBackground)
        .overlay(barBorder)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.50), radius: 24, x: 0, y: 12)
        .frame(width: 380)
        .onAppear { Task { @MainActor in fieldFocused = true } }
        .task { fieldFocused = true }
        .onChange(of: appState.isFindBarOpen) { _, open in
            if open { fieldFocused = true }
        }
        .onChange(of: appState.findChatId) { _, _ in
            fieldFocused = true
        }
        .onChange(of: appState.isFinding) { _, finding in
            if finding {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: spinnerRevealDelayMs * 1_000_000)
                    // Re-check on landing: the search may have finished
                    // during the wait, in which case the spinner stays
                    // hidden and the lupa never gets displaced.
                    if appState.isFinding {
                        withAnimation(.easeOut(duration: 0.12)) {
                            spinnerVisible = true
                        }
                    }
                }
            } else {
                withAnimation(.easeOut(duration: 0.12)) {
                    spinnerVisible = false
                }
            }
        }
    }

    private var topRow: some View {
        HStack(spacing: 10) {
            SearchIcon(size: 13)
                .foregroundColor(Color.white.opacity(0.55))

            TextField("Search chat…", text: Binding(
                get: { appState.findQuery },
                set: { appState.updateFindQuery($0) }
            ))
            .font(BodyFont.system(size: 13.5, wght: 500))
            .foregroundColor(.white)
            .textFieldStyle(.plain)
            .focused($fieldFocused)
            .onSubmit { appState.nextFindMatch() }
            .accessibilityLabel("Find in chat")

            if spinnerVisible {
                FindBarSpinner()
                    .frame(width: 14, height: 14)
                    .transition(.opacity)
            }

            Button {
                appState.closeFindBar()
            } label: {
                LucideIcon(.x, size: 13)
                    .foregroundColor(Color.white.opacity(0.6))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close find bar")
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, rowVerticalPadding)
    }

    private var bottomRow: some View {
        HStack(spacing: 6) {
            navButton(systemName: "arrow.up", action: appState.prevFindMatch)
                .keyboardShortcut("g", modifiers: [.shift, .command])
                .accessibilityLabel("Previous match")
            navButton(systemName: "arrow.down", action: appState.nextFindMatch)
                .accessibilityLabel("Next match")

            Spacer(minLength: 8)

            Text(counterText)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Color.white.opacity(0.55))
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, rowVerticalPadding)
    }

    @ViewBuilder
    private func navButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon.auto(systemName, size: 13)
                .foregroundColor(appState.findMatches.isEmpty
                                 ? Color.white.opacity(0.25)
                                 : Color.white.opacity(0.75))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(appState.findMatches.isEmpty)
    }

    private var barBackground: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
            Color.black.opacity(0.78)
        }
    }

    private var barBorder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(Color.white.opacity(0.18), lineWidth: 0.7)
    }

    private var counterText: String {
        if appState.findMatches.isEmpty {
            return "0 results"
        }
        let total = appState.findMatches.count
        let pos = appState.currentFindIndex + 1
        return "\(pos) / \(total) results"
    }
}

// MARK: - Spinner

/// Thin rotating ring that mirrors the sidebar's `SidebarChatRowSpinner`
/// (Sources/Clawix/SidebarView.swift) so the find bar reads as part of
/// the same family. Same diameter, same stroke weight, same 2.4s
/// linear sweep, so toggling between sidebar and find feels visually
/// continuous instead of introducing a third loading idiom.
private struct FindBarSpinner: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18),
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            Circle()
                .trim(from: 0.0, to: 0.79)
                .stroke(Color.white.opacity(0.75),
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: 11, height: 11)
        .onAppear {
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Highlighting helpers

/// Wrap each occurrence of `query` (case-insensitive) inside `source`
/// with a yellow background. Returns the original string unchanged when
/// the query is empty or no match is found, so callers can call this
/// unconditionally without paying the AttributedString cost on the
/// no-find hot path.
@MainActor
func highlightedAttributed(_ source: String, query: String) -> AttributedString {
    guard !query.isEmpty else { return AttributedString(source) }
    let haystack = source as NSString
    var attr = AttributedString(source)
    var searchRange = NSRange(location: 0, length: haystack.length)
    while searchRange.location < haystack.length {
        let r = haystack.range(of: query, options: [.caseInsensitive], range: searchRange)
        if r.location == NSNotFound { break }
        if let range = Range(r, in: source),
           let attrRange = attr.range(of: source[range]) {
            attr[attrRange].backgroundColor = .yellow
            attr[attrRange].foregroundColor = .black
        }
        let next = r.location + max(r.length, 1)
        if next >= haystack.length { break }
        searchRange = NSRange(location: next, length: haystack.length - next)
    }
    return attr
}

/// True when `query` is non-empty and at least one case-insensitive
/// match exists in `source`. Lets renderers decide between the cheap
/// `Text(String)` path and the AttributedString path without producing
/// the AttributedString twice.
func substringMatches(_ source: String, query: String) -> Bool {
    guard !query.isEmpty else { return false }
    return source.range(of: query, options: [.caseInsensitive]) != nil
}
