import SwiftUI


/// In-app Android emulator surface for the right sidebar.
///
/// The Android Emulator does not expose a public AppKit view that can be
/// embedded. This panel runs an AVD headlessly when possible, renders its
/// framebuffer with `adb exec-out screencap -p`, and routes pointer input back
/// through `adb shell input`, keeping the visible emulator inside Clawix.
struct AndroidSimulatorPanel: View {
    let payload: SidebarItem.AndroidSimulatorPayload
    var onPayloadChange: (SidebarItem.AndroidSimulatorPayload) -> Void = { _ in }
    @StateObject private var controller = AndroidSimulatorFramebufferController()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().background(Color.white.opacity(0.06))
            ZStack {
                Color.black
                simulatorStage
                if controller.showsOverlay {
                    overlay
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
        .onAppear {
            controller.configure(payload: payload, onPayloadChange: onPayloadChange)
            controller.start()
        }
        .onDisappear {
            controller.stop()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 7) {
            AndroidSimulatorIconButton(systemName: "arrow.clockwise", enabled: controller.canRefresh) {
                controller.refreshNow()
            }
            .accessibilityLabel("Refresh emulator")

            AndroidSimulatorIconButton(systemName: "house", enabled: controller.canControl) {
                controller.keyEvent("KEYCODE_HOME")
            }
            .accessibilityLabel("Home")

            AndroidSimulatorIconButton(systemName: "chevron.left", enabled: controller.canControl) {
                controller.keyEvent("KEYCODE_BACK")
            }
            .accessibilityLabel("Back")

            AndroidSimulatorIconButton(systemName: "square.on.square", enabled: controller.canControl) {
                controller.keyEvent("KEYCODE_APP_SWITCH")
            }
            .accessibilityLabel("App switcher")

            AndroidSimulatorIconButton(systemName: "globe", enabled: controller.canControl) {
                controller.openURL("https://www.google.com")
            }
            .accessibilityLabel("Open browser")

            AndroidSimulatorIconButton(systemName: "sun.max", enabled: controller.canControl) {
                controller.setNightMode(false)
            }
            .accessibilityLabel("Light mode")

            AndroidSimulatorIconButton(systemName: "moon", enabled: controller.canControl) {
                controller.setNightMode(true)
            }
            .accessibilityLabel("Dark mode")

            Menu {
                ForEach(controller.availableAVDs) { avd in
                    Button(avd.menuTitle) {
                        controller.selectAVD(avd)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(controller.selectedDeviceName)
                        .font(BodyFont.system(size: 11.5, wght: 600))
                        .foregroundColor(Color(white: 0.82))
                        .lineLimit(1)
                    LucideIcon(.chevronDown, size: 10)
                        .foregroundColor(Color(white: 0.55))
                }
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
            }
            .menuStyle(.borderlessButton)
            .disabled(controller.availableAVDs.isEmpty)
            .accessibilityLabel("Select Android emulator")

            Spacer(minLength: 0)

            Text(controller.statusLine)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Color(white: 0.58))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(Color.black)
    }

    @ViewBuilder
    private var simulatorStage: some View {
        if let image = controller.frameImage {
            GeometryReader { proxy in
                let screenAspect = max(0.1, image.size.width / max(1, image.size.height))
                AndroidSimulatorFrameSurface(
                    image: image,
                    aspectRatio: screenAspect,
                    stageSize: proxy.size
                ) { phase, point in
                    controller.handlePointer(phase: phase, devicePoint: point)
                }
            }
        } else {
            VStack(spacing: 10) {
                LucideIcon.auto("smartphone", size: 28)
                    .foregroundColor(Color(white: 0.32))
                Text("Waiting for Android display")
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color(white: 0.54))
            }
        }
    }

    private var overlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                switch controller.state {
                case .running:
                    LucideIcon(.circleCheck, size: 14)
                        .foregroundColor(Color.green.opacity(0.85))
                case .failed:
                    LucideIcon(.triangleAlert, size: 14)
                        .foregroundColor(Color.orange.opacity(0.90))
                default:
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                        .frame(width: 14, height: 14)
                }

                Text(controller.state.title)
                    .font(BodyFont.system(size: 12.5, wght: 600))
                    .foregroundColor(Color(white: 0.92))
            }

            if let detail = controller.state.detail {
                Text(detail)
                    .font(BodyFont.system(size: 11.5, wght: 400))
                    .foregroundColor(Color(white: 0.66))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if controller.state.allowsRetry {
                Button("Retry") {
                    controller.restart()
                }
                .buttonStyle(AndroidSimulatorPanelButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: 390, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
        )
    }
}
