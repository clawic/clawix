import SwiftUI

/// Left rail listing every slot in the template. Click selects the
/// slot and bubbles up via `onSelect`. Used as the navigation anchor
/// when the user prefers a flat list over clicking on the canvas.
struct EditorLayers: View {
    let template: TemplateManifest
    let document: EditorDocument
    let selectedSlotId: String?
    var onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(white: 0.55))
                Text("Layers")
                    .font(BodyFont.manrope(size: 11, wght: 700))
                    .foregroundColor(Color(white: 0.65))
                    .tracking(0.4)
                Spacer()
                Text("\(template.slots.count)")
                    .font(BodyFont.manrope(size: 11, wght: 600))
                    .foregroundColor(Color(white: 0.50))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider().opacity(0.18)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(template.slots) { slot in
                        layerRow(slot)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
        }
    }

    private func layerRow(_ slot: TemplateSlot) -> some View {
        let selected = slot.id == selectedSlotId
        return Button {
            onSelect(slot.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: slotIcon(slot.kind))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(selected ? Palette.unreadDot : Color(white: 0.75))
                    .frame(width: 18, alignment: .center)
                VStack(alignment: .leading, spacing: 1) {
                    Text(slot.label)
                        .font(BodyFont.manrope(size: 12.5, wght: selected ? 600 : 500))
                        .foregroundColor(selected ? Palette.textPrimary : Color(white: 0.85))
                        .lineLimit(1)
                    Text(summary(slot))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Color(white: 0.50))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func summary(_ slot: TemplateSlot) -> String {
        let value = document.data[slot.id]
        switch slot.kind {
        case .heading, .subheading, .body, .button, .metric, .quote, .table:
            if let text = value?.asText, !text.isEmpty {
                return text.prefix(28) + (text.count > 28 ? "…" : "")
            }
            return "[\(slot.kind.rawValue)]"
        case .list:
            let items = value?.asItems ?? []
            return items.isEmpty ? "[empty]" : "\(items.count) item\(items.count == 1 ? "" : "s")"
        case .image, .logo:
            if let asset = value?.asAsset {
                return asset.filename
            }
            return "no asset"
        case .divider, .shape:
            return "[decorative]"
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
