import SwiftUI

struct ChargeRuleEditorView: View {
    @Environment(\.dismiss) private var dismiss

    // Inputs
    let existingRule: ChargeRule?
    let defaultLeadMinutes: Int
    let onSave: (ChargeRule) -> Void

    // Form state
    @State private var label: String
    @State private var selectedDays: Set<Int>
    @State private var targetDate: Date
    @State private var leadMinutes: Int

    // Calendar weekday: 1=Sun, 2=Mon, ..., 7=Sat
    // Display order: 월(2), 화(3), 수(4), 목(5), 금(6), 토(7), 일(1)
    private let dayLabelMap: [Int: String] = [
        1: "일", 2: "월", 3: "화", 4: "수", 5: "목", 6: "금", 7: "토"
    ]
    private let displayOrder: [Int] = [2, 3, 4, 5, 6, 7, 1]

    init(existingRule: ChargeRule?, defaultLeadMinutes: Int, onSave: @escaping (ChargeRule) -> Void) {
        self.existingRule = existingRule
        self.defaultLeadMinutes = defaultLeadMinutes
        self.onSave = onSave

        if let rule = existingRule {
            _label = State(initialValue: rule.label)
            _selectedDays = State(initialValue: rule.daysOfWeek)
            _targetDate = State(initialValue: {
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                comps.hour = rule.targetHour
                comps.minute = rule.targetMinute
                return Calendar.current.date(from: comps) ?? Date()
            }())
            _leadMinutes = State(initialValue: rule.leadMinutes)
        } else {
            _label = State(initialValue: "")
            _selectedDays = State(initialValue: [2, 3, 4, 5, 6]) // 평일 기본값 (월~금, Calendar weekday 2-6)
            _targetDate = State(initialValue: {
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                comps.hour = 9
                comps.minute = 0
                return Calendar.current.date(from: comps) ?? Date()
            }())
            _leadMinutes = State(initialValue: defaultLeadMinutes)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(existingRule != nil ? "규칙 편집" : "규칙 추가")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            Form {
                // Label
                Section {
                    TextField("예: 화요일 회의", text: $label)
                } header: {
                    Text("이름")
                }

                // Day selection
                Section {
                    HStack(spacing: 6) {
                        ForEach(displayOrder, id: \.self) { dayIndex in
                            DayToggleButton(
                                label: dayLabelMap[dayIndex] ?? "",
                                isSelected: selectedDays.contains(dayIndex)
                            ) {
                                if selectedDays.contains(dayIndex) {
                                    // Keep at least one day selected
                                    if selectedDays.count > 1 {
                                        selectedDays.remove(dayIndex)
                                    }
                                } else {
                                    selectedDays.insert(dayIndex)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("요일")
                }

                // Target time
                Section {
                    DatePicker(
                        "목표 시각",
                        selection: $targetDate,
                        displayedComponents: .hourAndMinute
                    )
                } header: {
                    Text("목표 시각")
                }

                // Lead minutes
                Section {
                    Stepper(
                        "\(leadMinutes)분 전에 충전 시작",
                        value: $leadMinutes,
                        in: 30...120,
                        step: 15
                    )
                } header: {
                    Text("여유 시간")
                }
            }
            .formStyle(.grouped)

            Divider()

            // Buttons
            HStack(spacing: 12) {
                Spacer()

                Button("취소") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("저장") {
                    saveRule()
                }
                .keyboardShortcut(.return)
                .disabled(selectedDays.isEmpty)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 360, height: 420)
    }

    // MARK: - Save

    private func saveRule() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: targetDate)
        let hour = comps.hour ?? 9
        let minute = comps.minute ?? 0

        let rule = ChargeRule(
            id: existingRule?.id ?? UUID(),
            label: label.trimmingCharacters(in: .whitespaces),
            daysOfWeek: selectedDays,
            targetHour: hour,
            targetMinute: minute,
            leadMinutes: leadMinutes,
            enabled: existingRule?.enabled ?? true
        )

        onSave(rule)
        dismiss()
    }
}

// MARK: - DayToggleButton

private struct DayToggleButton: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .bold : .regular))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
