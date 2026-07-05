import Foundation
import IOKit
import IOKit.ps

/// 蓝牙与 USB（含 2.4G 无线接收器）外设电量的尽力而为读取。
///
/// 数据来源：
/// - IORegistry 中上报 `BatteryPercent` 的 HID 服务（多数蓝牙耳机、无线接收器走这里）；
/// - 系统电源列表中的外接附件电池。
/// 两者都只有设备名，最终按名称与音频设备模糊匹配。
final class DeviceBatteryService {

    static let shared = DeviceBatteryService()

    private init() {}

    /// 设备名 → 电量百分比（0-100）。
    func batteryLevels() -> [String: Int] {
        var levels: [String: Int] = [:]
        for className in ["AppleDeviceManagementHIDEventService", "IOHIDDevice"] {
            addHIDBatteryEntries(matching: className, to: &levels)
        }
        addPowerSourceEntries(to: &levels)
        return levels
    }

    /// 名称模糊匹配：忽略大小写与符号后互相包含即视为同一设备。
    func battery(for deviceName: String, in levels: [String: Int]) -> Int? {
        let target = normalize(deviceName)
        guard !target.isEmpty else { return nil }
        for (name, percent) in levels {
            let candidate = normalize(name)
            guard !candidate.isEmpty else { continue }
            if target.contains(candidate) || candidate.contains(target) {
                return percent
            }
        }
        return nil
    }

    private func normalize(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
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
