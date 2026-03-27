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
}
