<p align="center">
  <img src="battery.png" width="128" alt="BatteryAgent Icon">
</p>

<h1 align="center">BatteryAgent</h1>

<p align="center">
  macOS 메뉴바 배터리 충전 제한 관리 앱
</p>

<p align="center">
  <a href="https://github.com/leonardo204/BetteryAgent/releases/latest">
    <img src="https://img.shields.io/github/v/release/leonardo204/BetteryAgent?label=Download&color=brightgreen" alt="Latest Release">
  </a>
  <img src="https://img.shields.io/badge/macOS-14.0%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6.0-orange" alt="Swift 6">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="MIT License">
</p>

---

## 주요 기능

- **충전 제한 관리** — 사용자 설정 %까지만 충전, 이후 SMC로 충전 차단 (AC 모드 유지)
- **스마트 충전** — 사용 패턴 학습(14일) 기반 예측 충전, 캘린더 연동, 수동 규칙
- **메뉴바 전용** — Dock 아이콘 없이 메뉴바에서 즉시 제어
- **배터리 건강 분석** — Claude Code 연동 AI 배터리 상태 분석 및 수명 예측
- **충전 이력** — SQLite 기반 충전/방전 기록 및 차트

## 스크린샷

| 메뉴바 팝오버 | 스마트 충전 설정 |
|:---:|:---:|
| 배터리 상태, 충전 제한 슬라이더, 활성화 토글 | 패턴 학습, 캘린더 연동, 수동 규칙 관리 |

## 설치

### DMG 다운로드 (권장)

1. [최신 릴리스](https://github.com/leonardo204/BetteryAgent/releases/latest)에서 `BatteryAgent-x.x.x.dmg`를 다운로드합니다.
2. DMG 파일을 열고 `BatteryAgent.app`을 **Applications** 폴더로 드래그합니다.
3. Launchpad 또는 Applications 폴더에서 BatteryAgent를 실행합니다.
4. 최초 실행 시 헬퍼 설치를 위해 **관리자 비밀번호**를 입력합니다 (충전 제어 권한 획득, 최초 1회).

> Apple 공증(Notarization)이 완료된 빌드이므로 Gatekeeper 경고 없이 실행됩니다.

### v1.5.2 이전 버전에서 업그레이드

v1.5.1 이하에서 업그레이드하는 경우, 기존 데몬이 잘못된 세션에 로드되어 있을 수 있습니다. 새 앱 설치 **전에** 터미널에서 다음 명령을 실행하여 기존 데몬을 정리해주세요:

```bash
launchctl bootout gui/$(id -u)/com.zerolive.BatteryAgentHelper 2>/dev/null
sudo launchctl bootout system/com.zerolive.BatteryAgentHelper 2>/dev/null
sudo rm -f /tmp/BatteryAgentHelper.sock
```

이후 새 버전 앱을 설치하면 헬퍼가 자동으로 재설치됩니다.

### 빌드

```bash
# Xcode에서 BatteryAgent scheme으로 빌드
open BatteryAgent.xcodeproj

# 또는 DMG 생성 (Developer ID 서명 + 공증 포함)
bash build_dmg.sh
```

## 요구 사항

- macOS 14.0 (Sonoma) 이상
- Apple Silicon 또는 Intel Mac
- 충전 제어를 위한 관리자 권한 (최초 1회)
- (선택) [Claude Code](https://claude.ai/claude-code) — AI 배터리 분석 및 캘린더 이벤트 분류

### Claude Code 연동

AI 분석 및 캘린더 이벤트 자동 분류를 사용하려면 Claude Code가 필요합니다.

```bash
npm install -g @anthropic-ai/claude-code
claude /login    # 키체인에 인증 저장 (환경변수 방식은 이 앱에서 인식 불가)
```

> **참고**: 환경변수(`ANTHROPIC_API_KEY` 등)로 인증하면 터미널에서만 동작합니다.
> `claude /login`으로 키체인에 저장해야 BatteryAgent에서도 연결됩니다.
> 연결 실패 시 설정 > AI 분석 정보에서 상세 원인과 해결 방법을 확인할 수 있습니다.

## 아키텍처

```
BatteryAgent/
├── App/                  # AppDelegate, 메뉴바 설정
├── Models/               # BatteryState, SmartChargingState, ChargeRule
├── ViewModels/           # BatteryViewModel (상태 관리 중심)
├── Views/
│   ├── PopoverView       # 메뉴바 팝오버
│   └── Settings/         # 설정 탭 (AI, 스마트충전, 일반충전, 이력 등)
├── Services/
│   ├── BatteryMonitor    # IOKit 배터리 상태 읽기
│   ├── SMCClient         # SMC 충전 제어 (소켓 통신)
│   ├── SmartChargeScheduler  # 3계층 충전 스케줄러
│   ├── UsagePatternTracker   # EWMA 패턴 학습
│   └── CalendarMonitor       # EventKit 캘린더 연동
├── Utilities/            # Constants, MenuBarIconProvider
└── Resources/            # Info.plist, Assets

BatteryAgentHelper/       # 권한 헬퍼 데몬 (root, SMC 직접 제어)
Shared/                   # XPC 프로토콜
```

## 스마트 충전

3계층 하이브리드 시스템으로 예측 충전:

| 계층 | 방식 | 우선순위 |
|------|------|----------|
| Layer 3 | 사용자 수동 규칙 | 최우선 |
| Layer 2 | EventKit 캘린더 연동 | 보조 |
| Layer 1 | EWMA 히스토그램 패턴 학습 | 자동 |

- 14일 학습 후 자동 활성화
- 패턴 감지 시 100% 충전 → 이후 정상 제한 복귀
- 7일 x 48슬롯(30분) 히트맵 시각화

### 캘린더 이벤트 분류

캘린더 연동 시 30초 폴링으로 향후 24시간 이벤트를 조회하고, 노트북이 필요한 이벤트만 충전 대상으로 분류합니다.

| 분류 방법 | 조건 | 설명 |
|-----------|------|------|
| 키워드 매칭 | 제목에 "회의", "meeting", "스크럼" 등 포함 | 즉시 판별, 오프라인 동작 |
| 시간 기반 | 1시간 이상 이벤트 | 키워드 없어도 충전 대상 |
| AI 분류 | Claude Code 설치 시 | 제목 기반 자동 분류, 결과 캐싱 |

- Claude Code 미설치 시 키워드 + 시간 기반 폴백으로 동작
- AI 분류 결과는 캐싱되어 동일 이벤트 재질의 방지
- 이벤트 제목만 전달 (내용/참석자 미수집)

## 기술 스택

| 항목 | 기술 |
|------|------|
| UI | SwiftUI |
| 배터리 읽기 | IOKit (IOPSCopyPowerSourcesInfo, AppleSmartBattery) |
| 충전 제어 | SMC (CH0B, CH0C 키 — 충전 차단만, 강제 방전 없이 AC 모드 유지) |
| 데이터 저장 | SQLite (충전 이력, 패턴 데이터) |
| 캘린더 | EventKit + Claude Code AI 분류 |
| 권한 관리 | Security.framework (AuthorizationExecuteWithPrivileges) |
| 데몬 통신 | Unix Domain Socket |

## 라이선스

MIT License

## 개발

개발 관련 상세 사항은 [CLAUDE.md](CLAUDE.md)를 참조하세요.
