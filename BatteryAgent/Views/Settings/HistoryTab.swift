import SwiftUI
import Charts

struct HistoryTab: View {
    @State private var selectedRange: HistoryRange = .day
    @State private var records: [ChargeRecord] = []

    enum HistoryRange: String, CaseIterable {
        case day = "24시간"
        case week = "7일"

        var hours: Int {
            switch self {
            case .day: return 24
            case .week: return 168
            }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Picker("기간", selection: $selectedRange) {
                ForEach(HistoryRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            if records.isEmpty {
                ContentUnavailableView(
                    "이력 없음",
                    systemImage: "chart.xyaxis.line",
                    description: Text("배터리 데이터가 기록되면 여기에 표시됩니다.")
                )
            } else {
                Chart(records) { record in
                    LineMark(
                        x: .value("시간", record.timestamp),
                        y: .value("충전", record.charge)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text("\(v)%")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel(format: selectedRange == .day
                            ? .dateTime.hour()
                            : .dateTime.weekday(.abbreviated))
                    }
                }
                .frame(minHeight: 200)
            }
        }
        .padding()
        .onAppear { loadRecords() }
        .onChange(of: selectedRange) { _, _ in loadRecords() }
    }

    private func loadRecords() {
        records = ChargeHistoryStore.shared.fetchRecords(hours: selectedRange.hours)
    }
}
