import AppKit
import SwiftUI

/// 主界面：多标签页排版，分为「状态 / 设备 / 日志 / 设置」四页。
struct MainView: View {
    @Environment(PreferredInputDeviceKeeper.self) private var keeper
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var updater = UpdaterService.shared
    @State private var launchAtLogin = LoginItemManager.isEnabled
    @State private var loginError: String?

    private let visibleLogCount = 10

    var body: some View {
        TabView {
            Tab("状态", systemImage: "lock.shield") {
                statusTab
            }
            Tab("设备", systemImage: "mic") {
                devicesTab
            }
            Tab("日志", systemImage: "list.bullet.rectangle") {
                logsTab
            }
            Tab("设置", systemImage: "gearshape") {
                settingsTab
            }
        }
        .frame(width: 520, height: 480)
        .onAppear {
            keeper.refreshDevices()
            launchAtLogin = LoginItemManager.isEnabled
        }
    }

    // MARK: - 状态页

    private var statusTab: some View {
        @Bindable var keeper = keeper
        let status = LockStatus(keeper: keeper)

        return Form {
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

                Toggle(isOn: $keeper.isVolumeLockEnabled) {
                    Text("锁定输入音量")
                    Text("有些应用会偷偷改麦克风增益；开启后音量被改动时自动恢复。")
                }
                .disabled(keeper.preferredUID == nil)

                if keeper.isVolumeLockEnabled, let volume = keeper.lockedVolume {
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.wave.1")
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { Double(volume) },
                                set: { keeper.updateLockedVolume(Float($0)) }
                            ),
                            in: 0...1
                        )
                        Text("\(Int(volume * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }

            Section("输入电平") {
                Toggle(isOn: $keeper.isLevelMeterEnabled) {
                    Text("显示实时输入电平")
                    Text("本地实时采样计算响度，不录制、不保存任何音频；首次开启需要麦克风权限。")
                }
                if keeper.isLevelMeterEnabled {
                    InputLevelMeterView()
                        .padding(.vertical, 2)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 设备页

    private var devicesTab: some View {
        Form {
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
                            ),
                            density: .detailed
                        ) {
                            keeper.selectPreferred(device)
                        }
                    }
                }
                Button("刷新设备列表", systemImage: "arrow.clockwise") {
                    keeper.refreshDevices()
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 日志页

    private var logsTab: some View {
        let recentLogs = Array(keeper.logs.prefix(visibleLogCount))

        return Form {
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
    }

    // MARK: - 设置页

    private var settingsTab: some View {
        Form {
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

            Section("更新") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("版本 \(UpdaterService.currentVersion)")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if updater.supportsInAppUpdate {
                            Button(updater.checkButtonTitle, systemImage: updater.checkButtonSystemImage) {
                                updater.checkForUpdates()
                            }
                            .disabled(!updater.canInitiateCheck)
                            .help(updater.visibleStatusMessage ?? String(localized: "检查是否有新版本"))
                        } else {
                            Text("更新由 App Store 管理")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if updater.supportsInAppUpdate, let message = updater.visibleStatusMessage {
                        if updater.configurationError == nil {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func updateLoginItem(_ enabled: Bool) {
        do {
            try LoginItemManager.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = String(localized: "设置开机启动失败：\(error.localizedDescription)")
            launchAtLogin = LoginItemManager.isEnabled
        }
    }
}
