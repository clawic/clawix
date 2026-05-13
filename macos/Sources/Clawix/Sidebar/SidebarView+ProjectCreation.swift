import SwiftUI
import UniformTypeIdentifiers

struct NewProjectAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct NewProjectPopup: View {
    @Binding var isPresented: Bool
    let onBlank: () -> Void
    let onPickFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewProjectPopupRow(icon: "plus", label: "Start from scratch", action: onBlank)
            NewProjectPopupRow(icon: "folder", label: "Use an existing folder", action: onPickFolder)
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: 244)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isPresented))
    }
}

struct NewProjectPopupRow: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                IconImage(icon, size: 11)
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 18, alignment: .center)
                Text(label)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(MenuStyle.rowText)
                Spacer()
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
    }
}

struct ProjectEditorContext: Identifiable {
    let id = UUID()
    let project: Project?
}
