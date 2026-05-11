import SwiftUI

struct IOSSimulatorPanel: View {
    let payload: SidebarItem.IOSSimulatorPayload
    var onPayloadChange: (SidebarItem.IOSSimulatorPayload) -> Void = { _ in }
    @StateObject private var controller = IOSSimulatorFramebufferController()

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
            IOSSimulatorIconButton(systemName: "arrow.clockwise", enabled: controller.canRefresh) {
                controller.refreshNow()
            }
            .accessibilityLabel("Refresh simulator")

            IOSSimulatorIconButton(systemName: "house", enabled: controller.canControl) {
                controller.goHome()
            }
            .accessibilityLabel("Home")

            IOSSimulatorIconButton(systemName: "safari", enabled: controller.canControl) {
                controller.openURL("https://www.apple.com")
            }
            .accessibilityLabel("Open Safari")

            IOSSimulatorIconButton(systemName: "sun.max", enabled: controller.canControl) {
                controller.setAppearance(.light)
            }
            .accessibilityLabel("Light appearance")

            IOSSimulatorIconButton(systemName: "moon", enabled: controller.canControl) {
                controller.setAppearance(.dark)
            }
            .accessibilityLabel("Dark appearance")

            Menu {
                ForEach(controller.availableDevices) { device in
                    Button(device.menuTitle) {
                        controller.selectDevice(device)
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
            .disabled(controller.availableDevices.isEmpty)
            .accessibilityLabel("Select iOS simulator device")

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
        if let display = controller.nativeDisplay {
            IOSSimulatorNativeDisplayView(display: display)
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
        } else if let image = controller.frameImage {
            GeometryReader { proxy in
                let screenAspect = max(0.1, image.size.width / max(1, image.size.height))
                IOSSimulatorFrameSurface(
                    image: image,
                    aspectRatio: screenAspect,
                    stageSize: proxy.size
                ) { phase, point in
                    controller.handlePointer(phase: phase, devicePoint: point)
                }
            }
        } else {
            VStack(spacing: 10) {
                LucideIcon(.appWindow, size: 28)
                    .foregroundColor(Color(white: 0.32))
                Text("Waiting for iOS display")
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
                .buttonStyle(IOSSimulatorPanelButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: 360, alignment: .leading)
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
