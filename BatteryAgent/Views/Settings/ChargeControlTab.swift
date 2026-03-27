import SwiftUI

struct ChargeControlTab: View {
    @Bindable var viewModel: BatteryViewModel

    var body: some View {
        Form {
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
        }
        .formStyle(.grouped)
        .padding()
    }

    private var chargeLimitBinding: Binding<Double> {
        Binding(
            get: { Double(viewModel.chargeLimit) },
            set: { viewModel.chargeLimit = Int($0) }
        )
    }
}
