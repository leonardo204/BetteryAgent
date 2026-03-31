# 배포 로드맵 — BatteryAgent 배포 전략 및 기능 확장 계획

> 작성: 2026-03-30 | 기준: macOS Tahoe 26.4

---

## 배경

- Apple 공식 충전 제어 API 없음 (2026-03 기준)
- 모든 macOS 충전 제어 앱(AlDente, BatFi, batt 등)이 SMC 직접 접근 사용
- App Store 샌드박스에서 SMC 쓰기 불가 → App Store 배포 불가
- macOS 26.4에서 네이티브 충전 제한 슬라이더(80-100%) 추가, 프로그래밍 API는 미공개

---

## Phase 1: Notarization 직접 배포 (단기)

> 목표: 현재 아키텍처를 유지하면서 정식 배포 가능한 상태로 만든다.

### Step 1.1 — PrivacyInfo.xcprivacy 추가
- [ ] Privacy Manifest 파일 생성 (IOKit, EventKit, SQLite, UserDefaults API 선언)
- [ ] Xcode 프로젝트에 리소스로 등록
- [ ] 빌드 후 번들 포함 확인

### Step 1.2 — Developer ID 서명 설정
- [ ] Apple Developer Portal에서 Developer ID Application 인증서 확인/발급
- [ ] Developer ID Installer 인증서 확인/발급
- [ ] Xcode에서 Signing 설정을 Release 빌드에 Developer ID 적용 확인
- ⚠️ project.pbxproj의 CODE_SIGN_*, DEVELOPMENT_TEAM은 수정하지 않음

### Step 1.3 — Notarization 자동화 스크립트
- [ ] `scripts/notarize.sh` 작성
  - `xcodebuild archive` → Release 빌드
  - `xcrun notarytool submit` → Apple 공증 제출
  - `xcrun stapler staple` → 공증 티켓 앱에 첨부
- [ ] App-specific password 또는 Keychain 프로필 설정
- [ ] CI/CD 연동 고려 (GitHub Actions)

### Step 1.4 — DMG 패키징
- [ ] DMG 레이아웃 설계 (앱 아이콘 + Applications 폴더 바로가기)
- [ ] `create-dmg` 또는 수동 스크립트로 DMG 생성 자동화
- [ ] DMG에 공증 티켓 첨부 (`xcrun stapler staple`)
- [ ] 다운로드 후 설치 플로우 테스트

### Step 1.5 — 배포 채널
- [ ] GitHub Releases에 DMG 업로드
- [ ] README.md에 다운로드 배지/링크 추가
- [ ] 릴리스 노트 템플릿 작성

### Step 1.6 — 기존 사용자 데몬 정리 안내
- [ ] 업데이트 시 기존 LaunchDaemon 자동 감지 + 정리 (uninstall-daemon)
- [ ] 첫 실행 시 헬퍼 미설치 경고 → 설치 가이드

---

## Phase 2: 차별화 기능 강화 (중기)

> 목표: macOS 네이티브 충전 제한(80-100%)이 제공하지 않는 기능으로 차별화한다.

### Step 2.1 — 80% 미만 충전 제한
- macOS 네이티브는 80% 이상만 설정 가능
- BatteryAgent는 20-100% 전체 범위 지원 (현재 구현 완료)
- 마케팅 포인트로 강조

### Step 2.2 — 온도 기반 충전 보호
- [ ] 설정 온도 초과 시 자동 충전 중단
- [ ] 온도 임계값 사용자 설정 (기본 35°C)
- [ ] BatteryMonitor에서 이미 온도 읽기 가능 → 정책에 조건 추가

### Step 2.3 — 스마트 충전 고도화
- 패턴 학습 + 캘린더 연동 (현재 구현 완료)
- [ ] 학습 정확도 향상 — 공휴일/휴가 패턴 예외 처리
- [ ] 스마트 충전 리포트 (주간/월간 충전 패턴 시각화)

### Step 2.4 — AI 분석 강화
- Claude Code 연동 (현재 구현 완료)
- [ ] 배터리 수명 예측 (사이클 수 + 건강도 트렌드)
- [ ] 충전 습관 개선 제안

### Step 2.5 — 자동 업데이트 (Sparkle)
- [ ] Sparkle 프레임워크 통합
- [ ] appcast.xml 호스팅 (GitHub Pages 또는 별도 서버)
- [ ] EdDSA 키 생성 + 서명
- [ ] 업데이트 알림 UI

### Step 2.6 — 다국어 지원
- [ ] 영어 로컬라이제이션 (1순위)
- [ ] 중국어 간체/번체 (2순위)
- [ ] Localizable.strings 구조 정리

---

## Phase 3: 장기 전략 (macOS API 공개 대비)

> 목표: Apple이 충전 제어 프로그래밍 API를 공개하면 App Store 진출을 준비한다.

### Step 3.1 — Apple API 모니터링
- [ ] WWDC 2026 (6월) 세션에서 배터리/충전 관련 새 API 확인
- [ ] macOS 27 베타에서 `IOPMLib.h` 변경사항 추적
- [ ] Apple Developer Forums "battery charging" 태그 모니터링

### Step 3.2 — 충전 제어 추상화 레이어 (사전 준비)
- [ ] `ChargeControllerProtocol` 정의
  - `enableCharging() async -> Bool`
  - `disableCharging() async -> Bool`
  - `isAvailable: Bool`
  - `controllerType: ControllerType { .smc, .iopmAssertion, .appleNative }`
- [ ] 현재 SMC 방식을 `SMCChargeController`로 래핑
- [ ] 향후 Apple API 구현체를 `NativeChargeController`로 추가 가능
- 이 단계는 Phase 1 이후 리팩토링 시 병행 가능

### Step 3.3 — App Store 전환 (API 공개 시)
- [ ] App Sandbox 활성화
- [ ] Entitlements 재구성
- [ ] BatteryAgentHelper 타겟 제거
- [ ] SMCClient → NativeChargeController 전환
- [ ] App Store Connect 등록 + 심사 제출

### Step 3.4 — 하이브리드 배포 (과도기)
- App Store 버전: Apple API 기반 (기능 제한적일 수 있음)
- 직접 배포 버전: SMC 기반 (풀 기능)
- 사용자가 선택할 수 있도록 두 채널 유지

---

## macOS 네이티브 vs BatteryAgent 비교

| 기능 | macOS 26.4 네이티브 | BatteryAgent |
|------|:---:|:---:|
| 충전 제한 범위 | 80-100% | **20-100%** |
| 히스테리시스 자동 관리 | X | **O** |
| 패턴 학습 스마트 충전 | 제한적 (Optimized) | **O (14일 EWMA)** |
| 캘린더 연동 사전 충전 | X | **O** |
| 수동 규칙 (요일/시간) | X | **O** |
| AI 분석 리포트 | X | **O (Claude)** |
| 온도 기반 보호 | X | 예정 |
| 충전 이력/통계 | X | **O (SQLite)** |
| 패턴 히트맵 시각화 | X | **O** |
| 강제 방전 | X | **O** |
| 배터리 캘리브레이션 | X | **O** |

---

## 리스크

| 리스크 | 영향 | 대응 |
|--------|------|------|
| macOS 업데이트로 SMC 키 변경 | 높음 | Tahoe/Legacy 자동 감지 이미 구현. 새 키 발견 시 빠른 패치 |
| macOS가 SMC 쓰기 완전 차단 | 높음 | Phase 3 전환 준비, Apple API 대기 |
| Apple이 충전 API 미공개 유지 | 중간 | 직접 배포 계속 유지 |
| Notarization 거부 | 낮음 | Hardened Runtime 준수, 비공개 API 직접 호출 없음 (헬퍼 경유) |

---

*Phase 1 완료 목표: v1.4.0 릴리스*
*Phase 2 완료 목표: v2.0.0 릴리스*
*Phase 3: Apple API 공개 시점에 따라 유동적*
