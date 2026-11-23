#!/bin/sh
# Builds and runs the gesture logic tests (no XCTest target: the tested files have no OS dependencies).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
core="$here/../TouchUpCore"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter -I "$core" \
    "$core/TUCGestureSettings.m" "$core/TUCNativeGesture.m" "$core/TUCGestureRecognizer.m" "$here/GestureTests.m" \
    -framework Foundation -framework CoreGraphics -o "$out/gesture-tests"

"$out/gesture-tests"

# The settings rules (Swift, no app or framework needed).
swiftc -O -o "$out/settings-tests" "$here/../Touch Up/GestureSettings.swift" "$here/Swift/main.swift" -module-name SettingsTests
"$out/settings-tests"
