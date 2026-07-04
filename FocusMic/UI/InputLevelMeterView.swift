import SwiftUI

/// 实时输入电平条。挂载期间驱动 InputLevelMeter 采样，移除后自动停止。
struct InputLevelMeterView: View {
    @State private var meter = InputLevelMeter.shared

    private let segmentCount = 20

    var body: some View {
        Group {
            if meter.permissionDenied {
                Label("需要麦克风权限才能显示电平", systemImage: "mic.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 3) {
                    ForEach(0..<segmentCount, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(segmentColor(index))
                            .frame(height: 10)
                    }
                }
                .animation(.linear(duration: 0.08), value: activeSegments)
            }
        }
        .onAppear { meter.beginMonitoring() }
        .onDisappear { meter.endMonitoring() }
    }

    private var activeSegments: Int {
        Int(meter.level * Float(segmentCount))
    }

    private func segmentColor(_ index: Int) -> Color {
        guard index < activeSegments else {
            return Color.primary.opacity(0.08)
        }
        let ratio = Double(index) / Double(segmentCount)
        if ratio > 0.85 { return .red }
        if ratio > 0.65 { return .warmAccent }
        return .green
    }
}
