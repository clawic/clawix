import SwiftUI
import AppKit

struct EditorOption: Identifiable, Hashable {
    var id: String { bundleId }
    let bundleId: String
    let name: String
    let fallbackPath: String
}

private let clawixEditors: [EditorOption] = [
    .init(bundleId: "com.microsoft.VSCode", name: "VS Code",
          fallbackPath: "/Applications/Visual Studio Code.app"),
    .init(bundleId: "com.todesktop.230313mzl4w4u92", name: "Cursor",
          fallbackPath: "/Applications/Cursor.app"),
    .init(bundleId: "com.apple.finder", name: "Finder",
          fallbackPath: "/System/Library/CoreServices/Finder.app"),
    .init(bundleId: "com.apple.Terminal", name: "Terminal",
          fallbackPath: "/System/Applications/Utilities/Terminal.app"),
    .init(bundleId: "com.mitchellh.ghostty", name: "Ghostty",
          fallbackPath: "/Applications/Ghostty.app"),
    .init(bundleId: "com.apple.dt.Xcode", name: "Xcode",
          fallbackPath: "/Applications/Xcode.app"),
    .init(bundleId: "com.google.android.studio", name: "Android Studio",
          fallbackPath: "/Applications/Android Studio.app"),
]

struct AppIconImage: View {
    let bundleId: String
    let fallbackPath: String
    let size: CGFloat

    var body: some View {
        Group {
            if let nsImage = Self.resolveIcon(bundleId: bundleId, fallbackPath: fallbackPath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(white: 0.20))
            }
        }
        .frame(width: size, height: size)
    }

    static func resolveIcon(bundleId: String, fallbackPath: String) -> NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if FileManager.default.fileExists(atPath: fallbackPath) {
            return NSWorkspace.shared.icon(forFile: fallbackPath)
        }
        return nil
    }
}

struct EditorPickerDropdown: View {
    /// Absolute folder path to open with the chosen app. When `nil`, the
    /// dropdown is hidden entirely (the user is in "Work on a Project"
    /// mode and there is no real folder context to open).
    let folderPath: String?

    @State private var isOpen = false
    @State private var hoverTrigger = false

    private var triggerEditor: EditorOption {
        clawixEditors.first { $0.name == "Finder" } ?? clawixEditors[0]
    }

    var body: some View {
        if let folderPath {
            Button {
                isOpen.toggle()
            } label: {
                HStack(spacing: 5) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(white: 0.22))
                        AppIconImage(
                            bundleId: triggerEditor.bundleId,
                            fallbackPath: triggerEditor.fallbackPath,
                            size: 16
                        )
                    }
                    .frame(width: 22, height: 22)

                    Image(systemName: "chevron.down")
                        .font(BodyFont.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(white: 0.60))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            (hoverTrigger || isOpen)
                                ? Color.white.opacity(MenuStyle.rowHoverIntensity)
                                : Color.clear
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hoverTrigger = $0 }
            .animation(.easeOut(duration: 0.12), value: hoverTrigger)
            .accessibilityLabel("Open folder with")
            .anchorPreference(key: EditorPickerAnchorKey.self, value: .bounds) { $0 }
            .overlayPreferenceValue(EditorPickerAnchorKey.self) { anchor in
                GeometryReader { proxy in
                    if isOpen, let anchor {
                        let buttonFrame = proxy[anchor]
                        let popupWidth: CGFloat = 220
                        EditorPickerMenu(folderPath: folderPath, isOpen: $isOpen)
                            .frame(width: popupWidth)
                            .anchoredPopupPlacement(
                                buttonFrame: buttonFrame,
                                proxy: proxy,
                                horizontal: .trailing()
                            )
                            .transition(.softNudge(y: 4))
                    }
                }
                .allowsHitTesting(isOpen)
            }
            .animation(MenuStyle.openAnimation, value: isOpen)
        }
    }
}

private struct EditorPickerAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

private struct EditorPickerMenu: View {
    let folderPath: String
    @Binding var isOpen: Bool
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelMenuHeader("Open with")

            ForEach(clawixEditors) { editor in
                Button {
                    openFolder(folderPath, with: editor)
                    isOpen = false
                } label: {
                    HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                        AppIconImage(
                            bundleId: editor.bundleId,
                            fallbackPath: editor.fallbackPath,
                            size: 18
                        )
                        .frame(width: 22, alignment: .center)
                        Text(editor.name)
                            .font(BodyFont.system(size: 13.5))
                            .foregroundColor(MenuStyle.rowText)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, MenuStyle.rowHorizontalPadding)
                    .padding(.vertical, MenuStyle.rowVerticalPadding)
                    .background(MenuRowHover(active: hovered == editor.id))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { hovered = editor.id }
                    else if hovered == editor.id { hovered = nil }
                }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isOpen))
    }

    private func openFolder(_ path: String, with editor: EditorOption) {
        let folderURL = URL(fileURLWithPath: path, isDirectory: true)
        let appURL: URL? =
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleId)
            ?? (FileManager.default.fileExists(atPath: editor.fallbackPath)
                ? URL(fileURLWithPath: editor.fallbackPath)
                : nil)

        guard let appURL else {
            NSWorkspace.shared.open(folderURL)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [folderURL],
            withApplicationAt: appURL,
            configuration: configuration,
            completionHandler: nil
        )
    }
}
