import Foundation

struct BatteryState {
    // Basic
    var currentCharge: Int = 0
    var isCharging: Bool = false
    var isPluggedIn: Bool = false
    var maxCapacity: Int = 0
    var designCapacity: Int = 0

    // Detail
    var cycleCount: Int = 0
    var temperature: Double = 0.0
    var voltage: Double = 0.0
    var adapterWatts: Int = 0
    var timeRemaining: Int = -1

    // Health
    var healthPercentage: Int {
        guard designCapacity > 0 else { return 100 }
        return min(100, maxCapacity * 100 / designCapacity)
    }

    // Policy
    var chargeLimit: Int = 80
    var dischargeFloor: Int = 20
    var rechargeThreshold: Int = 75
    var isManaging: Bool = false
}
