import Foundation

@objc protocol BatteryAgentHelperProtocol {
    func enableCharging(reply: @escaping (Bool) -> Void)
    func disableCharging(reply: @escaping (Bool) -> Void)
    func setForceDischarge(_ enabled: Bool, reply: @escaping (Bool) -> Void)
    func getChargingStatus(reply: @escaping (Bool, Bool) -> Void)
}
