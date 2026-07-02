import SwiftUI

/// 单个输入设备行：类型图标 + 名称，右侧为使用中的波形动画与锁定徽章，点击即设为锁定设备。
struct DeviceRow: View {
    let device: AudioInputDevice
    let isPreferred: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: deviceSymbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isPreferred ? Color.accentColor : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        (isPreferred ? Color.accentColor : Color.secondary).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .fontWeight(isPreferred ? .medium : .regular)
                        .lineLimit(1)
                    Text("\(device.inputChannelCount) 通道 · \(device.shortUID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if device.isDefaultInput {
                    Image(systemName: "waveform")
                        .foregroundStyle(isPreferred ? Color.accentColor : Color.secondary)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                        .help("当前系统输入")
                }

                if isPreferred {
                    Text(device.isDefaultInput ? "已锁定" : "已选择")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(device.isDefaultInput ? Color.accentColor : Color.warmAccent, in: Capsule())
                } else if isHovering {
                    Text("点击锁定")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                Color.primary.opacity(isHovering && !isPreferred ? 0.06 : 0),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.spring(duration: 0.25), value: isPreferred)
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }

    /// 根据设备名称猜测类型图标，仅用于展示。
    private var deviceSymbol: String {
        let name = device.name.lowercased()
        if name.contains("airpods") { return "airpods" }
        if name.contains("headset") || name.contains("headphone") || name.contains("耳机") { return "headphones" }
        if name.contains("display") || name.contains("显示器") { return "display" }
        if name.contains("iphone") || name.contains("ipad") { return "iphone" }
        if name.contains("built-in") || name.contains("内置") || name.contains("macbook") { return "laptopcomputer" }
        if name.contains("usb") { return "cable.connector" }
        return "mic.fill"
    }
}
