import SwiftUI

struct PopoverView: View {
    @Bindable var viewModel: BatteryViewModel
    var onOpenSettings: () -> Void
    var onOpenAISettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Daemon warning banner
            if !SMCClient.shared.isDaemonRunning {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text("충전 제어를 위해 헬퍼 설치가 필요합니다")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                        Spacer()
                        Button("설치") {
                            SMCClient.shared.installDaemon { _ in }
                        }
                        .font(.caption)
                        .controlSize(.small)
                    }
                    if viewModel.daemonInstallFailed {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.shield")
                                .foregroundStyle(.secondary)
                                .font(.caption2)
                            Text("시스템 설정 > 개인정보 보호 및 보안에서 허용해주세요")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                Divider()
            }

            // Status row
            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.batteryState.currentCharge)%")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.batteryState.adapterWatts > 0 {
                    Text("\(viewModel.batteryState.adapterWatts)W")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }

            // Slider
            BatterySliderView(
                currentCharge: viewModel.batteryState.currentCharge,
                chargeLimit: $viewModel.chargeLimit,
                isCharging: viewModel.batteryState.isCharging
            )

            // Toggle + Full Charge + Settings
            HStack {
                Text("활성화")

                CustomToggle(isOn: $viewModel.isManaging, onColor: .blue)

                Spacer()

                // 풀충전 버튼
                if viewModel.isManaging && viewModel.chargeLimit < 100 {
                    Button {
                        viewModel.requestFullCharge()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "battery.100.bolt")
                                .font(.caption)
                            Text("풀충전")
                                .font(.caption)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.borderless)
                    .background(.green.opacity(0.15), in: Capsule())
                    .help("100%까지 충전 후 원래 제한으로 복원")
                } else if viewModel.isManaging && viewModel.isFullChargeMode {
                    Button {
                        viewModel.cancelFullCharge()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark.circle")
                                .font(.caption)
                            Text("풀충전 취소")
                                .font(.caption)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.borderless)
                    .background(.orange.opacity(0.15), in: Capsule())
                    .help("풀충전 취소, 이전 제한으로 복원")
                }

                Button {
                    onOpenSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body)
                }
                .buttonStyle(.borderless)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.body)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.borderless)
                .help("앱 종료")
            }

            Divider()

            // 스마트 충전 상태 섹션
            if viewModel.smartChargingStatus.isEnabled {
                PopoverSmartChargingSection(status: viewModel.smartChargingStatus)
            }

            // AI 상태 섹션
            AIStatusSectionView(
                healthPercentage: viewModel.batteryState.healthPercentage,
                cycleCount: viewModel.batteryState.cycleCount,
                estimatedCyclesRemaining: estimatedCyclesRemaining,
                onOpenAISettings: onOpenAISettings
            )
        }
        .padding(16)
        .frame(width: 280)
    }

    // MARK: - Computed

    private var estimatedCyclesRemaining: Int {
        let s = viewModel.batteryState
        let loss = max(0, s.designCapacity - s.maxCapacity)
        guard s.cycleCount > 0, loss > 0 else { return 999 }
        let perCycle = Double(loss) / Double(s.cycleCount)
        return perCycle > 0 ? Int(Double(s.maxCapacity) * 0.2 / perCycle) : 999
    }

    // MARK: - Status

    private var isOverLimit: Bool {
        viewModel.isManaging
        && viewModel.batteryState.currentCharge > viewModel.chargeLimit
    }

    private var isPlugged: Bool {
        viewModel.batteryState.isPluggedIn || viewModel.batteryState.adapterWatts > 0
    }

    private var statusIcon: String {
        if !isPlugged && !viewModel.batteryState.isCharging {
            return "minus.plus.batteryblock"
        }
        if viewModel.smartChargingStatus.isSmartCharging && viewModel.isManaging {
            return "bolt.fill"
        }
        if isOverLimit {
            return "powerplug.fill"
        } else if viewModel.batteryState.isCharging {
            return "bolt.fill"
        } else if isPlugged {
            return "powerplug.fill"
        } else {
            return "minus.plus.batteryblock"
        }
    }

    private var statusColor: Color {
        if viewModel.isThermalThrottled { return .red }
        if !isPlugged && !viewModel.batteryState.isCharging { return .secondary }
        if viewModel.smartChargingStatus.isSmartCharging && viewModel.isManaging { return .orange }
        if isOverLimit { return .orange }
        if viewModel.batteryState.isCharging { return .green }
        if isPlugged { return .yellow }
        return .secondary
    }

    private var statusText: String {
        if viewModel.isThermalThrottled {
            return String(format: "온도 보호 중 (%.1f°C)", viewModel.batteryState.temperature)
        }
        if !isPlugged && !viewModel.batteryState.isCharging {
            return "배터리 사용 중"
        }
        if isOverLimit {
            return "충전 차단 중 → \(viewModel.chargeLimit)%까지 대기"
        }
        if viewModel.smartChargingStatus.isSmartCharging && viewModel.isManaging {
            if viewModel.batteryState.isCharging {
                return "스마트 충전 중"
            } else {
                return "스마트 충전 대기 중"
            }
        }
        if viewModel.batteryState.isCharging { return "충전 중" }
        if viewModel.isManaging && viewModel.batteryState.currentCharge >= viewModel.chargeLimit {
            return "제한 유지 중"
        }
        if isPlugged {
            return "전원 연결됨"
        }
        return "배터리 사용 중"
    }

    private var timeRemainingText: String {
        let m = viewModel.batteryState.timeRemaining
        let h = m / 60
        let min = m % 60
        if viewModel.batteryState.isCharging {
            return h > 0 ? "완충 \(h)시간 \(min)분" : "완충 \(min)분"
        } else {
            return h > 0 ? "남은 \(h)시간 \(min)분" : "남은 \(min)분"
        }
    }
}

// MARK: - AI 상태 섹션

private struct AIStatusSectionView: View {
    let healthPercentage: Int
    let cycleCount: Int
    let estimatedCyclesRemaining: Int
    let onOpenAISettings: () -> Void

    private var healthColor: Color {
        switch healthPercentage {
        case 90...100: return .green
        case 75..<90:  return .yellow
        default:       return .red
        }
    }

    private var healthLabel: String {
        switch healthPercentage {
        case 90...100: return "우수"
        case 75..<90:  return "양호"
        case 50..<75:  return "주의"
        default:       return "교체 권장"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(healthColor)
                    .font(.caption)
                Text("배터리 건강도")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(healthPercentage)% · \(healthLabel)")
                    .font(.caption)
                    .foregroundStyle(healthColor)
            }

            HStack {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("사이클")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(cycleCount)회 (잔여 약 \(estimatedCyclesRemaining)회)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                onOpenAISettings()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                    Text("AI 분석")
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - Custom Toggle (macOS NSSwitch ignores .tint)

struct CustomToggle: View {
    @Binding var isOn: Bool
    var onColor: Color = .blue

    private let width: CGFloat = 40
    private let height: CGFloat = 22
    private let thumbSize: CGFloat = 18

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? onColor : Color.gray.opacity(0.35))
                .frame(width: width, height: height)

            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                .frame(width: thumbSize, height: thumbSize)
                .padding(2)
        }
        .animation(.easeInOut(duration: 0.15), value: isOn)
        .onTapGesture { isOn.toggle() }
    }
}
