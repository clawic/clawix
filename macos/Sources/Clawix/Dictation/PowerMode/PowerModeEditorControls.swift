import SwiftUI

struct EditorSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(BodyFont.system(size: 12, wght: 700))
                .foregroundColor(Palette.textSecondary)
                .textCase(.uppercase)
            content
        }
    }
}

struct EditorRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            content
        }
    }
}

struct EditorLabel: View {
    let text: LocalizedStringKey
    var body: some View {
        Text(text)
            .font(BodyFont.system(size: 12.5, wght: 500))
            .foregroundColor(Palette.textPrimary)
            .frame(width: 180, alignment: .leading)
    }
}

struct EditorTagList: View {
    let title: LocalizedStringKey
    let placeholder: LocalizedStringKey
    @Binding var draft: String
    @Binding var items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(BodyFont.system(size: 11.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
            }
            HStack(spacing: 8) {
                TextField(placeholder, text: $draft)
                    .textFieldStyle(.plain)
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(editorFieldBackground(radius: 6))
                    .onSubmit(submit)
                Button(action: submit) {
                    LucideIcon(.plus, size: 13)
                        .foregroundColor(canSubmit ? Palette.textPrimary : Palette.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color(white: 0.18)))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
            FlowingChips(items: items, onDelete: { idx in
                items.remove(at: idx)
            })
        }
    }

    private var canSubmit: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !items.contains(trimmed) {
            items.append(trimmed)
        }
        draft = ""
    }
}

struct FlowingChips: View {
    let items: [String]
    let onDelete: (Int) -> Void

    var body: some View {
        if items.isEmpty {
            Text("None yet")
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(Palette.textSecondary)
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 130), spacing: 6)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(spacing: 6) {
                        Text(item)
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .foregroundColor(Palette.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            onDelete(idx)
                        } label: {
                            LucideIcon(.x, size: 10)
                                .foregroundColor(Palette.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule(style: .continuous).fill(Color(white: 0.14)))
                }
            }
        }
    }
}

func editorFieldBackground(radius: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
        .fill(Color(white: 0.06))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
}
