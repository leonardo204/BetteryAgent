import Foundation

enum BatteryDisplayState {
    case charging
    case forceDischarging
    case pluggedIn
    case onBattery
}

enum MenuBarIconProvider {
    static func iconName(for level: Int, state: BatteryDisplayState) -> String {
        switch state {
        case .charging:
            return baseIcon(for: level) + ".bolt"
        case .forceDischarging:
            return "arrow.down.circle"
        case .pluggedIn:
            return baseIcon(for: level)
        case .onBattery:
            return baseIcon(for: level)
        }
    }

    private static func baseIcon(for level: Int) -> String {
        switch level {
        case 0..<13:  return "battery.0percent"
        case 13..<38: return "battery.25percent"
        case 38..<63: return "battery.50percent"
        case 63..<88: return "battery.75percent"
        default:      return "battery.100percent"
        }
    }
}
