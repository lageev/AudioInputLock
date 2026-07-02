import SwiftUI

/// 主界面：状态总览、守护开关、设备选择、开机启动与活动日志。
struct MainView: View {
    @Environment(PreferredInputDeviceKeeper.self) private var keeper
    @State private var launchAtLogin = LoginItemManager.isEnabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var keeper = keeper

        Form {
            Section("状态") {
                LabeledContent("锁定设备") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(lockStateColor)
                            .frame(width: 8, height: 8)
                        Text(lockStatusText)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("守护") {
                Toggle("守护输入设备", isOn: $keeper.isEnabled)
                Text("开启后，只要锁定设备在线，系统输入会自动保持为该设备；被切走后会自动切回。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("输入设备") {
                if keeper.devices.isEmpty {
                    Text("未检测到输入设备")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(keeper.devices) { device in
                        DeviceRow(device: device, isPreferred: device.uid == keeper.preferredUID) {
                            keeper.selectPreferred(device)
                        }
                    }
                }
                Button("刷新设备列表", systemImage: "arrow.clockwise") {
                    keeper.refreshDevices()
                }
            }

            Section("通用") {
                Toggle("开机自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        updateLoginItem(newValue)
                    }
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("活动日志") {
                if keeper.logs.isEmpty {
                    Text("暂无活动")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(keeper.logs.prefix(20)) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            Text(entry.date, format: .dateTime.hour().minute().second())
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(entry.message)
                                .font(.caption)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
        .onAppear {
            keeper.refreshDevices()
            launchAtLogin = LoginItemManager.isEnabled
        }
    }

    private var lockStatusText: String {
        guard keeper.preferredUID != nil else { return "尚未选择" }
        let name = lockedDevice?.name
            ?? PreferredInputDeviceSettings.preferredName
            ?? "锁定设备"

        guard let lockedDevice else { return "\(name)（离线）" }
        return lockedDevice.isDefaultInput ? "\(name)（已锁定）" : "\(name)（已选择）"
    }

    private var lockStateColor: Color {
        guard keeper.preferredUID != nil else { return .secondary }
        guard let lockedDevice else { return .orange }
        return lockedDevice.isDefaultInput ? .green : .blue
    }

    private var lockedDevice: AudioInputDevice? {
        guard let uid = keeper.preferredUID else { return nil }
        if let device = keeper.devices.first(where: { $0.uid == uid }) {
            return device
        }
        if let name = PreferredInputDeviceSettings.preferredName {
            return keeper.devices.first { $0.name == name }
        }
        return nil
    }

    private func updateLoginItem(_ enabled: Bool) {
        do {
            try LoginItemManager.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = "设置开机启动失败：\(error.localizedDescription)"
            launchAtLogin = LoginItemManager.isEnabled
        }
    }
}
