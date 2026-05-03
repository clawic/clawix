import SwiftUI
import AppKit

/// Pill card rendered under an assistant message for every file the agent
/// touched during the turn (apply_patch). Layout matches Codex Desktop:
/// a square doc icon, the file name + "Document · MD" subtitle, and a
/// trailing "Open ⌄" pill that pops a menu of editors.
struct ChangedFileCard: View {
    let path: String

    @EnvironmentObject var appState: AppState
    @State private var hovered = false
    @State private var menuOpen = false

    private var fileURL: URL { URL(fileURLWithPath: path) }
    private var fileName: String { fileURL.lastPathComponent }
    private var subtitle: String {
        let ext = fileURL.pathExtension
        let kind = String(localized: "Document",
                          bundle: AppLocale.bundle,
                          locale: AppLocale.current)
        if ext.isEmpty { return kind }
        return "\(kind) · \(ext.uppercased())"
    }

    var body: some View {
        HStack(spacing: 12) {
            iconBadge
            VStack(alignment: .leading, spacing: 4) {
                Text(fileName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(white: 0.55))
            }
            Spacer(minLength: 8)
            openPill
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(hovered ? 0.07 : 0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Whole card opens the file in the sidebar preview. The chevron
        // declares its own gesture below, which SwiftUI evaluates first
        // and therefore won't fall through to this handler.
        .onTapGesture {
            appState.openFileInSidebar(path)
        }
        .onHover { hovered = $0 }
        // Smoother, slightly longer easing so the highlight breathes
        // instead of snapping in/out of hover.
        .animation(.easeInOut(duration: 0.22), value: hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(fileName), \(subtitle)"))
    }

    // MARK: - Icon

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.07))
                .frame(width: 44, height: 44)
            FileChipIcon(size: 18)
                .foregroundColor(Color(white: 0.82))
        }
    }

    // MARK: - Open pill

    /// Compact "Open ⌄" pill that mirrors the Codex Desktop card. The pill
    /// shows no fill or hover state of its own (the parent card handles
    /// hover for the whole row). The label is purely visual: tapping
    /// anywhere on the card runs the open-in-sidebar action. Only the
    /// chevron registers its own gesture so it can intercept the tap and
    /// pop the editor dropdown instead of falling through to the card.
    private var openPill: some View {
        HStack(spacing: 4) {
            Text(String(localized: "Open",
                        bundle: AppLocale.bundle,
                        locale: AppLocale.current))
                .font(.system(size: 12.5, weight: .regular))
                .foregroundColor(Color(white: 0.94))

            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color(white: 0.72))
                .padding(.leading, 2)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    menuOpen.toggle()
                }
                .accessibilityLabel("Open with…")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
        )
        .anchorPreference(key: ChangedFileMenuAnchorKey.self, value: .bounds) { $0 }
        .overlayPreferenceValue(ChangedFileMenuAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if menuOpen, let anchor {
                    let buttonFrame = proxy[anchor]
                    let popupWidth: CGFloat = 220
                    ChangedFileMenu(path: path, isOpen: $menuOpen)
                        .frame(width: popupWidth)
                        .offset(
                            x: buttonFrame.maxX - popupWidth,
                            y: buttonFrame.maxY + 6
                        )
                        .frame(maxWidth: .infinity,
                               maxHeight: .infinity,
                               alignment: .topLeading)
                        .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(menuOpen)
        }
        .animation(MenuStyle.openAnimation, value: menuOpen)
    }
}

// MARK: - Menu

private struct ChangedFileMenuAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

private struct ChangedFileMenu: View {
    let path: String
    @Binding var isOpen: Bool
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ChangedFileOpenAction.editorActions) { action in
                row(action)
            }
            MenuStandardDivider()
            row(.openInFolder)
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isOpen))
    }

    @ViewBuilder
    private func row(_ action: ChangedFileOpenAction) -> some View {
        Button {
            action.run(path: path)
            isOpen = false
        } label: {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                action.iconView
                    .frame(width: 22, alignment: .center)
                Text(action.title)
                    .font(.system(size: 13.5))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .background(MenuRowHover(active: hovered == action.id))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hovered = action.id }
            else if hovered == action.id { hovered = nil }
        }
    }
}

// MARK: - Open actions

private enum ChangedFileOpenAction: Identifiable {
    case editor(EditorOption)
    case defaultApp
    case openInFolder

    var id: String {
        switch self {
        case .editor(let e):  return "editor.\(e.bundleId)"
        case .defaultApp:     return "defaultApp"
        case .openInFolder:   return "openInFolder"
        }
    }

    var title: String {
        switch self {
        case .editor(let e):
            return e.name
        case .defaultApp:
            return String(localized: "Default app",
                          bundle: AppLocale.bundle,
                          locale: AppLocale.current)
        case .openInFolder:
            return String(localized: "Open in folder",
                          bundle: AppLocale.bundle,
                          locale: AppLocale.current)
        }
    }

    @ViewBuilder
    var iconView: some View {
        switch self {
        case .editor(let e):
            AppIconImage(bundleId: e.bundleId,
                         fallbackPath: e.fallbackPath,
                         size: 18)
        case .defaultApp:
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(white: 0.20))
                    .frame(width: 18, height: 18)
                Image(systemName: "app.badge")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color(white: 0.85))
            }
        case .openInFolder:
            AppIconImage(bundleId: "com.apple.finder",
                         fallbackPath: "/System/Library/CoreServices/Finder.app",
                         size: 18)
        }
    }

    func run(path: String) {
        let fileURL = URL(fileURLWithPath: path)
        switch self {
        case .editor(let editor):
            ChangedFileOpenAction.openInEditor(editor: editor, fileURL: fileURL)
        case .defaultApp:
            NSWorkspace.shared.open(fileURL)
        case .openInFolder:
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
    }

    private static func openInEditor(editor: EditorOption, fileURL: URL) {
        let appURL: URL? =
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleId)
            ?? (FileManager.default.fileExists(atPath: editor.fallbackPath)
                ? URL(fileURLWithPath: editor.fallbackPath)
                : nil)
        guard let appURL else {
            NSWorkspace.shared.open(fileURL)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [fileURL],
            withApplicationAt: appURL,
            configuration: configuration,
            completionHandler: nil
        )
    }

    /// Editor entries shown in the dropdown, in the same order as Codex
    /// Desktop's "Open with" menu.
    static let editorActions: [ChangedFileOpenAction] = [
        .editor(.init(bundleId: "com.microsoft.VSCode", name: "VS Code",
                      fallbackPath: "/Applications/Visual Studio Code.app")),
        .editor(.init(bundleId: "com.todesktop.230313mzl4w4u92", name: "Cursor",
                      fallbackPath: "/Applications/Cursor.app")),
        .defaultApp,
        .editor(.init(bundleId: "com.apple.Terminal", name: "Terminal",
                      fallbackPath: "/System/Applications/Utilities/Terminal.app")),
        .editor(.init(bundleId: "com.mitchellh.ghostty", name: "Ghostty",
                      fallbackPath: "/Applications/Ghostty.app")),
        .editor(.init(bundleId: "com.apple.dt.Xcode", name: "Xcode",
                      fallbackPath: "/Applications/Xcode.app")),
        .editor(.init(bundleId: "com.google.android.studio", name: "Android Studio",
                      fallbackPath: "/Applications/Android Studio.app")),
    ]
}
