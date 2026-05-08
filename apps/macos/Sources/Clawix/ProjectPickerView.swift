import SwiftUI

struct ProjectPickerView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader("Project")

            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(appState.projects) { project in
                        ProjectRow(
                            project: project,
                            isSelected: appState.selectedProject?.id == project.id
                        ) {
                            appState.selectedProject = project
                        }
                    }

                    Button {
                    } label: {
                        HStack(spacing: 10) {
                            LucideIcon(.plus, size: 13)
                                .foregroundColor(Palette.textSecondary)
                                .frame(width: 36, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Palette.cardFill)
                                )
                            Text("Add project…")
                                .font(BodyFont.system(size: 13, wght: 500))
                                .foregroundColor(Palette.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Palette.border, style: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add project")
                }
                .padding(.horizontal, 24)
            }
            .thinScrollers()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}

private struct ProjectRow: View {
    let project: Project
    let isSelected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                LucideIcon(.folder, size: 16, filled: true)
                    .foregroundColor(isSelected ? Color.accentColor : Palette.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.15) : Palette.cardFill)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name)
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Text(project.path)
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textTertiary)
                }

                Spacer()

                if isSelected {
                    LucideIcon(.check, size: 11)
                        .foregroundColor(Color.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.06) : (hovered ? Palette.cardHover : Palette.cardFill))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? Color.accentColor.opacity(0.3) : Palette.border, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(project.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

}
