#!/usr/bin/env bash
# Generate UI preview screenshots from golden tests
# Output: test/golden/goldens/*.png

set -euo pipefail
cd "$(dirname "$0")/.."

flutter test test/golden/screenshot_test.dart --update-goldens --tags golden

echo "Screenshots saved to test/golden/goldens/"
ls -1 test/golden/goldens/*.png 2>/dev/null | wc -l | xargs -I{} echo "{} images generated"
