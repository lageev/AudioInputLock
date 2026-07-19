import CoreAudio
import Foundation
import Observation

/// 首选输入/输出设备守护器，同时作为 SwiftUI 的可观察状态源。
///
/// 职责：
/// - 枚举/刷新输入与输出设备列表；
/// - 监听设备插拔与系统默认输入/输出设备变化；
/// - 在对应守护开启且目标设备可用时，把系统默认设备切回目标设备；
/// - 防抖，避免短时间内重复切换。
@MainActor
@Observable
final class PreferredInputDeviceKeeper {

    static let shared = PreferredInputDeviceKeeper()

    struct LogEntry: Codable, Identifiable {
        let id: UUID
        let date: Date
        let message: String

        init(id: UUID = UUID(), date: Date, message: String) {
            self.id = id
            self.date = date
            self.message = message
        }
    }

    // MARK: - UI 可观察状态

    private(set) var devices: [AudioDevice] = []
    private(set) var outputDevices: [AudioDevice] = []
    private(set) var logs: [LogEntry] = []

    /// 是否启用守护。切换后立即持久化，并在开启时尝试切回目标设备。
    var isEnabled: Bool = PreferredInputDeviceSettings.isEnabled {
        didSet {
            PreferredInputDeviceSettings.isEnabled = isEnabled
            guard isStarted, isEnabled else { return }
            scheduleEnforce(reason: "enabled", delay: 0)
        }
    }

    /// 是否启用输出设备守护。与输入设备守护独立开关。
    var isOutputEnabled: Bool = PreferredOutputDeviceSettings.isEnabled {
        didSet {
            PreferredOutputDeviceSettings.isEnabled = isOutputEnabled
            guard isStarted, isOutputFeatureEnabled, isOutputEnabled else { return }
            scheduleOutputEnforce(reason: "enabled", delay: 0)
        }
    }

    /// 是否启用输出设备相关功能。关闭后暂停枚举、监听和自动回切。
    var isOutputFeatureEnabled: Bool = PreferredOutputDeviceSettings.isFeatureEnabled {
        didSet {
            PreferredOutputDeviceSettings.isFeatureEnabled = isOutputFeatureEnabled
            guard isStarted else { return }

            if isOutputFeatureEnabled {
                addDefaultOutputDeviceListener()
                refreshOutputDevices()
                if isOutputEnabled {
                    scheduleOutputEnforce(reason: "feature-enabled", delay: 0)
                }
            } else {
                pendingOutputEnforce?.cancel()
                removeDefaultOutputDeviceListener()
                isOutputEnabled = false
                PreferredOutputDeviceSettings.clearGuardSettings()
                outputDevices = []
            }
        }
    }

    /// 是否锁定输入音量。开启时以当前音量为基准；独立于设备守护开关生效。
    var isVolumeLockEnabled: Bool = PreferredInputDeviceSettings.isVolumeLockEnabled {
        didSet {
            PreferredInputDeviceSettings.isVolumeLockEnabled = isVolumeLockEnabled
            guard isVolumeLockEnabled else { return }
            if lockedVolume == nil, let device = preferredDevice(), let volume = service.getInputVolume(device.id) {
                lockedVolume = volume
            }
            enforceVolume(reason: "volume-lock-enabled")
        }
    }

    /// 锁定的输入音量（0.0-1.0）。
    var lockedVolume: Float? = PreferredInputDeviceSettings.lockedVolume {
        didSet { PreferredInputDeviceSettings.lockedVolume = lockedVolume }
    }

    /// 是否在界面上显示实时输入电平。
    var isLevelMeterEnabled: Bool = PreferredInputDeviceSettings.isLevelMeterEnabled {
        didSet { PreferredInputDeviceSettings.isLevelMeterEnabled = isLevelMeterEnabled }
    }

    var preferredUID: String? { PreferredInputDeviceSettings.preferredUID }
    var preferredOutputUID: String? { PreferredOutputDeviceSettings.preferredUID }

    /// 目标设备当前是否在线可用。
    var isPreferredAvailable: Bool {
        guard let uid = preferredUID else { return false }
        return findPreferred(uid: uid, name: PreferredInputDeviceSettings.preferredName) != nil
    }

    var isPreferredOutputAvailable: Bool {
        guard isOutputFeatureEnabled else { return false }
        guard let uid = preferredOutputUID else { return false }
        return findPreferredOutput(uid: uid, name: PreferredOutputDeviceSettings.preferredName) != nil
    }

    var currentDefaultDevice: AudioDevice? {
        devices.first { $0.isDefault }
    }

    var currentDefaultOutputDevice: AudioDevice? {
        outputDevices.first { $0.isDefault }
    }

    // MARK: - 内部状态

    private let service = AudioHardwareService.shared
    private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private let logLimit = 50
    private let logsStorageKey = "activityLogs"

    private var deviceListListener: AudioObjectPropertyListenerBlock?
    private var defaultInputListener: AudioObjectPropertyListenerBlock?
    private var defaultOutputListener: AudioObjectPropertyListenerBlock?
    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var volumeListenerDeviceID: AudioObjectID?
    private var pendingEnforce: DispatchWorkItem?
    private var pendingOutputEnforce: DispatchWorkItem?
    private var isStarted = false
    private var isEnforcing = false
    private var isEnforcingOutput = false
    private var isEnforcingVolume = false

    private init() {
        logs = loadPersistedLogs()
        refreshDevices()
    }

    // MARK: - 生命周期

    func start() {
        guard !isStarted else { return }
        isStarted = true
        addDeviceListListener()
        addDefaultInputDeviceListener()
        if isOutputFeatureEnabled {
            addDefaultOutputDeviceListener()
        }
        refreshDevices()
        if isEnabled {
            scheduleEnforce(reason: "start", delay: 0)
        }
        if isOutputFeatureEnabled, isOutputEnabled {
            scheduleOutputEnforce(reason: "start", delay: 0)
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        pendingEnforce?.cancel()
        pendingOutputEnforce?.cancel()
        removeListeners()
    }

    // MARK: - 设备操作

    func refreshDevices() {
        devices = service.getInputDevices()
        refreshOutputDevices()
        updateVolumeListener()
    }

    private func refreshOutputDevices() {
        outputDevices = isOutputFeatureEnabled ? service.getOutputDevices() : []
    }

    /// 用户选择锁定设备：保存偏好并立即切换一次（守护开关是否开启不影响这一次切换）。
    func selectPreferred(_ device: AudioDevice) {
        // 已是锁定设备且正在使用：重复点击不做任何事，也不记日志。
        guard device.uid != preferredUID || !device.isDefault else { return }

        PreferredInputDeviceSettings.preferredUID = device.uid
        PreferredInputDeviceSettings.preferredName = device.name

        do {
            try service.setDefaultInputDevice(device.id)
            if isEnabled {
                addLog(String(localized: "已选择锁定设备并切换：\(device.name)"))
            } else {
                addLog(String(localized: "已切换输入设备：\(device.name)"))
            }
            // 音量锁定跟随锁定设备：换设备后以新设备当前音量为基准。
            if isVolumeLockEnabled {
                lockedVolume = service.getInputVolume(device.id)
            }
        } catch {
            if isEnabled {
                addLog(String(localized: "切换到锁定设备失败：\(device.name) error=\(String(describing: error))"))
            } else {
                addLog(String(localized: "切换输入设备失败：\(device.name) error=\(String(describing: error))"))
            }
        }
        refreshDevices()
    }

    /// 用户选择锁定输出设备：保存偏好并立即切换一次。
    func selectPreferredOutput(_ device: AudioDevice) {
        guard isOutputFeatureEnabled else { return }
        guard device.uid != preferredOutputUID || !device.isDefault else { return }

        PreferredOutputDeviceSettings.preferredUID = device.uid
        PreferredOutputDeviceSettings.preferredName = device.name

        do {
            try service.setDefaultOutputDevice(device.id)
            if isOutputEnabled {
                addLog(String(localized: "已选择锁定输出设备并切换：\(device.name)"))
            } else {
                addLog(String(localized: "已切换输出设备：\(device.name)"))
            }
        } catch {
            if isOutputEnabled {
                addLog(String(localized: "切换到锁定输出设备失败：\(device.name) error=\(String(describing: error))"))
            } else {
                addLog(String(localized: "切换输出设备失败：\(device.name) error=\(String(describing: error))"))
            }
        }
        refreshDevices()
    }

    // MARK: - 强制切换

    private func scheduleEnforce(reason: String, delay: TimeInterval = 0.25) {
        pendingEnforce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.enforce(reason: reason) }
        }
        pendingEnforce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func enforce(reason: String) {
        guard isStarted, isEnabled, !isEnforcing else { return }
        isEnforcing = true
        defer { isEnforcing = false }

        refreshDevices()

        guard let uid = preferredUID else { return }
        guard let target = findPreferred(uid: uid, name: PreferredInputDeviceSettings.preferredName) else {
            addLog(String(localized: "锁定设备不可用，暂不切换。reason=\(reason)"))
            return
        }
        // 目标已经是默认输入：直接返回，避免因自身设置回调造成的循环。
        guard !target.isDefault else { return }

        do {
            try service.setDefaultInputDevice(target.id)
            addLog(String(localized: "已切回锁定设备：\(target.name)。reason=\(reason)"))
            refreshDevices()
            enforceVolume(reason: reason)
        } catch {
            addLog(String(localized: "切回锁定设备失败：\(target.name) error=\(String(describing: error))。reason=\(reason)"))
        }
    }

    private func scheduleOutputEnforce(reason: String, delay: TimeInterval = 0.25) {
        pendingOutputEnforce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.enforceOutput(reason: reason) }
        }
        pendingOutputEnforce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func enforceOutput(reason: String) {
        guard isStarted, isOutputFeatureEnabled, isOutputEnabled, !isEnforcingOutput else { return }
        isEnforcingOutput = true
        defer { isEnforcingOutput = false }

        refreshDevices()

        guard let uid = preferredOutputUID else { return }
        guard let target = findPreferredOutput(uid: uid, name: PreferredOutputDeviceSettings.preferredName) else {
            addLog(String(localized: "锁定输出设备不可用，暂不切换。reason=\(reason)"))
            return
        }
        guard !target.isDefault else { return }

        do {
            try service.setDefaultOutputDevice(target.id)
            addLog(String(localized: "已切回锁定输出设备：\(target.name)。reason=\(reason)"))
            refreshDevices()
        } catch {
            addLog(String(localized: "切回锁定输出设备失败：\(target.name) error=\(String(describing: error))。reason=\(reason)"))
        }
    }

    /// 优先 UID 精确匹配，UID 变化时回退到名称匹配。
    private func findPreferred(uid: String, name: String?) -> AudioDevice? {
        if let device = devices.first(where: { $0.uid == uid }) {
            return device
        }
        if let name, let device = devices.first(where: { $0.name == name }) {
            return device
        }
        return nil
    }

    private func preferredDevice() -> AudioDevice? {
        guard let uid = preferredUID else { return nil }
        return findPreferred(uid: uid, name: PreferredInputDeviceSettings.preferredName)
    }

    private func findPreferredOutput(uid: String, name: String?) -> AudioDevice? {
        if let device = outputDevices.first(where: { $0.uid == uid }) {
            return device
        }
        if let name, let device = outputDevices.first(where: { $0.name == name }) {
            return device
        }
        return nil
    }

    // MARK: - 输入音量锁定

    /// 用户拖动音量滑块：更新锁定值并立即写入设备。
    func updateLockedVolume(_ volume: Float) {
        lockedVolume = volume
        guard let device = preferredDevice() else { return }
        try? service.setInputVolume(device.id, volume: volume)
        refreshDevices()
    }

    private func enforceVolume(reason: String) {
        guard isVolumeLockEnabled, !isEnforcingVolume,
              let target = lockedVolume,
              let device = preferredDevice(),
              let current = service.getInputVolume(device.id),
              abs(current - target) > 0.01 else { return }

        isEnforcingVolume = true
        defer { isEnforcingVolume = false }

        do {
            try service.setInputVolume(device.id, volume: target)
            addLog(String(localized: "已恢复输入音量：\(device.name) \(Int(current * 100))% → \(Int(target * 100))%。reason=\(reason)"))
            refreshDevices()
        } catch {
            addLog(String(localized: "恢复输入音量失败：\(device.name) error=\(String(describing: error))。reason=\(reason)"))
        }
    }

    // MARK: - 监听

    private func addDeviceListListener() {
        deviceListListener = addListener(on: systemObject, address: globalAddress(kAudioHardwarePropertyDevices)) { [weak self] in
            self?.refreshDevices()
            self?.scheduleEnforce(reason: "device-list-changed", delay: 0.3)
            if self?.isOutputFeatureEnabled == true {
                self?.scheduleOutputEnforce(reason: "device-list-changed", delay: 0.3)
            }
        }
    }

    private func addDefaultInputDeviceListener() {
        defaultInputListener = addListener(on: systemObject, address: globalAddress(kAudioHardwarePropertyDefaultInputDevice)) { [weak self] in
            self?.refreshDevices()
            self?.scheduleEnforce(reason: "default-input-changed", delay: 0.15)
        }
    }

    private func addDefaultOutputDeviceListener() {
        guard isOutputFeatureEnabled, defaultOutputListener == nil else { return }
        defaultOutputListener = addListener(on: systemObject, address: globalAddress(kAudioHardwarePropertyDefaultOutputDevice)) { [weak self] in
            self?.refreshDevices()
            self?.scheduleOutputEnforce(reason: "default-output-changed", delay: 0.15)
        }
    }

    private func removeDefaultOutputDeviceListener() {
        removeListener(defaultOutputListener, on: systemObject, address: globalAddress(kAudioHardwarePropertyDefaultOutputDevice))
        defaultOutputListener = nil
    }

    /// 让音量监听始终跟随当前锁定设备：设备变化时先移除旧监听再挂到新设备上。
    private func updateVolumeListener() {
        guard isStarted else { return }
        let targetID = preferredDevice()?.id
        guard targetID != volumeListenerDeviceID else { return }

        removeVolumeListener()
        guard let targetID else { return }

        volumeListener = addListener(on: targetID, address: inputVolumeAddress()) { [weak self] in
            self?.enforceVolume(reason: "volume-changed")
        }
        volumeListenerDeviceID = volumeListener != nil ? targetID : nil
    }

    private func removeVolumeListener() {
        if let volumeListener, let volumeListenerDeviceID {
            removeListener(volumeListener, on: volumeListenerDeviceID, address: inputVolumeAddress())
        }
        volumeListener = nil
        volumeListenerDeviceID = nil
    }

    private func globalAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func inputVolumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementWildcard
        )
    }

    private func addListener(
        on objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        handler: @escaping @MainActor () -> Void
    ) -> AudioObjectPropertyListenerBlock? {
        var address = address
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { handler() }
        }
        let status = AudioObjectAddPropertyListenerBlock(objectID, &address, DispatchQueue.main, block)
        return status == noErr ? block : nil
    }

    private func removeListeners() {
        removeListener(deviceListListener, on: systemObject, address: globalAddress(kAudioHardwarePropertyDevices))
        removeListener(defaultInputListener, on: systemObject, address: globalAddress(kAudioHardwarePropertyDefaultInputDevice))
        removeDefaultOutputDeviceListener()
        deviceListListener = nil
        defaultInputListener = nil
        removeVolumeListener()
    }

    private func removeListener(
        _ block: AudioObjectPropertyListenerBlock?,
        on objectID: AudioObjectID,
        address: AudioObjectPropertyAddress
    ) {
        guard let block else { return }
        var address = address
        AudioObjectRemovePropertyListenerBlock(objectID, &address, DispatchQueue.main, block)
    }

    // MARK: - 日志

    private func addLog(_ message: String) {
        logs.insert(LogEntry(date: Date(), message: message), at: 0)
        if logs.count > logLimit {
            logs.removeLast(logs.count - logLimit)
        }
        persistLogs()
        #if DEBUG
        print("[PreferredInputDeviceKeeper] \(message)")
        #endif
    }

    private func loadPersistedLogs() -> [LogEntry] {
        guard let data = UserDefaults.standard.data(forKey: logsStorageKey) else {
            return []
        }

        do {
            return Array(try JSONDecoder().decode([LogEntry].self, from: data).prefix(logLimit))
        } catch {
            UserDefaults.standard.removeObject(forKey: logsStorageKey)
            #if DEBUG
            print("[PreferredInputDeviceKeeper] 读取活动日志失败，已清空持久化日志：\(error)")
            #endif
            return []
        }
    }

    private func persistLogs() {
        do {
            let data = try JSONEncoder().encode(Array(logs.prefix(logLimit)))
            UserDefaults.standard.set(data, forKey: logsStorageKey)
        } catch {
            #if DEBUG
            print("[PreferredInputDeviceKeeper] 保存活动日志失败：\(error)")
            #endif
        }
    }
}
