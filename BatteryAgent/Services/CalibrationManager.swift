import Foundation
import os.log

@MainActor
class CalibrationManager {
    var state = CalibrationState()

    private let logger = Logger(
        subsystem: Constants.appBundleIdentifier,
        category: "Calibration"
    )

    func start() {
        state.isActive = true
        state.currentStep = .chargingToFull
        state.stepProgress = 0.0
        logger.info("Calibration started: charging to full")
        NotificationManager.shared.sendCalibrationStepNotification(
            step: "캘리브레이션 시작: 100%까지 충전합니다."
        )
    }

    func cancel() {
        state.isActive = false
        state.currentStep = .idle
        state.stepProgress = 0.0
        logger.info("Calibration cancelled")
    }

    func update(charge: Int, isCharging: Bool, isPluggedIn: Bool,
                enableCharging: () -> Void, disableCharging: () -> Void,
                enableForceDischarge: () -> Void, disableForceDischarge: () -> Void) {
        guard state.isActive else { return }

        switch state.currentStep {
        case .chargingToFull:
            state.stepProgress = Double(charge) / 100.0
            enableCharging()
            if charge >= 100 {
                state.currentStep = .dischargingToEmpty
                state.stepProgress = 0.0
                logger.info("Calibration: full charge reached, starting discharge")
                NotificationManager.shared.sendCalibrationStepNotification(
                    step: "충전 완료. 방전을 시작합니다."
                )
                enableForceDischarge()
            }

        case .dischargingToEmpty:
            state.stepProgress = Double(100 - charge) / 100.0
            disableCharging()
            if charge <= 5 {
                state.currentStep = .rechargingToFull
                state.stepProgress = 0.0
                logger.info("Calibration: discharge complete, recharging")
                NotificationManager.shared.sendCalibrationStepNotification(
                    step: "방전 완료. 재충전을 시작합니다."
                )
                disableForceDischarge()
                enableCharging()
            }

        case .rechargingToFull:
            state.stepProgress = Double(charge) / 100.0
            enableCharging()
            if charge >= 100 {
                state.currentStep = .completed
                state.stepProgress = 1.0
                state.isActive = false
                logger.info("Calibration completed")
                NotificationManager.shared.sendCalibrationStepNotification(
                    step: "캘리브레이션 완료!"
                )
                disableCharging()
            }

        case .idle, .completed:
            break
        }
    }
}
