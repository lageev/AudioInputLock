import SwiftUI

@main
struct AudioInputLockApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var keeper = PreferredInputDeviceKeeper.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environment(keeper)
        } label: {
            Image("StatusBarIcon")
                .renderingMode(.template)
                .opacity(menuBarIconOpacity)
        }
        .menuBarExtraStyle(.window)

        Window(AppBrand.name, id: WindowID.main) {
            MainView()
                .environment(keeper)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }

    /// 守护可用时完整显示；关闭或目标离线时降低不透明度。
    private var menuBarIconOpacity: Double {
        keeper.isEnabled && keeper.isPreferredAvailable ? 1 : 0.45
    }
}

enum WindowID {
    static let main = "main"
}
