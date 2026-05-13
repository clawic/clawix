import AppKit
import SwiftUI
import ClawixCore

struct UserMessageEditor: View {
    @Binding var text: String
    var onCancel: () -> Void
    var onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ComposerTextEditor(
                text: $text,
                contentHeight: .constant(0),
                autofocus: true,
                onSubmit: onSubmit
            )
            .frame(minHeight: 60)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(BodyFont.system(size: 13, wght: 500))
                        .foregroundColor(Palette.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(white: 0.22))
                        )
                }
                .buttonStyle(.plain)

                Button(action: onSubmit) {
                    Text("Send")
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(Color.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(white: 0.13))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(white: 0.22), lineWidth: 0.5)
        )
    }
}

struct ChatFooterPill: View {
    let icon: String
    let label: String
    let accessibilityLabel: String
    var isOpen: Bool = false
    var action: () -> Void = {}

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                IconImage(icon, size: 12)
                Text(verbatim: label)
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .lineLimit(1)
                LucideIcon(.chevronDown, size: 12)
            }
            .foregroundColor(Color(white: (hovered || isOpen) ? 0.82 : 0.55))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
    }
}

struct WorkLocallyMenuPopup: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelMenuHeader(String(localized: "Continue in", bundle: AppLocale.bundle, locale: AppLocale.current))

            WorkLocallyRow(
                icon: "desktopcomputer",
                label: String(localized: "Work locally", bundle: AppLocale.bundle, locale: AppLocale.current),
                trailing: .check
            ) {
                isPresented = false
            }
            WorkLocallyRow(
                icon: "gauge.with.dots.needle.33percent",
                label: String(localized: "Remaining usage limits", bundle: AppLocale.bundle, locale: AppLocale.current),
                trailing: .chevron
            ) {
                isPresented = false
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: 268, alignment: .leading)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isPresented))
    }
}

struct WorkLocallyRow: View {
    enum Trailing { case none, check, chevron }

    let icon: String
    let label: String
    var trailing: Trailing = .none
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                Group {
                    if icon == "chart.bar" || icon == "gauge.with.dots.needle.33percent" {
                        UsageIcon(size: 14)
                    } else {
                        LucideIcon.auto(icon, size: 13)
                    }
                }
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 18, alignment: .center)
                Text(verbatim: label)
                    .font(BodyFont.system(size: 13.5, wght: 500))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                switch trailing {
                case .none:
                    EmptyView()
                case .check:
                    CheckIcon(size: 11)
                        .foregroundColor(MenuStyle.rowText)
                case .chevron:
                    LucideIcon(.chevronRight, size: 11)
                        .font(BodyFont.system(size: MenuStyle.rowTrailingIconSize, weight: .semibold))
                        .foregroundColor(MenuStyle.rowSubtle)
                }
            }
            .padding(.leading, MenuStyle.rowHorizontalPadding)
            .padding(.trailing, MenuStyle.rowHorizontalPadding
                                + (trailing == .chevron ? MenuStyle.rowTrailingIconExtra : 0))
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

struct BranchPickerPopup: View {
    @Binding var isPresented: Bool
    @Binding var searchText: String
    let branches: [String]
    let currentBranch: String?
    let uncommittedFiles: Int?
    let onSelect: (String) -> Void
    let onCreate: () -> Void

    @FocusState private var searchFocused: Bool

    private var filtered: [String] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return branches }
        return branches.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                SearchIcon(size: 12)
                    .foregroundColor(MenuStyle.rowSubtle)
                TextField(
                    String(localized: "Search branches", bundle: AppLocale.bundle, locale: AppLocale.current),
                    text: $searchText
                )
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 13.5, wght: 500))
                .foregroundColor(MenuStyle.rowText)
                .focused($searchFocused)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            ModelMenuHeader(String(localized: "Branches", bundle: AppLocale.bundle, locale: AppLocale.current))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered, id: \.self) { branch in
                        BranchRow(
                            label: branch,
                            isCurrent: branch == currentBranch,
                            uncommittedFiles: branch == currentBranch ? uncommittedFiles : nil
                        ) {
                            onSelect(branch)
                        }
                    }
                }
            }
            .thinScrollers()
            .frame(maxHeight: 256)

            MenuStandardDivider()
                .padding(.vertical, 4)

            BranchCreateRow(action: onCreate)
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: 340, alignment: .leading)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isPresented))
        .onAppear { searchFocused = true }
    }
}

struct BranchRow: View {
    let label: String
    let isCurrent: Bool
    let uncommittedFiles: Int?
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                BranchIcon(size: 13)
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 18, alignment: .center)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: label)
                        .font(BodyFont.system(size: 13.5, wght: 500))
                        .foregroundColor(MenuStyle.rowText)
                        .lineLimit(1)
                    if let files = uncommittedFiles, files > 0 {
                        Text(verbatim: uncommittedLabel(files))
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .foregroundColor(MenuStyle.rowSubtle)
                    }
                }
                Spacer(minLength: 8)
                if isCurrent {
                    CheckIcon(size: 11)
                        .foregroundColor(MenuStyle.rowText)
                        .padding(.top, 1)
                }
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    private func uncommittedLabel(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "Uncommitted: 1 file", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        return String(format: String(localized: "Uncommitted: %d files", bundle: AppLocale.bundle, locale: AppLocale.current), count)
    }
}

struct BranchCreateRow: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                LucideIcon(.plus, size: 13)
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 18, alignment: .center)
                Text(verbatim: String(localized: "Create and switch to a new branch...", bundle: AppLocale.bundle, locale: AppLocale.current))
                    .font(BodyFont.system(size: 13.5, wght: 500))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

struct BranchCreateSheet: View {
    let initialName: String
    let onCancel: () -> Void
    let onCreate: (String) -> Void

    @State private var name: String
    @FocusState private var nameFocused: Bool

    init(initialName: String,
         onCancel: @escaping () -> Void,
         onCreate: @escaping (String) -> Void) {
        self.initialName = initialName
        self.onCancel = onCancel
        self.onCreate = onCreate
        self._name = State(initialValue: initialName)
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "Create and switch branch", bundle: AppLocale.bundle, locale: AppLocale.current))
                    .font(BodyFont.system(size: 20, weight: .medium))
                    .foregroundColor(Color(white: 0.97))
                Spacer(minLength: 12)
                Button(action: onCancel) {
                    LucideIcon(.x, size: 11)
                        .foregroundColor(Color(white: 0.70))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: "Close"))
            }
            .padding(.bottom, 18)

            HStack {
                Text(String(localized: "Branch name", bundle: AppLocale.bundle, locale: AppLocale.current))
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color(white: 0.78))
                Spacer(minLength: 8)
                Button {
                    // Prefix toggle is visual-only for now: same suggestion
                    // shape Clawix shows in screenshot.
                } label: {
                    Text(String(localized: "Set prefix", bundle: AppLocale.bundle, locale: AppLocale.current))
                        .font(BodyFont.system(size: 12.5, wght: 500))
                        .foregroundColor(Color(white: 0.55))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)

            TextField("", text: $name)
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 14, wght: 500))
                .foregroundColor(Color(white: 0.95))
                .focused($nameFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(white: 0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                )
                .padding(.bottom, 22)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button(action: onCancel) {
                    Text(String(localized: "Close", bundle: AppLocale.bundle, locale: AppLocale.current))
                }
                .buttonStyle(SheetCancelButtonStyle())

                Button {
                    guard !trimmed.isEmpty else { return }
                    onCreate(trimmed)
                } label: {
                    Text(String(localized: "Create and switch", bundle: AppLocale.bundle, locale: AppLocale.current))
                }
                .buttonStyle(SheetPrimaryButtonStyle(enabled: !trimmed.isEmpty))
                .disabled(trimmed.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(width: 460)
        .sheetStandardBackground()
        .onAppear { nameFocused = true }
    }
}
