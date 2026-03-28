# Smart Charging — 사용 패턴 학습 기반 예측 충전 계획

## 1. 개요

**목표**: 사용자의 배터리 사용 패턴을 학습하여, 장시간 언플러그가 예상되는 시점 전에 자동으로 100% 충전 후 정상 충전 제한으로 복귀하는 기능.

**핵심 시나리오**:
- 매주 화/목 오후 2시 회의 → 1시에 자동 100% 충전 시작
- 평일 오전 9시 출근 → 8시에 자동 100% 충전
- 패턴이 깨지면 학습 자동 갱신

---

## 2. 시장 조사 결과

### 기존 macOS 배터리 도구 (모두 ML 기능 없음)

| 도구 | 특징 | 예측 기능 |
|------|------|-----------|
| AlDente | Sailing Mode, Heat Protection | 없음 (수동 제어만) |
| BatFi | 오픈소스, Apple Silicon | 없음 ("사용자 직접 제어에 집중") |
| batt | Go 기반, CLI | 없음 ("가능한 단순하게") |
| BCLM | CLI, SMC 직접 제어 | 없음 |

**결론**: macOS 배터리 도구 중 패턴 학습/예측 충전 기능을 가진 것은 **없음** → BatteryAgent 차별화 기회.

### Apple Optimized Battery Charging 분석

| 항목 | 내용 |
|------|------|
| 핵심 원리 | 80%까지 빠르게 충전 후 일시정지, 언플러그 직전에 100% 도달 |
| 학습 기간 | 최소 14일 |
| 활성화 조건 | 특정 위치에서 5시간+ 충전 9회+ |
| 입력 신호 | 시간대, 요일, 위치(Significant Locations), 충전 지속시간 |
| BatteryAgent 적용 | 위치 기반은 과도 → **시간+요일 기반**으로 충분 |

### Google Pixel Adaptive Charging

- 14일 학습 → 요일별 기상 시간 자동 인식
- 80%까지 정상 충전 후 나머지 20%를 저속 충전
- 평일/주말 다른 패턴 자동 구분

---

## 3. 기술 조사 결과

### 접근법 비교 (실용성 순위)

| 순위 | 접근법 | 복잡도 | 코드량 | 외부 의존성 | 효과 |
|------|--------|--------|--------|-------------|------|
| **1** | **EWMA 시간 슬롯 히스토그램** | 낮음 | ~100줄 | 없음 | 높음 |
| 2 | EventKit 캘린더 연동 | 낮음-중간 | ~80줄 | EventKit | 중간-높음 |
| 3 | 사용자 수동 규칙 | 매우 낮음 | ~50줄 | 없음 | 확실하지만 제한적 |
| 4 | CreateML TimeSeriesForecaster | 높음 | ~200줄 | CreateML | 히스토그램 대비 미미한 향상 |
| 5 | Chronos-Bolt-Tiny (HuggingFace) | 매우 높음 | ~300줄+ | PyTorch→CoreML 변환 | 과잉 설계 |

### HuggingFace / ML 모델 조사

| 모델 | 크기 | 적합성 |
|------|------|--------|
| Amazon Chronos-Bolt-Tiny | 9M params, 8.6MB | 제로샷 시계열 예측 가능하나 과도 |
| Amazon Chronos-T5-Tiny | 8M params, 8.4MB | 위와 유사 |
| Google TimesFM | 200M params | 메뉴바 앱에 부적합 |
| PatchTST | 설정 가능 | 커스텀 학습 필요 |

### Apple 네이티브 ML 프레임워크

| 프레임워크 | 용도 | BatteryAgent 적합성 |
|-----------|------|---------------------|
| **CreateML Components** | 앱 내 온디바이스 학습/추론 | TimeSeriesForecaster 제공, 2단계에 적합 |
| CoreML | 학습된 모델 추론 | CreateML 결과물 배포용 |
| Accelerate/vDSP | FFT 주기성 검출 | 히스토그램 보조용 |
| MLX Swift | Apple Silicon ML | 이 규모에는 과도 |

### 핵심 판단

> **이 문제는 본질적으로 "주간 주기성이 있는 이진 시계열의 슬롯별 빈도 추정"이다.**
> 신경망이 히스토그램보다 유의미하게 나은 결과를 내기 어렵다.
> Apple OBC도 내부적으로는 규칙 기반에 가까운 단순 모델로 추정된다.

---

## 4. 설계

### 4.1 아키텍처: 3계층 하이브리드

```
┌─────────────────────────────────────────────┐
│  Layer 3: 사용자 수동 규칙 (최우선)           │
│  "매주 화/목 14:00 전까지 100% 충전"          │
├─────────────────────────────────────────────┤
│  Layer 2: EventKit 캘린더 (보조, 선택적)      │
│  24시간 앞 이벤트 확인 → 시작 60분 전 충전     │
├─────────────────────────────────────────────┤
│  Layer 1: EWMA 히스토그램 (핵심, 자동)        │
│  7일 x 48슬롯 = 336개 확률값                 │
│  14일 학습 후 자동 활성화                      │
└─────────────────────────────────────────────┘
         ↓ 결정
┌─────────────────────────────────────────────┐
│  충전 스케줄러                                │
│  "패턴 시작 N분 전 → 100% 충전 시작"          │
│  "패턴 종료 후 → 정상 제한(80%) 복귀"          │
└─────────────────────────────────────────────┘
```

### 4.2 Layer 1: EWMA 시간 슬롯 히스토그램

**데이터 구조**:
```swift
struct UsagePattern {
    // 7일 x 48슬롯(30분) = 336개
    var slots: [[Double]]  // slots[dayOfWeek][halfHour] = 언플러그 확률 (0.0~1.0)
    var observationCounts: [[Int]]  // 관측 횟수 (confidence 판단용)
}
```

**알고리즘**:
```
매 5분 관측:
  1. (요일, 30분 슬롯) 결정
  2. observation = is_unplugged ? 1.0 : 0.0
  3. slots[day][slot] = α * observation + (1 - α) * slots[day][slot]
     (α = 0.1, 약 14일치 데이터가 유의미하게 반영)
  4. observationCounts[day][slot] += 1

패턴 감지:
  1. 확률 ≥ 0.7 AND 관측 ≥ 20회인 슬롯을 "언플러그 예상" 마킹
  2. 연속된 "언플러그 예상" 슬롯을 하나의 패턴으로 병합
  3. 패턴 시작 2슬롯(60분) 전에 100% 충전 트리거
```

**저장**: 기존 `ChargeHistoryStore`의 SQLite DB에 `usage_patterns` 테이블 추가.

### 4.3 Layer 2: EventKit 캘린더 연동 (선택적)

EventKit은 macOS 시스템 설정 > 인터넷 계정에 등록된 **모든 캘린더**를 읽습니다:
- iCloud, Google, Exchange/Outlook, CalDAV 등 모든 계정의 캘린더 포함
- 사용자가 macOS 기본 캘린더 앱에서 볼 수 있는 모든 이벤트 접근 가능

```
매 1시간:
  1. 향후 24시간 이벤트 조회 (모든 등록 캘린더)
  2. 30분+ 이벤트 필터링 (짧은 이벤트는 무시)
  3. 이벤트 시작 60분 전이 현재 이후이면 충전 예약 등록
```

**프라이버시**: 이벤트 제목/내용은 읽지 않음. 시작/종료 시간만 사용.

### 4.4 Layer 3: 사용자 수동 규칙

```swift
struct ChargeRule: Codable {
    let id: UUID
    let label: String           // "화요일 회의"
    let daysOfWeek: Set<Int>    // [2, 4] = 화, 목
    let targetTime: TimeOfDay   // 14:00 (이 시간까지 100%)
    let leadMinutes: Int        // 60 (60분 전부터 충전 시작)
    let enabled: Bool
}
```

### 4.5 충전 스케줄러

```
매 5분 (기존 BatteryMonitor 타이머에 통합):
  1. 수동 규칙 확인 → 매칭되면 100% 충전 시작
  2. 캘린더 예약 확인 → 매칭되면 100% 충전 시작
  3. EWMA 패턴 확인 → 패턴 시작 전이면 100% 충전 시작
  4. 어떤 것도 매칭 안 되면 → 정상 충전 제한 유지

상태 전이:
  [정상 제한] ──(패턴 감지)──→ [풀충전 모드]
       ↑                              │
       └──(패턴 종료 또는 사용자 복귀)──┘
```

---

## 5. 구현 계획

### Phase 1: 데이터 수집 인프라 (1일)

| 작업 | 파일 | 설명 |
|------|------|------|
| 1-1 | `ChargeHistoryStore.swift` | `usage_patterns` 테이블 추가 (336 슬롯) |
| 1-2 | `UsagePatternTracker.swift` (신규) | EWMA 업데이트 로직, 5분 간격 관측 기록 |
| 1-3 | `BatteryViewModel.swift` | PatternTracker 연동 |

### Phase 2: 패턴 감지 엔진 (1일)

| 작업 | 파일 | 설명 |
|------|------|------|
| 2-1 | `UsagePatternTracker.swift` | 연속 슬롯 병합, 패턴 추출 알고리즘 |
| 2-2 | `SmartChargeScheduler.swift` (신규) | 충전 트리거 결정 로직, 상태 전이 관리 |
| 2-3 | `BatteryManager.swift` | 스케줄러 → SMC 충전 제어 연동 |

### Phase 3: 수동 규칙 UI (1일)

| 작업 | 파일 | 설명 |
|------|------|------|
| 3-1 | `ChargeRule.swift` (신규) | 규칙 모델, UserDefaults 저장 |
| 3-2 | `SmartChargingTab.swift` (신규) | 설정 탭 — 규칙 추가/편집/삭제, 감지된 패턴 시각화 |
| 3-3 | `SettingsContainerView.swift` | 새 탭 추가 |

### Phase 4: 캘린더 연동 (0.5일)

| 작업 | 파일 | 설명 |
|------|------|------|
| 4-1 | `CalendarMonitor.swift` (신규) | EventKit 이벤트 조회, 충전 예약 생성 |
| 4-2 | `Info.plist` | `NSCalendarsFullAccessUsageDescription` 추가 |
| 4-3 | `SmartChargingTab.swift` | 캘린더 연동 On/Off 토글 |

### Phase 5: 메뉴바 아이콘 + 팝오버 + 알림 (1일)

| 작업 | 파일 | 설명 |
|------|------|------|
| 5-1 | `MenuBarIconProvider.swift` | 스마트 충전 상태 추가, 아이콘 틴트 색상 차별화 (아래 상세) |
| 5-2 | `AppDelegate.swift` | 스마트 충전 시 아이콘 색상(오렌지) 적용 |
| 5-3 | `PopoverView.swift` | 학습 진행률, 감지된 패턴, 스마트 충전 상태 표시 섹션 추가 |
| 5-4 | `NotificationManager.swift` | macOS 알림 센터 연동 — 스마트 충전 시작/완료 알림 |

---

## 6. 데이터 모델

### SQLite 스키마

```sql
-- 기존 charge_history 테이블 활용 (이미 있음)

-- 새 테이블: EWMA 패턴 데이터
CREATE TABLE IF NOT EXISTS usage_patterns (
    day_of_week INTEGER NOT NULL,    -- 0=일, 1=월, ..., 6=토
    half_hour   INTEGER NOT NULL,    -- 0~47 (00:00~23:30)
    probability REAL DEFAULT 0.0,    -- 언플러그 확률 (EWMA)
    observations INTEGER DEFAULT 0,  -- 총 관측 횟수
    last_updated TEXT,               -- ISO 8601
    PRIMARY KEY (day_of_week, half_hour)
);

-- 새 테이블: 감지된 패턴
CREATE TABLE IF NOT EXISTS detected_patterns (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    day_of_week INTEGER NOT NULL,
    start_slot  INTEGER NOT NULL,    -- 시작 30분 슬롯
    end_slot    INTEGER NOT NULL,    -- 종료 30분 슬롯
    confidence  REAL NOT NULL,       -- 평균 확률
    active      INTEGER DEFAULT 1,
    created_at  TEXT,
    updated_at  TEXT
);
```

### 수동 규칙 (UserDefaults)

```swift
struct ChargeRule: Codable, Identifiable {
    let id: UUID
    var label: String
    var daysOfWeek: Set<Int>     // 1=월 ... 7=일
    var targetHour: Int          // 0~23
    var targetMinute: Int        // 0~59
    var leadMinutes: Int         // 충전 시작 여유 시간 (기본 60)
    var enabled: Bool
}
```

---

## 7. UI 설계

### 설정 > 스마트 충전 탭

```
┌─────────────────────────────────────────┐
│  스마트 충전                              │
│                                         │
│  ┌─ 자동 패턴 학습 ──────────────────┐   │
│  │ [ON/OFF]  학습 상태: 12일째 [자세히]│   │
│  │                                   │   │
│  │  감지된 패턴:                       │   │
│  │  ● 월~금 09:00~12:00 (87%)        │   │
│  │  ● 화,목 14:00~16:00 (73%)        │   │
│  │                                   │   │
│  │  [패턴 초기화]                      │   │
│  └───────────────────────────────────┘   │
│                                         │
│  ┌─ 캘린더 연동 ─────────────────────┐   │
│  │ [ON/OFF]  연동됨 (3개 캘린더)       │   │
│  │ 이벤트 시작 [60]분 전 충전 시작      │   │
│  └───────────────────────────────────┘   │
│                                         │
│  ┌─ 수동 규칙 ──────────────────────┐    │
│  │  화요일 회의  화,목 14:00  [ON] [✏️]│   │
│  │  주말 외출    토,일 10:00  [ON] [✏️]│   │
│  │                                   │   │
│  │  [+ 규칙 추가]                     │   │
│  └───────────────────────────────────┘   │
│                                         │
│  ┌─ 충전 여유 시간 ─────────────────┐    │
│  │ 100%까지 예상 충전 시간: ~45분      │   │
│  │ 기본 여유: [60]분 전 시작           │   │
│  └───────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

### [자세히] 버튼 → 패턴 히트맵 매트릭스

`[자세히]` 버튼 클릭 시 시트/팝오버로 7일 x 48슬롯 히트맵 매트릭스를 표시합니다.
각 셀은 해당 (요일, 30분 슬롯)의 EWMA 언플러그 확률을 색상으로 나타냅니다.

```
┌─ 패턴 학습 상세 ─────────────────────────────────────────────┐
│                                                              │
│  학습 12일째 (활성화 기준: 14일, 임계값: 70%)                   │
│                                                              │
│       00  01  02  03  04  05  06  07  08  09  10  11         │
│       :   :   :   :   :   :   :   :   :   :   :   :         │
│  월   ░░  ░░  ░░  ░░  ░░  ░░  ░░  ▒▒  ██  ██  ██  ▒▒       │
│  화   ░░  ░░  ░░  ░░  ░░  ░░  ░░  ▒▒  ██  ██  ██  ▒▒       │
│  수   ░░  ░░  ░░  ░░  ░░  ░░  ░░  ▒▒  ██  ██  ██  ▒▒       │
│  목   ░░  ░░  ░░  ░░  ░░  ░░  ░░  ▒▒  ██  ██  ██  ▒▒       │
│  금   ░░  ░░  ░░  ░░  ░░  ░░  ░░  ▒▒  ██  ██  ██  ▒▒       │
│  토   ░░  ░░  ░░  ░░  ░░  ░░  ░░  ░░  ░░  ▒▒  ▒▒  ░░       │
│  일   ░░  ░░  ░░  ░░  ░░  ░░  ░░  ░░  ░░  ░░  ░░  ░░       │
│                                                              │
│       12  13  14  15  16  17  18  19  20  21  22  23         │
│       :   :   :   :   :   :   :   :   :   :   :   :         │
│  월   ▒▒  ▒▒  ▒▒  ▒▒  ▒▒  ▒▒  ░░  ░░  ░░  ░░  ░░  ░░       │
│  화   ▒▒  ▒▒  ██  ██  ▒▒  ▒▒  ░░  ░░  ░░  ░░  ░░  ░░       │
│  수   ▒▒  ▒▒  ▒▒  ▒▒  ▒▒  ▒▒  ░░  ░░  ░░  ░░  ░░  ░░       │
│  목   ▒▒  ▒▒  ██  ██  ▒▒  ▒▒  ░░  ░░  ░░  ░░  ░░  ░░       │
│  금   ▒▒  ▒▒  ▒▒  ▒▒  ▒▒  ░░  ░░  ░░  ░░  ░░  ░░  ░░       │
│  토   ░░  ░░  ░░  ░░  ░░  ░░  ░░  ░░  ░░  ░░  ░░  ░░       │
│  일   ░░  ░░  ░░  ░░  ░░  ░░  ░░  ░░  ░░  ░░  ░░  ░░       │
│                                                              │
│  ── 범례 ──────────────────────────────────────────────────  │
│                                                              │
│  ██ 충전 예약 (≥70%)   확률 높음 — 이 시간대 전에 100% 충전     │
│  ▒▒ 감지 중 (30~70%)   데이터 수집 중 — 아직 확정 아님          │
│  ░░ 정상 (< 30%)       플러그 연결 상태 유지 — 충전 제한 유지    │
│  ·· 데이터 없음         관측 5회 미만 — 판단 불가               │
│                                                              │
│  셀 위에 마우스를 올리면 상세 정보 표시:                          │
│  "화요일 14:00~14:30 | 확률: 87% | 관측: 24회"                 │
│                                                              │
│                                              [닫기]          │
└──────────────────────────────────────────────────────────────┘
```

**SwiftUI 구현 방식**:

```swift
// 히트맵 셀 — 확률에 따른 색상 매핑
struct PatternHeatmapCell: View {
    let probability: Double
    let observations: Int

    var color: Color {
        if observations < 5 { return .gray.opacity(0.1) }    // 데이터 없음
        if probability >= 0.7 { return .orange }              // 충전 예약
        if probability >= 0.3 { return .yellow.opacity(0.5) } // 감지 중
        return .green.opacity(0.2)                            // 정상
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 14, height: 14)
            .help("확률: \(Int(probability * 100))% | 관측: \(observations)회")
    }
}

// 전체 히트맵 매트릭스
struct PatternHeatmapView: View {
    let slots: [[UsageSlot]]  // [7][48]
    let dayLabels = ["월", "화", "수", "목", "금", "토", "일"]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 시간 헤더 (0~23시)
            HStack(spacing: 1) {
                Text("").frame(width: 20)
                ForEach(0..<24, id: \.self) { hour in
                    Text("\(hour)")
                        .font(.system(size: 8))
                        .frame(width: 29)
                }
            }
            // 요일 행
            ForEach(0..<7, id: \.self) { day in
                HStack(spacing: 1) {
                    Text(dayLabels[day])
                        .font(.system(size: 10))
                        .frame(width: 20)
                    ForEach(0..<48, id: \.self) { slot in
                        PatternHeatmapCell(
                            probability: slots[day][slot].probability,
                            observations: slots[day][slot].observations
                        )
                    }
                }
            }
            // 범례
            HStack(spacing: 12) {
                legendItem(color: .orange, label: "충전 예약 (≥70%)")
                legendItem(color: .yellow.opacity(0.5), label: "감지 중 (30~70%)")
                legendItem(color: .green.opacity(0.2), label: "정상 (<30%)")
                legendItem(color: .gray.opacity(0.1), label: "데이터 없음")
            }
            .font(.system(size: 9))
            .padding(.top, 8)
        }
    }
}
```

**셀 크기**: 14x14pt → 48슬롯 x 14 = 672pt 폭. 시트 최소 너비 ~720pt로 설정.
각 시간(1h)은 셀 2개(30분 슬롯)로 구성. 마우스 hover 시 `.help()` 툴팁으로 상세 정보 표시.

### 메뉴바 아이콘 색상 차별화

| 상태 | 아이콘 | 틴트 색상 | 설명 |
|------|--------|-----------|------|
| 정상 관리 | `battery.75percent` | 기본 (흑/백) | 충전 제한 유지 중 |
| 일반 충전 중 | `battery.100percent.bolt` | 기본 (흑/백) | 사용자 충전 중 |
| **스마트 충전 중** | `battery.100percent.bolt` | **오렌지** | 학습 패턴에 의한 예측 충전 |
| 강제 방전 | `arrow.down.circle` | 기본 (흑/백) | 방전 모드 |

**구현**: `NSStatusBarButton`의 `contentTintColor`를 `.orange`로 설정하여 구분. 스마트 충전 종료 시 nil로 복원.

```swift
// AppDelegate.swift - updateStatusBar()
if smartChargeScheduler.isSmartCharging {
    statusItem?.button?.contentTintColor = .orange
} else {
    statusItem?.button?.contentTintColor = nil
}
```

### 팝오버 — 학습 상태 및 패턴 표시

팝오버(`.transient` — 외부 클릭 시 자동 닫힘)에 스마트 충전 섹션을 추가합니다:

```
┌──────────────────────────────────────┐
│  🔋 87%  충전 중 (MagSafe 67W)       │
│  80% 제한 관리 중                     │
│                                      │
│  ── 스마트 충전 ────────────────────  │
│                                      │
│  (학습 중일 때)                        │
│  📊 패턴 학습 중 (5/14일)             │
│  ━━━━━━━━━░░░░░░░░░░  36%           │
│                                      │
│  (패턴 감지 후)                        │
│  📊 감지된 패턴                       │
│  ● 월~금 09:00~12:00  87%            │
│  ● 화,목 14:00~16:00  73%            │
│                                      │
│  (스마트 충전 활성 시)                  │
│  ⚡ 14:00 회의 대비 충전 중             │
│     87% → 100% (약 25분 남음)         │
│                                      │
│  ── ─────────────────────────────    │
│  [설정]              [AI 설정]        │
└──────────────────────────────────────┘
```

**표시 조건**:
- 스마트 충전 기능 OFF → 섹션 미표시
- 학습 14일 미만 → 프로그레스 바 표시
- 학습 완료 + 패턴 감지 → 감지된 패턴 목록
- 스마트 충전 활성 → 오렌지 강조 + 남은 시간

---

## 8. 프라이버시 정책

| 항목 | 정책 |
|------|------|
| 데이터 저장 | 100% 온디바이스 (SQLite) |
| 캘린더 접근 | 이벤트 시작/종료 시간만 사용, 제목/내용 미수집 |
| 위치 데이터 | 사용하지 않음 |
| 네트워크 | 이 기능에서 네트워크 통신 없음 |
| 데이터 보존 | 패턴 데이터는 앱 삭제 시 함께 제거 |
| 투명성 | 감지된 패턴을 UI에 표시하여 사용자가 확인/삭제 가능 |

---

## 9. 향후 확장 가능성

| 단계 | 내용 | 시기 |
|------|------|------|
| v1.1 | CreateML TimeSeriesForecaster로 예측 정확도 향상 | 데이터 충분 축적 후 |
| v1.2 | 충전 속도 기반 리드타임 자동 계산 (W 수 기반) | v1 안정화 후 |
| v1.3 | 패턴 공유 (iCloud Keychain으로 디바이스 간 동기화) | 멀티 디바이스 지원 시 |

---

## 10. 참고 자료

### 오픈소스 프로젝트
- [AlDente](https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring) — macOS 배터리 관리 (클로즈드 소스로 전환)
- [BatFi](https://github.com/rurza/BatFi) — 오픈소스 macOS 배터리 관리
- [batt](https://github.com/charlie0129/batt) — Go 기반 macOS 배터리 제어
- [Microsoft BatteryML](https://github.com/microsoft/BatteryML) — 배터리 열화 예측 프레임워크
- [Apple-OBC](https://github.com/Noah-Gallego/Apple-OBC) — Apple ML 과정 OBC 구현

### ML 모델 / 프레임워크
- [Amazon Chronos-Bolt-Tiny](https://huggingface.co/amazon/chronos-bolt-tiny) — 9M 시계열 예측 모델
- [Apple CreateML TimeSeriesForecaster](https://developer.apple.com/documentation/createmlcomponents/creating-a-time-series-forecaster)
- [Apple Accelerate/vDSP](https://developer.apple.com/documentation/accelerate/vdsp) — FFT 주기성 검출

### Apple 참고
- [Optimized Battery Charging](https://support.apple.com/en-us/102338)
- [EventKit](https://developer.apple.com/documentation/eventkit)
- [WWDC23 — Discover Calendar and EventKit](https://developer.apple.com/videos/play/wwdc2023/10052/)

### 학술 논문
- [EL-HARP: 경량 사용자 행동 예측 (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC12526510/)
- [Periodic Pattern Detection in Event Sequences (CIKM 2017)](http://chaozhang.org/papers/2017-cikm-periodic.pdf)
- [Context-aware Battery Management (Microsoft Research)](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/cabman-percom08.pdf)

---

*작성일: 2026-03-27*
