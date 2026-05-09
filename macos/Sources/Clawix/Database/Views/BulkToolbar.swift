import SwiftUI

/// Bottom-anchored toolbar that appears when the user has multi-selected
/// rows. Offers Archive / Restore / Delete with a confirmation prompt.
struct BulkToolbar: View {
    let collection: DBCollection
    @Binding var selectedIds: Set<String>
    @EnvironmentObject private var manager: DatabaseManager
    @State private var confirmDelete: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text("\(selectedIds.count) selected")
                .font(BodyFont.system(size: 12, wght: 600))
                .foregroundColor(Palette.textPrimary)

            Spacer()

            Button("Archive") {
                Task { await applyArchive() }
            }
            .buttonStyle(.borderless)
            .font(BodyFont.system(size: 12, wght: 500))
            .foregroundColor(Palette.textSecondary)

            Button("Restore") {
                Task { await applyRestore() }
            }
            .buttonStyle(.borderless)
            .font(BodyFont.system(size: 12, wght: 500))
            .foregroundColor(Palette.textSecondary)

            Button("Delete") {
                confirmDelete = true
            }
            .buttonStyle(.borderless)
            .font(BodyFont.system(size: 12, wght: 500))
            .foregroundColor(.red)

            Button {
                selectedIds = []
            } label: {
                Image(systemName: "xmark")
                    .foregroundColor(Palette.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
        .alert("Delete \(selectedIds.count) records?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                Task { await applyDelete() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func applyArchive() async {
        let ids = Array(selectedIds)
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask {
                    try? await manager.archiveRecord(collection: collection.name, id: id)
                }
            }
        }
        selectedIds = []
    }

    private func applyRestore() async {
        let ids = Array(selectedIds)
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask {
                    try? await manager.restoreRecord(collection: collection.name, id: id)
                }
            }
        }
        selectedIds = []
    }

    private func applyDelete() async {
        let ids = Array(selectedIds)
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask {
                    try? await manager.deleteRecord(collection: collection.name, id: id)
                }
            }
        }
        selectedIds = []
    }
}
