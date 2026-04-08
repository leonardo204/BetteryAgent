import SwiftUI

struct ChargeControlTab: View {
    @Bindable var viewModel: BatteryViewModel

    @State private var daemonInstalled = SMCClient.shared.isDaemonRunning
    @State private var installingDaemon = false

    var body: some View {
        Form {
            if !daemonInstalled {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading) {
                            Text("충전 제어 헬퍼가 설치되지 않았습니다")
                                .font(.caption.bold())
                            Text("충전 제어를 위해 헬퍼 설치가 필요합니다")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("설치") {
                            installingDaemon = true
                            SMCClient.shared.installDaemon { success in
                                DispatchQueue.main.async {
                                    installingDaemon = false
                                    daemonInstalled = success
                                }
                            }
                        }
                        .disabled(installingDaemon)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            Section("충전 제한") {
                HStack {
                    Text("충전 제한")
                    Spacer()
                    Text("\(viewModel.chargeLimit)%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper("", value: $viewModel.chargeLimit, in: 20...100, step: 5)
                        .labelsHidden()
                }
                Slider(value: chargeLimitBinding, in: 20...100, step: 5) {
                    Text("충전 제한")
                } minimumValueLabel: {
                    Text("20")
                        .font(.caption)
                } maximumValueLabel: {
                    Text("100")
                        .font(.caption)
                }
                if let conflict = viewModel.systemChargeLimitConflict {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(conflict)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            Section("방전 하한") {
                HStack {
                    Text("방전 하한")
                    Spacer()
                    Text("\(viewModel.dischargeFloor)%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper("", value: $viewModel.dischargeFloor, in: 5...50, step: 5)
                        .labelsHidden()
                }
            }

            Section("재충전") {
                Picker("모드", selection: $viewModel.rechargeMode) {
                    Text("스마트 (자동)").tag(RechargeMode.smart)
                    Text("수동").tag(RechargeMode.manual)
                }
                .pickerStyle(.radioGroup)

                if viewModel.rechargeMode == .smart {
                    HStack {
                        Text("재충전 시작")
                        Spacer()
                        Text("\(viewModel.chargeLimit - Constants.hysteresis)%")
                            .foregroundStyle(.secondary)
                        Text("(자동)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    HStack {
                        Text("재충전 시작")
                        Spacer()
                        Text("\(viewModel.manualRechargeThreshold)%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Stepper("", value: $viewModel.manualRechargeThreshold,
                                in: viewModel.dischargeFloor...viewModel.chargeLimit, step: 5)
                            .labelsHidden()
                    }
                }
            }

            Section("알림") {
                Toggle("충전 완료 시 알림", isOn: $viewModel.notifyOnComplete)
            }

            Section("열 보호") {
                Toggle("온도 기반 충전 보호", isOn: $viewModel.thermalProtectionEnabled)

                if viewModel.thermalProtectionEnabled {
                    HStack {
                        Text("온도 임계값")
                        Spacer()
                        Text(String(format: "%.0f°C", viewModel.thermalProtectionThreshold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Stepper(
                            "",
                            value: $viewModel.thermalProtectionThreshold,
                            in: 30...45,
                            step: 1
                        )
                        .labelsHidden()
                    }

                    HStack {
                        Text("현재 온도")
                        Spacer()
                        Text(String(format: "%.1f°C", viewModel.batteryState.temperature))
                            .monospacedDigit()
                            .foregroundStyle(temperatureColor)
                    }

                    Text(thermalHysteresisDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("macOS 배터리 설정") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text("최적화된 배터리 충전을 비활성화하세요")
                            .font(.caption.bold())
                    }
                    Text("macOS의 '최적화된 배터리 충전'이 활성화되어 있으면 BatteryAgent의 충전 제어와 충돌할 수 있습니다. 시스템 설정 > 배터리 > 충전에서 비활성화하세요.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("시스템 배터리 설정 열기") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.battery") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.caption)
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var temperatureColor: Color {
        let temp = viewModel.batteryState.temperature
        let threshold = viewModel.thermalProtectionThreshold
        if temp >= threshold { return .red }
        if temp >= threshold - Constants.thermalHysteresis { return .orange }
        return .secondary
    }

    private var thermalHysteresisDescription: String {
        let threshold = viewModel.thermalProtectionThreshold
        let resume = threshold - Constants.thermalHysteresis
        return String(format: "%.0f°C 초과 시 충전 중단, %.0f°C 이하로 내려가면 재개", threshold, resume)
    }

    private var chargeLimitBinding: Binding<Double> {
        Binding(
            get: { Double(viewModel.chargeLimit) },
            set: { viewModel.chargeLimit = Int($0) }
        )
    }
}
