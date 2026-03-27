# 아키텍처 — BatteryAgent 시스템 설계

## 프로젝트 구조

```
BatteryAgent/
├── BatteryAgent.xcodeproj
├── project.yml                        # xcodegen 설정
├── CLAUDE.md
├── BatteryAgent/                      # 메인 앱 타겟
│   ├── App/
│   │   ├── BatteryAgentApp.swift      # @main, Settings Scene
│   │   └── AppDelegate.swift          # NSStatusItem, NSPopover, 설정창, @MainActor
│   ├── Views/
│   │   ├── Popover/
│   │   │   ├── PopoverView.swift      # 간결한 팝오버 (상태 + 슬라이더 + 토글)
│   │   │   └── BatterySliderView.swift # 배터리 레벨 + 제한 슬라이더
│   │   └── Settings/
│   │       ├── SettingsWindowController.swift  # NSWindowController
│   │       ├── SettingsView.swift              # 설정 루트 (탭 컨테이너)
│   │       ├── ChargeControlTab.swift          # 충전 제어 탭
│   │       ├── BatteryInfoTab.swift            # 배터리 정보 탭
│   │       ├── HistoryTab.swift                # 충전 이력 그래프 탭
│   │       ├── CalibrationTab.swift            # 캘리브레이션 모드
│   │       └── GeneralTab.swift                # 일반 설정 탭
│   ├── ViewModels/
│   │   └── BatteryViewModel.swift     # @Observable @MainActor 중앙 상태
│   ├── Services/
│   │   ├── BatteryMonitor.swift       # IOKit 배터리 읽기
│   │   ├── SMCClient.swift            # XPC 클라이언트 (현재 스텁)
│   │   ├── ChargeHistoryStore.swift   # 충전 이력 SQLite 저장소
│   │   ├── NotificationManager.swift  # 충전 완료 알림
│   │   └── CalibrationManager.swift   # 캘리브레이션 3단계 관리
│   ├── Models/
│   │   ├── BatteryState.swift         # 배터리 상태 구조체
│   │   ├── ChargePolicy.swift         # 충전 정책 모델 (스마트/수동)
│   │   └── ChargeRecord.swift         # 이력 데이터 모델
│   ├── Utilities/
│   │   ├── Constants.swift            # 상수, 키, 기본값
│   │   └── MenuBarIconProvider.swift  # SF Symbol 선택
│   └── Resources/
│       └── Info.plist
├── BatteryAgentHelper/                # 권한 헬퍼 데몬 (Phase 3)
│   ├── main.swift
│   ├── HelperDelegate.swift
│   ├── SMCController.swift            # 직접 SMC 읽기/쓰기
│   └── Info.plist
├── Shared/
│   └── XPCProtocol.swift              # XPC 인터페이스 정의
└── Ref-docs/claude/                   # 문서
```

## UI 아키텍처

```
┌─── 메뉴바 ──────────────────────────────────────────┐
│  🔋 80%  (아이콘 + 선택적 퍼센트 표시)               │
└──────┬──────────────────────────────────────────────┘
       │ 클릭
       ▼
┌─── 팝오버 (간결) ──────────────────────┐
│                                        │
│  🔋 72%  충전 중 ⚡  42W               │
│  ━━━━━━━━━━━━━━━━━━━━●━━━━━  제한:80%  │
│  완충까지 약 35분                       │
│                                        │
│  [  관리 ON/OFF 토글  ]                │
│                                        │
│  ⚙️ 설정 열기                          │
└────────────────────────────────────────┘
                    │ "설정 열기" 클릭
                    ▼
┌─── 설정창 (별도 NSWindow) ─────────────────────────────┐
│                                                        │
│  ┌──────┬──────────┬──────┬────────────┬──────┐       │
│  │ 충전  │ 배터리    │ 이력  │ 캘리브레이션 │ 일반  │       │
│  └──┬───┴──────────┴──────┴────────────┴──────┘       │
│     ▼                                                  │
│  충전 제어 탭:                                         │
│  ┌────────────────────────────────────────────┐       │
│  │ 충전 제한       [━━━━━━━━━○━] 80%           │       │
│  │ 방전 하한       [━━○━━━━━━━] 20%            │       │
│  │                                            │       │
│  │ 재충전 모드     ◉ 스마트 (자동: 75%)        │       │
│  │                ○ 수동   [━━━━━○━━] 60%     │       │
│  │                                            │       │
│  │ 충전 완료 알림  [✓]                        │       │
│  └────────────────────────────────────────────┘       │
│                                                        │
│  배터리 정보 탭:                                       │
│  ┌────────────────────────────────────────────┐       │
│  │ 건강도          92%  ████████░░            │       │
│  │ 사이클 수       247                        │       │
│  │ 온도            32.5°C                     │       │
│  │ 설계 용량       5103 mAh                   │       │
│  │ 현재 최대 용량  4695 mAh                   │       │
│  │ 전압            12.8V                      │       │
│  │ 어댑터 전력     67W                        │       │
│  │ 예상 완충       35분                       │       │
│  └────────────────────────────────────────────┘       │
│                                                        │
│  이력 탭:                                              │
│  ┌────────────────────────────────────────────┐       │
│  │  100%│     ╭──╮                            │       │
│  │   80%│─ ─ ─│──│─ ─ ─ ─ ─ ─ ─ 제한선       │       │
│  │   60%│╭───╯  ╰───╮    ╭──                 │       │
│  │   40%││          ╰───╯                     │       │
│  │   20%│                                     │       │
│  │      └──────────────────────               │       │
│  │       00:00    06:00    12:00   18:00      │       │
│  │  [24시간] [7일]                            │       │
│  └────────────────────────────────────────────┘       │
│                                                        │
│  캘리브레이션 탭:                                      │
│  ┌────────────────────────────────────────────┐       │
│  │ 1. 100% 완전 충전  ✅ 완료                 │       │
│  │ 2. 완전 방전       ⏳ 진행 중 (42%)        │       │
│  │ 3. 재충전          ⬜ 대기                 │       │
│  │                                            │       │
│  │ [캘리브레이션 시작] [중단]                  │       │
│  └────────────────────────────────────────────┘       │
│                                                        │
│  일반 탭:                                              │
│  ┌────────────────────────────────────────────┐       │
│  │ 메뉴바에 % 표시  [✓]                      │       │
│  │ 로그인 시 실행   [✓]                      │       │
│  │ 버전             1.0.0                     │       │
│  │                                            │       │
│  │ [종료]                                     │       │
│  └────────────────────────────────────────────┘       │
└────────────────────────────────────────────────────────┘
```

## 시스템 아키텍처 다이어그램

```
┌──────────────────────────────────────────────────────────┐
│                BatteryAgent.app (User Space)              │
│                                                          │
│  ┌──────────────┐   ┌──────────┐   ┌──────────────────┐ │
│  │ AppDelegate   │   │ Popover  │   │ Settings Window  │ │
│  │ @MainActor    │◄─►│ View     │   │ (NSWindow)       │ │
│  │ - NSStatusItem│   └────┬─────┘   └────────┬─────────┘ │
│  │ - NSPopover   │        │                   │          │
│  └──────────────┘   ┌────▼───────────────────▼────┐     │
│                      │      BatteryViewModel       │     │
│                      │  @Observable @MainActor     │     │
│                      │  - chargeLimit / dischargeFloor│   │
│                      │  - rechargeThreshold (smart/manual)│
│                      │  - isManaging / showPercentage │   │
│                      └──┬──────┬──────┬──────┬─────┘     │
│                         │      │      │      │           │
│  ┌──────────────┐ ┌────▼──┐ ┌─▼────┐│┌─────▼────────┐  │
│  │ChargeHistory  │ │Battery││ │SMC   │││Notification  │  │
│  │Store (SQLite) │ │Monitor││ │Client│││Manager       │  │
│  └──────────────┘ │(IOKit)││ │(XPC) │││(UNNotification)│ │
│                    └───────┘│ └──┬───┘│└──────────────┘  │
│  ┌──────────────┐          │    │    │                   │
│  │Calibration   │──────────┘    │    │                   │
│  │Manager       │               │    │                   │
│  └──────────────┘               │    │                   │
└─────────────────────────────────┼────┘───────────────────┘
                                  │ XPC (Mach IPC)
┌─────────────────────────────────▼────────────────────────┐
│            BatteryAgentHelper (root daemon)               │
│  ┌──────────────┐    ┌─────────────────┐                 │
│  │HelperDelegate │───►│ SMCController    │                 │
│  │- XPC 검증     │    │ - CH0B/CH0C 쓰기 │                 │
│  │- 코드 서명    │    │ - CH0I 쓰기      │                 │
│  └──────────────┘    └────────┬────────┘                 │
└───────────────────────────────┼───────────────────────────┘
                                │
                       ┌────────▼────────┐
                       │ AppleSMC (Kernel)│
                       └─────────────────┘
```

## 핵심 컴포넌트 상세

### AppDelegate (@MainActor)
- NSStatusItem: 메뉴바 아이콘 (배터리 레벨에 따라 동적 변경)
- 선택적 퍼센트 텍스트 표시 (statusItem.button.title)
- NSPopover: .transient behavior (외부 클릭 시 닫힘)
- 설정창 NSWindow 생성 및 관리
- BatteryViewModel 소유, PopoverView/SettingsView에 주입

### BatteryViewModel (@Observable, @MainActor)
- 중앙 상태 관리
  - BatteryState (현재 배터리 상태)
  - chargeLimit: 충전 상한 (기본 80%)
  - dischargeFloor: 방전 하한 (기본 20%)
  - rechargeMode: .smart / .manual
  - rechargeThreshold: 재충전 시작 값 (스마트: chargeLimit - 5%, 수동: 사용자 지정)
  - isManaging: 관리 ON/OFF
  - showPercentage: 메뉴바 % 표시
  - notifyOnComplete: 충전 완료 알림
- UserDefaults 영속화 (didSet)
- BatteryMonitor 폴링 (30초)
- 충전 정책 평가 (evaluateChargingPolicy)

### ChargePolicy (충전 정책 모델)
```
충전 정책 평가 흐름:

isManaging == true?
  ├─ NO → 아무 동작 안 함
  └─ YES
      ├─ 캘리브레이션 모드? → CalibrationManager에 위임
      └─ 일반 모드
          ├─ charge >= chargeLimit && isCharging
          │   → disableCharging (CH0B/CH0C)
          │   → 알림 전송 (notifyOnComplete 시)
          ├─ charge < rechargeThreshold && isPluggedIn && !isCharging
          │   → enableCharging
          └─ charge <= dischargeFloor && forceDischarging
              → 강제 방전 해제
```

재충전 모드:
- **스마트**: rechargeThreshold = chargeLimit - 히스테리시스(5%)
- **수동**: rechargeThreshold = 사용자 지정 값 (dischargeFloor ~ chargeLimit 범위)

### BatteryMonitor (IOKit)
- IOPSCopyPowerSourcesInfo() / IOPSCopyPowerSourcesList()
- 읽기 항목:
  - currentCharge, maxCapacity, isCharging, isPluggedIn
  - cycleCount, temperature, designCapacity
  - voltage, adapterWatts
  - timeRemaining (충전/방전)
- root 권한 불필요

### ChargeHistoryStore (SQLite)
- 30초마다 충전 레벨 기록
- 스키마: `(timestamp INTEGER, charge INTEGER, isCharging INTEGER, isPluggedIn INTEGER)`
- 7일 초과 데이터 자동 정리
- SwiftUI Charts 데이터 제공 (24h / 7d 쿼리)

### NotificationManager
- UNUserNotificationCenter 래핑
- 충전 완료 알림 (목표치 도달 시)
- 캘리브레이션 단계 완료 알림

### CalibrationManager
- 3단계: 100% 충전 → 완전 방전 → 재충전
- 현재 단계/진행률 추적
- 일반 관리 일시 중지
- 각 단계 자동 전환

### SMCClient (현재 스텁)
- Sendable final class (싱글턴)
- enableCharging / disableCharging / setForceDischarge
- Phase 3에서 NSXPCConnection으로 교체

### SMC 충전 제어 (Phase 3 구현 예정)
- Apple Silicon: BCLM 키 없음, 능동적 제어 필요
- CH0B: 충전 억제 키 (0x02=비활성, 0x00=활성)
- CH0C: Apple Silicon 추가 충전 제어
- CH0I: 어댑터 비활성 (0x01=배터리 강제 사용)
- Sleep/Wake 후 상태 리셋 가능 → 데몬이 재적용 필요

## 데이터 흐름

1. BatteryMonitor → IOKit API로 배터리 상태 읽기
2. BatteryViewModel → 상태 비교 후 정책 평가
3. ChargeHistoryStore → 이력 기록
4. SMCClient → XPC로 헬퍼에 명령 전송
5. NotificationManager → 조건 충족 시 알림
6. SwiftUI → @Observable 바인딩으로 UI 자동 갱신

## BatteryState 확장 필드

```swift
struct BatteryState {
    // 기본
    var currentCharge: Int          // 0-100%
    var isCharging: Bool
    var isPluggedIn: Bool
    var maxCapacity: Int            // mAh
    var designCapacity: Int         // mAh

    // 상세
    var cycleCount: Int
    var temperature: Double         // °C
    var voltage: Double             // V
    var adapterWatts: Int           // W
    var timeRemaining: Int          // 분 (-1 = 계산 중)

    // 건강도
    var healthPercentage: Int       // maxCapacity / designCapacity * 100

    // 정책
    var chargeLimit: Int
    var dischargeFloor: Int
    var rechargeThreshold: Int
    var isManaging: Bool
}
```

## 기술 결정 기록

| 결정 | 선택 | 이유 |
|------|------|------|
| 헬퍼 등록 | SMAppService | macOS 13+ 권장, SMJobBless 대비 간단 |
| 상태 관리 | @Observable | macOS 14+, ObservableObject 대비 성능/간결 |
| 폴링 | Timer 30초 | IOKit 알림보다 안정적, 전원 변경 알림으로 보조 |
| 권한 분리 | launchd daemon | XPC Service는 부모 앱 권한 상속, root 불가 |
| 재충전 모드 | 스마트(자동)/수동 | 사용자 유연성 + 기본값 안전성 |
| Deployment Target | macOS 14.0 | @Observable, SwiftUI Charts |
| Concurrency | @MainActor | Swift 6 strict concurrency 호환 |
| 이력 저장 | SQLite | 경량, 쿼리 유연, 앱 내장 |
| 그래프 | SwiftUI Charts | macOS 14+ 기본 제공, 외부 의존 없음 |
| 알림 | UNUserNotificationCenter | macOS 표준, 권한 관리 내장 |
| 설정창 | NSWindow + SwiftUI | 팝오버와 독립적 라이프사이클 |

---

*최종 업데이트: 2026-03-27*
