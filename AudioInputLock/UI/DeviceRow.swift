import SwiftUI

/// 单个输入设备行：右侧状态表示锁定状态，点击即设为锁定设备。
struct DeviceRow: View {
    let device: AudioInputDevice
    let isPreferred: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .lineLimit(1)
                    Text("\(device.inputChannelCount) 通道 · \(device.shortUID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    if isPreferred {
                        Text(device.isDefaultInput ? "已锁定" : "已选择")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.accentColor)
                    } else if device.isDefaultInput {
                        Text("正在使用")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: isPreferred ? "checkmark.circle.fill" : "circle")
                        .imageScale(.large)
                        .foregroundStyle(isPreferred ? Color.accentColor : Color.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
