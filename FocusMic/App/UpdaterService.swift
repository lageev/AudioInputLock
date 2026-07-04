import Foundation

#if !APPSTORE
import Sparkle
#endif

/// 应用内更新的分发分流：
/// - 直发版（GitHub/Homebrew）：走 Sparkle，appcast 由官网托管；
/// - 商店版（编译条件 APPSTORE，不链接 Sparkle）：更新由 App Store 接管，隐藏入口。
@MainActor
final class UpdaterService {

    static let shared = UpdaterService()

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    #if APPSTORE
    let supportsInAppUpdate = false

    private init() {}

    func checkForUpdates() {}
    #else
    let supportsInAppUpdate = true

    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private init() {}

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
    #endif
}
