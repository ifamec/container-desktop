#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BINARY="$ROOT_DIR/.build/container-desktop-core-tests"

mkdir -p "$ROOT_DIR/.build"
swiftc -swift-version 6 \
    "$ROOT_DIR/Sources/ContainerDesktop/Models.swift" \
    "$ROOT_DIR/Sources/ContainerDesktop/CLI.swift" \
    "$ROOT_DIR/Tests/ContainerDesktopTests/ContainerDesktopTests.swift" \
    -o "$TEST_BINARY"

"$TEST_BINARY"
