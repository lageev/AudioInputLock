import Combine
import Foundation

#if !APPSTORE
import Sparkle
#endif

/// 应用内更新的分发分流：
/// - 直发版（GitHub/Homebrew）：走 Sparkle，appcast 由官网托管；
/// - 商店版（编译条件 APPSTORE，不链接 Sparkle）：更新由 App Store 接管，隐藏入口。
@MainActor
final class UpdaterService: NSObject, ObservableObject {

    static let shared = UpdaterService()

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    #if !APPSTORE
    private static let sparklePublicKeyPlaceholder = "REPLACE_WITH_SPARKLE_ED_PUBLIC_KEY"
    #endif

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isChecking = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var configurationError: String?

    #if APPSTORE
    let supportsInAppUpdate = false
    #else
    let supportsInAppUpdate = true

    private var userDriver: SPUStandardUserDriver?
    private var updater: SPUUpdater?
    private var updaterObservations: [NSKeyValueObservation] = []
    private var isStarted = false
    #endif

    var canInitiateCheck: Bool {
        supportsInAppUpdate && configurationError == nil && canCheckForUpdates
    }

    var checkButtonTitle: String {
        if configurationError != nil { return String(localized: "检查更新不可用") }
        return isChecking ? String(localized: "正在检查更新…") : String(localized: "检查更新…")
    }

    var checkButtonSystemImage: String {
        if configurationError != nil { return "exclamationmark.triangle" }
        return isChecking ? "arrow.triangle.2.circlepath" : "arrow.down.circle"
    }

    var visibleStatusMessage: String? {
        configurationError ?? statusMessage
    }

    private override init() {
        super.init()

        #if APPSTORE
        statusMessage = String(localized: "更新由 App Store 管理")
        #else
        configureSparkle()
        #endif
    }

    func start() {
        #if !APPSTORE
        guard !isStarted, configurationError == nil, let updater else { return }

        do {
            try updater.start()
            isStarted = true
            syncUpdateState(from: updater)
        } catch {
            setConfigurationError(String(localized: "Sparkle 启动失败：\(error.localizedDescription)"))
        }
        #endif
    }

    func checkForUpdates() {
        #if !APPSTORE
        guard configurationError == nil else {
            statusMessage = configurationError
            return
        }

        start()

        guard let updater else {
            setConfigurationError(String(localized: "Sparkle 更新器未初始化"))
            return
        }

        syncUpdateState(from: updater)
        guard updater.canCheckForUpdates else {
            statusMessage = updater.sessionInProgress
                ? String(localized: "正在检查更新…")
                : String(localized: "暂时不能检查更新")
            return
        }

        isChecking = true
        statusMessage = String(localized: "正在检查更新…")
        updater.checkForUpdates()
        #endif
    }

    #if !APPSTORE
    private func configureSparkle() {
        if let configurationProblem = Self.sparkleConfigurationProblem() {
            setConfigurationError(configurationProblem)
            return
        }

        let userDriver = SPUStandardUserDriver(hostBundle: .main, delegate: nil)
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: self
        )

        self.userDriver = userDriver
        self.updater = updater
        observeUpdater(updater)
    }

    private static func sparkleConfigurationProblem() -> String? {
        guard let feedURLString = infoString(for: "SUFeedURL"),
              let feedURL = URL(string: feedURLString),
              feedURL.scheme?.lowercased() == "https",
              feedURL.host?.isEmpty == false else {
            return String(localized: "更新源 URL 缺失或不是 HTTPS 地址")
        }

        guard let publicKey = infoString(for: "SUPublicEDKey") else {
            return String(localized: "缺少 Sparkle 公钥")
        }

        guard publicKey != sparklePublicKeyPlaceholder else {
            return String(localized: "发布前需要替换 Sparkle 公钥占位符")
        }

        guard let decodedKey = Data(base64Encoded: publicKey), decodedKey.count == 32 else {
            return String(localized: "Sparkle 公钥格式无效")
        }

        return nil
    }

    private static func infoString(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func setConfigurationError(_ message: String) {
        configurationError = String(localized: "检查更新不可用：\(message)")
        statusMessage = configurationError
        canCheckForUpdates = false
        isChecking = false
    }

    private func observeUpdater(_ updater: SPUUpdater) {
        updaterObservations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor in
                    self?.syncUpdateState(from: updater)
                }
            },
            updater.observe(\.sessionInProgress, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor in
                    self?.syncUpdateState(from: updater)
                }
            }
        ]
    }

    private func syncUpdateState(from updater: SPUUpdater) {
        canCheckForUpdates = updater.canCheckForUpdates
        isChecking = updater.sessionInProgress
    }

    private func noUpdateMessage(from error: Error) -> String {
        let nsError = error as NSError
        guard let reasonValue = nsError.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber,
              let reason = SPUNoUpdateFoundReason(rawValue: reasonValue.int32Value) else {
            return String(localized: "当前已是最新版本")
        }

        switch reason {
        case .onLatestVersion:
            return String(localized: "当前已是最新版本")
        case .onNewerThanLatestVersion:
            return String(localized: "当前版本高于更新源中的最新版本")
        case .systemIsTooOld:
            return String(localized: "有新版本，但当前系统版本过低")
        case .systemIsTooNew:
            return String(localized: "有新版本，但当前系统版本过高")
        case .hardwareDoesNotSupportARM64:
            return String(localized: "有新版本，但当前设备硬件不支持")
        case .unknown:
            fallthrough
        @unknown default:
            return String(localized: "未发现可用更新")
        }
    }

    private func isNoUpdateError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SUSparkleErrorDomain && nsError.code == Int(SUError.noUpdateError.rawValue)
    }
    #endif
}

#if !APPSTORE
extension UpdaterService: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        statusMessage = String(localized: "发现新版本 \(item.displayVersionString)")
        syncUpdateState(from: updater)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        statusMessage = noUpdateMessage(from: error)
        syncUpdateState(from: updater)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        guard !isNoUpdateError(error) else { return }
        statusMessage = String(localized: "检查更新失败：\(error.localizedDescription)")
        syncUpdateState(from: updater)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        syncUpdateState(from: updater)
        isChecking = false

        guard let error, !isNoUpdateError(error),
              statusMessage == String(localized: "正在检查更新…") else { return }
        statusMessage = String(localized: "检查更新失败：\(error.localizedDescription)")
    }
}
#endif
