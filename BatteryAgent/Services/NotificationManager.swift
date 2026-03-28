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
}
