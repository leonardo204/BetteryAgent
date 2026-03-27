import Foundation

extension Notification.Name {
    static let statusBarNeedsUpdate = Notification.Name("statusBarNeedsUpdate")
    static let apiServerToggled = Notification.Name("apiServerToggled")
    static let settingsTabSelected = Notification.Name("settingsTabSelected")
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
        static let apiEnabled = "apiEnabled"
        static let apiPort = "apiPort"
        static let claudeAPIKey = "claudeAPIKey"
        static let claudeAPIBase = "claudeAPIBase"
        static let claudeModel = "claudeModel"
    }

    // MARK: - SMC Keys

    enum SMCKey {
        static let chargingDisable = "CH0B"
        static let chargingControl = "CH0C"
        static let chargingInhibit = "CH0I"
    }

    // MARK: - Defaults

    static let defaultChargeLimit: Int = 80
    static let defaultDischargeFloor = 20
    static let defaultRechargeMode = RechargeMode.smart
    static let pollingInterval: TimeInterval = 30
    static let hysteresis: Int = 5
    static let historyRetentionDays = 7
    static let historyRecordInterval: TimeInterval = 60 // record every 60s
    static let defaultAPIPort: UInt16 = 18080
}
