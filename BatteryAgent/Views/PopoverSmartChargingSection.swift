import SwiftUI

struct PopoverSmartChargingSection: View {
    let status: SmartChargingStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Smart charging actively running
            if status.isSmartCharging {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(status.smartChargingReason)
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }

                // Remaining time estimate
                let remaining = max(0, 100 - status.currentCharge)
                let estimatedMinutes = remaining  // ~1min per 1%
                if estimatedMinutes > 0 {
                    Text("\(status.currentCharge)% → 100% (약 \(estimatedMinutes)분)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Calendar event pre-charge indicator
                if let eventDate = status.nextCalendarEvent {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .foregroundStyle(.blue)
                            .font(.caption)
                        Text("\(formatEventTime(eventDate)) 이벤트 대비 충전 중")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }

            // Learning in progress (not yet complete)
            if !status.isLearningComplete {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("패턴 학습 중 (\(status.learningDays)/14일)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: status.learningProgress)
                    .tint(.orange)
                    .scaleEffect(y: 0.7)
            } else if !status.detectedPatterns.isEmpty {
                // Show detected patterns after learning complete
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("감지된 패턴")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                ForEach(status.detectedPatterns.filter { $0.active }) { pattern in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 5, height: 5)
                        Text(formatPattern(pattern))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(pattern.confidence * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func formatEventTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func formatPattern(_ pattern: DetectedPattern) -> String {
        let dayName = dayLabel(pattern.dayOfWeek)
        let start = slotToTime(pattern.startSlot)
        let end = slotToTime(pattern.endSlot)
        return "\(dayName) \(start)~\(end)"
    }

    /// dayOfWeek: 1=일(Sun), 2=월(Mon), ..., 7=토(Sat)  [Calendar weekday]
    private func dayLabel(_ dayOfWeek: Int) -> String {
        let labels = ["", "일", "월", "화", "수", "목", "금", "토"]
        guard dayOfWeek >= 1 && dayOfWeek < labels.count else { return "?" }
        return labels[dayOfWeek]
    }

    private func slotToTime(_ slot: Int) -> String {
        let hour = slot / 2
        let minute = (slot % 2) * 30
        return String(format: "%02d:%02d", hour, minute)
    }
}
