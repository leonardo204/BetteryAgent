import Foundation

struct ChargeRecord: Identifiable {
    let id = UUID()
    let timestamp: Date
    let charge: Int
    let isCharging: Bool
    let isPluggedIn: Bool
}

/// 최근 7일간 충전 통계
struct WeeklyStats {
    /// 충전 중이었던 총 시간 (분)
    let totalChargingMinutes: Int
    /// 평균 배터리 잔량 (%)
    let avgChargeLevel: Double
    /// 플러그 해제 횟수 (충전 완료 후 분리)
    let chargeDisconnectCount: Int
    /// 플러그 연결 횟수
    let plugInCount: Int
}
