#!/usr/bin/env bash
#
# release.sh — bump version, tag, and push (CI builds + publishes)
#
# Usage:
#   ./scripts/release.sh              # bump patch (0.1.0 → 0.1.1)
#   ./scripts/release.sh minor        # bump minor (0.1.0 → 0.2.0)
#   ./scripts/release.sh major        # bump major (0.1.0 → 1.0.0)
#   ./scripts/release.sh 0.3.0        # set explicit version
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

log() { echo -e "${GREEN}==>${NC} ${BOLD}$*${NC}"; }
die() { echo -e "${RED}error:${NC} $*" >&2; exit 1; }

# ── preflight ───────────────────────────────────────────────────

command -v git >/dev/null || die "git not found on PATH"

[[ -z "$(git status --porcelain)" ]] || die "working tree is dirty — commit or stash first"

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
  [0-9]*.*)
    IFS='.' read -r major minor patch <<< "$arg"
    ;;
  *) die "usage: release.sh [patch|minor|major|X.Y.Z]" ;;
esac

new_version="${major}.${minor}.${patch}"
tag="v${new_version}"

git tag -l "$tag" | grep -q . && die "tag $tag already exists"

log "Version: $current_version → $new_version ($tag)"
echo ""
read -rp "Continue? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ── commit + tag + push ────────────────────────────────────────

sed -i "s/^version: .*/version: ${new_version}/" pubspec.yaml

git add pubspec.yaml
git commit -m "release ${tag}"
git tag -a "$tag" -m "release ${tag}"
git push origin main --tags

log "Pushed $tag — CI will build and publish the release"
echo "    https://github.com/efinilan/opview/actions"
