import CoreAudio

/// 对 Core Audio 硬件属性读写的封装：枚举设备、读取名称/UID/通道数、读写系统默认输入设备。
final class AudioHardwareService {

    static let shared = AudioHardwareService()

    private let systemObject = AudioObjectID(kAudioObjectSystemObject)

    private init() {}

    // MARK: - Address 构造

    private func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    // MARK: - 枚举设备

    func getAllAudioDeviceIDs() throws -> [AudioObjectID] {
        var address = self.address(kAudioHardwarePropertyDevices)

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &dataSize)
        guard status == noErr else {
            throw AudioHardwareError.getPropertySizeFailed(selector: address.mSelector, status: status)
        }
        guard dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: count)

        status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &dataSize, &deviceIDs)
        guard status == noErr else {
            throw AudioHardwareError.getPropertyDataFailed(selector: address.mSelector, status: status)
        }
        return deviceIDs
    }

    /// 只返回具备输入通道的设备，并标注当前默认输入。
    func getInputDevices() -> [AudioInputDevice] {
        let defaultInputID = getDefaultInputDeviceID()
        guard let allDeviceIDs = try? getAllAudioDeviceIDs() else { return [] }

        return allDeviceIDs.compactMap { deviceID in
            let channelCount = getInputChannelCount(deviceID)
            guard channelCount > 0, let uid = getDeviceUID(deviceID) else { return nil }

            return AudioInputDevice(
                id: deviceID,
                uid: uid,
                name: getDeviceName(deviceID) ?? "Unknown Input Device",
                inputChannelCount: channelCount,
                isDefaultInput: defaultInputID == deviceID,
                transport: AudioInputDevice.TransportType(rawValue: getTransportType(deviceID)),
                sampleRate: getNominalSampleRate(deviceID),
                bitDepth: getInputBitDepth(deviceID),
                isRunningSomewhere: isRunningSomewhere(deviceID),
                inputVolume: getInputVolume(deviceID)
            )
        }
    }

    // MARK: - 设备属性

    func getDeviceName(_ deviceID: AudioObjectID) -> String? {
        var address = self.address(kAudioObjectPropertyName)
        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &name)
        return status == noErr ? name as String : nil
    }

    func getDeviceUID(_ deviceID: AudioObjectID) -> String? {
        var address = self.address(kAudioDevicePropertyDeviceUID)
        var uid: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &uid)
        return status == noErr ? uid as String : nil
    }

    func getInputChannelCount(_ deviceID: AudioObjectID) -> UInt32 {
        var address = self.address(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeInput)

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return 0
        }

        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPointer.deallocate() }

        let bufferListPointer = rawPointer.assumingMemoryBound(to: AudioBufferList.self)
        var size = dataSize
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPointer) == noErr else {
            return 0
        }

        return UnsafeMutableAudioBufferListPointer(bufferListPointer).reduce(UInt32(0)) {
            $0 + $1.mNumberChannels
        }
    }

    func isInputDevice(_ deviceID: AudioObjectID) -> Bool {
        getInputChannelCount(deviceID) > 0
    }

    func getTransportType(_ deviceID: AudioObjectID) -> UInt32 {
        var address = self.address(kAudioDevicePropertyTransportType)
        var transport: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &transport)
        return status == noErr ? transport : 0
    }

    /// 标称采样率（Hz），读取失败返回 0。
    func getNominalSampleRate(_ deviceID: AudioObjectID) -> Double {
        var address = self.address(kAudioDevicePropertyNominalSampleRate)
        var sampleRate: Float64 = 0
        var dataSize = UInt32(MemoryLayout<Float64>.size)

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &sampleRate)
        return status == noErr ? sampleRate : 0
    }

    /// 第一条输入流的物理格式位深（bit），读取失败返回 0。
    func getInputBitDepth(_ deviceID: AudioObjectID) -> UInt32 {
        var address = self.address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeInput)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return 0
        }

        var streams = [AudioObjectID](repeating: 0, count: Int(dataSize) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &streams) == noErr,
              let stream = streams.first else {
            return 0
        }

        var formatAddress = self.address(kAudioStreamPropertyPhysicalFormat)
        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(stream, &formatAddress, 0, nil, &formatSize, &format)
        return status == noErr ? format.mBitsPerChannel : 0
    }

    /// 是否有任意进程正在使用该设备（kAudioDevicePropertyDeviceIsRunningSomewhere）。
    func isRunningSomewhere(_ deviceID: AudioObjectID) -> Bool {
        var address = self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        var isRunning: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &isRunning)
        return status == noErr && isRunning != 0
    }

    // MARK: - 输入音量

    /// 输入音量控制所在的 element：优先主控，回退到通道 1。
    private func inputVolumeElement(_ deviceID: AudioObjectID) -> AudioObjectPropertyElement? {
        for element in [kAudioObjectPropertyElementMain, AudioObjectPropertyElement(1)] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: element
            )
            if AudioObjectHasProperty(deviceID, &address) {
                return element
            }
        }
        return nil
    }

    func hasInputVolumeControl(_ deviceID: AudioObjectID) -> Bool {
        inputVolumeElement(deviceID) != nil
    }

    /// 输入音量（0.0-1.0），设备不支持或读取失败返回 nil。
    func getInputVolume(_ deviceID: AudioObjectID) -> Float? {
        guard let element = inputVolumeElement(deviceID) else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
        var volume: Float32 = 0
        var dataSize = UInt32(MemoryLayout<Float32>.size)

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &volume)
        return status == noErr ? volume : nil
    }

    /// 设置输入音量（0.0-1.0）。对多通道设备会同时写主控与各通道。
    func setInputVolume(_ deviceID: AudioObjectID, volume: Float) throws {
        let clamped = min(max(volume, 0), 1)
        let channelCount = getInputChannelCount(deviceID)
        var didSet = false

        // element 0 是主控，1... 是各通道；不同设备暴露的控制不一样，逐个尝试。
        for element in 0...channelCount {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: AudioObjectPropertyElement(element)
            )
            guard AudioObjectHasProperty(deviceID, &address) else { continue }

            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr,
                  settable.boolValue else { continue }

            var value = Float32(clamped)
            let dataSize = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectSetPropertyData(deviceID, &address, 0, nil, dataSize, &value) == noErr {
                didSet = true
            }
        }

        guard didSet else {
            throw AudioHardwareError.setPropertyDataFailed(
                selector: kAudioDevicePropertyVolumeScalar,
                status: kAudioHardwareUnsupportedOperationError
            )
        }
    }

    // MARK: - 默认输入设备

    func getDefaultInputDeviceID() -> AudioObjectID? {
        var address = self.address(kAudioHardwarePropertyDefaultInputDevice)
        var deviceID = AudioObjectID(0)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &dataSize, &deviceID)
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    @discardableResult
    func setDefaultInputDevice(_ deviceID: AudioObjectID) throws -> Bool {
        var address = self.address(kAudioHardwarePropertyDefaultInputDevice)
        var targetDeviceID = deviceID
        let dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectSetPropertyData(systemObject, &address, 0, nil, dataSize, &targetDeviceID)
        guard status == noErr else {
            throw AudioHardwareError.setPropertyDataFailed(selector: address.mSelector, status: status)
        }
        return true
    }
}
