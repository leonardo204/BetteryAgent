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
