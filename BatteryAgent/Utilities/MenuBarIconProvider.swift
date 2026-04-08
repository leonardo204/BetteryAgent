import AppKit

enum BatteryDisplayState {
    case charging
    case smartCharging
    case forceDischarging
    case pluggedIn
    case onBattery
}

enum MenuBarIconProvider {
    /// 메뉴바에 표시할 NSImage를 반환
    static func statusBarImage(for level: Int, state: BatteryDisplayState) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)

        switch state {
        case .charging, .smartCharging:
            if level >= 100 {
                // 100%: battery.100percent.bolt 단일 심볼
                return NSImage(
                    systemSymbolName: "battery.100percent.bolt",
                    accessibilityDescription: "BatteryAgent"
                )?.withSymbolConfiguration(config)
            } else {
                // 100% 미만: 배터리 아이콘 + 작은 bolt 조합
                return compositeChargingIcon(for: level, config: config)
            }

        case .pluggedIn, .forceDischarging, .onBattery:
            let iconName = baseIconName(for: level)
            return NSImage(
                systemSymbolName: iconName,
                accessibilityDescription: "BatteryAgent"
            )?.withSymbolConfiguration(config)
        }
    }

    /// 배터리 레벨 아이콘 + bolt.fill 오버레이 조합
    private static func compositeChargingIcon(for level: Int, config: NSImage.SymbolConfiguration) -> NSImage? {
        let iconName = baseIconName(for: level)
        guard let batteryImage = NSImage(
            systemSymbolName: iconName,
            accessibilityDescription: "BatteryAgent"
        )?.withSymbolConfiguration(config) else { return nil }

        let boltConfig = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
        guard let boltImage = NSImage(
            systemSymbolName: "bolt.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(boltConfig) else { return batteryImage }

        let batterySize = batteryImage.size
        let boltSize = boltImage.size

        let compositeImage = NSImage(size: NSSize(
            width: batterySize.width + boltSize.width + 1,
            height: batterySize.height
        ))

        compositeImage.lockFocus()
        batteryImage.draw(
            in: NSRect(origin: .zero, size: batterySize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
        // bolt를 배터리 오른쪽에 세로 중앙 배치
        let boltOrigin = NSPoint(
            x: batterySize.width + 1,
            y: (batterySize.height - boltSize.height) / 2
        )
        boltImage.draw(
            in: NSRect(origin: boltOrigin, size: boltSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
        compositeImage.unlockFocus()

        compositeImage.isTemplate = true
        return compositeImage
    }

    private static func baseIconName(for level: Int) -> String {
        switch level {
        case 100:         return "battery.100percent"
        case 63..<100:    return "battery.75percent"
        case 38..<63:     return "battery.50percent"
        case 13..<38:     return "battery.25percent"
        default:          return "battery.0percent"
        }
    }
}
