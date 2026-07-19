import SwiftUI

extension Color {
    /// 图标渐变中的暖黄辅色，用于「已选择未生效 / 离线」等过渡状态；
    /// 主色（橙红）由资产目录 AccentColor 提供，即 `Color.accentColor`。
    static let warmAccent = Color(red: 0.98, green: 0.72, blue: 0.18)
}

/// 由守护器状态推导出的锁定状态展示信息（图标、颜色、文案），供主界面与菜单栏面板共用。
@MainActor
struct LockStatus {
    let symbol: String
    let color: Color
    let kind: String
    let deviceName: String
    let detail: String

    init(
        keeper: PreferredInputDeviceKeeper,
        direction: AudioDevice.Direction = .input
    ) {
        let isInput = direction == .input
        kind = isInput ? String(localized: "输入") : String(localized: "输出")
        let preferredUID = isInput ? keeper.preferredUID : keeper.preferredOutputUID
        let preferredName = isInput
            ? PreferredInputDeviceSettings.preferredName
            : PreferredOutputDeviceSettings.preferredName
        let devices = isInput ? keeper.devices : keeper.outputDevices
        let isEnabled = isInput ? keeper.isEnabled : keeper.isOutputEnabled

        if !isEnabled {
            if let currentDevice = devices.first(where: \.isDefault) {
                symbol = isInput ? "mic.fill" : "speaker.wave.2.fill"
                color = .secondary
                deviceName = currentDevice.name
                detail = String(localized: "当前设备 · 未守护")
            } else {
                symbol = isInput ? "mic.slash" : "speaker.slash"
                color = .secondary
                deviceName = String(localized: "未检测到设备")
                detail = String(localized: "点击设备行进行切换")
            }
            return
        }

        guard let uid = preferredUID else {
            symbol = isInput ? "mic.badge.plus" : "speaker.badge.plus"
            color = .secondary
            deviceName = String(localized: "未选择设备")
            detail = String(localized: "点选设备即可锁定")
            return
        }

        let device = devices.first { $0.uid == uid }
            ?? preferredName.flatMap { name in devices.first { $0.name == name } }
        deviceName = device?.name ?? preferredName ?? String(localized: "锁定设备")

        guard let device else {
            symbol = isInput ? "mic.slash.fill" : "speaker.slash.fill"
            color = .warmAccent
            detail = isEnabled
                ? String(localized: "离线 · 重连后恢复")
                : String(localized: "设备离线")
            return
        }

        if device.isDefault {
            symbol = "lock.fill"
            color = .accentColor
            detail = String(localized: "已锁定 · 守护中")
        } else {
            symbol = "arrow.triangle.2.circlepath"
            color = .warmAccent
            detail = String(localized: "等待自动切回")
        }
    }
}
