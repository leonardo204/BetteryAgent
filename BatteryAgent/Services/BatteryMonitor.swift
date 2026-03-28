import Foundation
import IOKit
import IOKit.ps

class BatteryMonitor {

    private var powerSourceCallback: (() -> Void)?
    private var runLoopSource: CFRunLoopSource?

    /// 전원 상태 변경 시 즉시 콜백 호출 (충전 연결/해제 등)
    func startPowerSourceMonitoring(onChange: @escaping () -> Void) {
        powerSourceCallback = onChange
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSCreateLimitedPowerNotification({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.powerSourceCallback?()
        }, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    func stopPowerSourceMonitoring() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = nil
        }
        powerSourceCallback = nil
    }

    func getBatteryState() -> BatteryState {
        var state = BatteryState()

        // Power source info (charge %, charging status)
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
           let firstSource = sources.first,
           let desc = IOPSGetPowerSourceDescription(snapshot, firstSource as CFTypeRef)?
            .takeUnretainedValue() as? [String: Any] {

            state.currentCharge = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            state.isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false

            if let src = desc[kIOPSPowerSourceStateKey] as? String {
                state.isPluggedIn = (src == kIOPSACPowerValue)
            }

            if state.isCharging {
                state.timeRemaining = desc[kIOPSTimeToFullChargeKey] as? Int ?? -1
            } else {
                state.timeRemaining = desc[kIOPSTimeToEmptyKey] as? Int ?? -1
            }
        }

        // Detailed battery info from AppleSmartBattery IOService
        readSmartBatteryProperties(&state)

        return state
    }

    private func readSmartBatteryProperties(_ state: inout BatteryState) {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(service) }

        // Read all properties at once
        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let props = propsRef?.takeRetainedValue() as? [String: Any] else { return }

        // Capacity (mAh)
        state.designCapacity = props["DesignCapacity"] as? Int ?? 0
        state.maxCapacity = props["AppleRawMaxCapacity"] as? Int
            ?? props["MaxCapacity"] as? Int ?? 0

        // If DesignCapacity is 0, try NominalChargeCapacity
        if state.designCapacity == 0 {
            state.designCapacity = props["NominalChargeCapacity"] as? Int ?? 0
        }

        // Cycle count
        state.cycleCount = props["CycleCount"] as? Int ?? 0

        // Temperature (centi-degrees to Celsius)
        if let temp = props["Temperature"] as? Int {
            state.temperature = Double(temp) / 100.0
        }

        // Voltage (mV to V)
        if let voltage = props["Voltage"] as? Int {
            state.voltage = Double(voltage) / 1000.0
        }

        // Adapter wattage
        if let adapterDetails = props["AdapterDetails"] as? [String: Any] {
            state.adapterWatts = adapterDetails["Watts"] as? Int ?? 0
        }
    }
}
