import AppKit
import SwiftUI

/// 菜单栏弹出面板：快速查看状态、开关守护、切换锁定设备、进入设置、关于或退出。
struct MenuBarContentView: View {
    @Environment(PreferredInputDeviceKeeper.self) private var keeper
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var keeper = keeper

        VStack(alignment: .leading, spacing: 0) {
            menuInfoRow("锁定设备", value: lockedDeviceName)
                .padding(.top, 12)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("守护输入设备")
                    Text(keeper.isEnabled ? "自动保持锁定设备" : "仅手动切换输入设备")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $keeper.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            HStack(alignment: .center, spacing: 12) {
                Text("输入设备")
                Spacer(minLength: 0)
                Button {
                    refreshMenuDevices()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新设备列表")
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)

            if keeper.devices.isEmpty {
                menuInfoRow("设备列表", value: "未检测到输入设备")
                    .padding(.top, 6)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(keeper.devices) { device in
                            DeviceRow(device: device, isPreferred: device.uid == keeper.preferredUID) {
                                keeper.selectPreferred(device)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(height: deviceListHeight)
            }

            Divider()

            VStack(spacing: 2) {
                Button {
                    openSettings()
                } label: {
                    menuActionLabel("设置")
                }

                Button {
                    showAbout()
                } label: {
                    menuActionLabel("关于 AudioInputLock")
                }

                Button {
                    NSApp.terminate(nil)
                } label: {
                    menuActionLabel("退出")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 320)
        .onAppear { refreshMenuDevices() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refreshMenuDevices()
        }
    }

    private var lockedDeviceName: String {
        guard keeper.preferredUID != nil else { return "未选择" }
        return lockedDevice?.name
            ?? PreferredInputDeviceSettings.preferredName
            ?? "锁定设备"
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

    private var deviceListHeight: CGFloat {
        min(CGFloat(keeper.devices.count) * 54, 240)
    }

    private func menuInfoRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
            Spacer(minLength: 0)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func menuActionLabel(_ title: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 7)
    }

    private func openSettings() {
        openWindow(id: WindowID.main)
        NSApp.activate()
    }

    private func refreshMenuDevices() {
        keeper.refreshDevices()
    }

    private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: moreWorksLink()
        ])
    }

    private func moreWorksLink() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        return NSAttributedString(
            string: "更多作品",
            attributes: [
                .link: URL(string: "https://pastehub.yayalu.top")!,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .paragraphStyle: paragraphStyle
            ]
        )
    }
}
