import CoreAudio

/// 输入设备信息模型。
///
/// `id` 是 Core Audio 运行时对象 ID，插拔或重启后可能变化；
/// 需要持久化时应使用稳定的 `uid`。
struct AudioInputDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let inputChannelCount: UInt32
    let isDefaultInput: Bool
    let transport: TransportType
    /// 标称采样率（Hz），读取失败时为 0。
    let sampleRate: Double
    /// 输入流物理格式位深（bit），读取失败时为 0。
    let bitDepth: UInt32
    /// 是否有进程正在使用该设备。
    let isRunningSomewhere: Bool
    /// 输入音量（0.0-1.0），设备不支持音量控制时为 nil。
    let inputVolume: Float?

    /// 便于 UI 展示的简短 UID（区分多个同名设备）。
    var shortUID: String {
        uid.count > 28 ? "…" + uid.suffix(26) : uid
    }

    /// 「48 kHz」形式的采样率文案。
    var sampleRateText: String? {
        sampleRate > 0 ? String(format: "%g kHz", sampleRate / 1000) : nil
    }

    /// 「24 bit」形式的位深文案。
    var bitDepthText: String? {
        bitDepth > 0 ? "\(bitDepth) bit" : nil
    }
}

extension AudioInputDevice {
    /// 设备传输类型（kAudioDevicePropertyTransportType）。
    enum TransportType: Equatable {
        case builtIn
        case usb
        case bluetooth
        case hdmi
        case displayPort
        case airPlay
        case aggregate
        case virtual
        case thunderbolt
        case fireWire
        case pci
        case continuity
        case unknown

        init(rawValue: UInt32) {
            switch rawValue {
            case kAudioDeviceTransportTypeBuiltIn: self = .builtIn
            case kAudioDeviceTransportTypeUSB: self = .usb
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: self = .bluetooth
            case kAudioDeviceTransportTypeHDMI: self = .hdmi
            case kAudioDeviceTransportTypeDisplayPort: self = .displayPort
            case kAudioDeviceTransportTypeAirPlay: self = .airPlay
            case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: self = .aggregate
            case kAudioDeviceTransportTypeVirtual: self = .virtual
            case kAudioDeviceTransportTypeThunderbolt: self = .thunderbolt
            case kAudioDeviceTransportTypeFireWire: self = .fireWire
            case kAudioDeviceTransportTypePCI: self = .pci
            case kAudioDeviceTransportTypeContinuityCaptureWired,
                 kAudioDeviceTransportTypeContinuityCaptureWireless: self = .continuity
            default: self = .unknown
            }
        }

        var label: String? {
            switch self {
            case .builtIn: "内置"
            case .usb: "USB"
            case .bluetooth: "蓝牙"
            case .hdmi: "HDMI"
            case .displayPort: "DisplayPort"
            case .airPlay: "AirPlay"
            case .aggregate: "聚合设备"
            case .virtual: "虚拟设备"
            case .thunderbolt: "雷雳"
            case .fireWire: "FireWire"
            case .pci: "PCI"
            case .continuity: "连续互通"
            case .unknown: nil
            }
        }

        /// 名称猜不出设备类型时的图标兜底。
        var symbol: String? {
            switch self {
            case .builtIn: "laptopcomputer"
            case .usb, .fireWire, .pci: "cable.connector"
            case .bluetooth: "dot.radiowaves.right"
            case .hdmi, .displayPort: "display"
            case .airPlay: "airplayaudio"
            case .aggregate: "square.stack"
            case .virtual: "waveform"
            case .thunderbolt: "bolt"
            case .continuity: "iphone"
            case .unknown: nil
            }
        }
    }
}
