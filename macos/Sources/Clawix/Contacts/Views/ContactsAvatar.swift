import SwiftUI

struct ContactsAvatar: View {
    let contact: Contact
    var size: CGFloat
    var hoverable: Bool = false

    @State private var hovered: Bool = false

    var body: some View {
        ZStack {
            if let data = contact.photoData, let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(ContactsTokens.AvatarPalette.color(for: contact.id))
                Text(contact.initials)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(hoverable && hovered ? 1.04 : 1.0)
        .animation(ContactsTokens.Motion.avatarHover, value: hovered)
        .onHover { hov in
            guard hoverable else { return }
            hovered = hov
        }
    }
}
