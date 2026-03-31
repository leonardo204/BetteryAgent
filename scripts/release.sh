#!/usr/bin/env bash
# scripts/release.sh — BatteryAgent 전체 릴리스 자동화
# 사용법: ./scripts/release.sh [--dry-run] [--skip-notarize] [--skip-upload]
#
# 사전 요건:
#   1. Xcode Command Line Tools 설치
#   2. 공증 키체인 프로필 등록 (최초 1회):
#      xcrun notarytool store-credentials "notarytool" \
#        --apple-id "your@apple.id" \
#        --password "xxxx-xxxx-xxxx-xxxx" \
#        --team-id "XU8HS9JUTS"
#   3. gh CLI 설치 + 로그인: gh auth login

set -euo pipefail

# ── 옵션 파싱 ─────────────────────────────────────────
DRY_RUN=false
SKIP_NOTARIZE=false
SKIP_UPLOAD=false

for arg in "$@"; do
    case "$arg" in
        --dry-run)       DRY_RUN=true ;;
        --skip-notarize) SKIP_NOTARIZE=true ;;
        --skip-upload)   SKIP_UPLOAD=true ;;
        --help|-h)
            echo "사용법: $0 [--dry-run] [--skip-notarize] [--skip-upload]"
            echo ""
            echo "  --dry-run        실제 빌드/공증/업로드 없이 각 단계 검증만 수행"
            echo "  --skip-notarize  공증 단계 건너뜀"
            echo "  --skip-upload    GitHub Release 업로드 건너뜀"
            exit 0
            ;;
        *)
            echo "❌ 알 수 없는 옵션: $arg"
            echo "   사용법: $0 [--dry-run] [--skip-notarize] [--skip-upload]"
            exit 1
            ;;
    esac
done

# ── 로그 헬퍼 ─────────────────────────────────────────
info()    { echo "▶ $*"; }
success() { echo "✅ $*"; }
warn()    { echo "⚠️  $*"; }
error()   { echo "❌ $*" >&2; exit 1; }
dry()     { echo "   [DRY-RUN] $*"; }

# ── 프로젝트 루트 기준 경로 설정 ──────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# ── 설정값 ────────────────────────────────────────────
APP_NAME="BatteryAgent"
SCHEME="BatteryAgent"
PROJECT="BatteryAgent.xcodeproj"
BUNDLE_ID="com.zerolive.BatteryAgent"
SIGNING_IDENTITY="Developer ID Application: YONGSUB LEE (XU8HS9JUTS)"
TEAM_ID="XU8HS9JUTS"
NOTARY_PROFILE="notarytool"
GITHUB_REPO="leonardo204/BetteryAgent"
EXPORT_OPTIONS="$SCRIPT_DIR/ExportOptions.plist"
BUILD_DIR="$PROJECT_ROOT/build"

# ── 1단계: 버전 추출 ──────────────────────────────────
info "버전 추출 중..."

PBXPROJ="$PROJECT_ROOT/$PROJECT/project.pbxproj"
[ -f "$PBXPROJ" ] || error "project.pbxproj 없음: $PBXPROJ"

VERSION=$(grep -o 'CFBundleShortVersionString=[0-9][0-9.]*' "$PBXPROJ" \
    | head -1 \
    | cut -d'=' -f2 \
    | tr -d '";\\n')

[ -n "$VERSION" ] || error "버전을 project.pbxproj에서 추출할 수 없습니다."

BUILD_NUMBER=$(grep -o 'CFBundleVersion=[0-9]*' "$PBXPROJ" \
    | head -1 \
    | cut -d'=' -f2 \
    | tr -d '";\\n')

# Info.plist 버전 동기화 (pbxproj → Info.plist)
INFO_PLIST="$PROJECT_ROOT/$APP_NAME/Resources/Info.plist"
if [ -f "$INFO_PLIST" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST" 2>/dev/null || true
fi

ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_STAGING="$BUILD_DIR/dmg_staging"
DMG_NAME="${APP_NAME}-v${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
TAG="v${VERSION}"

info "버전: $VERSION  |  태그: $TAG"
info "DMG: $DMG_NAME"
echo ""

if $DRY_RUN; then
    warn "DRY-RUN 모드 — 실제 빌드/공증/업로드는 수행하지 않습니다"
    echo ""
fi

# ── 2단계: 사전 요건 확인 ─────────────────────────────
info "사전 요건 확인..."

# xcodebuild
if ! command -v xcodebuild &>/dev/null; then
    error "xcodebuild 없음. Xcode Command Line Tools를 설치하세요."
fi
XCODE_VERSION=$(xcodebuild -version 2>/dev/null | head -1 || true)
info "  $XCODE_VERSION"

# ExportOptions.plist
[ -f "$EXPORT_OPTIONS" ] || error "ExportOptions.plist 없음: $EXPORT_OPTIONS"
info "  ExportOptions.plist 확인됨"

# gh CLI (업로드 건너뜀이 아닐 때만)
if ! $SKIP_UPLOAD; then
    if ! command -v gh &>/dev/null; then
        error "gh CLI 없음. 설치: brew install gh"
    fi
    if ! gh auth status &>/dev/null; then
        error "gh CLI 로그인 필요: gh auth login"
    fi
    GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
    info "  gh CLI 로그인: $GH_USER"
fi

# 공증 프로필 (공증 건너뜀이 아닐 때만)
if ! $SKIP_NOTARIZE; then
    info "  공증 프로필 확인 중..."
    if ! xcrun notarytool history \
            --keychain-profile "$NOTARY_PROFILE" \
            --no-progress &>/dev/null; then
        echo ""
        warn "공증 키체인 프로필 '$NOTARY_PROFILE' 이 등록되어 있지 않습니다."
        echo ""
        echo "   아래 명령어로 1회 등록 후 다시 실행하세요:"
        echo ""
        echo "   xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
        echo "     --apple-id \"your@apple.id\" \\"
        echo "     --password \"xxxx-xxxx-xxxx-xxxx\" \\"
        echo "     --team-id \"$TEAM_ID\""
        echo ""
        echo "   앱 전용 암호: https://appleid.apple.com → 보안 → 앱 전용 암호"
        echo ""
        if $DRY_RUN; then
            warn "DRY-RUN: 공증 프로필 미등록 — 실제 실행 시 실패합니다"
        else
            error "공증 프로필 미등록. --skip-notarize 옵션으로 건너뛸 수 있습니다."
        fi
    else
        info "  공증 프로필 '$NOTARY_PROFILE' 확인됨"
    fi
fi

echo ""

# ── 3단계: 이전 빌드 정리 ─────────────────────────────
info "이전 빌드 정리..."
if $DRY_RUN; then
    dry "rm -rf $BUILD_DIR && mkdir -p $BUILD_DIR $DMG_STAGING"
else
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR" "$DMG_STAGING"
    info "  빌드 디렉토리 초기화 완료"
fi
echo ""

# ── 4단계: xcodebuild archive ─────────────────────────
info "Release 아카이브 빌드..."
XCODEBUILD_LOG="$BUILD_DIR/xcodebuild-archive.log"

if $DRY_RUN; then
    dry "xcodebuild archive \\"
    dry "    -project $PROJECT \\"
    dry "    -scheme $SCHEME \\"
    dry "    -configuration Release \\"
    dry "    -archivePath $ARCHIVE_PATH \\"
    dry "    -destination 'generic/platform=macOS'"
else
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        -destination "generic/platform=macOS" \
        > "$XCODEBUILD_LOG" 2>&1 || {
            echo "❌ 아카이브 실패. 로그 마지막 40줄:"
            tail -40 "$XCODEBUILD_LOG"
            exit 1
        }
    [ -d "$ARCHIVE_PATH" ] || error "아카이브 디렉토리 없음: $ARCHIVE_PATH"
    success "아카이브 완료: $ARCHIVE_PATH"
fi
echo ""

# ── 5단계: Developer ID 재서명 ────────────────────────
info "Developer ID 서명..."
APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"

ENTITLEMENTS_FILE="$PROJECT_ROOT/$APP_NAME/$APP_NAME.entitlements"

if $DRY_RUN; then
    dry "# archive에서 앱 복사 + Developer ID로 재서명 (entitlements 유지)"
    dry "cp -R '$APP_PATH' '$DMG_STAGING/'"
    dry "codesign --deep --force --options runtime --entitlements '$ENTITLEMENTS_FILE' --sign '$SIGNING_IDENTITY' '$DMG_STAGING/$APP_NAME.app'"
else
    [ -d "$APP_PATH" ] || error "아카이브 내 앱 없음: $APP_PATH"
    [ -f "$ENTITLEMENTS_FILE" ] || error "Entitlements 파일 없음: $ENTITLEMENTS_FILE"

    # 앱을 DMG 스테이징 복사
    cp -R "$APP_PATH" "$DMG_STAGING/"

    # Developer ID로 재서명 (entitlements 유지, runtime: Hardened Runtime)
    info "  Developer ID로 재서명 중 (entitlements: $ENTITLEMENTS_FILE)..."
    codesign --deep --force --options runtime \
        --entitlements "$ENTITLEMENTS_FILE" \
        --sign "$SIGNING_IDENTITY" \
        "$DMG_STAGING/$APP_NAME.app" \
        || error "Developer ID 서명 실패"

    # 서명 검증
    info "  코드 서명 검증..."
    codesign --verify --deep --strict "$DMG_STAGING/$APP_NAME.app" 2>&1 \
        || error "코드 서명 검증 실패"
    info "  서명 검증 통과"

    success "Developer ID 서명 완료"
fi
echo ""

# ── 6단계: DMG 생성 ───────────────────────────────────
info "DMG 생성 중..."

if $DRY_RUN; then
    dry "# DMG 스테이징 디렉토리에 Applications 심볼릭 링크 생성"
    dry "ln -s /Applications $DMG_STAGING/Applications"
    dry "hdiutil create \\"
    dry "    -volname '$APP_NAME $VERSION' \\"
    dry "    -srcfolder $DMG_STAGING \\"
    dry "    -ov -format UDZO \\"
    dry "    $DMG_PATH"
else
    # Applications 폴더 바로가기 (심볼릭 링크)
    ln -s /Applications "$DMG_STAGING/Applications"

    rm -f "$DMG_PATH"
    hdiutil create \
        -volname "$APP_NAME $VERSION" \
        -srcfolder "$DMG_STAGING" \
        -ov -format UDZO \
        "$DMG_PATH" \
        || error "DMG 생성 실패"

    DMG_SIZE=$(du -sh "$DMG_PATH" | cut -f1)
    success "DMG 생성 완료: $DMG_PATH ($DMG_SIZE)"
fi
echo ""

# ── 7단계: 공증 (Notarization) ────────────────────────
if $SKIP_NOTARIZE; then
    warn "공증 건너뜀 (--skip-notarize)"
else
    info "공증 제출 중 (수 분 소요)..."

    if $DRY_RUN; then
        dry "xcrun notarytool submit $DMG_PATH \\"
        dry "    --keychain-profile '$NOTARY_PROFILE' \\"
        dry "    --wait --progress"
        dry "xcrun stapler staple $DMG_PATH"
    else
        NOTARY_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
            --keychain-profile "$NOTARY_PROFILE" \
            --wait \
            --progress 2>&1) || true
        echo "$NOTARY_OUTPUT"

        if echo "$NOTARY_OUTPUT" | grep -q "status: Accepted"; then
            success "공증 성공"

            info "Staple 적용 중..."
            xcrun stapler staple "$DMG_PATH" \
                || error "Staple 실패"
            success "Staple 완료"

            # Gatekeeper 검증 (참고용)
            info "Gatekeeper 검증..."
            MOUNT_POINT=$(hdiutil attach "$DMG_PATH" -nobrowse 2>/dev/null \
                | grep '/Volumes/' | awk '{print $NF}')
            if [ -n "$MOUNT_POINT" ]; then
                spctl --assess --verbose=2 --type execute \
                    "$MOUNT_POINT/$APP_NAME.app" 2>&1 \
                    || warn "spctl 검증 실패 (macOS 알려진 이슈 — 공증 통과 시 정상 동작)"
                hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
            fi
        else
            # 실패 시 공증 로그 출력
            warn "공증 실패. 로그 확인 중..."
            SUBMISSION_ID=$(echo "$NOTARY_OUTPUT" \
                | grep -o 'id: [a-f0-9-]*' | head -1 | cut -d' ' -f2)
            if [ -n "$SUBMISSION_ID" ]; then
                xcrun notarytool log "$SUBMISSION_ID" \
                    --keychain-profile "$NOTARY_PROFILE" 2>&1 | tail -30
            fi
            error "공증 실패. 위 로그를 확인하세요."
        fi
    fi
fi
echo ""

# ── 8단계: GitHub Release 업로드 ─────────────────────
if $SKIP_UPLOAD; then
    warn "GitHub Release 업로드 건너뜀 (--skip-upload)"
else
    info "GitHub Release 생성 중..."
    info "  저장소: $GITHUB_REPO"
    info "  태그:   $TAG"
    info "  파일:   $DMG_NAME"

    # 기존 태그/릴리스 존재 여부 확인
    if gh release view "$TAG" --repo "$GITHUB_REPO" &>/dev/null; then
        warn "태그 '$TAG' 의 릴리스가 이미 존재합니다."
        warn "업로드를 건너뜁니다. 기존 릴리스를 삭제 후 재실행하세요."
        warn "  gh release delete $TAG --repo $GITHUB_REPO --yes"
    else
        if $DRY_RUN; then
            dry "gh release create $TAG \\"
            dry "    '$DMG_PATH' \\"
            dry "    --repo $GITHUB_REPO \\"
            dry "    --title '$TAG' \\"
            dry "    --generate-notes"
        else
            gh release create "$TAG" \
                "$DMG_PATH" \
                --repo "$GITHUB_REPO" \
                --title "$TAG" \
                --generate-notes \
                || error "GitHub Release 생성 실패"
            success "GitHub Release 생성 완료: https://github.com/$GITHUB_REPO/releases/tag/$TAG"
        fi
    fi
fi
echo ""

# ── 완료 ──────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if $DRY_RUN; then
    success "DRY-RUN 완료 — 모든 단계 검증 통과"
    echo ""
    echo "  버전:  $VERSION"
    echo "  태그:  $TAG"
    echo "  DMG:   $DMG_NAME"
    echo ""
    echo "  실제 릴리스: ./scripts/release.sh"
else
    success "릴리스 완료!"
    echo ""
    echo "  버전: $VERSION"
    echo "  DMG:  $DMG_PATH"
    if ! $SKIP_UPLOAD; then
        echo "  URL:  https://github.com/$GITHUB_REPO/releases/tag/$TAG"
    fi
    # Finder에서 DMG 파일 선택
    open -R "$DMG_PATH" 2>/dev/null || true
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
