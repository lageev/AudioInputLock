import CoreAudio
import Foundation
import Observation

/// 首选输入设备守护器，同时作为 SwiftUI 的可观察状态源。
///
/// 职责：
/// - 枚举/刷新输入设备列表；
/// - 监听设备插拔与系统默认输入变化；
/// - 在守护开启且目标设备可用时，把系统默认输入切回目标设备；
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

    private(set) var devices: [AudioInputDevice] = []
    private(set) var logs: [LogEntry] = []

    /// 是否启用守护。切换后立即持久化，并在开启时尝试切回目标设备。
    var isEnabled: Bool = PreferredInputDeviceSettings.isEnabled {
        didSet {
            PreferredInputDeviceSettings.isEnabled = isEnabled
            guard isStarted, isEnabled else { return }
            scheduleEnforce(reason: "enabled", delay: 0)
        }
    }

    var preferredUID: String? { PreferredInputDeviceSettings.preferredUID }

    /// 目标设备当前是否在线可用。
    var isPreferredAvailable: Bool {
        guard let uid = preferredUID else { return false }
        return findPreferred(uid: uid, name: PreferredInputDeviceSettings.preferredName) != nil
    }

    var currentDefaultDevice: AudioInputDevice? {
        devices.first { $0.isDefaultInput }
    }

    // MARK: - 内部状态

    private let service = AudioHardwareService.shared
    private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private let logLimit = 50
    private let logsStorageKey = "activityLogs"

    private var deviceListListener: AudioObjectPropertyListenerBlock?
    private var defaultInputListener: AudioObjectPropertyListenerBlock?
    private var pendingEnforce: DispatchWorkItem?
    private var isStarted = false
    private var isEnforcing = false

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
        refreshDevices()
        if isEnabled {
            scheduleEnforce(reason: "start", delay: 0)
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        pendingEnforce?.cancel()
        removeListeners()
    }

    // MARK: - 设备操作

    func refreshDevices() {
        devices = service.getInputDevices()
    }

    /// 用户选择锁定设备：保存偏好并立即切换一次（守护开关是否开启不影响这一次切换）。
    func selectPreferred(_ device: AudioInputDevice) {
        // 已是锁定设备且正在使用：重复点击不做任何事，也不记日志。
        guard device.uid != preferredUID || !device.isDefaultInput else { return }

        PreferredInputDeviceSettings.preferredUID = device.uid
        PreferredInputDeviceSettings.preferredName = device.name

        do {
            try service.setDefaultInputDevice(device.id)
            if isEnabled {
                addLog("已选择锁定设备并切换：\(device.name)")
            } else {
                addLog("已切换输入设备：\(device.name)")
            }
        } catch {
            if isEnabled {
                addLog("切换到锁定设备失败：\(device.name) error=\(error)")
            } else {
                addLog("切换输入设备失败：\(device.name) error=\(error)")
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
            addLog("锁定设备不可用，暂不切换。reason=\(reason)")
            return
        }
        // 目标已经是默认输入：直接返回，避免因自身设置回调造成的循环。
        guard !target.isDefaultInput else { return }

        do {
            try service.setDefaultInputDevice(target.id)
            addLog("已切回锁定设备：\(target.name)。reason=\(reason)")
            refreshDevices()
        } catch {
            addLog("切回锁定设备失败：\(target.name) error=\(error)。reason=\(reason)")
        }
    }

    /// 优先 UID 精确匹配，UID 变化时回退到名称匹配。
    private func findPreferred(uid: String, name: String?) -> AudioInputDevice? {
        if let device = devices.first(where: { $0.uid == uid }) {
            return device
        }
        if let name, let device = devices.first(where: { $0.name == name }) {
            return device
        }
        return nil
    }

    // MARK: - 监听

    private func addDeviceListListener() {
        deviceListListener = addListener(for: kAudioHardwarePropertyDevices) { [weak self] in
            self?.refreshDevices()
            self?.scheduleEnforce(reason: "device-list-changed", delay: 0.3)
        }
    }

    private func addDefaultInputDeviceListener() {
        defaultInputListener = addListener(for: kAudioHardwarePropertyDefaultInputDevice) { [weak self] in
            self?.refreshDevices()
            self?.scheduleEnforce(reason: "default-input-changed", delay: 0.15)
        }
    }

    private func addListener(
        for selector: AudioObjectPropertySelector,
        handler: @escaping @MainActor () -> Void
    ) -> AudioObjectPropertyListenerBlock? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { handler() }
        }
        let status = AudioObjectAddPropertyListenerBlock(systemObject, &address, DispatchQueue.main, block)
        return status == noErr ? block : nil
    }

    private func removeListeners() {
        removeListener(deviceListListener, for: kAudioHardwarePropertyDevices)
        removeListener(defaultInputListener, for: kAudioHardwarePropertyDefaultInputDevice)
        deviceListListener = nil
        defaultInputListener = nil
    }

    private func removeListener(_ block: AudioObjectPropertyListenerBlock?, for selector: AudioObjectPropertySelector) {
        guard let block else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(systemObject, &address, DispatchQueue.main, block)
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
