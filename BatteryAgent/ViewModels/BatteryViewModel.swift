import Foundation
import os.log
import Observation
import EventKit

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

    // MARK: - Daemon Install State

    /// 헬퍼 설치 시도 후 실패한 경우 true — PopoverView 안내 배너에서 사용
    var daemonInstallFailed: Bool = false

    // MARK: - Smart Charging

    var smartChargingStatus: SmartChargingStatus = .disabled
    var chargeRules: [ChargeRule] = []

    // MARK: - Calendar

    let calendarMonitor = CalendarMonitor()

    // MARK: - Private

    private let batteryMonitor = BatteryMonitor()
    private let smcClient = SMCClient.shared
    private let historyStore = ChargeHistoryStore.shared
    private let calibrationManager = CalibrationManager()
    private let patternTracker = UsagePatternTracker()
    private let smartScheduler = SmartChargeScheduler()
    private var pollingTimer: Timer?
    private var historyTimer: Timer?
    private var patternTimer: Timer?
    private var hasNotifiedCompletion = false
    private let logger = Logger(
        subsystem: Constants.appBundleIdentifier,
        category: "BatteryViewModel"
    )

    private var isSmartChargingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.smartChargingEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.smartChargingEnabled) }
    }

    private var isCalendarIntegrationEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.calendarIntegrationEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.calendarIntegrationEnabled) }
    }

    // MARK: - Init

    init() {
        loadSettings()
        loadChargeRules()
        updateBatteryState()
        startPolling()
        startHistoryRecording()
        startPatternObservation()
        startPowerSourceMonitoring()
        checkAndInstallDaemon()

        Task {
            await NotificationManager.shared.requestAuthorization()
            if isCalendarIntegrationEnabled {
                let granted = await calendarMonitor.requestAccess()
                if granted { syncSmartChargingStatus() }
            }
        }
    }

    private func checkAndInstallDaemon() {
        let client = SMCClient.shared
        let daemonRunning = client.isDaemonRunning

        if daemonRunning {
            // 데몬 실행 중 — 버전 비교 후 불일치 시 업데이트
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let mismatch = client.isHelperVersionMismatch
                guard mismatch else {
                    self.logger.info("Daemon is up-to-date (v\(client.bundleVersion))")
                    return
                }
                let installedVer = client.getHelperVersion() ?? "unknown"
                self.logger.info("Daemon version mismatch: installed=\(installedVer), bundle=\(client.bundleVersion). Updating...")
                client.installDaemon { [weak self] success in
                    DispatchQueue.main.async {
                        if success {
                            self?.logger.info("Daemon updated to v\(client.bundleVersion)")
                            self?.daemonInstallFailed = false
                        } else {
                            self?.logger.error("Daemon update failed")
                            self?.daemonInstallFailed = true
                        }
                    }
                }
            }
        } else {
            // 데몬 미실행 — 최초 설치 시도
            logger.info("Daemon not running, attempting install (bundle v\(client.bundleVersion))...")
            client.installDaemon { [weak self] success in
                DispatchQueue.main.async {
                    if success {
                        self?.logger.info("Daemon installed successfully (v\(client.bundleVersion))")
                        self?.daemonInstallFailed = false
                    } else {
                        self?.logger.error("Daemon install failed")
                        self?.daemonInstallFailed = true
                    }
                }
            }
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
        patternTimer?.invalidate()
        patternTimer = nil
        batteryMonitor.stopPowerSourceMonitoring()
    }

    private func startPowerSourceMonitoring() {
        batteryMonitor.startPowerSourceMonitoring { [weak self] in
            Task { @MainActor in
                self?.updateBatteryState()
                NotificationCenter.default.post(name: .statusBarNeedsUpdate, object: nil)
            }
        }
    }

    private func startPatternObservation() {
        patternTimer = Timer.scheduledTimer(
            withTimeInterval: Constants.patternObservationInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.patternTracker.recordObservation(isPluggedIn: self.batteryState.isPluggedIn)
            }
        }
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

        // Determine effective limit via smart charging
        let effectiveLimit: Int
        if isSmartChargingEnabled {
            let learnedPatterns = historyStore.loadDetectedPatterns()
            let leadMinutes = UserDefaults.standard.integer(forKey: Constants.UserDefaultsKey.defaultLeadMinutes)
            let effectiveLead = leadMinutes > 0 ? leadMinutes : Constants.defaultSmartLeadMinutes
            let calendarEventDate: Date? = isCalendarIntegrationEnabled
                ? calendarMonitor.shouldPreCharge(leadMinutes: effectiveLead)
                : nil
            let decision = smartScheduler.evaluate(
                currentCharge: charge,
                isPluggedIn: pluggedIn,
                normalChargeLimit: chargeLimit,
                manualRules: chargeRules,
                learnedPatterns: learnedPatterns,
                calendarEventDate: calendarEventDate
            )
            switch decision {
            case .useNormalLimit:
                effectiveLimit = chargeLimit
            case .overrideLimit(let limit):
                effectiveLimit = limit
            }
        } else {
            effectiveLimit = chargeLimit
        }

        let wasSmartCharging = smartChargingStatus.isSmartCharging
        syncSmartChargingStatus()
        if !wasSmartCharging && smartChargingStatus.isSmartCharging {
            NotificationManager.shared.sendSmartChargingStartNotification(
                reason: smartChargingStatus.smartChargingReason
            )
        }
        if wasSmartCharging && !smartChargingStatus.isSmartCharging && batteryState.currentCharge >= 99 {
            NotificationManager.shared.sendSmartChargingCompleteNotification()
        }

        // If smart charging is active and we're below the effective limit, ensure charging is enabled
        if effectiveLimit == 100 && batteryState.currentCharge < 100 && batteryState.isPluggedIn {
            smcClient.setForceDischarge(false) { _ in }
            if !batteryState.isCharging {
                smcClient.enableCharging { _ in }
            }
            return  // Skip normal charge limit logic during smart charging
        }

        if charge > effectiveLimit && pluggedIn {
            // 충전 차단만 — 강제 방전 없이 AC 모드 유지, 자연 방전으로 제한치까지 하강
            logger.info("Charge \(charge)% > effectiveLimit \(effectiveLimit)%, disabling charging (AC mode maintained)")
            smcClient.disableCharging { _ in }
            smcClient.setForceDischarge(false) { _ in }

            if notifyOnComplete && !hasNotifiedCompletion {
                NotificationManager.shared.sendChargeCompleteNotification(limit: effectiveLimit)
                hasNotifiedCompletion = true
            }
        } else if charge == effectiveLimit && pluggedIn {
            logger.info("Charge \(charge)% == effectiveLimit \(effectiveLimit)%, holding")
            smcClient.disableCharging { _ in }
            smcClient.setForceDischarge(false) { _ in }
        } else if charge < effectiveLimit && pluggedIn {
            // 히스테리시스는 limit 도달 후 차단된 상태에서만 적용
            // 새로 전원 연결 시(hasNotifiedCompletion=false)에는 바로 충전
            if charge < effectiveRechargeThreshold || !hasNotifiedCompletion {
                if !batteryState.isCharging {
                    logger.info("Charge \(charge)% < effectiveLimit \(effectiveLimit)%, enabling charging (rechargeThreshold=\(self.effectiveRechargeThreshold), wasLimited=\(self.hasNotifiedCompletion))")
                    smcClient.enableCharging { _ in }
                }
                if charge < effectiveRechargeThreshold {
                    hasNotifiedCompletion = false
                }
            }
            smcClient.setForceDischarge(false) { _ in }
        }

        // Safety: never go below discharge floor
        if charge <= dischargeFloor {
            logger.info("Charge \(charge)% <= floor \(self.dischargeFloor)%, stopping discharge")
            smcClient.setForceDischarge(false) { _ in }
            smcClient.enableCharging { _ in }
        }
    }

    // MARK: - Smart Charging Methods

    func syncSmartChargingStatus() {
        let learningDays = patternTracker.learningDays
        let learnedPatterns = historyStore.loadDetectedPatterns()
        let progress = min(1.0, Double(learningDays) / Double(Constants.learningPeriodDays))

        // Determine next calendar event if integration is enabled
        let nextCalendarEvent: Date?
        if isCalendarIntegrationEnabled {
            let leadMinutes = UserDefaults.standard.integer(forKey: Constants.UserDefaultsKey.defaultLeadMinutes)
            let effectiveLead = leadMinutes > 0 ? leadMinutes : Constants.defaultSmartLeadMinutes
            let upcomingEvents = calendarMonitor.fetchUpcomingEvents(leadMinutes: effectiveLead)
            nextCalendarEvent = upcomingEvents.first?.startDate
            if let next = nextCalendarEvent {
                logger.info("Next calendar event: \(next), lead=\(effectiveLead)min")
            } else {
                logger.info("No upcoming calendar events (lead=\(effectiveLead)min)")
            }
        } else {
            nextCalendarEvent = nil
        }

        smartChargingStatus = SmartChargingStatus(
            isEnabled: isSmartChargingEnabled,
            isSmartCharging: smartScheduler.isSmartCharging,
            smartChargingReason: {
                switch smartScheduler.currentTrigger {
                case .manualRule(let rule): return "규칙: \(rule.label)"
                case .learnedPattern: return "학습된 패턴"
                case .calendarEvent: return "캘린더 이벤트"
                case .none: return ""
                }
            }(),
            learningDays: learningDays,
            learningProgress: progress,
            isLearningComplete: learningDays >= Constants.learningPeriodDays,
            detectedPatterns: learnedPatterns,
            calendarEnabled: isCalendarIntegrationEnabled,
            calendarAuthorized: calendarMonitor.authorizationStatus == EKAuthorizationStatus.fullAccess,
            nextCalendarEvent: nextCalendarEvent,
            currentCharge: batteryState.currentCharge
        )
    }

    func toggleCalendarIntegration(_ enabled: Bool) {
        isCalendarIntegrationEnabled = enabled
        syncSmartChargingStatus()
        logger.info("Calendar integration toggled: \(enabled)")
    }

    func toggleSmartCharging() {
        isSmartChargingEnabled.toggle()
        if isSmartChargingEnabled {
            smartScheduler.clearForceDeactivate()
        }
        syncSmartChargingStatus()
        logger.info("Smart charging toggled: \(self.isSmartChargingEnabled)")
    }

    func saveChargeRule(_ rule: ChargeRule) {
        if let idx = chargeRules.firstIndex(where: { $0.id == rule.id }) {
            chargeRules[idx] = rule
        } else {
            chargeRules.append(rule)
        }
        persistChargeRules()
    }

    func deleteChargeRule(id: UUID) {
        chargeRules.removeAll { $0.id == id }
        persistChargeRules()
    }

    func resetPatterns() {
        patternTracker.resetPatterns()
        smartScheduler.clearForceDeactivate()
        syncSmartChargingStatus()
        logger.info("Patterns reset by user")
    }

    var patternSlots: [[UsageSlot]] {
        patternTracker.slots
    }

    var lastObservationDate: Date? {
        patternTracker.lastObservationDate
    }

    private func loadChargeRules() {
        guard let data = UserDefaults.standard.data(forKey: Constants.UserDefaultsKey.chargeRules),
              let rules = try? JSONDecoder().decode([ChargeRule].self, from: data) else {
            chargeRules = []
            return
        }
        chargeRules = rules
    }

    private func persistChargeRules() {
        guard let data = try? JSONEncoder().encode(chargeRules) else { return }
        UserDefaults.standard.set(data, forKey: Constants.UserDefaultsKey.chargeRules)
    }
}
