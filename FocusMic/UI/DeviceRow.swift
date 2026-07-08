import SwiftUI

/// 单个输入设备行：类型图标 + 名称 + 信息徽标，右侧为使用中的波形动画与锁定徽章，点击即设为锁定设备。
///
/// 两种信息密度：菜单栏用 `.compact`（传输类型 + 采样率 + 电量），
/// 主窗口用 `.detailed`（追加位深、通道与输入音量），UID 放在名称的悬停提示里。
struct DeviceRow: View {
    enum Density {
        case compact
        case detailed
    }

    let device: AudioInputDevice
    let status: DeviceRowStatus
    var density: Density = .compact
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
                    .overlay(alignment: .topTrailing) {
                        if device.isRunningSomewhere {
                            Circle()
                                .fill(.green)
                                .frame(width: 7, height: 7)
                                .offset(x: 2, y: -2)
                                .help("有应用正在使用此设备")
                        }
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .fontWeight(status.isPreferred ? .medium : .regular)
                        .lineLimit(1)
                        .help(device.uid)
                    HStack(spacing: 4) {
                        ForEach(badges) { badge in
                            InfoBadge(badge: badge)
                        }
                    }
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
                rowBackgroundColor,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(rowBorderColor, lineWidth: status.usesStateBackground ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.spring(duration: 0.25), value: status)
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }

    /// 按密度组装徽标：compact 求短，detailed 尽量给全；电量读到了就展示。
    private var badges: [DeviceInfoBadge] {
        var result: [DeviceInfoBadge] = []
        if let transport = device.transport.label {
            result.append(DeviceInfoBadge(id: "transport", text: transport))
        }
        if let sampleRate = device.sampleRateText {
            result.append(DeviceInfoBadge(id: "rate", text: sampleRate))
        }
        if density == .detailed {
            if let bitDepth = device.bitDepthText {
                result.append(DeviceInfoBadge(id: "depth", text: bitDepth))
            }
            result.append(DeviceInfoBadge(id: "channels", text: "\(device.inputChannelCount)ch"))
            if let volume = device.inputVolume {
                result.append(DeviceInfoBadge(
                    id: "volume",
                    text: "\(Int(volume * 100))%",
                    symbol: "speaker.wave.1.fill"
                ))
            }
        } else if result.isEmpty {
            result.append(DeviceInfoBadge(id: "channels", text: "\(device.inputChannelCount)ch"))
        }
        if let battery = device.batteryPercent {
            result.append(DeviceInfoBadge(
                id: "battery",
                text: "\(battery)%",
                symbol: batterySymbol(battery),
                tint: battery <= 20 ? .red : .green,
                help: String(localized: "设备电量 \(battery)%")
            ))
        }
        return result
    }

    private func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case 88...: "battery.100percent"
        case 63...: "battery.75percent"
        case 38...: "battery.50percent"
        case 13...: "battery.25percent"
        default: "battery.0percent"
        }
    }

    /// 根据设备名称猜测类型图标，猜不出时回退到传输类型，仅用于展示。
    private var deviceSymbol: String {
        let name = device.name.lowercased()
        if name.contains("airpods") { return "airpods" }
        if name.contains("headset") || name.contains("headphone") || name.contains("耳机") { return "headphones" }
        if name.contains("display") || name.contains("显示器") { return "display" }
        if name.contains("iphone") || name.contains("ipad") { return "iphone" }
        if name.contains("built-in") || name.contains("内置") || name.contains("macbook") { return "laptopcomputer" }
        if name.contains("usb") { return "cable.connector" }
        return device.transport.symbol ?? "mic.fill"
    }

    private var statusAccessoryHeight: CGFloat { 22 }

    private var rowBackgroundColor: Color {
        if status.usesStateBackground {
            return status.tint.opacity(isHovering ? 0.16 : 0.10)
        }
        return Color.primary.opacity(isHovering ? 0.06 : 0)
    }

    private var rowBorderColor: Color {
        guard status.usesStateBackground else { return .clear }
        return status.tint.opacity(isHovering ? 0.28 : 0.18)
    }
}

/// 设备行里的一枚信息徽标（传输类型、采样率、电量等短信息）。
struct DeviceInfoBadge: Identifiable {
    let id: String
    let text: String
    var symbol: String?
    var tint: Color = .secondary
    var help: String?
}

private struct InfoBadge: View {
    let badge: DeviceInfoBadge

    var body: some View {
        HStack(spacing: 2) {
            if let symbol = badge.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 8))
            }
            Text(badge.text)
        }
        .font(.system(size: 9, weight: .medium).monospacedDigit())
        .foregroundStyle(badge.tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(badge.tint.opacity(0.12), in: Capsule())
        .lineLimit(1)
        .fixedSize()
        .help(badge.help ?? badge.text)
    }
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
            String(localized: "已锁定")
        case .selected:
            String(localized: "已选择")
        case .switched:
            String(localized: "已切换")
        case .preempted:
            String(localized: "被抢占")
        case .unattendedTransfer:
            String(localized: "未守护自动转移")
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

    var usesStateBackground: Bool {
        switch self {
        case .locked, .selected, .switched, .preempted, .unattendedTransfer:
            true
        case .idle, .idleSwitch, .currentInput:
            false
        }
    }

    var help: String {
        switch self {
        case .locked:
            String(localized: "当前系统输入，守护中")
        case .selected:
            String(localized: "锁定设备已选择，守护会自动切回")
        case .switched:
            String(localized: "已手动切换为当前系统输入，未开启守护")
        case .preempted:
            String(localized: "已选择的设备被其他默认输入抢占")
        case .unattendedTransfer:
            String(localized: "关闭守护时系统自动转移到此输入设备")
        case .currentInput:
            String(localized: "当前系统输入")
        case .idle:
            String(localized: "点击锁定此输入设备")
        case .idleSwitch:
            String(localized: "点击切换到此输入设备")
        }
    }

    var hoverLabel: String {
        switch self {
        case .idle:
            String(localized: "点击锁定")
        case .idleSwitch:
            String(localized: "点击切换")
        case .currentInput, .locked, .selected, .switched, .preempted, .unattendedTransfer:
            help
        }
    }
}
