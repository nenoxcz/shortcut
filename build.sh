#!/bin/bash
# 릴리스 빌드 후 build/StudyHelper.app 번들 생성 (LSUIElement 메뉴 막대 전용 앱)
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/StudyHelper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/StudyHelper" "$APP/Contents/MacOS/StudyHelper"
cp Support/Info.plist "$APP/Contents/Info.plist"

# 화면 기록 권한(TCC)은 서명에 묶이므로 서명 필수. 기본은 ad-hoc, 인증서가 있으면 CODESIGN_IDENTITY로 지정.
codesign --force --sign "${CODESIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
