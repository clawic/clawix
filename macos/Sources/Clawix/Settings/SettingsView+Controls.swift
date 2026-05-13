import SwiftUI

@MainActor
enum SettingsUtilities {
    static func revealDiagnosticsFolder() {
        ResourceSampler.persistLastSample()
        guard let file = ResourceSampler.diagnosticsFileURL(named: "last-resources.json") else {
            ToastCenter.shared.show("Diagnostics folder unavailable", icon: .error)
            return
        }
        let dir = file.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([dir])
        ToastCenter.shared.show("Diagnostics folder opened")
    }

    static func openConfigToml(scope: String, selectedProject: Project?) async {
        let projectPath = selectedProject?.path
        if scope == "Project settings", projectPath?.isEmpty ?? true {
            ToastCenter.shared.show("Select a project before opening project config", icon: .warning)
            return
        }
        do {
            let result = try ClawJSMCPClient().configPath(
                scope: scope == "Project settings" ? "project" : "user",
                projectPath: projectPath
            )
            guard result.exists else {
                ToastCenter.shared.show("config.toml not found", icon: .warning)
                return
            }
            NSWorkspace.shared.open(URL(fileURLWithPath: result.configPath))
            ToastCenter.shared.show("config.toml opened")
        } catch {
            ToastCenter.shared.show(error.localizedDescription, icon: .error)
        }
    }
}

struct PillToggle: View {
    @Binding var isOn: Bool

    private let trackWidth: CGFloat = 34
    private let trackHeight: CGFloat = 20
    private let knobSize: CGFloat = 16
    private let inset: CGFloat = 2

    private var knobOffset: CGFloat {
        isOn ? trackWidth - knobSize - inset : inset
    }

    private var trackFill: Color {
        isOn ? Color(red: 0.16, green: 0.46, blue: 0.98) : Color(white: 0.22)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(trackFill)
            Circle()
                .fill(Color.white)
                .frame(width: knobSize, height: knobSize)
                .shadow(color: .black.opacity(0.20), radius: 1, x: 0, y: 1)
                .offset(x: knobOffset)
        }
        .frame(width: trackWidth, height: trackHeight)
        .contentShape(Capsule(style: .continuous))
        .onTapGesture {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) {
                isOn.toggle()
            }
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? Text("On") : Text("Off"))
    }
}

struct SettingsDropdown<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var iconForOption: ((T) -> AnyView?)? = nil
    var descriptionForOption: ((T) -> String?)? = nil
    /// Optional view rendered inside the trigger, between the label
    /// and the chevron. Used by the Microphone row to inline the
    /// level meter with the device name.
    var trailingAccessory: (() -> AnyView)? = nil
    /// Minimum capsule width. The trigger will only ever be wider than
    /// this if its content (longest option's text + icon + chevron +
    /// padding) requires it.
    var minWidth: CGFloat = 160
    /// Kept for source compatibility with existing call sites; the
    /// trigger now sizes adaptively to its content, so this flag is a
    /// no-op. It can be deleted once nothing references it.
    var fillsWidth: Bool = false

    @State private var isOpen = false
    @State private var hovered = false

    private var currentLabel: String {
        options.first(where: { $0.0 == selection })?.1 ?? ""
    }

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 10) {
                // ZStack overlays a phantom layer (every option's
                // label, hidden) on top of the visible current
                // selection. The ZStack's intrinsic width is the max
                // of its children's widths, so the capsule is exactly
                // wide enough to display the LONGEST option without
                // truncation, regardless of which one is currently
                // selected. Keeps the trigger from jumping width when
                // the user picks a longer option.
                ZStack(alignment: .leading) {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                        triggerLabel(option: opt.0, label: opt.1)
                            .opacity(0)
                            .accessibilityHidden(true)
                    }
                    triggerLabel(option: selection, label: currentLabel)
                }
                Spacer(minLength: 8)
                if let accessory = trailingAccessory?() {
                    accessory
                }
                LucideIcon(.chevronDown, size: 11)
                    .foregroundColor(Palette.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(minWidth: minWidth, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                Capsule(style: .continuous)
                    .fill(hovered || isOpen
                          ? Color(white: 0.165)
                          : Color(white: 0.135))
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .anchorPreference(key: SettingsDropdownAnchorKey.self, value: .bounds) { $0 }
        .overlayPreferenceValue(SettingsDropdownAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if isOpen, let anchor {
                    let buttonFrame = proxy[anchor]
                    SettingsDropdownPopup(
                        options: options,
                        selection: $selection,
                        isOpen: $isOpen,
                        iconForOption: iconForOption,
                        descriptionForOption: descriptionForOption,
                        minWidth: buttonFrame.width
                    )
                    .anchoredPopupPlacement(
                        buttonFrame: buttonFrame,
                        proxy: proxy,
                        horizontal: .leading()
                    )
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(isOpen)
        }
        .animation(MenuStyle.openAnimation, value: isOpen)
        // Bubbles "any descendant dropdown is open" up the view tree so
        // wrappers (row, card, page) can apply `.zIndex` and keep the
        // popup above later siblings that would otherwise paint on top.
        .preference(key: SettingsDropdownOpenKey.self, value: isOpen)
    }

    @ViewBuilder
    private func triggerLabel(option: T, label: String) -> some View {
        HStack(spacing: 10) {
            if let icon = iconForOption?(option) {
                icon
            }
            Text(label)
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct SettingsDropdownOpenKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    /// Lifts this view above its layout siblings while any descendant
    /// `SettingsDropdown` is open, so the open popup paints over later
    /// siblings (next row, next card, next section). Apply on every
    /// layout level that has siblings the popup might extend into.
    func liftWhenSettingsDropdownOpen() -> some View {
        modifier(LiftWhenSettingsDropdownOpenModifier())
    }
}

struct LiftWhenSettingsDropdownOpenModifier: ViewModifier {
    @State private var hasOpenDropdown = false
    func body(content: Content) -> some View {
        content
            .zIndex(hasOpenDropdown ? 1 : 0)
            .onPreferenceChange(SettingsDropdownOpenKey.self) { hasOpenDropdown = $0 }
    }
}

struct SettingsRow<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            leading
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct SettingsDropdownAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct SettingsDropdownPopup<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    @Binding var isOpen: Bool
    var iconForOption: ((T) -> AnyView?)? = nil
    var descriptionForOption: ((T) -> String?)? = nil
    let minWidth: CGFloat

    @State private var hoveredIndex: Int? = nil

    private var hasAnyDescription: Bool {
        guard let resolver = descriptionForOption else { return false }
        return options.contains { resolver($0.0)?.isEmpty == false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                Button {
                    selection = opt.0
                    isOpen = false
                } label: {
                    HStack(alignment: hasAnyDescription ? .top : .center, spacing: 10) {
                        if let icon = iconForOption?(opt.0) {
                            icon
                        }
                        if hasAnyDescription {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(opt.1)
                                    .font(BodyFont.system(size: 13, wght: 600))
                                    .foregroundColor(MenuStyle.rowText)
                                    .lineLimit(1)
                                if let desc = descriptionForOption?(opt.0), !desc.isEmpty {
                                    Text(desc)
                                        .font(BodyFont.system(size: 11.5, wght: 500))
                                        .foregroundColor(MenuStyle.rowSubtle)
                                        .lineLimit(1)
                                }
                            }
                        } else {
                            Text(opt.1)
                                .font(BodyFont.system(size: 12.5))
                                .foregroundColor(MenuStyle.rowText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if opt.0 == selection {
                            CheckIcon(size: 11)
                                .foregroundColor(MenuStyle.rowText)
                                .padding(.top, hasAnyDescription ? 3 : 0)
                        }
                    }
                    .padding(.horizontal, MenuStyle.rowHorizontalPadding)
                    .padding(.vertical, hasAnyDescription ? 8 : MenuStyle.rowVerticalPadding)
                    .background(MenuRowHover(active: hoveredIndex == idx))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { hoveredIndex = idx }
                    else if hoveredIndex == idx { hoveredIndex = nil }
                }
            }
        }
        .frame(minWidth: minWidth, alignment: .leading)
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isOpen))
    }
}

struct SegmentedRow<T: Hashable>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    let options: [(T, String)]
    @Binding var selection: T
    var width: CGFloat = 190

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RowLabel(title: title, detail: detail)
            Spacer(minLength: 12)
            SlidingSegmented(selection: $selection, options: options)
                .frame(width: width)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct ActionPillRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    let primaryLabel: LocalizedStringKey
    var trailingDisabled: LocalizedStringKey? = nil
    var isEnabled = true
    let onPrimary: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RowLabel(title: title, detail: detail)
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                if let trailingDisabled {
                    Text(trailingDisabled)
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                Button(action: onPrimary) {
                    Text(primaryLabel)
                        .font(BodyFont.system(size: 12, wght: 600))
                        .foregroundColor(isEnabled ? Palette.textPrimary : Palette.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct SlidingSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    var animation: Animation = .snappy(duration: 0.32, extraBounce: 0)
    var height: CGFloat = 30
    var fontSize: CGFloat = 11.5

    private var selectedIndex: CGFloat {
        CGFloat(options.firstIndex(where: { $0.0 == selection }) ?? 0)
    }

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 3
            let chipW = max(0, (geo.size.width - inset * 2) / CGFloat(options.count))

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.black.opacity(0.30))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .frame(width: chipW, height: height - inset * 2)
                    .offset(x: inset + selectedIndex * chipW, y: inset)
                    .animation(animation, value: selection)

                HStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                        let isOn = opt.0 == selection
                        Button {
                            selection = opt.0
                        } label: {
                            Text(verbatim: opt.1)
                                .font(BodyFont.system(size: fontSize, weight: isOn ? .medium : .regular))
                                .foregroundColor(isOn ? Palette.textPrimary : Palette.textSecondary)
                                .frame(width: chipW, height: height - inset * 2)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(inset)
            }
        }
        .frame(height: height)
    }
}
