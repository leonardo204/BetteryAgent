import SwiftUI

struct SmartChargingTab: View {
    @Bindable var viewModel: BatteryViewModel
    @State private var showPatternHeatmap = false
    @State private var showResetAlert = false
    @State private var showAddRuleSheet = false
    @State private var editingRule: ChargeRule? = nil
    @State private var defaultLeadMinutes: Int = {
        let v = UserDefaults.standard.integer(forKey: Constants.UserDefaultsKey.defaultLeadMinutes)
        return v > 0 ? v : Constants.defaultSmartLeadMinutes
    }()
    @State private var calendarEnabled: Bool = UserDefaults.standard.bool(
        forKey: Constants.UserDefaultsKey.calendarIntegrationEnabled
    )

    var body: some View {
        Form {
            // MARK: - Section 1: 자동 패턴 학습
            Section {
                // Smart charging toggle
                HStack {
                    Toggle("스마트 충전 활성화", isOn: Binding(
                        get: { viewModel.smartChargingStatus.isEnabled },
                        set: { _ in viewModel.toggleSmartCharging() }
                    ))
                }

                if viewModel.smartChargingStatus.isEnabled {
                    // Learning status row
                    HStack {
                        if viewModel.smartChargingStatus.isLearningComplete {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text("학습 완료 (\(viewModel.smartChargingStatus.learningDays)일)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "clock.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text("학습 상태: \(viewModel.smartChargingStatus.learningDays)일째")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("자세히") {
                            showPatternHeatmap = true
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    }

                    // Learning progress bar (if not complete)
                    if !viewModel.smartChargingStatus.isLearningComplete {
                        ProgressView(value: viewModel.smartChargingStatus.learningProgress)
                            .tint(.orange)
                    }

                    // Detected patterns list (if learning complete)
                    if viewModel.smartChargingStatus.isLearningComplete
                        && !viewModel.smartChargingStatus.detectedPatterns.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("감지된 패턴")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            ForEach(viewModel.smartChargingStatus.detectedPatterns) { pattern in
                                if pattern.active {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(Color.orange)
                                            .frame(width: 6, height: 6)
                                        Text(formatPattern(pattern))
                                            .font(.caption)
                                        Spacer()
                                        Text("\(Int(pattern.confidence * 100))%")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Reset button
                    Button(role: .destructive) {
                        showResetAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("패턴 초기화")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .alert("패턴 초기화", isPresented: $showResetAlert) {
                        Button("취소", role: .cancel) {}
                        Button("초기화", role: .destructive) {
                            viewModel.resetPatterns()
                        }
                    } message: {
                        Text("학습된 모든 패턴 데이터를 삭제합니다. 이 작업은 되돌릴 수 없습니다.")
                    }
                }
            } header: {
                Label("자동 패턴 학습", systemImage: "brain.head.profile")
            }

            // MARK: - Section 2: 캘린더 연동
            Section {
                Toggle("캘린더 이벤트 기반 충전", isOn: $calendarEnabled)
                    .onChange(of: calendarEnabled) { _, newValue in
                        guard newValue else {
                            viewModel.toggleCalendarIntegration(false)
                            return
                        }
                        // ON → 권한 요청 → 거부 시 토글 OFF
                        Task {
                            let granted = await viewModel.calendarMonitor.requestAccess()
                            if granted {
                                viewModel.toggleCalendarIntegration(true)
                                viewModel.syncSmartChargingStatus()
                            } else {
                                calendarEnabled = false
                            }
                        }
                    }

                if calendarEnabled {
                    HStack {
                        Text("권한 상태")
                        Spacer()
                        Text(calendarPermissionText)
                            .foregroundStyle(calendarPermissionColor)
                            .font(.caption)
                    }

                    HStack {
                        Text("이벤트 시작")
                        Spacer()
                        Text("\(defaultLeadMinutes)분 전 충전 시작")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label("캘린더 연동", systemImage: "calendar.badge.clock")
            }

            // MARK: - Section 3 (was 2): 수동 규칙
            Section {
                if viewModel.chargeRules.isEmpty {
                    Text("등록된 규칙 없음")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                } else {
                    ForEach(viewModel.chargeRules) { rule in
                        ChargeRuleRow(
                            rule: rule,
                            onEdit: { editingRule = rule },
                            onToggle: {
                                var updated = rule
                                updated.enabled = !rule.enabled
                                viewModel.saveChargeRule(updated)
                            }
                        )
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let rule = viewModel.chargeRules[index]
                            viewModel.deleteChargeRule(id: rule.id)
                        }
                    }
                }

                Button {
                    editingRule = nil
                    showAddRuleSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("규칙 추가")
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderless)
            } header: {
                Label("수동 규칙", systemImage: "calendar.badge.clock")
            }

            // MARK: - Section 3: 충전 여유 시간
            Section {
                Stepper(
                    "기본 여유: \(defaultLeadMinutes)분 전 시작",
                    value: $defaultLeadMinutes,
                    in: 30...120,
                    step: 15
                )
                .font(.caption)
                .onChange(of: defaultLeadMinutes) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.defaultLeadMinutes)
                }
            } header: {
                Label("충전 여유 시간", systemImage: "clock.badge.checkmark")
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showPatternHeatmap) {
            PatternHeatmapView(
                patternSlots: viewModel.patternSlots,
                learningDays: viewModel.smartChargingStatus.learningDays,
                lastObservationDate: viewModel.lastObservationDate
            )
        }
        .sheet(isPresented: $showAddRuleSheet) {
            ChargeRuleEditorView(
                existingRule: nil,
                defaultLeadMinutes: defaultLeadMinutes
            ) { newRule in
                viewModel.saveChargeRule(newRule)
            }
        }
        .sheet(item: $editingRule) { rule in
            ChargeRuleEditorView(
                existingRule: rule,
                defaultLeadMinutes: defaultLeadMinutes
            ) { updatedRule in
                viewModel.saveChargeRule(updatedRule)
            }
        }
    }

    // MARK: - Calendar Permission

    private var calendarPermissionText: String {
        if viewModel.smartChargingStatus.calendarAuthorized { return "허용됨" }
        switch viewModel.calendarMonitor.authorizationStatus {
        case .denied, .restricted: return "거부됨"
        default: return "확인 중…"
        }
    }

    private var calendarPermissionColor: Color {
        if viewModel.smartChargingStatus.calendarAuthorized { return .green }
        switch viewModel.calendarMonitor.authorizationStatus {
        case .denied, .restricted: return .red
        default: return .secondary
        }
    }

    // MARK: - Helpers

    private func formatPattern(_ pattern: DetectedPattern) -> String {
        let days = formatDayRange(pattern.dayOfWeek)
        let start = slotToTime(pattern.startSlot)
        let end = slotToTime(pattern.endSlot)
        return "\(days) \(start)~\(end)"
    }

    /// dayOfWeek: 1=일(Sun), 2=월(Mon), ..., 7=토(Sat)  [Calendar weekday]
    private func formatDayRange(_ dayOfWeek: Int) -> String {
        // Map Calendar weekday (1-7) to label
        let labels = ["", "일", "월", "화", "수", "목", "금", "토"]
        guard dayOfWeek >= 1 && dayOfWeek < labels.count else { return "알 수 없음" }
        return labels[dayOfWeek]
    }

    private func slotToTime(_ slot: Int) -> String {
        let hour = slot / 2
        let minute = (slot % 2) * 30
        return String(format: "%02d:%02d", hour, minute)
    }
}

// MARK: - ChargeRuleRow

private struct ChargeRuleRow: View {
    let rule: ChargeRule
    let onEdit: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.label.isEmpty ? "이름 없음" : rule.label)
                    .font(.caption.bold())

                HStack(spacing: 4) {
                    Text(formatDays(rule.daysOfWeek))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%02d:%02d", rule.targetHour, rule.targetMinute))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil.circle")
                    .font(.caption)
            }
            .buttonStyle(.borderless)

            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .controlSize(.mini)
        }
    }

    /// days: Calendar weekday values (1=일, 2=월, ..., 7=토)
    private func formatDays(_ days: Set<Int>) -> String {
        let labelMap: [Int: String] = [
            1: "일", 2: "월", 3: "화", 4: "수", 5: "목", 6: "금", 7: "토"
        ]
        let sorted = days.sorted()
        // 평일: 월(2)~금(6)
        if sorted.count == 5 && !sorted.contains(1) && !sorted.contains(7) {
            return "평일"
        }
        // 주말: 토(7), 일(1)
        if sorted.count == 2 && sorted.contains(1) && sorted.contains(7) {
            return "주말"
        }
        if sorted.count == 7 {
            return "매일"
        }
        return sorted.compactMap { labelMap[$0] }.joined(separator: "·")
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
