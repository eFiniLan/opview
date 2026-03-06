#!/usr/bin/env bash
#
# release.sh — tag, build, and create a GitHub release
#
# Usage:
#   ./scripts/release.sh              # bump patch (0.1.0 → 0.1.1)
#   ./scripts/release.sh minor        # bump minor (0.1.0 → 0.2.0)
#   ./scripts/release.sh major        # bump major (0.1.0 → 1.0.0)
#   ./scripts/release.sh 0.3.0        # set explicit version
#
# What it does:
#   1. Bumps version in pubspec.yaml
#   2. Runs checks (analyze + test)
#   3. Builds Android APK
#   4. Commits version bump, tags, and pushes
#   5. Creates GitHub release with APK attached
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${GREEN}==>${NC} ${BOLD}$*${NC}"; }
warn() { echo -e "${YELLOW}warn:${NC} $*"; }
die()  { echo -e "${RED}error:${NC} $*" >&2; exit 1; }

# ── preflight ───────────────────────────────────────────────────

command -v flutter >/dev/null || die "flutter not found on PATH"
command -v gh >/dev/null      || die "gh (GitHub CLI) not found on PATH"
command -v git >/dev/null     || die "git not found on PATH"

# ensure clean working tree
[[ -z "$(git status --porcelain)" ]] || die "working tree is dirty — commit or stash first"

# ensure we're on main
branch="$(git branch --show-current)"
[[ "$branch" == "main" ]] || die "releases must be from main (currently on $branch)"

# ── version bump ────────────────────────────────────────────────

current_version=$(grep '^version:' pubspec.yaml | sed 's/version: //')
IFS='.' read -r major minor patch <<< "$current_version"

arg="${1:-patch}"
case "$arg" in
  patch) patch=$((patch + 1)) ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  major) major=$((major + 1)); minor=0; patch=0 ;;
  [0-9]*.*)  # explicit version
    IFS='.' read -r major minor patch <<< "$arg"
    ;;
  *) die "usage: release.sh [patch|minor|major|X.Y.Z]" ;;
esac

new_version="${major}.${minor}.${patch}"
tag="v${new_version}"

# check tag doesn't already exist
git tag -l "$tag" | grep -q . && die "tag $tag already exists"

log "Version: $current_version → $new_version ($tag)"

# ── update pubspec.yaml ────────────────────────────────────────

sed -i "s/^version: .*/version: ${new_version}/" pubspec.yaml
log "Updated pubspec.yaml"

# ── check + build ──────────────────────────────────────────────

log "Running checks..."
flutter pub get
flutter analyze --no-fatal-infos
flutter test

log "Building Android APK..."
flutter build apk --release

OUT="$ROOT/out"
mkdir -p "$OUT"
apk_src="build/app/outputs/flutter-apk/app-release.apk"
apk_out="$OUT/opview-${new_version}.apk"
[[ -f "$apk_src" ]] || die "APK not found at $apk_src"
cp "$apk_src" "$apk_out"
log "APK: $apk_out ($(du -h "$apk_out" | cut -f1))"

# ── commit, tag, push ─────────────────────────────────────────

log "Committing and tagging..."
git add pubspec.yaml
git commit -m "release ${tag}"
git tag -a "$tag" -m "release ${tag}"
git push origin main --tags

# ── github release ─────────────────────────────────────────────

log "Creating GitHub release..."
changelog=$(git log --pretty=format:'- %s' "$(git describe --tags --abbrev=0 "$tag^" 2>/dev/null || git rev-list --max-parents=0 HEAD)".."$tag^" 2>/dev/null || echo "- Initial release")

gh release create "$tag" "$apk_out" \
  --title "$tag" \
  --notes "$(cat <<EOF
## What's Changed

${changelog}

## Download

- **opview-${new_version}.apk** — Universal Android APK
EOF
)"

echo ""
log "Released $tag"
gh release view "$tag" --json url -q '.url'
