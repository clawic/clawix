import SwiftUI
import AppKit

/// Right-hand inspector for the editor. Renders controls contextual to
/// the currently selected slot. When nothing is selected, surfaces
/// document-level metadata (style picker, variant picker, name).
struct EditorInspector: View {
    @Binding var document: EditorDocument
    let template: TemplateManifest
    let style: StyleManifest
    let selectedSlotId: String?
    let availableStyles: [StyleManifest]
    var onAssetPick: (String, URL) -> Void
    var onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let slot = selectedSlot {
                slotHeader(slot)
                slotControls(slot)
            } else {
                documentControls
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var selectedSlot: TemplateSlot? {
        guard let id = selectedSlotId else { return nil }
        return template.slots.first { $0.id == id }
    }

    private func slotHeader(_ slot: TemplateSlot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: slotIcon(slot.kind))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Palette.pastelBlue)
                Text(slot.label)
                    .font(BodyFont.system(size: 15, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Text(slot.kind.rawValue.uppercased())
                    .font(BodyFont.system(size: 9, wght: 700))
                    .foregroundColor(Color(white: 0.55))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            Text(slot.id)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(white: 0.55))
        }
    }

    @ViewBuilder
    private func slotControls(_ slot: TemplateSlot) -> some View {
        switch slot.kind {
        case .heading, .subheading, .button, .metric:
            textField(slot, multiline: false)
        case .body, .quote, .table:
            textField(slot, multiline: true)
        case .list:
            listControls(slot)
        case .image, .logo:
            imageControls(slot)
        case .divider, .shape:
            emptyHint("Decorative slot. No content to edit.")
        }
        if let max = slot.maxLength {
            captionRow("Max length", "\(max) chars")
        }
        if let max = slot.maxItems {
            captionRow("Max items", "\(max)")
        }
    }

    private func textField(_ slot: TemplateSlot, multiline: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Content")
            let binding = textBinding(for: slot.id, placeholder: slot.placeholder ?? "")
            if multiline {
                TextEditor(text: binding)
                    .scrollContentBackground(.hidden)
                    .font(BodyFont.system(size: 13, wght: 400))
                    .foregroundColor(Color(white: 0.92))
                    .frame(minHeight: 120)
                    .padding(10)
                    .background(controlBackground)
            } else {
                TextField(slot.placeholder ?? "", text: binding)
                    .textFieldStyle(.plain)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color(white: 0.92))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(controlBackground)
            }
        }
    }

    private func listControls(_ slot: TemplateSlot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Items")
            let items = document.data[slot.id]?.asItems ?? []
            ForEach(Array(items.enumerated()), id: \.offset) { index, _ in
                HStack(spacing: 6) {
                    Text("\(index + 1).")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(white: 0.55))
                    TextField("Item \(index + 1)", text: itemBinding(slot.id, index: index))
                        .textFieldStyle(.plain)
                        .font(BodyFont.system(size: 13, wght: 500))
                        .foregroundColor(Color(white: 0.92))
                    Button {
                        removeItem(slot.id, at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(white: 0.55))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(controlBackground)
            }
            Button {
                appendItem(slot.id, max: slot.maxItems)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Add item")
                        .font(BodyFont.system(size: 12, wght: 600))
                }
                .foregroundColor(Palette.pastelBlue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Palette.pastelBlue.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .disabled(items.count >= (slot.maxItems ?? 99))
        }
    }

    private func imageControls(_ slot: TemplateSlot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Asset")
            if let asset = document.data[slot.id]?.asAsset {
                HStack(spacing: 8) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Palette.pastelBlue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(asset.filename)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(Color(white: 0.85))
                            .lineLimit(1)
                        if let width = asset.width, let height = asset.height {
                            Text("\(Int(width)) × \(Int(height)) px")
                                .font(BodyFont.system(size: 10.5, wght: 500))
                                .foregroundColor(Color(white: 0.55))
                        }
                    }
                    Spacer()
                    Button {
                        document.data[slot.id] = .empty
                        onCommit()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(white: 0.65))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(controlBackground)
            }
            Button {
                pickAsset(slotId: slot.id)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Choose image…")
                        .font(BodyFont.system(size: 12, wght: 600))
                }
                .foregroundColor(Palette.pastelBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.pastelBlue.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var documentControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Document")
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("NAME")
                TextField("Untitled", text: documentNameBinding())
                    .textFieldStyle(.plain)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color(white: 0.92))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(controlBackground)
            }
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("STYLE")
                Picker("", selection: documentStyleBinding()) {
                    ForEach(availableStyles) { style in
                        Text(style.name).tag(style.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            if template.variants.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("VARIANT")
                    Picker("", selection: documentVariantBinding()) {
                        ForEach(template.variants) { v in
                            Text(v.label).tag(v.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
            Divider().opacity(0.18)
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("TEMPLATE")
                Text(template.name)
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Color(white: 0.85))
                Text("\(template.category.displayName) · \(template.aspect.displayLabel)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(white: 0.55))
            }
            emptyHint("Click a slot on the canvas to edit it.")
        }
    }

    // MARK: - Bindings

    private func textBinding(for slotId: String, placeholder: String) -> Binding<String> {
        Binding(
            get: { document.data[slotId]?.asText ?? "" },
            set: {
                document.data[slotId] = $0.isEmpty ? .empty : .text($0)
                onCommit()
            }
        )
    }

    private func itemBinding(_ slotId: String, index: Int) -> Binding<String> {
        Binding(
            get: {
                let items = document.data[slotId]?.asItems ?? []
                return items.indices.contains(index) ? items[index] : ""
            },
            set: { newValue in
                var items = document.data[slotId]?.asItems ?? []
                while items.count <= index { items.append("") }
                items[index] = newValue
                document.data[slotId] = .items(items)
                onCommit()
            }
        )
    }

    private func appendItem(_ slotId: String, max: Int?) {
        var items = document.data[slotId]?.asItems ?? []
        if let max, items.count >= max { return }
        items.append("New item")
        document.data[slotId] = .items(items)
        onCommit()
    }

    private func removeItem(_ slotId: String, at index: Int) {
        var items = document.data[slotId]?.asItems ?? []
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        document.data[slotId] = items.isEmpty ? .empty : .items(items)
        onCommit()
    }

    private func documentNameBinding() -> Binding<String> {
        Binding(
            get: { document.name },
            set: { document.name = $0; onCommit() }
        )
    }

    private func documentStyleBinding() -> Binding<String> {
        Binding(
            get: { document.styleId },
            set: { document.styleId = $0; onCommit() }
        )
    }

    private func documentVariantBinding() -> Binding<String> {
        Binding(
            get: { document.variantId ?? template.variants.first?.id ?? "default" },
            set: { document.variantId = $0; onCommit() }
        )
    }

    // MARK: - Asset picking

    private func pickAsset(slotId: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .png, .jpeg, .gif, .tiff, .heic, .webP]
        panel.message = "Pick an image for \(slotId)"
        if panel.runModal() == .OK, let url = panel.url {
            onAssetPick(slotId, url)
        }
    }

    // MARK: - Shared chrome

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(BodyFont.system(size: 10, wght: 700))
            .foregroundColor(Color(white: 0.55))
            .tracking(0.5)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(BodyFont.system(size: 9.5, wght: 700))
            .foregroundColor(Color(white: 0.50))
            .tracking(0.5)
    }

    private var controlBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Palette.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Palette.border, lineWidth: 0.5)
            )
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(BodyFont.system(size: 12, wght: 400))
            .foregroundColor(Color(white: 0.50))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
    }

    private func captionRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundColor(Color(white: 0.50))
            Spacer()
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(white: 0.65))
        }
    }

    private func slotIcon(_ kind: TemplateSlotKind) -> String {
        switch kind {
        case .heading:    return "textformat.size.larger"
        case .subheading: return "textformat.size"
        case .body:       return "text.alignleft"
        case .list:       return "list.bullet"
        case .quote:      return "quote.opening"
        case .metric:     return "chart.bar"
        case .image:      return "photo"
        case .logo:       return "sparkles"
        case .button:     return "rectangle.fill"
        case .divider:    return "minus"
        case .shape:      return "circle.dashed"
        case .table:      return "tablecells"
        }
    }
}
