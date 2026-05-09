import SwiftUI

// Shared chrome and button styles for edit-name sheets (rename chat,
// rename project, edit project, create branch). Aligned with the
// dropdown canon: blurred backdrop + tinted fill + hairline stroke.

extension View {
    func sheetStandardBackground(cornerRadius: CGFloat = 18) -> some View {
        self.background(
            ZStack {
                VisualEffectBlur(material: .hudWindow,
                                 blendingMode: .behindWindow,
                                 state: .active)
                Color(white: 0.10).opacity(0.78)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
            )
            .shadow(color: Color.black.opacity(0.40), radius: 22, x: 0, y: 12)
        )
    }
}

struct SheetPrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BodyFont.system(size: 13.5, wght: 500))
            .foregroundColor(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.85 : 1.0))
            )
            .contentShape(Rectangle())
            .opacity(enabled ? 1.0 : 0.45)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SheetCancelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SheetCancelButtonLabel(configuration: configuration)
    }
}

private struct SheetCancelButtonLabel: View {
    let configuration: ButtonStyle.Configuration
    @State private var hovered = false

    var body: some View {
        configuration.label
            .font(BodyFont.system(size: 13.5, wght: 500))
            .foregroundColor(Color(white: configuration.isPressed ? 0.70 : 0.94))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(hovered ? 0.05 : 0.0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(hovered ? 0.18 : 0.13), lineWidth: 0.7)
                    )
            )
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

struct SheetDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SheetDestructiveButtonLabel(configuration: configuration)
    }
}

private struct SheetDestructiveButtonLabel: View {
    let configuration: ButtonStyle.Configuration
    @State private var hovered = false

    var body: some View {
        configuration.label
            .font(BodyFont.system(size: 13, wght: 600))
            .foregroundColor(Color(red: 0.95, green: 0.42, blue: 0.42)
                .opacity(configuration.isPressed ? 0.75 : 1.0))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(red: 0.95, green: 0.42, blue: 0.42).opacity(hovered ? 0.10 : 0.0))
            )
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

struct SheetTextFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(BodyFont.system(size: 14, wght: 500))
            .foregroundColor(Color(white: 0.96))
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
                    )
            )
    }
}

extension View {
    func sheetTextFieldStyle() -> some View {
        modifier(SheetTextFieldStyle())
    }
}
