import AppKit
import SwiftUI

/// 菜单栏弹出面板：快速查看状态、开关守护、切换锁定设备、进入主窗口、关于或退出。
struct MenuBarContentView: View {
    @Environment(PreferredInputDeviceKeeper.self) private var keeper
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var keeper = keeper
        let status = LockStatus(keeper: keeper)

        VStack(alignment: .leading, spacing: 0) {
            statusCard(status)
                .padding(.horizontal, 10)
                .padding(.top, 10)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("守护输入设备")
                    Text(keeper.isEnabled ? "自动保持锁定设备" : "仅手动切换输入设备")
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
                emptyDeviceView
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
                .frame(height: deviceListHeight)
                .animation(.spring(duration: 0.3), value: keeper.devices)
            }

            Divider()
                .padding(.horizontal, 10)

            VStack(spacing: 1) {
                menuActionButton("主窗口", symbol: "macwindow") {
                    openMainWindow()
                }

                menuActionButton("关于 \(AppBrand.name)", symbol: "info.circle") {
                    showAbout()
                }

                menuActionButton("退出", symbol: "power", shortcut: "⌘Q") {
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

    /// 顶部状态卡片：图标 + 设备名 + 一句话状态说明。
    private func statusCard(_ status: LockStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: status.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(status.color)
                .frame(width: 34, height: 34)
                .background(status.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 2) {
                Text(status.deviceName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(status.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(status.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(.easeOut(duration: 0.25), value: status.symbol)
    }

    private var emptyDeviceView: some View {
        VStack(spacing: 6) {
            Image(systemName: "mic.slash")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text("未检测到输入设备")
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
        action: @escaping () -> Void
    ) -> some View {
        MenuActionButton(title: title, symbol: symbol, shortcut: shortcut, action: action)
    }

    // MARK: - 状态与操作

    private var deviceListHeight: CGFloat {
        min(CGFloat(keeper.devices.count) * 48 + 8, 240)
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

        appendAboutLinks(
            [
                ("官网", "https://focusmic.yayalu.top/"),
                ("打赏", "https://donation.yayalu.top/"),
                ("服务条款", "https://focusmic.yayalu.top/terms"),
                ("隐私政策", "https://focusmic.yayalu.top/privacy"),
                ("更多作品", "https://pastehub.yayalu.top")
            ],
            to: credits,
            paragraphStyle: paragraphStyle
        )

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
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(title)
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
        .onHover { isHovering = $0 }
    }
}
