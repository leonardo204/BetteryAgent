import Foundation
import AppKit

@MainActor
final class ConflictNotifier {
    weak var viewModel: BatteryViewModel?

    private var lastNotifiedKey: String = ""
    private var debounceTask: Task<Void, Never>?
    // C1: NSObjectProtocol 토큰 배열로 observer 추적
    private var observers: [NSObjectProtocol] = []

    init(viewModel: BatteryViewModel) {
        self.viewModel = viewModel
        setupObservers()
        // W4: [weak self] 캡처로 순환 참조 방지
        Task { [weak self] in
            await self?.evaluate()
        }
    }

    private func setupObservers() {
        let ws = NSWorkspace.shared
        // C1: 클로저 기반 observer 등록으로 토큰 저장
        let wakeObs = ws.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleEvaluate() }
        }
        let sessionObs = ws.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleEvaluate() }
        }
        observers = [wakeObs, sessionObs]
    }

    // C1: 외부에서 명시적으로 해제할 수 있도록 cleanup 메서드 제공
    func cleanup() {
        let ws = NSWorkspace.shared
        for o in observers { ws.notificationCenter.removeObserver(o) }
        observers.removeAll()
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func scheduleEvaluate() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5초
            guard !Task.isCancelled else { return }
            await self?.evaluate()
        }
    }

    private func evaluate() async {
        guard let vm = viewModel else { return }
        vm.updateBatteryState()
        let state = vm.conflictState
        guard state.needsUserAttention else { return }
        guard !isSnoozed(for: state) else { return }

        let key = stateKey(for: state)
        guard key != lastNotifiedKey else { return }
        lastNotifiedKey = key

        NotificationManager.shared.sendChargeConflictNotification(state: state)
    }

    // MARK: - Snooze (UserDefaults, 24h)

    func isSnoozed(for state: ConflictState) -> Bool {
        let key = Constants.UserDefaultsKey.conflictAlertSnoozedUntil + "_" + stateKey(for: state)
        guard let until = UserDefaults.standard.object(forKey: key) as? Date else { return false }
        return until > Date()
    }

    func snooze(for state: ConflictState) {
        let key = Constants.UserDefaultsKey.conflictAlertSnoozedUntil + "_" + stateKey(for: state)
        let until = Date().addingTimeInterval(24 * 60 * 60)
        UserDefaults.standard.set(until, forKey: key)
    }

    // C2: StateKind별 선택적 스누즈 삭제
    func clearSnooze(for stateKind: String) {
        let key = Constants.UserDefaultsKey.conflictAlertSnoozedUntil + "_" + stateKind
        UserDefaults.standard.removeObject(forKey: key)
        // lastNotifiedKey도 해당 kind일 때만 리셋
        if lastNotifiedKey == stateKind {
            lastNotifiedKey = ""
        }
    }

    // 전체 스누즈 삭제 (명시적 사용자 액션 시)
    func clearSnooze() {
        let keys = [
            Constants.UserDefaultsKey.conflictAlertSnoozedUntil + "_osLower",
            Constants.UserDefaultsKey.conflictAlertSnoozedUntil + "_osBlocking",
        ]
        for k in keys {
            UserDefaults.standard.removeObject(forKey: k)
        }
        lastNotifiedKey = ""
    }

    // C2: 이전 상태와 현재 상태를 비교해 해소된 케이스의 스누즈만 삭제
    func clearSnoozeIfResolved(previous: ConflictState, current: ConflictState) {
        // osLower 해소: 이전이 osLower였고 현재는 osLower가 아닌 경우
        if case .osLower = previous, !(current == previous) {
            if case .osLower = current { /* 아직 osLower — 해소 아님 */ }
            else { clearSnooze(for: "osLower") }
        }
        // osBlocking 해소: 이전이 osBlocking이었고 현재는 osBlocking이 아닌 경우
        if case .osBlocking = previous, !(current == previous) {
            if case .osBlocking = current { /* 아직 osBlocking — 해소 아님 */ }
            else { clearSnooze(for: "osBlocking") }
        }
    }

    private func stateKey(for state: ConflictState) -> String {
        switch state {
        case .osLower:    return "osLower"
        case .osBlocking: return "osBlocking"
        default:          return ""
        }
    }
}
