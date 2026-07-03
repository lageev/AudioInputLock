import AppKit
import SwiftUI

/// 主界面：状态总览、守护开关、设备选择、开机启动与活动日志。
struct MainView: View {
    @Environment(PreferredInputDeviceKeeper.self) private var keeper
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin = LoginItemManager.isEnabled
    @State private var loginError: String?

    private let visibleLogCount = 5

    var body: some View {
        @Bindable var keeper = keeper
        let status = LockStatus(keeper: keeper)
        let recentLogs = Array(keeper.logs.prefix(visibleLogCount))

        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: status.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(status.color)
                        .frame(width: 40, height: 40)
                        .background(status.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentTransition(.symbolEffect(.replace))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.deviceName)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(status.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .animation(.easeOut(duration: 0.25), value: status.symbol)
            }

            Section("守护") {
                Toggle(isOn: $keeper.isEnabled) {
                    Text("守护输入设备")
                    Text("只要锁定设备在线，系统输入会自动保持为该设备；被切走后自动切回。")
                }
            }

            Section("输入设备") {
                if keeper.devices.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "mic.slash")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                            Text("未检测到输入设备")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                } else {
                    ForEach(keeper.devices) { device in
                        DeviceRow(
                            device: device,
                            status: DeviceRowStatus(
                                device: device,
                                isPreferred: device.uid == keeper.preferredUID,
                                hasPreferredDevice: keeper.preferredUID != nil,
                                isGuardEnabled: keeper.isEnabled
                            )
                        ) {
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
                    Label(loginError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("活动日志") {
                if keeper.logs.isEmpty {
                    Text("暂无活动")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(recentLogs) { entry in
                            ActivityLogRow(entry: entry)
                        }

                        Divider()
                            .opacity(0.55)
                            .padding(.top, 2)

                        Button {
                            openWindow(id: WindowID.activityLog)
                            NSApp.activate()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.down.circle")
                                    .font(.caption2)
                                Text("查看全部日志")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("打开完整活动日志")
                        .accessibilityLabel("查看全部日志")
                        .overlay(alignment: .leading) {
                            if keeper.logs.count > recentLogs.count {
                                Text("最新 \(recentLogs.count) / \(keeper.logs.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
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
