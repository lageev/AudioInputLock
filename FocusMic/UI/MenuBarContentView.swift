import AppKit
import SwiftUI

/// 菜单栏弹出面板：快速查看状态、开关守护、切换锁定设备、进入主窗口、关于或退出。
struct MenuBarContentView: View {
    @Environment(PreferredInputDeviceKeeper.self) private var keeper
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var updater = UpdaterService.shared

    var body: some View {
        @Bindable var keeper = keeper
        let inputStatus = LockStatus(keeper: keeper)
        let outputStatus = LockStatus(keeper: keeper, direction: .output)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                statusCard(inputStatus)
                if keeper.isOutputFeatureEnabled {
                    statusCard(outputStatus)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            if keeper.isLevelMeterEnabled {
                InputLevelMeterView()
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("守护输入设备")
                    Text(keeper.isEnabled ? String(localized: "自动保持锁定设备") : String(localized: "仅手动切换输入设备"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $keeper.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .animation(.easeOut(duration: 0.2), value: keeper.isEnabled)

            if keeper.isOutputFeatureEnabled {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("守护输出设备")
                        Text(keeper.isOutputEnabled ? String(localized: "自动保持锁定输出") : String(localized: "仅手动切换输出"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: $keeper.isOutputEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .animation(.easeOut(duration: 0.2), value: keeper.isOutputEnabled)
            }

            Divider()
                .padding(.horizontal, 10)

            HStack(alignment: .center, spacing: 12) {
                Text("输入设备")
                    .font(.caption.weight(.medium))
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
            .padding(.top, 10)
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
                                    hasPreferredDevice: keeper.preferredUID != nil,
                                    isGuardEnabled: keeper.isEnabled
                                )
                            ) {
                                keeper.selectPreferred(device)
                            }
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
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
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
                                        hasPreferredDevice: keeper.preferredOutputUID != nil,
                                        isGuardEnabled: keeper.isOutputEnabled
                                    )
                                ) {
                                    keeper.selectPreferredOutput(device)
                                }
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
        .onAppear { refreshMenuDevices() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refreshMenuDevices()
        }
    }

    // MARK: - 子视图

    /// 顶部半宽状态卡片：输入与输出并排显示。
    private func statusCard(_ status: LockStatus) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: status.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(status.color)
                    .frame(width: 26, height: 26)
                    .background(status.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentTransition(.symbolEffect(.replace))
                Spacer(minLength: 4)
                Text(status.kind)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }

            Text(status.deviceName)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(status.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(status.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(.easeOut(duration: 0.25), value: status.symbol)
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
        min(CGFloat(keeper.devices.count) * 48 + 8, 160)
    }

    private var outputDeviceListHeight: CGFloat {
        min(CGFloat(keeper.outputDevices.count) * 48 + 8, 160)
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
