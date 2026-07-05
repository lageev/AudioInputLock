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
    let deviceName: String
    let detail: String

    init(keeper: PreferredInputDeviceKeeper) {
        guard let uid = keeper.preferredUID else {
            symbol = "mic.badge.plus"
            color = .secondary
            deviceName = String(localized: "未选择锁定设备")
            detail = String(localized: "在设备列表中点选一个设备即可锁定")
            return
        }

        let savedName = PreferredInputDeviceSettings.preferredName
        let device = keeper.devices.first { $0.uid == uid }
            ?? savedName.flatMap { name in keeper.devices.first { $0.name == name } }
        deviceName = device?.name ?? savedName ?? String(localized: "锁定设备")

        guard let device else {
            symbol = "mic.slash.fill"
            color = .warmAccent
            detail = keeper.isEnabled
                ? String(localized: "设备离线，重新接入后自动锁定")
                : String(localized: "设备离线")
            return
        }

        if device.isDefaultInput {
            if keeper.isEnabled {
                symbol = "lock.fill"
                color = .accentColor
                detail = String(localized: "已锁定，守护中")
            } else {
                symbol = "mic.fill"
                color = .warmAccent
                detail = String(localized: "已切换，未开启守护")
            }
        } else {
            symbol = "arrow.triangle.2.circlepath"
            color = .warmAccent
            detail = keeper.isEnabled
                ? String(localized: "已选择，即将切回")
                : String(localized: "被抢占，未开启守护")
        }
    }
}
