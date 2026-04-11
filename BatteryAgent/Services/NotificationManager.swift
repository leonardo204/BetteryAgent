import Foundation
import UserNotifications

final class NotificationManager: Sendable {
    static let shared = NotificationManager()

    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func sendChargeCompleteNotification(limit: Int) {
        let content = UNMutableNotificationContent()
        content.title = "충전 완료"
        content.body = "배터리가 목표치 \(limit)%에 도달했습니다."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "chargeComplete-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func sendCalibrationStepNotification(step: String) {
        let content = UNMutableNotificationContent()
        content.title = "캘리브레이션"
        content.body = step
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "calibration-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func sendSmartChargingStartNotification(reason: String) {
        let content = UNMutableNotificationContent()
        content.title = "스마트 충전 시작"
        content.body = reason
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "smartChargingStart",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func sendSmartChargingCompleteNotification() {
        let content = UNMutableNotificationContent()
        content.title = "스마트 충전 완료"
        content.body = "100% 충전 완료. 정상 충전 제한으로 복귀합니다."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "smartChargingComplete",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func sendChargeConflictNotification(state: ConflictState) {
        let content = UNMutableNotificationContent()
        content.sound = .default

        switch state {
        case .osLower(let baLimit, let osLimit):
            content.title = "충전 한도 충돌"
            content.body = "macOS 충전 한도(\(osLimit)%)가 BatteryAgent(\(baLimit)%)보다 낮습니다. BatteryAgent를 \(osLimit)%로 조정할 수 있습니다."
        case .osBlocking(let osLimit, _):
            content.title = "BatteryAgent가 제어할 수 없습니다"
            content.body = "macOS 시스템 설정 > 배터리의 충전 한도(\(osLimit)%)를 확인해주세요."
        default:
            return
        }

        // W1: stateKey 기반 고정 ID — 앱 재시작 후에도 UNCenter가 자동으로 덮어써 중복 알림 차단
        let stateID: String
        switch state {
        case .osLower:    stateID = "osLower"
        case .osBlocking: stateID = "osBlocking"
        default:          stateID = "unknown"
        }
        let request = UNNotificationRequest(
            identifier: "chargeConflict-\(stateID)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
