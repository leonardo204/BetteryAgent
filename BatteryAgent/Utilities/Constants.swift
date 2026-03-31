import Foundation

extension Notification.Name {
    static let statusBarNeedsUpdate = Notification.Name("statusBarNeedsUpdate")
    static let settingsTabSelected = Notification.Name("settingsTabSelected")
    static let settingsWindowNeedsFront = Notification.Name("settingsWindowNeedsFront")
}

enum Constants {
    // MARK: - Bundle Identifiers

    static let appBundleIdentifier = "com.zerolive.BatteryAgent"
    static let helperBundleIdentifier = "com.zerolive.BatteryAgentHelper"

    // MARK: - UserDefaults Keys

    enum UserDefaultsKey {
        static let chargeLimit = "chargeLimit"
        static let isManaging = "isManaging"
        static let dischargeFloor = "dischargeFloor"
        static let rechargeMode = "rechargeMode"
        static let rechargeThreshold = "rechargeThreshold"
        static let showPercentage = "showPercentage"
        static let notifyOnComplete = "notifyOnComplete"
        static let claudeAPIKey = "claudeAPIKey"
        static let claudeAPIBase = "claudeAPIBase"
        static let claudeModel = "claudeModel"
        static let smartChargingEnabled = "smartChargingEnabled"
        static let chargeRules = "chargeRules"
        static let defaultLeadMinutes = "defaultLeadMinutes"
        static let calendarIntegrationEnabled = "calendarIntegrationEnabled"
        static let thermalProtectionEnabled = "thermalProtectionEnabled"
        static let thermalProtectionThreshold = "thermalProtectionThreshold"
    }

    // MARK: - SMC Keys

    enum SMCKey {
        static let chargingDisable = "CH0B"
        static let chargingControl = "CH0C"
        static let chargingInhibit = "CH0I"
    }

    // MARK: - Defaults

    static let defaultChargeLimit: Int = 80
    static let defaultThermalThreshold: Double = 35.0
    static let thermalHysteresis: Double = 2.0
    static let defaultDischargeFloor = 20
    static let defaultRechargeMode = RechargeMode.smart
    static let pollingInterval: TimeInterval = 30
    static let hysteresis: Int = 5
    static let historyRetentionDays = 30
    static let historyRecordInterval: TimeInterval = 60 // record every 60s

    // MARK: - Smart Charging

    static let patternObservationInterval: TimeInterval = 300
    static let ewmaAlpha: Double = 0.1
    static let patternThreshold: Double = 0.7
    static let minPatternObservations: Int = 20
    static let learningPeriodDays: Int = 14
    static let defaultSmartLeadMinutes: Int = 60
}
