# 릴리스 가이드 — 버전 관리, 빌드, 배포, 유지보수

> 갱신: 2026-03-31

---

## 버전 관리

### 버전 체계

`MAJOR.MINOR.PATCH` (Semantic Versioning)

| 구분 | 올리는 경우 | 예시 |
|------|-----------|------|
| MAJOR | 아키텍처 변경, 호환성 깨짐 | 1.x → 2.0 |
| MINOR | 새 기능 추가 | 1.5 → 1.6 |
| PATCH | 버그 수정, UI 조정 | 1.5.2 → 1.5.3 |

### 버전 수정 위치 (2곳 — 자동 동기화)

| 파일 | 키 | 역할 |
|------|-----|------|
| `project.pbxproj` | `CFBundleShortVersionString` + `CFBundleVersion` | 빌드 시스템 (마스터) |
| `BatteryAgent/Resources/Info.plist` | 동일 키 | 런타임 표시 |

**`release.sh`가 자동 동기화**: pbxproj 값을 Info.plist에 복사하므로 pbxproj만 수정하면 됨.

### 헬퍼 버전

`BatteryAgentHelper/main.swift`의 `helperVersion` 상수도 함께 업데이트해야 함.
앱이 시작 시 헬퍼 버전과 `CFBundleShortVersionString`을 비교하여 불일치 시 자동 재설치.

### 버전 변경 예시 (1.5.3 → 1.6.0)

```swift
// project.pbxproj (2곳, replace_all)
CFBundleShortVersionString=1.6.0\nCFBundleVersion=11

// BatteryAgentHelper/main.swift
let helperVersion = "1.6.0"
```

---

## 릴리스 프로세스

### 자동화 스크립트

```bash
./scripts/release.sh              # 전체: 빌드 → 서명 → 공증 → DMG → GitHub Release
./scripts/release.sh --dry-run    # 검증만
./scripts/release.sh --skip-notarize  # 공증 건너뜀
./scripts/release.sh --skip-upload    # GitHub 업로드 건너뜀
```

### 릴리스 순서

```
1. 코드 변경 + 버전 업데이트
2. git commit + push
3. ./scripts/release.sh          → 빌드+공증+DMG+GitHub Release
4. sign_update로 DMG 서명         → EdDSA 서명값 획득
5. appcast.xml에 새 항목 추가     → 서명값 + length + 버전
6. git commit + push (appcast)   → 기존 사용자 자동 업데이트 활성화
```

### Sparkle 자동 업데이트 (appcast.xml)

EdDSA 서명 도구 경로:
```bash
SPARKLE_BIN="$(find ~/Library/Developer/Xcode/DerivedData/BatteryAgent-*/SourcePackages/artifacts/sparkle -name sign_update -path '*/bin/*' | head -1 | xargs dirname)"
```

DMG 서명:
```bash
"$SPARKLE_BIN/sign_update" build/BatteryAgent-v{VERSION}.dmg
```

출력: `sparkle:edSignature="..." length="..."`

appcast.xml 항목 구조:
```xml
<item>
  <title>BatteryAgent {VERSION}</title>
  <link>https://github.com/leonardo204/BetteryAgent/releases/tag/v{VERSION}</link>
  <sparkle:version>{BUILD_NUMBER}</sparkle:version>
  <sparkle:shortVersionString>{VERSION}</sparkle:shortVersionString>
  <description><![CDATA[<h2>v{VERSION} — 제목</h2><ul><li>변경사항</li></ul>]]></description>
  <pubDate>{RFC 2822 날짜}</pubDate>
  <enclosure
    url="https://github.com/leonardo204/BetteryAgent/releases/download/v{VERSION}/BatteryAgent-v{VERSION}.dmg"
    sparkle:edSignature="{서명값}"
    length="{파일크기}"
    type="application/octet-stream"
  />
  <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
</item>
```

### EdDSA 키 관리

- 공개키: `Info.plist` → `SUPublicEDKey`
- 비밀키: macOS 키체인 (자동 저장, `generate_keys` 최초 1회 실행)
- **비밀키 분실 시 기존 사용자 업데이트 불가** — 키체인 백업 권장

---

## 서명 및 공증

### 인증서

| 인증서 | 용도 | 확인 명령 |
|--------|------|----------|
| Developer ID Application | 앱 코드 서명 | `security find-identity -v \| grep "Developer ID Application"` |
| Developer ID Installer | PKG 서명 (선택) | `security find-identity -v \| grep "Developer ID Installer"` |

### Notarization 프로필

```bash
# 등록 (최초 1회)
xcrun notarytool store-credentials "notarytool" \
  --apple-id "your@apple.id" \
  --password "xxxx-xxxx-xxxx-xxxx" \
  --team-id "XU8HS9JUTS"

# 확인
xcrun notarytool history --keychain-profile "notarytool"
```

### 코드 서명 검증

```bash
codesign --verify --deep --strict BatteryAgent.app
codesign -dvv BatteryAgent.app  # 서명 상세 정보
```

---

## 헬퍼 데몬 관리

### 설치 위치

| 파일 | 경로 |
|------|------|
| 바이너리 | `/usr/local/bin/BatteryAgentHelper` |
| LaunchDaemon plist | `/Library/LaunchDaemons/com.zerolive.BatteryAgentHelper.plist` |
| 소켓 | `/tmp/BatteryAgentHelper.sock` |
| 로그 | `/tmp/BatteryAgentHelper.log` |

### 데몬 관리 명령

```bash
# 상태 확인
sudo launchctl list com.zerolive.BatteryAgentHelper

# 재시작
sudo launchctl bootout system/com.zerolive.BatteryAgentHelper
sudo launchctl bootstrap system /Library/LaunchDaemons/com.zerolive.BatteryAgentHelper.plist

# 완전 제거
sudo launchctl bootout system/com.zerolive.BatteryAgentHelper
sudo rm /Library/LaunchDaemons/com.zerolive.BatteryAgentHelper.plist
sudo rm /usr/local/bin/BatteryAgentHelper
sudo rm -f /tmp/BatteryAgentHelper.sock
```

### 버전 불일치 시 동작

앱 시작 → `checkAndInstallDaemon()` → 소켓으로 `version` 명령 → 응답과 `CFBundleShortVersionString` 비교 → 불일치 시 `installDaemon()` 자동 호출 (암호 1회)

---

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| 앱에 이전 버전 표시 | Info.plist 하드코딩 | release.sh가 자동 동기화 — 수동 빌드 시 pbxproj+Info.plist 모두 확인 |
| 헬퍼 설치 배너 계속 표시 | 데몬 소켓 없음 | `sudo launchctl bootstrap system ...` 또는 앱에서 "설치" 클릭 |
| 암호 여러 번 요청 | sendCommand 내부 재설치 (v1.5.1에서 수정) | v1.5.2 이상으로 업데이트 |
| Sparkle 업데이트 → GitHub 열림 | Sparkle 미링크 (v1.5.3에서 수정) | Frameworks Build Phase에 Sparkle 확인 |
| 공증 실패 | Hardened Runtime 미활성 | project.pbxproj `ENABLE_HARDENED_RUNTIME = YES` 확인 |

---

## 현재 릴리스 이력

| 버전 | 날짜 | 주요 내용 |
|------|------|----------|
| v1.3.0 | 2026-03-28 | AC 모드 유지 + AI 연결 개선 |
| v1.4.0 | 2026-03-31 | PrivacyInfo + Notarization 배포 |
| v1.5.0 | 2026-03-31 | Phase 2: 온도 보호, 스마트 충전, Sparkle, 다국어 |
| v1.5.1 | 2026-03-31 | 반복 암호 요청 수정 |
| v1.5.2 | 2026-03-31 | launchctl bootstrap, 버전 비교 수정 |
| v1.5.3 | 2026-03-31 | Sparkle 링크 수정, 캘린더 권한 즉시 반영 |
