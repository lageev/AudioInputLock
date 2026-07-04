import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        PreferredInputDeviceKeeper.shared.start()
        // 直发版：初始化 Sparkle，让定时检查更新在启动时就开始工作；商店版为空实现。
        _ = UpdaterService.shared
    }

    func applicationWillTerminate(_ notification: Notification) {
        PreferredInputDeviceKeeper.shared.stop()
    }
}
