import AppKit
import SwiftUI

/// 菜单栏弹出面板：快速查看状态、切换或守护设备、进入主窗口、关于或退出。
struct MenuBarContentView: View {
    @Environment(PreferredInputDeviceKeeper.self) private var keeper
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var updater = UpdaterService.shared

    var body: some View {
        let inputStatus = LockStatus(keeper: keeper)
        let outputStatus = LockStatus(keeper: keeper, direction: .output)

        VStack(alignment: .leading, spacing: 0) {
            guardOverview(inputStatus: inputStatus, outputStatus: outputStatus)
                .padding(.horizontal, 10)
                .padding(.top, 10)

            if keeper.isLevelMeterEnabled {
                InputLevelMeterView()
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }

            Divider()
                .padding(.horizontal, 10)

            HStack(alignment: .center, spacing: 12) {
                Text("输入设备")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    refreshMenuDevices()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.small)
                }
                .buttonStyle(.borderless)
                .help("刷新设备列表")
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 2)

            if keeper.devices.isEmpty {
                emptyDeviceView(direction: .input)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(keeper.devices) { device in
                            DeviceRow(
                                device: device,
                                status: DeviceRowStatus(
                                    device: device,
                                    isPreferred: device.uid == keeper.preferredUID,
                                    isGuardEnabled: keeper.isEnabled
                                ),
                                action: {
                                    keeper.switchInputDevice(device)
                                },
                                lockAction: {
                                    keeper.toggleInputGuard(device)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .frame(height: inputDeviceListHeight)
                .animation(.spring(duration: 0.3), value: keeper.devices)
            }

            if keeper.isOutputFeatureEnabled {
                Divider()
                    .padding(.horizontal, 10)

                HStack(alignment: .center, spacing: 12) {
                    Text("输出设备")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 2)

                if keeper.outputDevices.isEmpty {
                    emptyDeviceView(direction: .output)
                } else {
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(keeper.outputDevices) { device in
                                DeviceRow(
                                    device: device,
                                    status: DeviceRowStatus(
                                        device: device,
                                        isPreferred: device.uid == keeper.preferredOutputUID,
                                        isGuardEnabled: keeper.isOutputEnabled
                                    ),
                                    action: {
                                        keeper.switchOutputDevice(device)
                                    },
                                    lockAction: {
                                        keeper.toggleOutputGuard(device)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                    }
                    .frame(height: outputDeviceListHeight)
                    .animation(.spring(duration: 0.3), value: keeper.outputDevices)
                }
            }

            Divider()
                .padding(.horizontal, 10)

            VStack(spacing: 1) {
                menuActionButton(String(localized: "主窗口"), symbol: "macwindow") {
                    openMainWindow()
                }

                menuActionButton(String(localized: "关于 \(AppBrand.name)"), symbol: "info.circle") {
                    showAbout()
                }

                if updater.supportsInAppUpdate {
                    menuActionButton(
                        updater.checkButtonTitle,
                        symbol: updater.checkButtonSystemImage,
                        isDisabled: !updater.canInitiateCheck,
                        help: updater.visibleStatusMessage
                    ) {
                        NSApp.activate()
                        updater.checkForUpdates()
                    }
                }

                menuActionButton(String(localized: "退出"), symbol: "power", shortcut: "⌘Q") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.94))
        .onAppear { refreshMenuDevices() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refreshMenuDevices()
        }
    }

    // MARK: - 子视图

    /// 顶部只保留方向图标、设备名和锁状态，详细说明放在悬停提示中。
    private func guardOverview(inputStatus: LockStatus, outputStatus: LockStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            overviewDeviceRow(
                status: inputStatus,
                direction: .input,
                isGuarded: keeper.isEnabled && keeper.preferredUID != nil
            )
            if keeper.isOutputFeatureEnabled {
                overviewDeviceRow(
                    status: outputStatus,
                    direction: .output,
                    isGuarded: keeper.isOutputEnabled && keeper.preferredOutputUID != nil
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func overviewDeviceRow(
        status: LockStatus,
        direction: AudioDevice.Direction,
        isGuarded: Bool
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: direction == .input ? "mic.fill" : "speaker.wave.2.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(status.deviceName)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Image(systemName: isGuarded ? "lock.fill" : "lock.open")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isGuarded ? Color.accentColor : Color.secondary.opacity(0.65))
                .contentTransition(.symbolEffect(.replace))
                .help(status.detail)
        }
        .frame(height: 18)
    }

    private func emptyDeviceView(direction: AudioDevice.Direction) -> some View {
        VStack(spacing: 6) {
            Image(systemName: direction == .input ? "mic.slash" : "speaker.slash")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text(direction == .input ? "未检测到输入设备" : "未检测到输出设备")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private func menuActionButton(
        _ title: String,
        symbol: String,
        shortcut: String? = nil,
        isDisabled: Bool = false,
        help: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        MenuActionButton(
            title: title,
            symbol: symbol,
            shortcut: shortcut,
            isDisabled: isDisabled,
            help: help,
            action: action
        )
    }

    // MARK: - 状态与操作

    private var inputDeviceListHeight: CGFloat {
        min(CGFloat(keeper.devices.count) * 42 + 8, 152)
    }

    private var outputDeviceListHeight: CGFloat {
        min(CGFloat(keeper.outputDevices.count) * 42 + 8, 152)
    }

    private func openMainWindow() {
        closeMenuBarPanel()
        openWindow(id: WindowID.main)
        NSApp.activate()
    }

    /// MenuBarExtra(.window) 面板没有官方关闭 API，按窗口类名找到面板并关闭。
    private func closeMenuBarPanel() {
        NSApp.windows.first { $0.className.contains("MenuBarExtraWindow") }?.close()
    }

    private func refreshMenuDevices() {
        keeper.refreshDevices()
    }

    private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppBrand.name,
            .credits: aboutCredits()
        ])
    }

    private func aboutCredits() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let credits = NSMutableAttributedString(
            string: "\(AppBrand.slogan)\n\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraphStyle
            ]
        )

        appendAboutLinks(AppBrand.links, to: credits, paragraphStyle: paragraphStyle)

        return credits
    }

    private func appendAboutLinks(
        _ links: [(title: String, url: String)],
        to credits: NSMutableAttributedString,
        paragraphStyle: NSParagraphStyle
    ) {
        let linkAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
            .foregroundColor: NSColor.linkColor,
            .paragraphStyle: paragraphStyle
        ]
        let separatorAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]

        for (index, item) in links.enumerated() {
            if index > 0 {
                credits.append(NSAttributedString(string: "  ·  ", attributes: separatorAttributes))
            }
            guard let link = URL(string: item.url) else { continue }
            var attributes = linkAttributes
            attributes[.link] = link
            credits.append(NSAttributedString(string: item.title, attributes: attributes))
        }
    }
}

/// 底部操作行：图标 + 标题 + 快捷键提示，悬停时高亮。
private struct MenuActionButton: View {
    let title: String
    let symbol: String
    let shortcut: String?
    let isDisabled: Bool
    let help: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 16)
                    .foregroundStyle(isDisabled ? .tertiary : .secondary)
                Text(title)
                    .foregroundStyle(isDisabled ? .tertiary : .primary)
                Spacer(minLength: 0)
                if let shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Color.primary.opacity(isHovering ? 0.06 : 0),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help ?? title)
        .onHover { isHovering = $0 }
    }
}
