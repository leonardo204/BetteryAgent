import Foundation

// MARK: - Usage Slot

struct UsageSlot {
    var probability: Double
    var observations: Int
}

// MARK: - Detected Pattern

struct DetectedPattern: Identifiable {
    let id: UUID
    var dayOfWeek: Int      // 1=Sunday ... 7=Saturday (Calendar weekday)
    var startSlot: Int      // 0-47 half-hour slot
    var endSlot: Int
    var confidence: Double
    var active: Bool

    init(
        id: UUID = UUID(),
        dayOfWeek: Int,
        startSlot: Int,
        endSlot: Int,
        confidence: Double,
        active: Bool = true
    ) {
        self.id = id
        self.dayOfWeek = dayOfWeek
        self.startSlot = startSlot
        self.endSlot = endSlot
        self.confidence = confidence
        self.active = active
    }
}

// MARK: - Charge Rule

struct ChargeRule: Codable, Identifiable {
    var id: UUID
    var label: String
    var daysOfWeek: Set<Int>  // 1=Sunday ... 7=Saturday
    var targetHour: Int
    var targetMinute: Int
    var leadMinutes: Int
    var enabled: Bool

    init(
        id: UUID = UUID(),
        label: String,
        daysOfWeek: Set<Int>,
        targetHour: Int,
        targetMinute: Int,
        leadMinutes: Int = Constants.defaultSmartLeadMinutes,
        enabled: Bool = true
    ) {
        self.id = id
        self.label = label
        self.daysOfWeek = daysOfWeek
        self.targetHour = targetHour
        self.targetMinute = targetMinute
        self.leadMinutes = leadMinutes
        self.enabled = enabled
    }
}

// MARK: - Smart Charging Status

struct UpcomingCalendarEvent: Identifiable {
    let id = UUID()
    let title: String
    let startDate: Date
    let durationMinutes: Int
    let needsCharging: Bool  // 충전 필요 이벤트 여부
}

struct SmartChargingStatus {
    var isEnabled: Bool
    var isSmartCharging: Bool
    var smartChargingReason: String
    var learningDays: Int
    var learningProgress: Double  // 0.0 - 1.0
    var isLearningComplete: Bool
    var detectedPatterns: [DetectedPattern]
    var calendarEnabled: Bool = false
    var calendarAuthorized: Bool = false
    var nextCalendarEvent: Date? = nil
    var currentCharge: Int = 0
    var upcomingCalendarEvents: [UpcomingCalendarEvent] = []

    static let disabled = SmartChargingStatus(
        isEnabled: false,
        isSmartCharging: false,
        smartChargingReason: "",
        learningDays: 0,
        learningProgress: 0,
        isLearningComplete: false,
        detectedPatterns: []
    )
}

// MARK: - Smart Charge Trigger

enum SmartChargeTrigger {
    case manualRule(ChargeRule)
    case learnedPattern(DetectedPattern)
    case calendarEvent(Date)  // the event start date
    case none
}

// MARK: - Smart Charge Decision

enum SmartChargeDecision {
    case useNormalLimit
    case overrideLimit(Int)  // 100 means "allow full charge"
}
