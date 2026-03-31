# 배포 로드맵 — BatteryAgent 배포 전략 및 기능 확장 계획

> 작성: 2026-03-30 | 갱신: 2026-03-31 | 기준: macOS Tahoe 26.4

---

## 배경

- Apple 공식 충전 제어 API 없음 (2026-03 기준)
- 모든 macOS 충전 제어 앱(AlDente, BatFi, batt 등)이 SMC 직접 접근 사용
- App Store 샌드박스에서 SMC 쓰기 불가 → App Store 배포 불가
- macOS 26.4에서 네이티브 충전 제한 슬라이더(80-100%) 추가, 프로그래밍 API는 미공개

---

## Phase 1: Notarization 직접 배포 (단기)

> 목표: 현재 아키텍처를 유지하면서 정식 배포 가능한 상태로 만든다.

### Step 1.1 — PrivacyInfo.xcprivacy 추가 ✅
- [x] Privacy Manifest 파일 생성 (UserDefaults `CA92.1`, FileTimestamp `C617.1`)
- [x] Xcode 프로젝트에 리소스로 등록
- [x] 빌드 후 번들 포함 확인

### Step 1.2 — Developer ID 서명 설정 ✅
- [x] Developer ID Application 인증서 확인 (`YONGSUB LEE (XU8HS9JUTS)`)
- [x] Developer ID Installer 인증서 발급 + 키체인 설치
- [x] Notarization 키체인 프로필 (`notarytool`) 확인
- ⚠️ project.pbxproj의 CODE_SIGN_*, DEVELOPMENT_TEAM은 수정하지 않음

### Step 1.3 — Notarization + DMG + Release 자동화 ✅
- [x] `scripts/release.sh` — 전체 릴리스 자동화 (archive → 서명 → DMG → 공증 → GitHub Release)
- [x] `scripts/ExportOptions.plist` — Developer ID automatic 서명 설정
- [x] 키체인 프로필 기반 인증 (비밀번호 하드코딩 없음)
- [x] `--dry-run`, `--skip-notarize`, `--skip-upload` 옵션
- [ ] CI/CD 연동 고려 (GitHub Actions) — 향후

### Step 1.4 — v1.4.0 릴리스 ✅
- [x] Apple Notarization 통과 (Accepted)
- [x] Staple 적용 완료
- [x] DMG 생성 (BatteryAgent-v1.4.0.dmg, 1.2MB)
- [x] GitHub Release 업로드: https://github.com/leonardo204/BetteryAgent/releases/tag/v1.4.0

### Step 1.5 — 배포 채널 보완 ✅
- [x] GitHub Releases에 DMG 업로드
- [x] README.md에 다운로드 배지/링크 추가 (동적 버전 배지, MIT 배지)
- [x] v1.4.0 릴리스 노트 상세 작성

### Step 1.6 — 데몬 자동 관리 + 설치 가이드 ✅
- [x] 헬퍼 버전 감지 (`version` 소켓 명령 추가) + 버전 불일치 시 자동 재설치
- [x] 설치 실패 시 "시스템 설정 > 개인정보 보호 및 보안" 안내 배너
- [x] PopoverView 헬퍼 설치 안내 문구 개선

---

## Phase 2: 차별화 기능 강화 (중기)

> 목표: macOS 네이티브 충전 제한(80-100%)이 제공하지 않는 기능으로 차별화한다.

### Step 2.1 — 80% 미만 충전 제한 ✅
- macOS 네이티브는 80% 이상만 설정 가능
- BatteryAgent는 20-100% 전체 범위 지원 (구현 완료)
- 마케팅 포인트로 강조

### Step 2.2 — 온도 기반 충전 보호 ✅
- [x] 설정 온도 초과 시 자동 충전 중단 (기본 35°C, 히스테리시스 2°C)
- [x] ChargeControlTab에 "열 보호" Section UI
- [x] PopoverView 빨간색 "온도 보호 중" 상태 표시
- [x] evaluateChargingPolicy() 최우선 온도 체크

### Step 2.3 — 스마트 충전 고도화 ✅
- [x] 공휴일/휴가 패턴 예외 — 종일 이벤트 있는 날 학습 패턴 무시
- [x] 주간 리포트 sheet — 학습 진행률, 감지 패턴, 충전 통계, 미니 히트맵

### Step 2.4 — AI 분석 강화 ✅
- [x] 프롬프트에 최근 7일 충전 이력 통계 추가
- [x] 배터리 수명 예측 (사이클 수 + 건강도 기반 잔여 사이클 추정)
- [x] 충전 습관 개선 제안 항목 추가

### Step 2.5 — 자동 업데이트 (Sparkle) ✅
- [x] UpdateChecker.swift — `#if canImport(Sparkle)` 조건부 컴파일
- [x] GeneralTab.swift — 업데이트 확인 UI + 현재 버전 표시
- [x] appcast.xml — v1.4.0 피드 생성
- [x] Info.plist에 SUFeedURL 추가
- [x] Sparkle SPM 추가 완료 (2.9.1)
- [ ] EdDSA 키 생성 (`generate_keys`) + DMG 서명 (`sign_update`) — 릴리스 시

### Step 2.6 — 다국어 지원 ✅
- [x] 영어 로컬라이제이션 (en.lproj/Localizable.strings)
- [x] 한국어 로컬라이제이션 (ko.lproj/Localizable.strings)
- [ ] 중국어 간체/번체 — 향후

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
| 공휴일/휴가 자동 예외 | X | **O** |
| 수동 규칙 (요일/시간) | X | **O** |
| AI 분석 리포트 | X | **O (Claude)** |
| 배터리 수명 예측 | X | **O** |
| 온도 기반 보호 | X | **O (35°C)** |
| 충전 이력/통계 | X | **O (SQLite)** |
| 주간 충전 리포트 | X | **O** |
| 패턴 히트맵 시각화 | X | **O** |
| 강제 방전 | X | **O** |
| 배터리 캘리브레이션 | X | **O** |
| 자동 업데이트 | O (시스템) | **O (Sparkle)** |
| 다국어 (한/영) | O | **O** |

---

## 리스크

| 리스크 | 영향 | 대응 |
|--------|------|------|
| macOS 업데이트로 SMC 키 변경 | 높음 | Tahoe/Legacy 자동 감지 이미 구현. 새 키 발견 시 빠른 패치 |
| macOS가 SMC 쓰기 완전 차단 | 높음 | Phase 3 전환 준비, Apple API 대기 |
| Apple이 충전 API 미공개 유지 | 중간 | 직접 배포 계속 유지 |
| Notarization 거부 | 낮음 | Hardened Runtime 준수, 비공개 API 직접 호출 없음 (헬퍼 경유) |

---

*Phase 1: 완료 (2026-03-31) — v1.4.0 릴리스, 전 Step 완료*
*Phase 2: 완료 (2026-03-31) — 중국어 로컬라이제이션, EdDSA 서명만 잔여*
*Phase 3: Apple API 공개 시점에 따라 유동적*
