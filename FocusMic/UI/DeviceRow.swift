import SwiftUI

/// 单个音频设备行：主体用于切换设备，行末独立锁按钮用于开启或解除守护。
///
/// 两种信息密度：菜单栏用 `.compact`（传输类型 + 采样率 + 电量），
/// 主窗口用 `.detailed`（追加位深、通道与输入音量），UID 放在名称的悬停提示里。
struct DeviceRow: View {
    enum Density {
        case compact
        case detailed
    }

    let device: AudioDevice
    let status: DeviceRowStatus
    var density: Density = .compact
    let action: () -> Void
    let lockAction: () -> Void

    @State private var isHovering = false
    @State private var isLockHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: deviceSymbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(status.isGuarded ? status.tint : Color.secondary)
                        .frame(width: 26, height: 26)
                        .background(
                            (status.isGuarded ? status.tint : Color.secondary).opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(device.name)
                                .font(.system(size: 13, weight: status.isGuarded ? .medium : .regular))
                                .lineLimit(1)
                                .help(device.uid)
                            if device.isRunningSomewhere {
                                Image(systemName: "waveform")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(.green)
                                    .help("有应用正在使用此设备")
                                    .accessibilityLabel("设备使用中")
                            }
                        }
                        HStack(spacing: 4) {
                            ForEach(badges) { badge in
                                InfoBadge(badge: badge)
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    if device.isDefault {
                        Image(systemName: device.direction == .input ? "waveform" : "speaker.wave.2.fill")
                            .frame(width: statusAccessoryHeight, height: statusAccessoryHeight)
                            .foregroundStyle(.secondary)
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                            .help(status.help(for: device.direction))
                    } else if isHovering, !isLockHovering {
                        Text("点击切换")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(height: statusAccessoryHeight)
                            .transition(.opacity)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: lockAction) {
                Image(systemName: status.isGuarded ? "lock.fill" : "lock.open")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(status.isGuarded ? Color.accentColor : Color.secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        lockBackgroundColor,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(status.isGuarded ? String(localized: "解除设备守护") : String(localized: "守护此设备"))
            .accessibilityLabel(status.isGuarded ? String(localized: "解除设备守护") : String(localized: "守护此设备"))
            .onHover { isLockHovering = $0 }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background(
            rowBackgroundColor,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
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
            result.append(DeviceInfoBadge(id: "channels", text: "\(device.channelCount)ch"))
            if let volume = device.volume {
                result.append(DeviceInfoBadge(
                    id: "volume",
                    text: "\(Int(volume * 100))%",
                    symbol: "speaker.wave.1.fill"
                ))
            }
        } else if result.isEmpty {
            result.append(DeviceInfoBadge(id: "channels", text: "\(device.channelCount)ch"))
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
        return device.transport.symbol ?? (device.direction == .input ? "mic.fill" : "speaker.wave.2.fill")
    }

    private var statusAccessoryHeight: CGFloat { 22 }

    private var rowBackgroundColor: Color {
        if status.usesStateBackground {
            return status.tint.opacity(isHovering ? 0.11 : 0.065)
        }
        return Color.primary.opacity(isHovering ? 0.06 : 0)
    }

    private var lockBackgroundColor: Color {
        if status.isGuarded {
            return Color.accentColor.opacity(isLockHovering ? 0.18 : 0.11)
        }
        return Color.primary.opacity(isLockHovering ? 0.08 : 0)
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
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(badge.tint.opacity(0.07), in: Capsule())
        .lineLimit(1)
        .fixedSize()
        .help(badge.help ?? badge.text)
    }
}

/// 设备列表中单行的右侧状态。菜单栏和主窗口共用这一套判断，避免文案不一致。
enum DeviceRowStatus: Equatable {
    case idle
    case currentInput
    case locked
    case selected

    init(
        device: AudioDevice,
        isPreferred: Bool,
        isGuardEnabled: Bool
    ) {
        if isGuardEnabled, isPreferred {
            self = device.isDefault ? .locked : .selected
        } else {
            self = device.isDefault ? .currentInput : .idle
        }
    }

    var isGuarded: Bool {
        switch self {
        case .locked, .selected:
            true
        case .idle, .currentInput:
            false
        }
    }

    var tint: Color {
        switch self {
        case .locked:
            .accentColor
        case .selected:
            .warmAccent
        case .currentInput, .idle:
            .secondary
        }
    }

    var usesStateBackground: Bool {
        isGuarded
    }

    func help(for direction: AudioDevice.Direction) -> String {
        let deviceKind = direction == .input
            ? String(localized: "输入")
            : String(localized: "输出")
        return switch self {
        case .locked:
            String(localized: "当前系统\(deviceKind)设备，守护中")
        case .selected:
            String(localized: "锁定设备已选择，守护会自动切回")
        case .currentInput:
            String(localized: "当前系统\(deviceKind)设备")
        case .idle:
            String(localized: "点击切换到此\(deviceKind)设备")
        }
    }
}
