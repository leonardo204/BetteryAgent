import Foundation
import os.log

@MainActor
final class UsagePatternTracker {
    // MARK: - State

    private(set) var slots: [[UsageSlot]]  // [day 0-6][slot 0-47]
    private let store = ChargeHistoryStore.shared
    private let logger = Logger(subsystem: Constants.appBundleIdentifier, category: "UsagePatternTracker")

    // MARK: - Learning Metadata

    var learningDays: Int {
        guard let firstStr = store.loadMeta(key: "first_observation_date"),
              let firstDate = ISO8601DateFormatter().date(from: firstStr) else {
            return 0
        }
        return Calendar.current.dateComponents([.day], from: firstDate, to: Date()).day ?? 0
    }

    var lastObservationDate: Date? {
        guard let str = store.loadMeta(key: "last_observation_date") else { return nil }
        return ISO8601DateFormatter().date(from: str)
    }

    // MARK: - Init

    init() {
        slots = store.loadUsagePatterns()
        applyWeeklyDecayIfNeeded()
    }

    // MARK: - Weekly Decay (Rolling Window)

    /// 주간 단위로 observation 카운트를 감쇠시켜 오래된 패턴이 자연스럽게 사라지도록 함.
    /// 최근 14일 데이터에 가중치를 두는 롤링 윈도우 효과.
    private func applyWeeklyDecayIfNeeded() {
        let lastDecayKey = "last_decay_date"
        let now = Date()

        guard let lastStr = store.loadMeta(key: lastDecayKey),
              let lastDate = ISO8601DateFormatter().date(from: lastStr) else {
            // 첫 실행 — 현재 날짜 기록만
            store.saveMeta(key: lastDecayKey, value: ISO8601DateFormatter().string(from: now))
            return
        }

        let daysSinceDecay = Calendar.current.dateComponents([.day], from: lastDate, to: now).day ?? 0
        guard daysSinceDecay >= 7 else { return }

        // 경과 주 수만큼 감쇠 적용 (decay factor 0.7 per week)
        let weeks = daysSinceDecay / 7
        let decayFactor = pow(0.7, Double(weeks))

        logger.info("Applying weekly decay: \(weeks) week(s), factor=\(decayFactor, format: .fixed(precision: 3))")

        for day in 0..<7 {
            for slot in 0..<48 {
                var s = slots[day][slot]
                guard s.observations > 0 else { continue }

                // observation 카운트 감쇠 (최소 관측 기준 미달 시 패턴 자동 소멸)
                let decayed = Int(Double(s.observations) * decayFactor)
                s.observations = max(0, decayed)

                // 관측 0이면 확률도 리셋
                if s.observations == 0 {
                    s.probability = 0
                }

                slots[day][slot] = s
                store.upsertUsageSlot(day: day, slot: slot, probability: s.probability, observations: s.observations)
            }
        }

        store.saveMeta(key: lastDecayKey, value: ISO8601DateFormatter().string(from: now))
    }

    // MARK: - Record Observation

    /// Called every `patternObservationInterval` seconds.
    func recordObservation(isPluggedIn: Bool) {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: now)

        // weekday: 1=Sunday ... 7=Saturday → index 0-6
        guard let weekday = components.weekday,
              let hour = components.hour,
              let minute = components.minute else { return }

        let dayIndex = weekday - 1          // 0-6
        let slotIndex = hour * 2 + (minute >= 30 ? 1 : 0)  // 0-47

        let alpha = Constants.ewmaAlpha
        let current = slots[dayIndex][slotIndex]
        let newValue = isPluggedIn ? 1.0 : 0.0
        let newProbability = current.probability * (1 - alpha) + newValue * alpha
        let newObservations = current.observations + 1

        slots[dayIndex][slotIndex] = UsageSlot(probability: newProbability, observations: newObservations)

        // Persist asynchronously
        store.upsertUsageSlot(day: dayIndex, slot: slotIndex, probability: newProbability, observations: newObservations)

        // Record first observation date if needed
        let dateStr = ISO8601DateFormatter().string(from: now)
        if store.loadMeta(key: "first_observation_date") == nil {
            store.saveMeta(key: "first_observation_date", value: dateStr)
            logger.info("First observation recorded: \(dateStr)")
        }
        store.saveMeta(key: "last_observation_date", value: dateStr)

        logger.debug("Slot [\(dayIndex)][\(slotIndex)] prob=\(newProbability, format: .fixed(precision: 3)) obs=\(newObservations)")
    }

    // MARK: - Detect Patterns

    /// Merge consecutive high-probability slots into DetectedPattern entries.
    func detectPatterns() -> [DetectedPattern] {
        var patterns: [DetectedPattern] = []
        let threshold = Constants.patternThreshold
        let minObs = Constants.minPatternObservations

        for day in 0..<7 {
            var i = 0
            while i < 48 {
                let slot = slots[day][i]
                guard slot.probability >= threshold && slot.observations >= minObs else {
                    i += 1
                    continue
                }

                // Start of a candidate run
                var runStart = i
                var runEnd = i
                var confidenceSum = slot.probability

                i += 1
                while i < 48 {
                    let next = slots[day][i]
                    if next.probability >= threshold && next.observations >= minObs {
                        runEnd = i
                        confidenceSum += next.probability
                        i += 1
                    } else if i + 1 < 48 {
                        // Allow gap of 1
                        let afterGap = slots[day][i + 1]
                        if afterGap.probability >= threshold && afterGap.observations >= minObs {
                            runEnd = i + 1
                            confidenceSum += afterGap.probability
                            i += 2
                        } else {
                            break
                        }
                    } else {
                        break
                    }
                }

                let length = runEnd - runStart + 1
                let avgConfidence = confidenceSum / Double(length)
                let pattern = DetectedPattern(
                    dayOfWeek: day + 1,  // 1=Sunday ... 7=Saturday
                    startSlot: runStart,
                    endSlot: runEnd,
                    confidence: avgConfidence
                )
                patterns.append(pattern)
            }
        }

        // Persist
        store.replaceDetectedPatterns(patterns)
        logger.info("Detected \(patterns.count) patterns")
        return patterns
    }

    // MARK: - Reset

    func resetPatterns() {
        slots = Array(repeating: Array(repeating: UsageSlot(probability: 0, observations: 0), count: 48), count: 7)
        store.clearSmartChargingData()
        logger.info("All usage patterns cleared")
    }
}
