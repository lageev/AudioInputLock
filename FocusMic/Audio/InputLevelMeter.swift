import AVFoundation
import Observation

/// 实时输入电平监测：用 AVAudioEngine 对系统默认输入做 RMS 采样。
///
/// 只在有界面需要显示电平时运行（引用计数），不做任何录制或存储；
/// 首次使用会触发系统麦克风权限弹窗。
@MainActor
@Observable
final class InputLevelMeter {

    static let shared = InputLevelMeter()

    /// 归一化电平（0.0-1.0），约对应 -60dB 至 0dB。
    private(set) var level: Float = 0
    private(set) var isRunning = false
    private(set) var permissionDenied = false

    private var engine: AVAudioEngine?
    private var activeClients = 0
    private var configurationChangeObserver: NSObjectProtocol?

    private init() {}

    // MARK: - 引用计数

    /// 界面出现时调用。第一个使用方会启动采样。
    func beginMonitoring() {
        activeClients += 1
        guard activeClients == 1 else { return }
        requestPermissionThenStart()
    }

    /// 界面消失时调用。最后一个使用方离开后停止采样。
    func endMonitoring() {
        activeClients = max(0, activeClients - 1)
        guard activeClients == 0 else { return }
        stopEngine()
    }

    // MARK: - 引擎

    private func requestPermissionThenStart() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    self.permissionDenied = !granted
                    if granted, self.activeClients > 0 {
                        self.startEngine()
                    }
                }
            }
        default:
            permissionDenied = true
        }
    }

    private func startEngine() {
        guard engine == nil else { return }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let level = Self.normalizedLevel(of: buffer)
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                // 上升快、回落慢，视觉上更接近常见电平表。
                self.level = level > self.level ? level : self.level * 0.8 + level * 0.2
            }
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return
        }

        self.engine = engine
        isRunning = true

        // 默认输入设备变化时引擎会失效，收到配置变更通知后重启。
        configurationChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restartEngine()
            }
        }
    }

    private func stopEngine() {
        if let configurationChangeObserver {
            NotificationCenter.default.removeObserver(configurationChangeObserver)
            self.configurationChangeObserver = nil
        }
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        isRunning = false
        level = 0
    }

    private func restartEngine() {
        stopEngine()
        guard activeClients > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.activeClients > 0, self.engine == nil else { return }
                self.startEngine()
            }
        }
    }

    /// RMS → dB → 0...1 归一化（-60dB 为 0，0dB 为 1）。
    private nonisolated static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let frames = Int(buffer.frameLength)

        var sum: Float = 0
        for i in 0..<frames {
            sum += data[i] * data[i]
        }
        let rms = sqrt(sum / Float(frames))
        guard rms > 0 else { return 0 }

        let db = 20 * log10(rms)
        return min(max((db + 60) / 60, 0), 1)
    }
}
