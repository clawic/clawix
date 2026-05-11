import SwiftUI
import UIKit

/// iOS port of the right-hand inspector. Same controls per slot kind
/// as the desktop, but the image / logo asset picker is delegated to
/// the parent (which mounts a `PHPickerViewController` sheet) instead
/// of running its own `NSOpenPanel` modal.
struct EditorInspector: View {
    @Binding var document: EditorDocument
    let template: TemplateManifest
    let style: StyleManifest
    let selectedSlotId: String?
    let availableStyles: [StyleManifest]
    var resolveAssetURL: ((SlotAssetValue) -> URL?)? = nil
    var onPickAsset: (String) -> Void
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
                    .foregroundColor(Palette.unreadDot)
                Text(slot.label)
                    .font(BodyFont.manrope(size: 15, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Text(slot.kind.rawValue.uppercased())
                    .font(BodyFont.manrope(size: 9, wght: 700))
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
                    .font(BodyFont.manrope(size: 14, wght: 400))
                    .foregroundColor(Color(white: 0.92))
                    .frame(minHeight: 140)
                    .padding(10)
                    .background(controlBackground)
            } else {
                TextField(slot.placeholder ?? "", text: binding)
                    .textFieldStyle(.plain)
                    .font(BodyFont.manrope(size: 14, wght: 500))
                    .foregroundColor(Color(white: 0.92))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
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
                        .font(BodyFont.manrope(size: 14, wght: 500))
                        .foregroundColor(Color(white: 0.92))
                    Button {
                        removeItem(slot.id, at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(white: 0.55))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(controlBackground)
            }
            Button {
                appendItem(slot.id, max: slot.maxItems)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Add item")
                        .font(BodyFont.manrope(size: 13, wght: 600))
                }
                .foregroundColor(Palette.unreadDot)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.unreadDot.opacity(0.16))
                )
            }
            .buttonStyle(.plain)
            .disabled(items.count >= (slot.maxItems ?? 99))
        }
    }

    private func imageControls(_ slot: TemplateSlot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Asset")
            if let asset = document.data[slot.id]?.asAsset {
                AssetPreviewCard(asset: asset,
                                 url: resolveAssetURL?(asset),
                                 onClear: {
                                     Haptics.tap()
                                     document.data[slot.id] = .empty
                                     onCommit()
                                 })
            }
            Button {
                Haptics.selection()
                onPickAsset(slot.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 13, weight: .semibold))
                    Text(document.data[slot.id]?.asAsset == nil ? "Choose image…" : "Replace image…")
                        .font(BodyFont.manrope(size: 13, wght: 600))
                }
                .foregroundColor(Palette.unreadDot)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Palette.unreadDot.opacity(0.16))
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
                    .font(BodyFont.manrope(size: 14, wght: 500))
                    .foregroundColor(Color(white: 0.92))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
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
                    .font(BodyFont.manrope(size: 13, wght: 500))
                    .foregroundColor(Color(white: 0.85))
                Text("\(template.category.displayName) · \(template.aspect.displayLabel)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(white: 0.55))
            }
            emptyHint("Tap a slot on the canvas to edit it. Double-tap to edit text inline.")
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
            get: { document.data[slotId]?.asItems?[safeIndex: index] ?? "" },
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

    // MARK: - Shared chrome

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(BodyFont.manrope(size: 10, wght: 700))
            .foregroundColor(Color(white: 0.55))
            .tracking(0.5)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(BodyFont.manrope(size: 9.5, wght: 700))
            .foregroundColor(Color(white: 0.50))
            .tracking(0.5)
    }

    private var controlBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Palette.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Palette.border, lineWidth: 0.5)
            )
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(BodyFont.manrope(size: 12, wght: 400))
            .foregroundColor(Color(white: 0.50))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
    }

    private func captionRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(BodyFont.manrope(size: 11, wght: 600))
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

private extension Array {
    subscript(safeIndex index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Image preview block for the inspector. Follows the cross-project
/// rule for image selectors: inset animated from 0 → ~3pt on appear,
/// inner `ClipRRect` radius equal to outer − inset so both curves stay
/// concentric, and a `TweenAnimationBuilder`-style bounce zoom on each
/// asset change. Kept here (not in `GlassPill`) because the geometry
/// is design-system, not Liquid Glass chrome.
private struct AssetPreviewCard: View {
    let asset: SlotAssetValue
    let url: URL?
    let onClear: () -> Void

    @State private var inset: CGFloat = 0
    @State private var zoom: CGFloat = 0.9

    private let outerRadius: CGFloat = 14
    private let insetAmount: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                content
                    .padding(inset)
                    .scaleEffect(zoom)
                Button {
                    Haptics.tap()
                    onClear()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(white: 0.95))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.black.opacity(0.60)))
                }
                .buttonStyle(.plain)
                .padding(8)
            }
            .background(
                RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                    .fill(Palette.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                            .stroke(Palette.border, lineWidth: 0.5)
                    )
            )
            HStack(spacing: 6) {
                Text(asset.filename)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(white: 0.55))
                    .lineLimit(1)
                if let w = asset.width, let h = asset.height {
                    Text("·  \(Int(w))×\(Int(h))")
                        .font(BodyFont.manrope(size: 10.5, wght: 500))
                        .foregroundColor(Color(white: 0.45))
                }
                Spacer()
            }
            .padding(.top, 8)
        }
        .id(asset.filename)
        .onAppear { applyAppearAnimations() }
        .onChange(of: asset.filename) { _, _ in
            zoom = 0.9
            applyAppearAnimations()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let url, let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: outerRadius - insetAmount, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: outerRadius - insetAmount, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                Image(systemName: "photo")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(Color(white: 0.55))
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
        }
    }

    private func applyAppearAnimations() {
        withAnimation(.easeOut(duration: 0.55)) {
            inset = insetAmount
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
            zoom = 1.0
        }
    }
}
