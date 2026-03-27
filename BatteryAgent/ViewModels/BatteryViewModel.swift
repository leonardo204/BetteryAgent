import Foundation
import os.log
import Observation

@MainActor
@Observable
class BatteryViewModel {

    // MARK: - State

    var batteryState = BatteryState()

    var chargeLimit: Int = Constants.defaultChargeLimit {
        didSet {
            UserDefaults.standard.set(chargeLimit, forKey: Constants.UserDefaultsKey.chargeLimit)
            batteryState.chargeLimit = chargeLimit
            updateRechargeThreshold()
        }
    }

    var dischargeFloor: Int = Constants.defaultDischargeFloor {
        didSet {
            UserDefaults.standard.set(dischargeFloor, forKey: Constants.UserDefaultsKey.dischargeFloor)
            batteryState.dischargeFloor = dischargeFloor
        }
    }

    var rechargeMode: RechargeMode = .smart {
        didSet {
            UserDefaults.standard.set(rechargeMode.rawValue, forKey: Constants.UserDefaultsKey.rechargeMode)
            updateRechargeThreshold()
        }
    }

    var manualRechargeThreshold: Int = 60 {
        didSet {
            UserDefaults.standard.set(manualRechargeThreshold, forKey: Constants.UserDefaultsKey.rechargeThreshold)
            updateRechargeThreshold()
        }
    }

    var isManaging: Bool = false {
        didSet {
            UserDefaults.standard.set(isManaging, forKey: Constants.UserDefaultsKey.isManaging)
            batteryState.isManaging = isManaging
            if isManaging {
                evaluateChargingPolicy()
            } else {
                // Turn off: re-enable charging and stop force discharge
                smcClient.enableCharging { _ in }
                smcClient.setForceDischarge(false) { _ in }
            }
            // Refresh state after a short delay for SMC to take effect
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.updateBatteryState()
                NotificationCenter.default.post(name: .statusBarNeedsUpdate, object: nil)
            }
        }
    }

    var showPercentage: Bool = false {
        didSet {
            UserDefaults.standard.set(showPercentage, forKey: Constants.UserDefaultsKey.showPercentage)
            NotificationCenter.default.post(name: .statusBarNeedsUpdate, object: nil)
        }
    }

    var notifyOnComplete: Bool = true {
        didSet {
            UserDefaults.standard.set(notifyOnComplete, forKey: Constants.UserDefaultsKey.notifyOnComplete)
        }
    }

    var calibration: CalibrationState {
        calibrationManager.state
    }

    // MARK: - Private

    private let batteryMonitor = BatteryMonitor()
    private let smcClient = SMCClient.shared
    private let historyStore = ChargeHistoryStore.shared
    private let calibrationManager = CalibrationManager()
    private var pollingTimer: Timer?
    private var historyTimer: Timer?
    private var hasNotifiedCompletion = false
    private let logger = Logger(
        subsystem: Constants.appBundleIdentifier,
        category: "BatteryViewModel"
    )

    // MARK: - Init

    init() {
        loadSettings()
        updateBatteryState()
        startPolling()
        startHistoryRecording()

        Task {
            await NotificationManager.shared.requestAuthorization()
        }
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard

        let savedLimit = defaults.integer(forKey: Constants.UserDefaultsKey.chargeLimit)
        chargeLimit = savedLimit > 0 ? savedLimit : Constants.defaultChargeLimit

        let savedFloor = defaults.integer(forKey: Constants.UserDefaultsKey.dischargeFloor)
        dischargeFloor = savedFloor > 0 ? savedFloor : Constants.defaultDischargeFloor

        let savedMode = defaults.integer(forKey: Constants.UserDefaultsKey.rechargeMode)
        rechargeMode = RechargeMode(rawValue: savedMode) ?? .smart

        let savedThreshold = defaults.integer(forKey: Constants.UserDefaultsKey.rechargeThreshold)
        manualRechargeThreshold = savedThreshold > 0 ? savedThreshold : (chargeLimit - Constants.hysteresis)

        isManaging = defaults.bool(forKey: Constants.UserDefaultsKey.isManaging)
        showPercentage = defaults.bool(forKey: Constants.UserDefaultsKey.showPercentage)
        notifyOnComplete = defaults.object(forKey: Constants.UserDefaultsKey.notifyOnComplete) == nil
            ? true : defaults.bool(forKey: Constants.UserDefaultsKey.notifyOnComplete)

        // Sync to batteryState
        batteryState.chargeLimit = chargeLimit
        batteryState.dischargeFloor = dischargeFloor
        batteryState.isManaging = isManaging
        updateRechargeThreshold()
    }

    // MARK: - Battery State

    func updateBatteryState() {
        var state = batteryMonitor.getBatteryState()
        state.chargeLimit = chargeLimit
        state.dischargeFloor = dischargeFloor
        state.rechargeThreshold = effectiveRechargeThreshold
        state.isManaging = isManaging
        batteryState = state

        if calibrationManager.state.isActive {
            calibrationManager.update(
                charge: state.currentCharge,
                isCharging: state.isCharging,
                isPluggedIn: state.isPluggedIn,
                enableCharging: { [weak self] in self?.smcClient.enableCharging { _ in } },
                disableCharging: { [weak self] in self?.smcClient.disableCharging { _ in } },
                enableForceDischarge: { [weak self] in self?.smcClient.setForceDischarge(true) { _ in } },
                disableForceDischarge: { [weak self] in self?.smcClient.setForceDischarge(false) { _ in } }
            )
        } else if isManaging {
            evaluateChargingPolicy()
        }
    }

    // MARK: - Charge Limit Controls

    func incrementChargeLimit() {
        chargeLimit = min(chargeLimit + 5, 100)
    }

    func decrementChargeLimit() {
        chargeLimit = max(chargeLimit - 5, 20)
    }

    // MARK: - Management

    func toggleManaging() {
        isManaging.toggle()
    }

    func forceDischarge() {
        logger.info("Force discharge requested")
        smcClient.setForceDischarge(true) { _ in }
    }

    func forceCharge() {
        logger.info("Force charge requested")
        smcClient.enableCharging { _ in }
    }

    // MARK: - Calibration

    func startCalibration() {
        calibrationManager.start()
    }

    func cancelCalibration() {
        calibrationManager.cancel()
        smcClient.setForceDischarge(false) { _ in }
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        pollingTimer = Timer.scheduledTimer(
            withTimeInterval: Constants.pollingInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateBatteryState()
            }
        }
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        historyTimer?.invalidate()
        historyTimer = nil
    }

    private func startHistoryRecording() {
        historyTimer = Timer.scheduledTimer(
            withTimeInterval: Constants.historyRecordInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.historyStore.record(
                    charge: self.batteryState.currentCharge,
                    isCharging: self.batteryState.isCharging,
                    isPluggedIn: self.batteryState.isPluggedIn
                )
            }
        }
        // Prune old records on start
        historyStore.pruneOldRecords()
    }

    // MARK: - Private

    private var effectiveRechargeThreshold: Int {
        switch rechargeMode {
        case .smart: return chargeLimit - Constants.hysteresis
        case .manual: return manualRechargeThreshold
        }
    }

    private func updateRechargeThreshold() {
        batteryState.rechargeThreshold = effectiveRechargeThreshold
    }

    private func evaluateChargingPolicy() {
        let charge = batteryState.currentCharge
        let pluggedIn = batteryState.isPluggedIn

        if charge > chargeLimit && pluggedIn {
            // Over limit: disable charging AND force discharge to bring level down
            logger.info("Charge \(charge)% > limit \(self.chargeLimit)%, disabling charging + force discharge")
            smcClient.disableCharging { _ in }
            smcClient.setForceDischarge(true) { _ in }

            if notifyOnComplete && !hasNotifiedCompletion {
                NotificationManager.shared.sendChargeCompleteNotification(limit: chargeLimit)
                hasNotifiedCompletion = true
            }
        } else if charge == chargeLimit && pluggedIn {
            // At limit: disable charging, stop force discharge (hold at limit)
            logger.info("Charge \(charge)% == limit \(self.chargeLimit)%, holding")
            smcClient.disableCharging { _ in }
            smcClient.setForceDischarge(false) { _ in }
        } else if charge < effectiveRechargeThreshold && pluggedIn {
            // Below recharge threshold: enable charging, stop force discharge
            logger.info("Charge \(charge)% < \(self.effectiveRechargeThreshold)%, re-enabling charging")
            smcClient.enableCharging { _ in }
            smcClient.setForceDischarge(false) { _ in }
            hasNotifiedCompletion = false
        }

        // Safety: never go below discharge floor
        if charge <= dischargeFloor {
            logger.info("Charge \(charge)% <= floor \(self.dischargeFloor)%, stopping discharge")
            smcClient.setForceDischarge(false) { _ in }
            smcClient.enableCharging { _ in }
        }
    }
}
