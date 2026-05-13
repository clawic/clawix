import SwiftUI

struct AppearancePage: View {
    @State private var theme: ThemeMode = .system
    @State private var lightAccent: String = "#0169CC"
    @State private var lightBg: String = "#FFFFFF"
    @State private var lightFg: String = "#0D0D0D"
    @State private var lightTranslucent: Bool = true
    @State private var lightContrast: Double = 45
    @State private var darkAccent: String = "#0169CC"
    @State private var darkBg: String = "#111111"
    @State private var darkFg: String = "#FCFCFC"
    @State private var darkTranslucent: Bool = true
    @State private var darkContrast: Double = 57
    @State private var pointerCursors: Bool = false
    @State private var fontSize: String = "14"
    @State private var fontSmoothing: Bool = true

    enum ThemeMode: Hashable { case light, dark, system }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Appearance")

            // Theme switcher card
            SettingsCard {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Theme")
                            .font(BodyFont.system(size: 13, wght: 500))
                            .foregroundColor(Palette.textPrimary)
                        Text("Use light, dark, or system appearance")
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 6) {
                        ThemeChip(icon: "sun.max", label: "Light", isOn: theme == .light) { theme = .light }
                        ThemeChip(icon: "moon", label: "Dark", isOn: theme == .dark) { theme = .dark }
                        ThemeChip(icon: "laptopcomputer", label: "System", isOn: theme == .system) { theme = .system }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)

                CardDivider()

                ThemePreviewDiff()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
            .padding(.bottom, 14)

            // Light theme
            ThemeSubSection(
                title: "Light theme",
                accentHex: $lightAccent,
                bgHex: $lightBg,
                fgHex: $lightFg,
                translucent: $lightTranslucent,
                contrast: $lightContrast,
                bgPreview: Color.white,
                fgPreview: Color.black
            )
            .padding(.bottom, 14)

            // Dark theme
            ThemeSubSection(
                title: "Dark theme",
                accentHex: $darkAccent,
                bgHex: $darkBg,
                fgHex: $darkFg,
                translucent: $darkTranslucent,
                contrast: $darkContrast,
                bgPreview: Color(white: 0.07),
                fgPreview: Color.white
            )
            .padding(.bottom, 14)

            SettingsCard {
                ToggleRow(
                    title: "Use pointer cursors",
                    detail: "Switch the cursor to a pointer over interactive elements",
                    isOn: $pointerCursors
                )
                CardDivider()
                FontSizeRow(value: $fontSize)
                CardDivider()
                ToggleRow(
                    title: "Font smoothing",
                    detail: "Use the native macOS font smoothing",
                    isOn: $fontSmoothing
                )
            }
        }
    }
}

struct ThemeChip: View {
    let icon: String
    let label: LocalizedStringKey
    let isOn: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                LucideIcon.auto(icon, size: 11)
                Text(label)
                    .font(BodyFont.system(size: 12, wght: 500))
            }
            .foregroundColor(isOn ? Palette.textPrimary : Palette.textSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isOn ? Color.white.opacity(0.10) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ThemePreviewDiff: View {
    var body: some View {
        HStack(spacing: 0) {
            DiffSide(
                lines: [
                    (.gutter, "1", "const themePreview: ThemeConfig ="),
                    (.removed, "2", "  surface: \"sidebar\","),
                    (.removed, "3", "  accent: \"#2563eb\","),
                    (.removed, "4", "  contrast: 42,"),
                    (.gutter, "5", "};")
                ],
                isAdd: false
            )
            DiffSide(
                lines: [
                    (.gutter, "1", "const themePreview: ThemeConfig ="),
                    (.added, "2", "  surface: \"sidebar-elevated\","),
                    (.added, "3", "  accent: \"#0ea5e9\","),
                    (.added, "4", "  contrast: 68,"),
                    (.gutter, "5", "};")
                ],
                isAdd: true
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        )
    }
}

enum DiffLineKind { case gutter, added, removed }

struct DiffSide: View {
    let lines: [(DiffLineKind, String, String)]
    let isAdd: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                let (kind, num, text) = l
                HStack(spacing: 10) {
                    Text(num)
                        .font(BodyFont.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(white: 0.45))
                        .frame(width: 22, alignment: .trailing)
                    Text(text)
                        .font(BodyFont.system(size: 11.5, design: .monospaced))
                        .foregroundColor(textColor(kind: kind))
                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(rowBackground(kind: kind))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func textColor(kind: DiffLineKind) -> Color {
        switch kind {
        case .gutter:  return Color(white: 0.65)
        case .added:   return Color(red: 0.55, green: 0.95, blue: 0.65)
        case .removed: return Color(red: 1.0, green: 0.55, blue: 0.55)
        }
    }

    private func rowBackground(kind: DiffLineKind) -> Color {
        switch kind {
        case .gutter:  return .clear
        case .added:   return Color(red: 0.10, green: 0.30, blue: 0.15).opacity(0.55)
        case .removed: return Color(red: 0.35, green: 0.10, blue: 0.10).opacity(0.55)
        }
    }
}

struct ThemeSubSection: View {
    let title: LocalizedStringKey
    @Binding var accentHex: String
    @Binding var bgHex: String
    @Binding var fgHex: String
    @Binding var translucent: Bool
    @Binding var contrast: Double
    let bgPreview: Color
    let fgPreview: Color

    @State private var themeFont: String = "Clawix"

    var body: some View {
        SettingsCard {
            HStack(alignment: .center, spacing: 16) {
                Text(title)
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer(minLength: 8)
                Text("Import")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                Text("Copy theme")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                SettingsDropdown(
                    options: [("Clawix", "Clawix"), ("Mono", "Mono"), ("Sans", "Sans")],
                    selection: $themeFont,
                    minWidth: 130
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            CardDivider()
            ColorRow(title: "Accent color", hex: $accentHex, swatch: Color(red: 0.0, green: 0.42, blue: 0.85))
            CardDivider()
            ColorRow(title: "Background color", hex: $bgHex, swatch: bgPreview)
            CardDivider()
            ColorRow(title: "Foreground color", hex: $fgHex, swatch: fgPreview)
            CardDivider()
            FontFieldRow(title: "Interface font", value: "-apple-system, BlinkM")
            CardDivider()
            ToggleRow(title: "Translucent sidebar", detail: nil, isOn: $translucent)
            CardDivider()
            SliderRow(title: "Contrast", value: $contrast, range: 0...100)
        }
    }
}

struct ColorRow: View {
    let title: LocalizedStringKey
    @Binding var hex: String
    let swatch: Color

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Palette.textPrimary)
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.black.opacity(0.20), lineWidth: 0.5))
                Text(hex)
                    .font(BodyFont.system(size: 12, design: .monospaced))
                    .foregroundColor(swatch == .white || swatch == Color.white
                                     ? Color.black
                                     : Palette.textPrimary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(swatch)
                    .overlay(
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
            .frame(width: 170)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct FontFieldRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Palette.textPrimary)
            Spacer(minLength: 12)
            Text(value)
                .font(BodyFont.system(size: 12, design: .monospaced))
                .foregroundColor(Palette.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .frame(width: 170, alignment: .leading)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct SliderRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Palette.textPrimary)
            Spacer(minLength: 12)
            Slider(value: $value, in: range)
                .frame(width: 220)
                .tint(Color(red: 0.30, green: 0.55, blue: 1.0))
            Text("\(Int(value))")
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct FontSizeRow: View {
    @Binding var value: String

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Interface font size")
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text("Adjust the base size used for the Clawix interface")
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                TextField("", text: $value)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(BodyFont.system(size: 12, design: .monospaced))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(width: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                    )
                Text("px")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
