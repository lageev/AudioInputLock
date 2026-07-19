import AppKit
import SwiftUI

/// 主界面：输入与输出设备各自使用独立标签页，另有日志、设置和关于页。
struct MainView: View {
    @Environment(PreferredInputDeviceKeeper.self) private var keeper
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var updater = UpdaterService.shared
    @State private var launchAtLogin = LoginItemManager.isEnabled
    @State private var loginError: String?

    private let visibleLogCount = 10

    var body: some View {
        TabView {
            Tab("输入", systemImage: "mic") {
                inputTab
            }
            if keeper.isOutputFeatureEnabled {
                Tab("输出", systemImage: "speaker.wave.2") {
                    outputTab
                }
            }
            Tab("日志", systemImage: "list.bullet.rectangle") {
                logsTab
            }
            Tab("设置", systemImage: "gearshape") {
                settingsTab
            }
            Tab("关于", systemImage: "info.circle") {
                aboutTab
            }
        }
        .frame(width: 520, height: 560)
        .onAppear {
            keeper.refreshDevices()
            launchAtLogin = LoginItemManager.isEnabled
        }
    }

    // MARK: - 输入页

    private var inputTab: some View {
        @Bindable var keeper = keeper
        let inputStatus = LockStatus(keeper: keeper)

        return Form {
            Section {
                lockStatusRow(inputStatus)
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
                                isGuardEnabled: keeper.isEnabled
                            ),
                            density: .detailed,
                            action: {
                                keeper.switchInputDevice(device)
                            },
                            lockAction: {
                                keeper.toggleInputGuard(device)
                            }
                        )
                    }
                }
                Button("刷新设备列表", systemImage: "arrow.clockwise") {
                    keeper.refreshDevices()
                }
            }

            Section("输入音量") {
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

    // MARK: - 输出页

    private var outputTab: some View {
        let outputStatus = LockStatus(keeper: keeper, direction: .output)

        return Form {
            Section {
                lockStatusRow(outputStatus)
            }

            Section("输出设备") {
                if keeper.outputDevices.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "speaker.slash")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                            Text("未检测到输出设备")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                } else {
                    ForEach(keeper.outputDevices) { device in
                        DeviceRow(
                            device: device,
                            status: DeviceRowStatus(
                                device: device,
                                isPreferred: device.uid == keeper.preferredOutputUID,
                                isGuardEnabled: keeper.isOutputEnabled
                            ),
                            density: .detailed,
                            action: {
                                keeper.switchOutputDevice(device)
                            },
                            lockAction: {
                                keeper.toggleOutputGuard(device)
                            }
                        )
                    }
                }
                Button("刷新设备列表", systemImage: "arrow.clockwise") {
                    keeper.refreshDevices()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func lockStatusRow(_ status: LockStatus) -> some View {
        HStack(spacing: 12) {
            Image(systemName: status.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(status.color)
                .frame(width: 40, height: 40)
                .background(status.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(status.deviceName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(status.kind)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Text(status.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .animation(.easeOut(duration: 0.25), value: status.symbol)
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
        @Bindable var keeper = keeper

        return Form {
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

            Section("功能") {
                Toggle(isOn: $keeper.isOutputFeatureEnabled) {
                    Text("启用输出设备功能")
                    Text("显示输出设备列表，并允许切换和守护系统默认输出设备。")
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

    // MARK: - 关于页

    private var aboutTab: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text(AppBrand.name)
                .font(.title2.weight(.semibold))
            Text("版本 \(UpdaterService.currentVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(AppBrand.slogan)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            HStack(spacing: 14) {
                ForEach(AppBrand.links, id: \.url) { link in
                    if let url = URL(string: link.url) {
                        Link(link.title, destination: url)
                            .font(.caption)
                    }
                }
            }
            .padding(.top, 10)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
