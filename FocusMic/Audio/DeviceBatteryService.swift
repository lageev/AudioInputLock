import Foundation
import IOBluetooth
import IOKit
import IOKit.ps

/// 蓝牙与 USB（含 2.4G 无线接收器）外设电量的尽力而为读取。
///
/// 数据来源按传输类型选择，避免无谓触发蓝牙权限弹窗：
/// - 蓝牙设备：IOBluetooth 已连接设备的电量属性（AirPods 等在新系统上只有这里能读到），
///   按 MAC 地址精确匹配，读不到时回退到 HID / 电源列表；
/// - USB 设备：IORegistry 中上报 `BatteryPercent` 的 HID 服务与系统电源列表的外接电池，
///   这些来源只有设备名，按名称与音频设备模糊匹配。
final class DeviceBatteryService {

    static let shared = DeviceBatteryService()

    private init() {}

    func battery(uid: String, name: String, transport: AudioDevice.TransportType) -> Int? {
        switch transport {
        case .bluetooth:
            bluetoothBattery(uid: uid, name: name) ?? battery(for: name, in: hidAndPowerSourceLevels())
        case .usb:
            battery(for: name, in: hidAndPowerSourceLevels())
        default:
            nil
        }
    }

    /// 名称匹配：先找忽略大小写与符号后完全相同的，再退到互相包含的模糊匹配。
    private func battery(for deviceName: String, in levels: [String: Int]) -> Int? {
        let target = normalize(deviceName)
        guard !target.isEmpty else { return nil }
        var fuzzy: Int?
        for (name, percent) in levels {
            let candidate = normalize(name)
            guard !candidate.isEmpty else { continue }
            if candidate == target { return percent }
            if fuzzy == nil, target.contains(candidate) || candidate.contains(target) {
                fuzzy = percent
            }
        }
        return fuzzy
    }

    private func normalize(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - 蓝牙

    /// 已连接蓝牙设备的电量。蓝牙音频设备的 UID 里含 MAC 地址，
    /// 优先按 MAC 精确匹配，避免多副同名耳机（如几副 AirPods）串数据；
    /// UID 里没有 MAC 时才退回名称匹配。
    /// 首次调用会触发系统蓝牙权限弹窗；被拒绝时读不到值，只是不显示电量。
    private func bluetoothBattery(uid: String, name: String) -> Int? {
        let target = normalize(uid)
        var levelsByName: [String: Int] = [:]
        for device in IOBluetoothDevice.pairedDevices() ?? [] {
            guard let device = device as? IOBluetoothDevice,
                  device.isConnected(),
                  let percent = batteryPercent(of: device) else { continue }

            let address = normalize(device.addressString ?? "")
            if !address.isEmpty, target.contains(address) {
                return percent
            }
            if let deviceName = device.name {
                levelsByName[deviceName] = percent
            }
        }
        return battery(for: name, in: levelsByName)
    }

    /// batteryPercent* 是 IOBluetoothDevice 的私有属性，
    /// 用 KVC 读取并做 responds(to:) 防护；左右耳分开上报时取较低值。
    private func batteryPercent(of device: IOBluetoothDevice) -> Int? {
        ["batteryPercentSingle", "batteryPercentCombined", "batteryPercentLeft", "batteryPercentRight"]
            .compactMap { key -> Int? in
                guard device.responds(to: Selector(key)) else { return nil }
                let percent = (device.value(forKey: key) as? Int) ?? 0
                return percent > 0 ? percent : nil
            }
            .min()
    }

    // MARK: - HID 与电源列表

    private func hidAndPowerSourceLevels() -> [String: Int] {
        var levels: [String: Int] = [:]
        for className in ["AppleDeviceManagementHIDEventService", "IOHIDDevice"] {
            addHIDBatteryEntries(matching: className, to: &levels)
        }
        addPowerSourceEntries(to: &levels)
        return levels
    }

    private func addHIDBatteryEntries(matching className: String, to levels: inout [String: Int]) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let percent = property(of: service, key: "BatteryPercent") as? Int,
                  let name = property(of: service, key: "Product") as? String else { continue }
            levels[name] = percent
        }
    }

    private func property(of service: io_object_t, key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private func addPowerSourceEntries(to levels: inout [String: Int]) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String != kIOPSInternalBatteryType,
                  let name = description[kIOPSNameKey] as? String,
                  let percent = description[kIOPSCurrentCapacityKey] as? Int else { continue }
            levels[name] = percent
        }
    }
}
