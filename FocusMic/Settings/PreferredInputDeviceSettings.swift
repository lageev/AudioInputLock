import Foundation

/// 首选输入设备的持久化配置。
///
/// 只保存稳定的 UID（并附带名称用于 UID 变化时的兜底匹配），不保存运行时的 AudioObjectID。
enum PreferredInputDeviceSettings {
    private static let preferredUIDKey = "preferredInputDeviceUID"
    private static let preferredNameKey = "preferredInputDeviceName"
    private static let enabledKey = "keepPreferredInputEnabled"
    private static let volumeLockEnabledKey = "inputVolumeLockEnabled"
    private static let lockedVolumeKey = "lockedInputVolume"
    private static let levelMeterEnabledKey = "inputLevelMeterEnabled"

    static var preferredUID: String? {
        get { UserDefaults.standard.string(forKey: preferredUIDKey) }
        set { UserDefaults.standard.set(newValue, forKey: preferredUIDKey) }
    }

    static var preferredName: String? {
        get { UserDefaults.standard.string(forKey: preferredNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: preferredNameKey) }
    }

    /// 是否启用「保持首选输入设备为默认」守护。
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// 是否锁定锁定设备的输入音量。
    static var isVolumeLockEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: volumeLockEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: volumeLockEnabledKey) }
    }

    /// 锁定的输入音量（0.0-1.0），未设置过返回 nil。
    static var lockedVolume: Float? {
        get {
            UserDefaults.standard.object(forKey: lockedVolumeKey) == nil
                ? nil
                : UserDefaults.standard.float(forKey: lockedVolumeKey)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: lockedVolumeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lockedVolumeKey)
            }
        }
    }

    /// 是否在界面上显示实时输入电平。
    static var isLevelMeterEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: levelMeterEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: levelMeterEnabledKey) }
    }
}

/// 首选输出设备的持久化配置。与输入守护完全独立。
enum PreferredOutputDeviceSettings {
    private static let preferredUIDKey = "preferredOutputDeviceUID"
    private static let preferredNameKey = "preferredOutputDeviceName"
    private static let enabledKey = "keepPreferredOutputEnabled"
    private static let featureEnabledKey = "outputDeviceFeatureEnabled"

    static var preferredUID: String? {
        get { UserDefaults.standard.string(forKey: preferredUIDKey) }
        set { UserDefaults.standard.set(newValue, forKey: preferredUIDKey) }
    }

    static var preferredName: String? {
        get { UserDefaults.standard.string(forKey: preferredNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: preferredNameKey) }
    }

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// 是否启用输出设备相关功能。新安装与升级用户默认开启。
    static var isFeatureEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: featureEnabledKey) == nil
                ? true
                : UserDefaults.standard.bool(forKey: featureEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: featureEnabledKey) }
    }
}
