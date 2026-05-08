import SwiftUI
import AppKit

/// App-wide notification toast bus. One pill shows at a time, anchored
/// at the top-center of the window. Any feature can call
/// `ToastCenter.shared.show("message")` to surface a transient
/// confirmation; replacing the visible toast is fine and intentional, so
/// rapid back-to-back actions don't pile up a queue the user has already
/// moved past.
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    @Published private(set) var current: ToastItem?

    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    /// Surface a toast. `icon` defaults to a check-circle (success).
    /// `duration` is how long the pill remains fully visible before the
    /// auto-dismiss animation runs.
    func show(
        _ message: String,
        icon: ToastItem.Icon = .checkCircle,
        duration: TimeInterval = 2.4
    ) {
        let item = ToastItem(message: message, icon: icon)
        // Drop any pending auto-dismiss from a previous toast so the
        // new one gets its own full visible window.
        dismissWorkItem?.cancel()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            current = item
        }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.dismissIfMatches(item.id) }
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        withAnimation(.easeIn(duration: 0.22)) {
            current = nil
        }
    }

    private func dismissIfMatches(_ id: UUID) {
        guard current?.id == id else { return }
        withAnimation(.easeIn(duration: 0.22)) {
            current = nil
        }
    }
}

struct ToastItem: Identifiable, Equatable {
    enum Icon: Equatable {
        case checkCircle
        case info
        case warning
        case error
        case none
    }

    let id = UUID()
    let message: String
    let icon: Icon
}

/// Overlay that mounts a single floating pill at the top of the window.
/// Intended to be installed once at the app root so every screen
/// inherits it. The host is purely presentational, all state lives in
/// `ToastCenter.shared`.
struct ToastHost: View {
    @ObservedObject private var center = ToastCenter.shared

    var body: some View {
        VStack {
            ZStack {
                if let item = center.current {
                    ToastPill(item: item) {
                        center.dismiss()
                    }
                    .id(item.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top)
                            .combined(with: .opacity),
                        removal: .move(edge: .top)
                            .combined(with: .opacity)
                    ))
                }
            }
            .padding(.top, 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(center.current != nil)
    }
}

private struct ToastPill: View {
    let item: ToastItem
    let onDismiss: () -> Void

    @State private var hoverClose = false

    var body: some View {
        HStack(spacing: 10) {
            iconView

            Text(item.message)
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(Color(white: 0.98))
                .fixedSize(horizontal: true, vertical: false)

            Button(action: onDismiss) {
                LucideIcon(.x, size: 11)
                    .foregroundColor(hoverClose ? Color(white: 0.95) : Color(white: 0.62))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoverClose = $0 }
            .accessibilityLabel("Dismiss notification")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(
            ZStack {
                Capsule(style: .continuous)
                    .fill(Color(white: 0.115).opacity(0.92))
                VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow, state: .active)
                    .clipShape(Capsule(style: .continuous))
                    .opacity(0.55)
            }
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
        )
        .shadow(color: Color.black.opacity(0.34), radius: 18, x: 0, y: 8)
    }

    @ViewBuilder
    private var iconView: some View {
        switch item.icon {
        case .checkCircle:
            LucideIcon(.circleCheck, size: 14)
                .foregroundColor(Color(white: 0.92))
        case .info:
            LucideIcon(.circleAlert, size: 14)
                .foregroundColor(Color(white: 0.92))
        case .warning:
            LucideIcon(.circleAlert, size: 14)
                .foregroundColor(Color(red: 0.95, green: 0.78, blue: 0.40))
        case .error:
            LucideIcon(.circleAlert, size: 14)
                .foregroundColor(Color(red: 0.95, green: 0.45, blue: 0.45))
        case .none:
            EmptyView()
        }
    }
}
