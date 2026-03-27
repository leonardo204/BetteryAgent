import SwiftUI

struct BatteryInfoTab: View {
    @Bindable var viewModel: BatteryViewModel

    var body: some View {
        Form {
            Section("건강") {
                HStack {
                    Text("건강도")
                    Spacer()
                    healthBar
                        .frame(width: 100)
                    Text("\(viewModel.batteryState.healthPercentage)%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                InfoRow(label: "사이클 수", value: "\(viewModel.batteryState.cycleCount)")
            }

            Section("용량") {
                InfoRow(label: "현재 충전", value: "\(viewModel.batteryState.currentCharge)%")
                InfoRow(label: "설계 용량", value: "\(viewModel.batteryState.designCapacity) mAh")
                InfoRow(label: "현재 최대 용량", value: "\(viewModel.batteryState.maxCapacity) mAh")
            }

            Section("상태") {
                InfoRow(label: "온도", value: String(format: "%.1f°C", viewModel.batteryState.temperature))
                InfoRow(label: "전압", value: String(format: "%.2fV", viewModel.batteryState.voltage))
                InfoRow(label: "어댑터 전력",
                        value: viewModel.batteryState.adapterWatts > 0
                            ? "\(viewModel.batteryState.adapterWatts)W" : "—")
                InfoRow(label: "전원", value: viewModel.batteryState.isPluggedIn ? "연결됨" : "배터리")
                InfoRow(label: "충전 상태",
                        value: viewModel.batteryState.isCharging ? "충전 중" : "미충전")
                if viewModel.batteryState.timeRemaining > 0 {
                    InfoRow(label: viewModel.batteryState.isCharging ? "완충까지" : "남은 시간",
                            value: formatTime(viewModel.batteryState.timeRemaining))
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private var healthBar: some View {
        let health = viewModel.batteryState.healthPercentage
        ProgressView(value: Double(health), total: 100)
            .tint(health > 80 ? .green : health > 50 ? .yellow : .red)
    }

    private func formatTime(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 {
            return "\(h)시간 \(m)분"
        }
        return "\(m)분"
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
