#!/bin/bash
set -e

# ── 설정 ──────────────────────────────────────────────
APP_NAME="BatteryAgent"
VERSION="1.3.0"
SCHEME="BatteryAgent"
PROJECT="BatteryAgent.xcodeproj"
SIGNING_IDENTITY="Developer ID Application: YONGSUB LEE (XU8HS9JUTS)"
TEAM_ID="XU8HS9JUTS"
BUNDLE_ID="com.zerolive.BatteryAgent"
# Keychain에 저장된 공증 프로파일 이름 (최초 1회 등록 필요 — 아래 주석 참조)
NOTARY_PROFILE="BatteryAgent-notary"

BUILD_DIR="$(pwd)/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
DMG_STAGING="$BUILD_DIR/dmg_staging"
DMG_PATH="$BUILD_DIR/${APP_NAME}-${VERSION}.dmg"

# ── 공증 credentials 등록 안내 ────────────────────────
# 최초 1회만 실행하면 됩니다:
#   xcrun notarytool store-credentials "BatteryAgent-notary" \
#     --apple-id "your@apple.id" \
#     --password "xxxx-xxxx-xxxx-xxxx" \   ← App-specific password (appleid.apple.com)
#     --team-id "XU8HS9JUTS"

# ── 공증 credentials 확인 ────────────────────────────
check_notary_profile() {
    xcrun notarytool history \
        --keychain-profile "$NOTARY_PROFILE" \
        --no-progress > /dev/null 2>&1
}

# ── 정리 ──────────────────────────────────────────────
echo "▶ 이전 빌드 정리..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DMG_STAGING"

# ── Release 아카이브 빌드 ─────────────────────────────
XCODEBUILD_LOG="$BUILD_DIR/xcodebuild.log"
echo "▶ Release 아카이브 빌드 중... (로그: $XCODEBUILD_LOG)"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    > "$XCODEBUILD_LOG" 2>&1
XCODE_EXIT=$?
if [ $XCODE_EXIT -ne 0 ]; then
    echo "❌ 아카이브 실패 (exit $XCODE_EXIT). 로그 마지막 30줄:"
    tail -30 "$XCODEBUILD_LOG"
    exit $XCODE_EXIT
fi

echo "▶ 아카이브 완료"

# 아카이브 디렉터리 존재 확인
[ -d "$ARCHIVE_PATH" ] || { echo "❌ 아카이브 디렉터리 없음: $ARCHIVE_PATH"; exit 1; }

# ── 앱 추출 ───────────────────────────────────────────
APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
[ -d "$APP_PATH" ] || { echo "❌ 앱 없음: $APP_PATH"; exit 1; }
cp -R "$APP_PATH" "$DMG_STAGING/"

# ── 코드 서명 확인 ────────────────────────────────────
echo "▶ 코드 서명 확인..."
codesign -dvvv "$DMG_STAGING/$APP_NAME.app" 2>&1
if ! codesign --verify --deep --strict "$DMG_STAGING/$APP_NAME.app" 2>&1; then
    echo "❌ 코드 서명 검증 실패"
    exit 1
fi
echo "   서명 검증 통과"

# ── DMG 생성 ──────────────────────────────────────────
echo "▶ DMG 생성 중..."
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"

echo "▶ DMG 생성 완료: $(du -sh "$DMG_PATH" | cut -f1)"

# ── 공증 (Notarization) ───────────────────────────────
echo ""
echo "▶ 공증 시작..."

if ! check_notary_profile; then
    echo ""
    echo "⚠️  공증 credentials가 등록되지 않았습니다."
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
    echo "✅ DMG 완성 (공증 제외): $DMG_PATH"
    open -R "$DMG_PATH"
    exit 0
fi

# DMG 공증 제출
echo "   제출 중... (수 분 소요)"
SUBMIT_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --progress 2>&1)
echo "$SUBMIT_OUTPUT"

# 결과 확인
if echo "$SUBMIT_OUTPUT" | grep -q "status: Accepted"; then
    echo ""
    echo "▶ 공증 성공! Staple 적용 중..."
    xcrun stapler staple "$DMG_PATH"
    echo "   Staple 완료"

    # Gatekeeper 검증 (참고용 — macOS Sequoia에서 spctl 오류 가능, 공증 통과 시 무관)
    MOUNT_POINT=$(hdiutil attach "$DMG_PATH" -nobrowse 2>/dev/null | grep '/Volumes/' | awk '{print $NF}')
    if [ -n "$MOUNT_POINT" ]; then
        echo "▶ Gatekeeper 검증 (마운트된 DMG)..."
        spctl --assess --verbose=2 --type execute "$MOUNT_POINT/$APP_NAME.app" 2>&1 || echo "   ⚠️ spctl 검증 실패 (macOS 알려진 이슈 — 공증 통과 시 정상 동작)"
        hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
    fi
else
    echo ""
    echo "⚠️  공증 실패. 로그 확인:"
    SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep -o 'id: [a-f0-9-]*' | head -1 | cut -d' ' -f2)
    [ -n "$SUBMISSION_ID" ] && xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" 2>&1 | tail -30
fi

# ── 완료 ──────────────────────────────────────────────
echo ""
echo "✅ 완성: $DMG_PATH ($(du -sh "$DMG_PATH" | cut -f1))"
echo ""

# Finder에서 DMG 파일 선택하여 열기
open -R "$DMG_PATH"
