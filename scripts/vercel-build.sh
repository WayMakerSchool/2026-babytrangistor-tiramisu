#!/usr/bin/env bash
# Vercel 빌드 스크립트: Flutter SDK를 받아 웹으로 빌드합니다.
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.5}"
FLUTTER_DIR="_flutter"

if [ ! -d "$FLUTTER_DIR" ]; then
  echo "▶ Flutter $FLUTTER_VERSION 설치 중..."
  git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi

export PATH="$PWD/$FLUTTER_DIR/bin:$PATH"

# Vercel 빌드 환경에서는 git 소유권 검사를 통과시켜야 합니다.
git config --global --add safe.directory "$PWD/$FLUTTER_DIR"

flutter --version
flutter config --no-analytics --no-cli-animations
flutter pub get

echo "▶ 웹 빌드 중..."
flutter build web --release

echo "✅ build/web 생성 완료"
