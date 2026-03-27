import SwiftUI

struct CalibrationTab: View {
    @Bindable var viewModel: BatteryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("배터리 캘리브레이션")
                .font(.headline)

            Text("배터리 건강도 표시를 정확하게 보정합니다.\n100% 충전 → 완전 방전 → 재충전 과정을 자동으로 진행합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                StepRow(
                    number: 1,
                    title: "100% 완전 충전",
                    step: .chargingToFull,
                    current: viewModel.calibration.currentStep,
                    progress: viewModel.calibration.currentStep == .chargingToFull
                        ? viewModel.calibration.stepProgress : nil
                )
                StepRow(
                    number: 2,
                    title: "완전 방전",
                    step: .dischargingToEmpty,
                    current: viewModel.calibration.currentStep,
                    progress: viewModel.calibration.currentStep == .dischargingToEmpty
                        ? viewModel.calibration.stepProgress : nil
                )
                StepRow(
                    number: 3,
                    title: "재충전",
                    step: .rechargingToFull,
                    current: viewModel.calibration.currentStep,
                    progress: viewModel.calibration.currentStep == .rechargingToFull
                        ? viewModel.calibration.stepProgress : nil
                )
            }

            Spacer()

            HStack {
                if viewModel.calibration.isActive {
                    Button("중단") {
                        viewModel.cancelCalibration()
                    }
                    .controlSize(.large)
                } else if viewModel.calibration.currentStep == .completed {
                    VStack(spacing: 8) {
                        Label("캘리브레이션 완료", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("다시 시작") {
                            viewModel.startCalibration()
                        }
                        .controlSize(.large)
                    }
                } else {
                    Button("캘리브레이션 시작") {
                        viewModel.startCalibration()
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding()
    }
}

private struct StepRow: View {
    let number: Int
    let title: String
    let step: CalibrationStep
    let current: CalibrationStep
    let progress: Double?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .frame(width: 28, height: 28)
                if current.rawValue > step.rawValue || current == .completed {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.caption.bold())
                        .foregroundStyle(current == step ? .white : .secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(current == step ? .semibold : .regular)
                if let progress, current == step {
                    ProgressView(value: progress)
                        .frame(width: 150)
                }
            }
        }
    }

    private var fillColor: Color {
        if current.rawValue > step.rawValue || current == .completed {
            return .green
        } else if current == step {
            return .blue
        } else {
            return .gray.opacity(0.3)
        }
    }
}
