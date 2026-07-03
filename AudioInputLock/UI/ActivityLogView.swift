import SwiftUI

/// 完整活动日志窗口：主窗口只保留摘要，这里展示本地保存的全部日志。
struct ActivityLogView: View {
    @Environment(PreferredInputDeviceKeeper.self) private var keeper

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if keeper.logs.isEmpty {
                ContentUnavailableView(
                    "暂无活动",
                    systemImage: "clock.badge.questionmark",
                    description: Text("设备切换或守护动作会显示在这里。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(keeper.logs) { entry in
                            ActivityLogRow(entry: entry)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)

                            Divider()
                                .padding(.leading, 20)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("活动日志")
                    .font(.title3.weight(.semibold))
                Text("当前 \(keeper.logs.count) 条，本地最多保留 50 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }
}

struct ActivityLogRow: View {
    let entry: PreferredInputDeviceKeeper.LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(entry.date, format: .dateTime.hour().minute().second())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)

            Text(entry.message)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
