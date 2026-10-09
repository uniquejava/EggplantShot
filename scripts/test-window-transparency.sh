#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d /tmp/eggplantshot-transparency.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT
swiftc -O -module-cache-path "$check_dir/module-cache" \
    EggplantShot/Capture/WindowHitTester.swift \
    EggplantShot/Capture/WindowCornerTransparency.swift \
    EggplantShot/Capture/ScreenshotImageEncoder.swift \
    EggplantShot/Annotation/*.swift EggplantShot/History/*.swift \
    EggplantShot/L10n/AppLanguage.swift Tests/WindowCornerTransparencyTests.swift \
    -o "$check_dir/checks"
"$check_dir/checks"
