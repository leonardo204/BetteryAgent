import Foundation

// MARK: - Tone

enum Tone {
    case info
    case ok
    case warning
    case critical
}

// MARK: - ConflictState

enum ConflictState: Equatable {
    /// 케이스 D: OS 한도 없음 또는 관리 중 아님
    case none
    /// 케이스 A: BA가 먼저 차단 (sysLimit > chargeLimit)
    case baFirst(baLimit: Int, osLimit: Int)
    /// 케이스 B: OS 한도가 더 낮음 (sysLimit < chargeLimit)
    case osLower(baLimit: Int, osLimit: Int)
    /// 케이스 C: OS와 동일한 한도 (sysLimit == chargeLimit)
    case equal(limit: Int)
    /// 케이스 E: OS가 차단 중 (휴리스틱 추정)
    case osBlocking(osLimit: Int, reasonCode: Int)

    var title: String {
        switch self {
        case .none:
            return ""
        case .baFirst:
            return "BatteryAgent가 먼저 차단"
        case .osLower(_, let osLimit):
            return "OS 한도(\(osLimit)%)가 더 낮음"
        case .equal(let limit):
            return "OS와 동일한 한도(\(limit)%)"
        case .osBlocking:
            return "BA가 제어 못함 — macOS 설정 확인"
        }
    }

    var subtitle: String {
        switch self {
        case .none:
            return ""
        case .baFirst(let baLimit, let osLimit):
            return "BatteryAgent가 \(baLimit)%에서 먼저 차단합니다. macOS 한도(\(osLimit)%)는 도달하지 않습니다."
        case .osLower(let baLimit, let osLimit):
            return "macOS 충전 한도(\(osLimit)%)가 BatteryAgent 설정(\(baLimit)%)보다 낮아 목표에 도달하지 못할 수 있습니다. BatteryAgent를 \(osLimit)%로 조정하거나 macOS 설정을 변경하세요."
        case .equal(let limit):
            return "BatteryAgent와 macOS 모두 \(limit)%에서 충전을 제한합니다."
        case .osBlocking(let osLimit, _):
            return "BA가 제어할 수 없습니다. macOS 시스템 설정 > 배터리에서 충전 한도(\(osLimit)%)를 확인해주세요. (추정)"
        }
    }

    var iconSystemName: String {
        switch self {
        case .none:
            return ""
        case .baFirst:
            return "checkmark.shield"
        case .osLower:
            return "exclamationmark.triangle"
        case .equal:
            return "checkmark.circle"
        case .osBlocking:
            return "lock.shield"
        }
    }

    var tone: Tone {
        switch self {
        case .none:
            return .info
        case .baFirst:
            return .ok
        case .osLower:
            return .warning
        case .equal:
            return .info
        case .osBlocking:
            return .critical
        }
    }

    var needsUserAttention: Bool {
        switch self {
        case .osLower, .osBlocking:
            return true
        default:
            return false
        }
    }
}

// MARK: - ConflictAnalyzer

struct ConflictAnalyzer {
    static func analyze(
        state: BatteryState,
        chargeLimit: Int,
        isManaging: Bool
    ) -> ConflictState {
        // W3: 관리 중이 아니면 early return — 불필요한 배지 표시 방지
        guard isManaging else { return .none }

        // 관리 중이어도 OS 한도 없으면 none
        guard let sysLimit = state.systemChargeLimit else {
            return .none
        }

        // 케이스 E: OS가 차단 중 (휴리스틱)
        // 조건: 충전기 연결 + 관리 중 + 충전 안 됨 + notChargingReason != 0
        // + chargerInhibitReason == 0 (BA가 스스로 억제 중이 아님 — W2 false positive 제거)
        // + 현재 충전량이 sysLimit 이상이고 chargeLimit 미만 (BA는 아직 차단할 이유 없음)
        if state.isPluggedIn
            && !state.isCharging
            && state.notChargingReason != 0
            && state.chargerInhibitReason == 0
            && state.currentCharge >= sysLimit
            && state.currentCharge < chargeLimit {
            return .osBlocking(osLimit: sysLimit, reasonCode: state.notChargingReason)
        }

        // 케이스 A: BA가 먼저 차단 (sysLimit > chargeLimit)
        if sysLimit > chargeLimit {
            return .baFirst(baLimit: chargeLimit, osLimit: sysLimit)
        }

        // 케이스 B: OS 한도가 더 낮음 (sysLimit < chargeLimit)
        if sysLimit < chargeLimit {
            return .osLower(baLimit: chargeLimit, osLimit: sysLimit)
        }

        // 케이스 C: 동일
        return .equal(limit: sysLimit)
    }
}

// MARK: - ChargerDiagnostics

struct ChargerDiagnostics {
    static func decodeNotCharging(_ code: Int) -> [String] {
        guard code != 0 else { return [] }
        var reasons: [String] = []
        let knownBits: [(Int, String)] = [
            (0x01, "배터리 풀충전"),
            (0x02, "온도 초과"),
            (0x04, "배터리 불량"),
            (0x08, "충전 억제됨"),
            (0x10, "어댑터 전류 제한"),
            (0x20, "시스템 한도 도달"),
        ]
        var remaining = code
        for (bit, label) in knownBits {
            if code & bit != 0 {
                reasons.append(label)
                remaining &= ~bit
            }
        }
        if remaining != 0 {
            reasons.append(String(format: "Unknown(0x%X)", remaining))
        }
        return reasons
    }

    static func decodeInhibit(_ code: Int) -> [String] {
        guard code != 0 else { return [] }
        var reasons: [String] = []
        let knownBits: [(Int, String)] = [
            (0x01, "충전 억제 활성"),
            (0x02, "어댑터 비활성"),
            (0x04, "온도 보호"),
            (0x08, "외부 억제"),
        ]
        var remaining = code
        for (bit, label) in knownBits {
            if code & bit != 0 {
                reasons.append(label)
                remaining &= ~bit
            }
        }
        if remaining != 0 {
            reasons.append(String(format: "Unknown(0x%X)", remaining))
        }
        return reasons
    }

    #if DEBUG
    static func _runSelfCheck() {
        var state = BatteryState()
        state.systemChargeLimit = nil

        // 케이스 D: sysLimit 없음
        let d = ConflictAnalyzer.analyze(state: state, chargeLimit: 80, isManaging: true)
        assert(d == .none, "케이스 D 실패")

        // 케이스 A: sysLimit > chargeLimit
        state.systemChargeLimit = 90
        let a = ConflictAnalyzer.analyze(state: state, chargeLimit: 80, isManaging: true)
        assert(a == .baFirst(baLimit: 80, osLimit: 90), "케이스 A 실패")

        // 케이스 B: sysLimit < chargeLimit
        state.systemChargeLimit = 70
        let b = ConflictAnalyzer.analyze(state: state, chargeLimit: 80, isManaging: true)
        assert(b == .osLower(baLimit: 80, osLimit: 70), "케이스 B 실패")

        // 케이스 C: sysLimit == chargeLimit
        state.systemChargeLimit = 80
        let c = ConflictAnalyzer.analyze(state: state, chargeLimit: 80, isManaging: true)
        assert(c == .equal(limit: 80), "케이스 C 실패")

        // 케이스 E: osBlocking
        state.systemChargeLimit = 75
        state.isPluggedIn = true
        state.isCharging = false
        state.notChargingReason = 0x20
        state.currentCharge = 75  // >= sysLimit(75), < chargeLimit(80)
        let e = ConflictAnalyzer.analyze(state: state, chargeLimit: 80, isManaging: true)
        assert(e == .osBlocking(osLimit: 75, reasonCode: 0x20), "케이스 E 실패")

        print("[ChargeLimitConflict] Self-check passed: 5/5 cases OK")
    }
    #endif
}
