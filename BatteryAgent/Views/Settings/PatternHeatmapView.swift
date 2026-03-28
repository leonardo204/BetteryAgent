import SwiftUI

struct PatternHeatmapView: View {
    let patternSlots: [[UsageSlot]]
    let learningDays: Int
    let lastObservationDate: Date?

    @Environment(\.dismiss) private var dismiss

    // slots index: 0=일(Sun), 1=월(Mon), ..., 6=토(Sat)
    // Display order: 월(1), 화(2), 수(3), 목(4), 금(5), 토(6), 일(0)
    private let displayDayOrder: [Int] = [1, 2, 3, 4, 5, 6, 0]
    private let dayLabelMap: [Int: String] = [
        0: "일", 1: "월", 2: "화", 3: "수", 4: "목", 5: "금", 6: "토"
    ]

    // Cell size — plan spec: 14x14pt
    private let cellSize: CGFloat = 14
    private let cellSpacing: CGFloat = 1

    // Day label column width
    private let dayLabelWidth: CGFloat = 44

    private var lastDateString: String {
        guard let date = lastObservationDate else { return "없음" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func recentDateLabel(for dayIndex: Int) -> String {
        let calWeekday = dayIndex + 1
        let calendar = Calendar.current
        let today = Date()
        let todayWeekday = calendar.component(.weekday, from: today)

        var offset = todayWeekday - calWeekday
        if offset < 0 { offset += 7 }

        guard let targetDate = calendar.date(byAdding: .day, value: -offset, to: today) else {
            return ""
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: targetDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title area
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("패턴 학습 상세 (최근 14일 기준)")
                        .font(.headline)
                    Text("마지막 학습: \(lastDateString)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("닫기") {
                    dismiss()
                }
                .buttonStyle(.borderless)
            }

            Divider()

            // Upper half: hours 0–11 (slots 0–23)
            heatmapBlock(slotRange: 0..<24, hourLabels: Array(0..<12))

            // Lower half: hours 12–23 (slots 24–47)
            heatmapBlock(slotRange: 24..<48, hourLabels: Array(12..<24))

            Divider()

            // Legend
            HStack(spacing: 12) {
                LegendItem(color: .gray.opacity(0.15), label: "데이터 없음")
                LegendItem(color: .green.opacity(0.2), label: "정상")
                LegendItem(color: .yellow.opacity(0.5), label: "감지 중 (30%+)")
                LegendItem(color: .orange, label: "충전 예약 (70%+)")
            }

            Text("학습 \(learningDays)일째 (활성화 기준: 14일, 임계값: 70%)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .fixedSize()
    }

    // MARK: - Heatmap Block (12 hours = 24 slots)

    @ViewBuilder
    private func heatmapBlock(slotRange: Range<Int>, hourLabels: [Int]) -> some View {
        VStack(alignment: .leading, spacing: cellSpacing) {
            // Time header row — each hour label spans 2 cells
            HStack(spacing: 0) {
                Spacer()
                    .frame(width: dayLabelWidth)

                ForEach(hourLabels, id: \.self) { hour in
                    Text("\(hour)")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .frame(width: (cellSize + cellSpacing) * 2, alignment: .leading)
                }
            }

            // 7 day rows
            ForEach(displayDayOrder, id: \.self) { dayIndex in
                HStack(spacing: cellSpacing) {
                    // Day label
                    let dayName = dayLabelMap[dayIndex] ?? ""
                    let dateStr = recentDateLabel(for: dayIndex)
                    Text("\(dayName) (\(dateStr))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: dayLabelWidth, alignment: .trailing)

                    // 24 slots per block
                    if dayIndex < patternSlots.count {
                        let slots = patternSlots[dayIndex]
                        ForEach(slotRange, id: \.self) { slotIndex in
                            let slot = slotIndex < slots.count
                                ? slots[slotIndex]
                                : UsageSlot(probability: 0, observations: 0)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(cellColor(slot: slot))
                                .frame(width: cellSize, height: cellSize)
                                .help(tooltipText(
                                    dayIndex: dayIndex,
                                    slotIndex: slotIndex,
                                    slot: slot
                                ))
                        }
                    } else {
                        ForEach(slotRange, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.15))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func cellColor(slot: UsageSlot) -> Color {
        if slot.observations < 5 {
            return .gray.opacity(0.15)
        } else if slot.probability >= 0.7 {
            return .orange
        } else if slot.probability >= 0.3 {
            return .yellow.opacity(0.5)
        } else {
            return .green.opacity(0.2)
        }
    }

    private func tooltipText(dayIndex: Int, slotIndex: Int, slot: UsageSlot) -> String {
        let dayName = dayLabelMap[dayIndex] ?? "알 수 없음"
        let startHour = slotIndex / 2
        let startMinute = (slotIndex % 2) * 30
        let endHour = (slotIndex + 1) / 2
        let endMinute = ((slotIndex + 1) % 2) * 30
        let timeRange = String(
            format: "%02d:%02d~%02d:%02d",
            startHour, startMinute, endHour, endMinute
        )
        let probPct = Int(slot.probability * 100)
        return "\(dayName)요일 \(timeRange) | 확률: \(probPct)% | 관측: \(slot.observations)회"
    }
}

// MARK: - LegendItem

private struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
