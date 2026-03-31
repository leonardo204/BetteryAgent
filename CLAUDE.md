# Claude Code 개발 가이드

> 공통 규칙(Agent Delegation, 커밋 정책, Context DB 등)은 글로벌 설정(`~/.claude/CLAUDE.md`)을 따릅니다.
> 글로벌 미설치 시: `curl -fsSL https://raw.githubusercontent.com/leonardo204/dotclaude/main/install.sh | bash`

---

## Slim 정책

이 파일은 **100줄 이하**를 유지한다. 새 지침 추가 시:
1. 매 턴 참조 필요 → 이 파일에 1줄 추가
2. 상세/예시/테이블 → ref-docs/*.md에 작성 후 여기서 참조
3. ref-docs 헤더: `# 제목 — 한 줄 설명` (모델이 첫 줄만 보고 필요 여부 판단)

---

## PROJECT

> 아래 섹션을 프로젝트에 맞게 작성하세요.

### 개요

**BatteryAgent** — macOS 메뉴바 배터리 충전 제한 관리 앱

| 항목 | 값 |
|------|-----|
| 기술 스택 | macOS 14+, Swift, SwiftUI, IOKit, SMC |
| 빌드 방법 | Xcode → BatteryAgent scheme |
| 상태 | 개발 중 |
| 원격 저장소 | https://github.com/leonardo204/BetteryAgent |

### 핵심 기능
- 메뉴바 전용 앱 (Dock 아이콘 없음, LSUIElement)
- 사용자 설정 %까지만 충전, 이후 SMC로 충전 차단
- 충전 차단 후 방전→재충전 자동 관리
- 충전/방전 수동 제어 버튼

### 상세 문서

- [구현 계획](Ref-docs/claude/implementation-plan.md) — 5단계 구현 로드맵
- [아키텍처](Ref-docs/claude/architecture.md) — 시스템 설계, 컴포넌트, 기술 결정
- [Context DB](Ref-docs/claude/context-db.md) — SQLite 기반 세션/태스크/결정 저장소
- [Context Monitor](Ref-docs/claude/context-monitor.md) — HUD + compaction 감지/복구
- [Hooks](Ref-docs/claude/hooks.md) — 5개 자동 실행 Hook 상세
- [컨벤션](Ref-docs/claude/conventions.md) — 커밋, 주석, 로깅 규칙
- [셋업](Ref-docs/claude/setup.md) — 새 환경 초기 설정
- [Agent Delegation](Ref-docs/claude/agent-delegation.md) — 에이전트 위임/파이프라인 상세
- [배포 로드맵](Ref-docs/claude/distribution-roadmap.md) — Notarization 배포 + 차별화 + App Store 장기 전략
- [릴리스 가이드](Ref-docs/claude/release-guide.md) — 버전 관리, 빌드/서명/공증, Sparkle 업데이트, 헬퍼 데몬

> 프로젝트별 문서를 추가하세요.

### 핵심 규칙

- SMC 접근은 반드시 권한 헬퍼(root)를 통해서만 수행
- 충전 제어 키: CH0B, CH0C (충전 억제), CH0I (어댑터 비활성)
- 히스테리시스 5%: 제한치에서 충전 차단, 제한치-5%에서 재활성화
- **Xcode Signing & Capabilities, Team 설정은 절대 수정하지 않음** (project.pbxproj의 CODE_SIGN_*, DEVELOPMENT_TEAM 포함)

---

*최종 업데이트: 2026-03-31*
