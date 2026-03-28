import AppKit
import EventKit
import os.log

@MainActor
final class CalendarMonitor {
    private let eventStore = EKEventStore()
    private let logger = Logger(subsystem: Constants.appBundleIdentifier, category: "CalendarMonitor")

    private(set) var isAuthorized = false
    private(set) var upcomingEvents: [UpcomingEvent] = []

    struct UpcomingEvent {
        let startDate: Date
        let endDate: Date
        let durationMinutes: Int
    }

    /// Request calendar access — returns true if granted
    func requestAccess() async -> Bool {
        let status = authorizationStatus
        logger.info("Calendar authorization status: \(String(describing: status))")

        switch status {
        case .fullAccess:
            isAuthorized = true
            return true

        case .denied, .restricted:
            isAuthorized = false
            return false

        case .notDetermined:
            return await requestWithActivation()

        @unknown default:
            isAuthorized = false
            return false
        }
    }

    /// .notDetermined 상태에서 권한 요청 — .accessory 앱은 일시적으로 .regular로 전환
    private func requestWithActivation() async -> Bool {
        let previousPolicy = NSApp.activationPolicy()
        let needsPolicySwitch = previousPolicy == .accessory

        if needsPolicySwitch {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            // run loop가 activation policy 변경을 처리할 때까지 대기
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    continuation.resume()
                }
            }
        }

        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            isAuthorized = granted
            logger.info("Calendar access result: \(granted)")

            if needsPolicySwitch {
                restoreAccessoryPolicy()
            }
            return granted
        } catch {
            logger.error("Calendar access error: \(error.localizedDescription)")
            isAuthorized = false

            if needsPolicySwitch {
                restoreAccessoryPolicy()
            }
            return false
        }
    }

    /// .accessory 복원 + 설정 창 다시 앞으로
    private func restoreAccessoryPolicy() {
        NSApp.setActivationPolicy(.accessory)
        // 설정 창이 있으면 다시 앞으로 가져오기
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(name: .settingsWindowNeedsFront, object: nil)
        }
    }

    /// Check current authorization status
    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// Fetch events in the next 24 hours that are 30+ minutes long
    func fetchUpcomingEvents(leadMinutes: Int = 60) -> [UpcomingEvent] {
        guard isAuthorized || authorizationStatus == .fullAccess else { return [] }

        let now = Date()
        let endDate = Calendar.current.date(byAdding: .hour, value: 24, to: now)!

        let predicate = eventStore.predicateForEvents(
            withStart: now,
            end: endDate,
            calendars: nil  // all calendars
        )

        let events = eventStore.events(matching: predicate)
        logger.info("Calendar: found \(events.count) raw events in next 24h")
        for event in events {
            let duration = Int(event.endDate.timeIntervalSince(event.startDate) / 60)
            logger.info("  - \(event.title ?? "(no title)") | allDay=\(event.isAllDay) | \(duration)min | \(event.startDate) ~ \(event.endDate)")
        }

        let filtered = events
            .filter { !$0.isAllDay }  // skip all-day events
            .filter { event in
                let duration = event.endDate.timeIntervalSince(event.startDate) / 60
                return duration >= 30  // only 30+ minute events
            }
        logger.info("Calendar: \(filtered.count) events after filtering (non-allDay, 30min+)")

        return filtered
            .map { event in
                UpcomingEvent(
                    startDate: event.startDate,
                    endDate: event.endDate,
                    durationMinutes: Int(event.endDate.timeIntervalSince(event.startDate) / 60)
                )
            }
    }

    /// Check if there's an upcoming event that needs pre-charging
    /// Returns the event start date if charging should begin now
    func shouldPreCharge(leadMinutes: Int) -> Date? {
        let events = fetchUpcomingEvents(leadMinutes: leadMinutes)
        let now = Date()

        for event in events {
            let chargeStartTime = event.startDate.addingTimeInterval(-Double(leadMinutes) * 60)
            if now >= chargeStartTime && now < event.startDate {
                return event.startDate
            }
        }
        return nil
    }
}
