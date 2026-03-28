import Foundation
import os.log

@MainActor
final class SmartChargeScheduler {
    // MARK: - State

    private(set) var isSmartCharging: Bool = false
    private(set) var currentTrigger: SmartChargeTrigger = .none

    private let logger = Logger(subsystem: Constants.appBundleIdentifier, category: "SmartChargeScheduler")
    private var forceDeactivated: Bool = false

    // MARK: - Evaluate

    /// Returns a decision based on current conditions.
    /// Priority: manual rules > calendar events > learned patterns > normal.
    func evaluate(
        currentCharge: Int,
        isPluggedIn: Bool,
        normalChargeLimit: Int,
        manualRules: [ChargeRule],
        learnedPatterns: [DetectedPattern],
        calendarEventDate: Date? = nil
    ) -> SmartChargeDecision {
        // If the user forced deactivation, respect that until conditions change.
        if forceDeactivated {
            isSmartCharging = false
            currentTrigger = .none
            return .useNormalLimit
        }

        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        guard let weekday = comps.weekday,
              let hour = comps.hour,
              let minute = comps.minute else {
            return .useNormalLimit
        }

        let currentMinuteOfDay = hour * 60 + minute

        // 1. Check manual rules (highest priority)
        for rule in manualRules where rule.enabled && rule.daysOfWeek.contains(weekday) {
            let targetMinuteOfDay = rule.targetHour * 60 + rule.targetMinute
            let windowStart = targetMinuteOfDay - rule.leadMinutes
            let windowEnd = targetMinuteOfDay

            let inWindow: Bool
            if windowStart < 0 {
                // Window crosses midnight
                let adjustedStart = windowStart + 24 * 60
                inWindow = currentMinuteOfDay >= adjustedStart || currentMinuteOfDay <= windowEnd
            } else {
                inWindow = currentMinuteOfDay >= windowStart && currentMinuteOfDay <= windowEnd
            }

            if inWindow {
                logger.info("Manual rule matched: \(rule.label)")
                isSmartCharging = true
                currentTrigger = .manualRule(rule)
                return .overrideLimit(100)
            }
        }

        // 2. Check calendar events (medium priority)
        if let eventDate = calendarEventDate {
            logger.info("Calendar event pre-charge matched: event at \(eventDate)")
            isSmartCharging = true
            currentTrigger = .calendarEvent(eventDate)
            return .overrideLimit(100)
        }

        // 3. Check learned patterns
        let currentSlot = hour * 2 + (minute >= 30 ? 1 : 0)

        for pattern in learnedPatterns where pattern.active && pattern.dayOfWeek == weekday {
            let windowStart = max(0, pattern.startSlot - 2)  // 60 min lead (2 slots)
            let windowEnd = pattern.startSlot

            if currentSlot >= windowStart && currentSlot <= windowEnd {
                logger.info("Learned pattern matched: day=\(pattern.dayOfWeek) slot=\(pattern.startSlot)")
                isSmartCharging = true
                currentTrigger = .learnedPattern(pattern)
                return .overrideLimit(100)
            }
        }

        // No match
        isSmartCharging = false
        currentTrigger = .none
        return .useNormalLimit
    }

    // MARK: - Control

    func forceDeactivate() {
        forceDeactivated = true
        isSmartCharging = false
        currentTrigger = .none
        logger.info("Smart charging force deactivated")
    }

    func clearForceDeactivate() {
        forceDeactivated = false
    }
}
