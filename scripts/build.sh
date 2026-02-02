#!/usr/bin/env bash
set -e

cd "$(dirname "$0")/.."

# generate app icons from source asset
echo "Generating icons..."
python3 scripts/generate_icons.py

case "${1:-android}" in
  android)
    echo "Building Android release APK..."
    flutter build apk --release
    echo ""
    echo "APK: build/app/outputs/flutter-apk/app-release.apk"
    ;;
  ios)
    echo "Building iOS release..."
    flutter build ios --release
    echo ""
    echo "To archive: open ios/Runner.xcworkspace in Xcode"
    ;;
  *)
    echo "Usage: ./build.sh [android|ios]"
    exit 1
    ;;
esac
