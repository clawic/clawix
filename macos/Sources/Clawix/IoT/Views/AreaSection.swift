import SwiftUI

/// Grouper for `IoTDevicesView`. Header with area label + count;
/// adaptive grid of `DeviceCard`s underneath. Collapsible on header
/// tap (state stored in `@AppStorage` so the user's preference
/// survives relaunches).
struct AreaSection: View {
    let label: String
    let devices: [IoTDeviceRecord]
    var onSelect: (IoTDeviceRecord) -> Void

    @AppStorage private var collapsed: Bool

    init(label: String, devices: [IoTDeviceRecord], onSelect: @escaping (IoTDeviceRecord) -> Void) {
        self.label = label
        self.devices = devices
        self.onSelect = onSelect
        let key = "clawix.iot.area.collapsed.\(label.replacingOccurrences(of: " ", with: "_"))"
        self._collapsed = AppStorage(wrappedValue: false, key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy(duration: 0.20)) {
                    collapsed.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Palette.textTertiary)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                    Text(verbatim: label)
                        .font(BodyFont.system(size: 13, weight: .semibold))
                        .foregroundColor(Palette.textPrimary)
                    Text(verbatim: "\(devices.count)")
                        .font(BodyFont.system(size: 11))
                        .foregroundColor(Palette.textTertiary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsed {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 12)],
                    spacing: 12,
                ) {
                    ForEach(devices) { device in
                        DeviceCard(device: device, onTap: { onSelect(device) })
                    }
                }
            }
        }
    }
}
