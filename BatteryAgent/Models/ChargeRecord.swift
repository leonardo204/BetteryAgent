import Foundation

struct ChargeRecord: Identifiable {
    let id = UUID()
    let timestamp: Date
    let charge: Int
    let isCharging: Bool
    let isPluggedIn: Bool
}
