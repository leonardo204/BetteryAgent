# 구현 계획 — BatteryAgent 5단계 구현 로드맵

## 개요
- BatteryAgent: macOS 메뉴바 배터리 충전 제한 관리 앱
- 기술 스택: macOS 14+, Swift 6, SwiftUI, IOKit, SMC
- 원격 저장소: https://github.com/leonardo204/BetteryAgent

---

## UI 구조

### 팝오버 (메뉴바 클릭) — 간결한 핵심 제어
- 현재 배터리 상태 (%, 충전/방전, 예상 남은 시간)
- 충전 제한 슬라이더
- 관리 ON/OFF 토글
- 어댑터 와트(W) 표시

### 설정창 (별도 윈도우) — 상세 설정 + 정보
- **충전 제어**
  - 방전 값 (최소 허용 %)
  - 재충전 값 (스마트 모드: 자동 계산 / 수동 모드: 직접 지정)
  - 충전 제한 값 (스테퍼)
- **표시 옵션**
  - 메뉴바 퍼센트 표시 토글
- **배터리 정보**
  - 건강도 (설계용량 vs 현재최대용량 비율)
  - 사이클 수
  - 온도
  - 설계 용량 / 현재 최대 용량
  - 전압
  - 어댑터 전력 (W)
  - 충전 완충/방전 예상 시간
- **충전 이력**
  - 최근 24h / 7d 충전 레벨 추이 그래프
- **유틸리티**
  - 캘리브레이션 모드 (100% 충전 → 완전 방전 → 재충전 가이드)
- **알림**
  - 충전 완료 알림 (목표치 도달 시 macOS 알림)
- **일반**
  - 로그인 시 자동 실행
  - 앱 버전
  - 종료 버튼

---

## Phase 1: 프로젝트 스캐폴딩 + 메뉴바 셸 ✅ 완료
- Xcode 프로젝트 (xcodegen)
- LSUIElement=true (Dock 아이콘 없음)
- NSStatusItem + NSPopover 구조
- AppDelegate에서 메뉴바 아이콘 + 팝오버 토글

## Phase 2: 배터리 모니터링 + UI ✅ 완료 (리팩토링 예정)
- IOKit Power Sources API로 배터리 상태 읽기 (BatteryMonitor)
- BatteryViewModel (@Observable, @MainActor) - 30초 폴링
- PopoverView - 제한%, 방전/충전 버튼, 슬라이더, 상태 표시
- BatterySliderView - 충전량 시각화 + 드래그로 제한 설정
- SettingsView - 충전 제한 조정, 관리 토글, 종료
- MenuBarIconProvider - 배터리 레벨에 따른 동적 아이콘

### Phase 2.5: UI 리팩토링 (다음)
Goal: 팝오버 간소화 + 별도 설정창 분리
- **팝오버 간소화**
  - 현재 상태 (%, 충전/방전, 어댑터 W)
  - 충전 제한 슬라이더
  - 관리 ON/OFF 토글
  - 예상 남은 시간
  - 설정창 열기 버튼
- **설정창 (NSWindow)**
  - 탭 또는 섹션 구분: 충전 제어 / 배터리 정보 / 이력 / 일반
  - 방전 값, 재충전 값 (스마트/수동)
  - 배터리 상세 정보 (건강도, 사이클, 온도, 용량, 전압)
  - 메뉴바 퍼센트 표시 토글
  - 충전 완료 알림 토글
  - 로그인 시 자동 실행
  - 앱 버전 + 종료
- **메뉴바 퍼센트 표시**
  - statusItem.button.title에 "80%" 표시 (옵션)
- **어댑터 전력(W) 표시**
  - IOKit에서 AdapterDetails/Watts 읽기

## Phase 3: 권한 헬퍼 + SMC 제어
Goal: SMC 키 쓰기로 실제 충전 제어
- BatteryAgentHelper (권한 데몬, root로 실행)
- SMCController: AppleSMC IOKit 드라이버를 통한 SMC 읽기/쓰기
  - IOServiceGetMatchingService("AppleSMC")
  - IOServiceOpen → IOConnectCallStructMethod
  - SMC 키: CH0B/CH0C (충전 억제), CH0I (어댑터 비활성)
- XPC 통신: NSXPCConnection으로 앱↔헬퍼 통신
- HelperDelegate: 코드 서명 검증
- SMAppService.daemon(plistName:) 으로 헬퍼 등록 (macOS 13+)
- SMCClient를 스텁에서 실제 XPC 클라이언트로 교체
- 헬퍼는 앱 번들 내 Contents/Library/LaunchDaemons/에 내장

## Phase 4: 충전 제한 로직 + 자동 관리
Goal: 사용자 설정 %에 따른 자동 충전 제어
- **방전/재충전 제어**
  - 방전 하한 값 설정 (예: 20%)
  - 재충전 시작 값 — 스마트 모드: chargeLimit - 히스테리시스(자동) / 수동 모드: 사용자 지정
- **충전 정책 엔진**
  - currentCharge >= chargeLimit && isCharging → disableCharging (CH0B/CH0C)
  - currentCharge < rechargeThreshold && isPluggedIn && !isCharging → enableCharging
  - currentCharge <= dischargeFloor → 강제 방전 해제
- Sleep/Wake 대응: NSWorkspace 알림으로 재적용
- 충전기 탈착 감지 및 정책 재평가
- 방전 모드: CH0I로 어댑터 연결 상태에서도 배터리 사용 강제
- **충전 완료 알림**: UNUserNotificationCenter로 목표치 도달 알림

## Phase 5: 이력, 캘리브레이션, 폴리시
Goal: 고급 기능 + 앱 완성도
- **충전 이력 그래프**
  - 30초마다 충전 레벨 기록 (SQLite 또는 파일)
  - SwiftUI Charts로 24h / 7d 추이 표시
  - 설정창 내 "이력" 탭
- **캘리브레이션 모드**
  - 3단계 가이드: 100% 충전 → 완전 방전 → 재충전
  - 각 단계 자동 전환 + 진행률 표시
  - 캘리브레이션 중 일반 관리 일시 중지
- **로그인 시 자동 실행** (SMAppService.mainApp)
- **에러 처리**: 헬퍼 미설치, XPC 연결 끊김, SMC 쓰기 실패
- **앱 아이콘**

---

## 핵심 기술 결정
1. SMAppService vs SMJobBless: SMAppService 채택 (macOS 13+ 권장 방식)
2. Timer 폴링 vs IOKit 알림: Timer 30초 + 전원 상태 변경 알림 보조
3. 데몬 vs XPC Service: root 권한 필요 → launchd 데몬
4. 히스테리시스: 스마트 모드(자동) / 수동 모드(사용자 지정)
5. macOS 버전 대응: macOS 14+에서 네이티브 충전 제한 API 충돌 감지
6. 이력 저장: SQLite (경량, 앱 내장)
7. 그래프: SwiftUI Charts (macOS 14+)
8. 알림: UNUserNotificationCenter
9. 설정창: NSWindow + SwiftUI (팝오버와 분리)

---

*최종 업데이트: 2026-03-27*
