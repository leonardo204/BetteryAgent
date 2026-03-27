#!/bin/bash
# DMG 생성 + 공증 스크립트 (Xcode Post-Archive Action용)
# 사용법: bash make_dmg.sh <archive_path>
#   $1 = xcarchive 경로 (Xcode Post-Archive에서는 $ARCHIVE_PATH 사용)
set -e

APP_NAME="BatteryAgent"
VERSION="1.0.0"
SIGNING_IDENTITY="Developer ID Application: YONGSUB LEE (XU8HS9JUTS)"
NOTARY_PROFILE="BatteryAgent-notary"

ARCHIVE_PATH="${1:-}"
if [ -z "$ARCHIVE_PATH" ]; then
    echo "❌ 사용법: bash make_dmg.sh <path/to/BatteryAgent.xcarchive>"
    exit 1
fi

BUILD_DIR="$(dirname "$ARCHIVE_PATH")"
DMG_STAGING="$BUILD_DIR/dmg_staging"
DMG_PATH="$BUILD_DIR/${APP_NAME}-${VERSION}.dmg"

rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# ── 앱 추출 ───────────────────────────────────────────
APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
[ -d "$APP_PATH" ] || { echo "❌ 앱 없음: $APP_PATH"; exit 1; }
cp -R "$APP_PATH" "$DMG_STAGING/"

# ── 코드 서명 확인 ────────────────────────────────────
echo "▶ 코드 서명 확인..."
codesign --verify --deep --strict "$DMG_STAGING/$APP_NAME.app" 2>&1 | tail -1

# ── DMG 생성 ──────────────────────────────────────────
echo "▶ DMG 생성 중..."
rm -f "$DMG_PATH"
create-dmg \
    --volname "$APP_NAME" \
    --window-pos 200 120 \
    --window-size 560 340 \
    --icon-size 100 \
    --icon "$APP_NAME.app" 140 160 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 420 160 \
    --no-internet-enable \
    "$DMG_PATH" \
    "$DMG_STAGING"

echo "▶ DMG 생성 완료: $(du -sh "$DMG_PATH" | cut -f1)"

# ── 공증 ──────────────────────────────────────────────
echo "▶ 공증 시작... (수 분 소요)"
SUBMIT_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --progress 2>&1)
echo "$SUBMIT_OUTPUT"

if echo "$SUBMIT_OUTPUT" | grep -q "status: Accepted"; then
    echo "▶ 공증 성공! Staple 적용 중..."
    xcrun stapler staple "$DMG_PATH"
    echo "   Staple 완료"
    spctl --assess --verbose=2 --type execute "$DMG_STAGING/$APP_NAME.app" 2>&1 | tail -3 || true
else
    echo "⚠️  공증 실패"
    SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep -o 'id: [a-f0-9-]*' | head -1 | cut -d' ' -f2)
    [ -n "$SUBMISSION_ID" ] && xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" 2>&1 | tail -30
fi

echo ""
echo "✅ 완성: $DMG_PATH"
open -R "$DMG_PATH"
