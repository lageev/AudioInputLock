import SwiftUI

/// 单个输入设备行：类型图标 + 名称，右侧为使用中的波形动画与锁定徽章，点击即设为锁定设备。
struct DeviceRow: View {
    let device: AudioInputDevice
    let status: DeviceRowStatus
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: deviceSymbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(status.isPreferred ? status.tint : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        (status.isPreferred ? status.tint : Color.secondary).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .fontWeight(status.isPreferred ? .medium : .regular)
                        .lineLimit(1)
                    Text("\(device.inputChannelCount) 通道 · \(device.shortUID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if let label = status.label {
                    HStack(spacing: 4) {
                        if let symbol = status.badgeSymbol {
                            Image(systemName: symbol)
                                .imageScale(.small)
                                .symbolEffect(.variableColor.iterative, options: .repeating)
                        }
                        Text(label)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(height: statusAccessoryHeight)
                    .background(status.tint, in: Capsule())
                    .help(status.help)
                } else if status.showsCurrentInputSymbol {
                    Image(systemName: "waveform")
                        .frame(width: statusAccessoryHeight, height: statusAccessoryHeight)
                        .foregroundStyle(status.tint)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                        .help(status.help)
                } else if isHovering {
                    Text(status.hoverLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(height: statusAccessoryHeight)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                Color.primary.opacity(isHovering && !status.isPreferred ? 0.06 : 0),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.spring(duration: 0.25), value: status)
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

    private var statusAccessoryHeight: CGFloat { 22 }
}

/// 设备列表中单行的右侧状态。菜单栏和主窗口共用这一套判断，避免文案不一致。
enum DeviceRowStatus: Equatable {
    case idle
    case idleSwitch
    case currentInput
    case locked
    case selected
    case switched
    case preempted
    case unattendedTransfer

    init(
        device: AudioInputDevice,
        isPreferred: Bool,
        hasPreferredDevice: Bool,
        isGuardEnabled: Bool
    ) {
        if isGuardEnabled {
            if isPreferred {
                self = device.isDefaultInput ? .locked : .selected
            } else {
                self = device.isDefaultInput ? .currentInput : .idle
            }
            return
        }

        if isPreferred {
            self = device.isDefaultInput ? .switched : .preempted
        } else if hasPreferredDevice, device.isDefaultInput {
            self = .unattendedTransfer
        } else {
            self = device.isDefaultInput ? .currentInput : .idleSwitch
        }
    }

    var isPreferred: Bool {
        switch self {
        case .locked, .selected, .switched, .preempted:
            true
        case .idle, .idleSwitch, .currentInput, .unattendedTransfer:
            false
        }
    }

    var label: String? {
        switch self {
        case .locked:
            "已锁定"
        case .selected:
            "已选择"
        case .switched:
            "已切换"
        case .preempted:
            "被抢占"
        case .unattendedTransfer:
            "未守护自动转移"
        case .idle, .idleSwitch, .currentInput:
            nil
        }
    }

    var badgeSymbol: String? {
        switch self {
        case .switched, .unattendedTransfer:
            "waveform"
        case .locked, .selected, .preempted, .idle, .idleSwitch, .currentInput:
            nil
        }
    }

    var tint: Color {
        switch self {
        case .locked:
            .accentColor
        case .switched, .preempted, .selected:
            .warmAccent
        case .unattendedTransfer:
            .red
        case .currentInput:
            .secondary
        case .idle, .idleSwitch:
            .secondary
        }
    }

    var showsCurrentInputSymbol: Bool {
        self == .currentInput
    }

    var help: String {
        switch self {
        case .locked:
            "当前系统输入，守护中"
        case .selected:
            "锁定设备已选择，守护会自动切回"
        case .switched:
            "已手动切换为当前系统输入，未开启守护"
        case .preempted:
            "已选择的设备被其他默认输入抢占"
        case .unattendedTransfer:
            "关闭守护时系统自动转移到此输入设备"
        case .currentInput:
            "当前系统输入"
        case .idle:
            "点击锁定此输入设备"
        case .idleSwitch:
            "点击切换到此输入设备"
        }
    }

    var hoverLabel: String {
        switch self {
        case .idle:
            "点击锁定"
        case .idleSwitch:
            "点击切换"
        case .currentInput, .locked, .selected, .switched, .preempted, .unattendedTransfer:
            help
        }
    }
}
