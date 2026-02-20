#!/usr/bin/env bash
#
# build.sh — build opview for Android and iOS
#
# Usage:
#   ./scripts/build.sh                  # default: icons + check + android
#   ./scripts/build.sh android          # icons + check + android APK
#   ./scripts/build.sh ios              # icons + check + ios
#   ./scripts/build.sh icons            # regenerate app icons only
#   ./scripts/build.sh check            # analyze + test only
#   ./scripts/build.sh clean            # flutter clean + remove outputs
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="$ROOT/out"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${GREEN}==>${NC} ${BOLD}$*${NC}"; }
warn() { echo -e "${YELLOW}warn:${NC} $*"; }
die()  { echo -e "${RED}error:${NC} $*" >&2; exit 1; }

# ── prerequisites ──────────────────────────────────────────────────

preflight() {
  command -v flutter >/dev/null || die "flutter not found on PATH"
  command -v uv >/dev/null      || die "uv not found on PATH"

  if [[ "${1:-}" == "android" ]]; then
    [[ -n "${ANDROID_HOME:-}" ]] || die "ANDROID_HOME not set"
    [[ -d "${ANDROID_HOME}" ]]   || die "ANDROID_HOME dir not found: $ANDROID_HOME"
  fi
}

# ── subcommands ────────────────────────────────────────────────────

do_icons() {
  log "Generating app icons..."
  uv run --with Pillow python3 scripts/generate_icons.py
}

do_check() {
  log "Resolving dependencies..."
  flutter pub get

  log "Running flutter analyze..."
  flutter analyze --no-fatal-infos

  log "Running tests..."
  flutter test
}

do_android() {
  preflight android

  do_icons
  do_check

  log "Building Android release APK..."
  flutter build apk --release

  # collect artifacts
  local apk_dir="build/app/outputs/flutter-apk"
  mkdir -p "$OUT"

  # universal APK
  if [[ -f "$apk_dir/app-release.apk" ]]; then
    cp "$apk_dir/app-release.apk" "$OUT/opview-release.apk"
  fi

  # per-ABI APKs
  for abi in arm64-v8a armeabi-v7a; do
    local src="$apk_dir/app-${abi}-release.apk"
    [[ -f "$src" ]] && cp "$src" "$OUT/opview-${abi}-release.apk"
  done

  echo ""
  log "Build complete. Artifacts:"
  ls -lh "$OUT"/opview-*release.apk 2>/dev/null || warn "no APKs found"
}

do_ios() {
  preflight ios

  [[ "$(uname)" == "Darwin" ]] || die "iOS builds require macOS"
  command -v xcodebuild >/dev/null || die "Xcode not installed"

  do_icons
  do_check

  log "Building iOS release..."
  flutter build ios --release

  echo ""
  log "Build complete."
  echo "    To archive: open ios/Runner.xcworkspace in Xcode"
  echo "    Then: Product → Archive"
}

do_clean() {
  log "Cleaning..."
  flutter clean
  rm -rf "$OUT"
  log "Done."
}

# ── main ───────────────────────────────────────────────────────────

cmd="${1:-android}"

case "$cmd" in
  android) do_android ;;
  ios)     do_ios     ;;
  icons)   do_icons   ;;
  check)   do_check   ;;
  clean)   do_clean   ;;
  *)
    echo "Usage: ./scripts/build.sh [android|ios|icons|check|clean]"
    exit 1
    ;;
esac
