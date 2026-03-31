import SwiftUI

struct SmartChargingReportView: View {
    let status: SmartChargingStatus
    let patternSlots: [[UsageSlot]]

    @Environment(\.dismiss) private var dismiss
    @State private var weeklyStats: WeeklyStats = WeeklyStats(
        totalChargingMinutes: 0,
        avgChargeLevel: 0,
        chargeDisconnectCount: 0,
        plugInCount: 0
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("충전 패턴 리포트")
                        .font(.headline)
                    Text("최근 7일 기준")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("닫기") {
                    dismiss()
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // MARK: - 학습 진행률
                    reportSection(title: "학습 현황", systemImage: "brain.head.profile") {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("학습 일수")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(alignment: .lastTextBaseline, spacing: 2) {
                                    Text("\(status.learningDays)")
                                        .font(.title2.bold())
                                    Text("/ 14일")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text(status.isLearningComplete ? "학습 완료" : "학습 중")
                                    .font(.caption)
                                    .foregroundStyle(status.isLearningComplete ? .green : .orange)
                                ProgressView(value: status.learningProgress)
                                    .tint(status.isLearningComplete ? .green : .orange)
                                    .frame(width: 100)
                            }
                        }
                    }

                    // MARK: - 감지된 패턴
                    reportSection(title: "감지된 패턴", systemImage: "chart.line.uptrend.xyaxis") {
                        let activePatterns = status.detectedPatterns.filter { $0.active }
                        if activePatterns.isEmpty {
                            Text("아직 감지된 패턴이 없습니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 4)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(activePatterns) { pattern in
                                    HStack(spacing: 8) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.orange)
                                            .frame(width: 4)

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(formatPatternTitle(pattern))
                                                .font(.caption.bold())
                                            Text(formatPatternTime(pattern))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Text("\(Int(pattern.confidence * 100))%")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    // MARK: - 이번 주 충전 통계
                    reportSection(title: "이번 주 충전 통계", systemImage: "bolt.fill") {
                        let hours = weeklyStats.totalChargingMinutes / 60
                        let minutes = weeklyStats.totalChargingMinutes % 60

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            statCard(
                                label: "총 충전 시간",
                                value: hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)분",
                                icon: "clock.fill",
                                color: .blue
                            )
                            statCard(
                                label: "평균 충전 잔량",
                                value: String(format: "%.0f%%", weeklyStats.avgChargeLevel),
                                icon: "battery.75",
                                color: .green
                            )
                            statCard(
                                label: "플러그 연결",
                                value: "\(weeklyStats.plugInCount)회",
                                icon: "powerplug.fill",
                                color: .orange
                            )
                            statCard(
                                label: "플러그 해제",
                                value: "\(weeklyStats.chargeDisconnectCount)회",
                                icon: "powerplug",
                                color: .secondary
                            )
                        }
                    }

                    // MARK: - 패턴 히트맵 미니
                    reportSection(title: "사용 패턴 히트맵", systemImage: "square.grid.3x3.fill") {
                        MiniHeatmapView(patternSlots: patternSlots)
                    }

                }
                .padding(16)
            }
        }
        .frame(width: 400, height: 560)
        .onAppear {
            weeklyStats = ChargeHistoryStore.shared.loadWeeklyStats()
        }
    }

    // MARK: - Section Builder

    @ViewBuilder
    private func reportSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            content()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Stat Card

    @ViewBuilder
    private func statCard(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.callout.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Helpers

    private func formatPatternTitle(_ pattern: DetectedPattern) -> String {
        let days = ["", "일", "월", "화", "수", "목", "금", "토"]
        guard pattern.dayOfWeek >= 1 && pattern.dayOfWeek < days.count else { return "알 수 없음" }
        return "\(days[pattern.dayOfWeek])요일 패턴"
    }

    private func formatPatternTime(_ pattern: DetectedPattern) -> String {
        let startH = pattern.startSlot / 2
        let startM = (pattern.startSlot % 2) * 30
        let endH = pattern.endSlot / 2
        let endM = (pattern.endSlot % 2) * 30
        return String(format: "%02d:%02d ~ %02d:%02d", startH, startM, endH, endM)
    }
}

// MARK: - MiniHeatmapView (히트맵 축소 버전)

private struct MiniHeatmapView: View {
    let patternSlots: [[UsageSlot]]

    // 미니 버전: 셀 크기 7pt, 6시간 단위 레이블
    private let cellSize: CGFloat = 7
    private let cellSpacing: CGFloat = 1
    private let dayLabelWidth: CGFloat = 20

    // slots index 0=일(Sun)..6=토(Sat), display 월~일 순서
    private let displayDayOrder: [Int] = [1, 2, 3, 4, 5, 6, 0]
    private let dayLabelMap: [Int: String] = [
        0: "일", 1: "월", 2: "화", 3: "수", 4: "목", 5: "금", 6: "토"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: cellSpacing) {
            // Hour labels (0, 6, 12, 18시)
            HStack(spacing: 0) {
                Spacer().frame(width: dayLabelWidth)
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    Text("\(hour)h")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                        .frame(
                            width: CGFloat(12) * (cellSize + cellSpacing),
                            alignment: .leading
                        )
                }
            }

            ForEach(displayDayOrder, id: \.self) { dayIndex in
                HStack(spacing: cellSpacing) {
                    Text(dayLabelMap[dayIndex] ?? "")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .frame(width: dayLabelWidth, alignment: .trailing)

                    if dayIndex < patternSlots.count {
                        let slots = patternSlots[dayIndex]
                        ForEach(0..<48, id: \.self) { slotIndex in
                            let slot = slotIndex < slots.count
                                ? slots[slotIndex]
                                : UsageSlot(probability: 0, observations: 0)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(cellColor(slot: slot))
                                .frame(width: cellSize, height: cellSize)
                        }
                    } else {
                        ForEach(0..<48, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.gray.opacity(0.15))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }

            // 범례
            HStack(spacing: 8) {
                miniLegend(color: .gray.opacity(0.15), label: "없음")
                miniLegend(color: .yellow.opacity(0.5), label: "30%+")
                miniLegend(color: .orange, label: "70%+")
            }
            .padding(.top, 4)
        }
    }

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

    @ViewBuilder
    private func miniLegend(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
    }
}
