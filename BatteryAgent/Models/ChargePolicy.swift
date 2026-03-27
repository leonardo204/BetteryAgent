import Foundation

enum RechargeMode: Int {
    case smart = 0
    case manual = 1
}

enum CalibrationStep: Int {
    case idle = 0
    case chargingToFull = 1
    case dischargingToEmpty = 2
    case rechargingToFull = 3
    case completed = 4
}

struct CalibrationState {
    var isActive: Bool = false
    var currentStep: CalibrationStep = .idle
    var stepProgress: Double = 0.0
}
