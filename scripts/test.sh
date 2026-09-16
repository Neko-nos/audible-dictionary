#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

#######################################
# Run Swift Testing with the framework bundled with the selected Apple toolchain.
# Arguments:
#   None
# Outputs:
#   Compiler diagnostics and test results.
#######################################
function test_swift() {
    local developer_path
    local framework_path
    developer_path="$(xcode-select -p)"
    framework_path="$developer_path/Library/Developer/Frameworks"
    if [[ ! -d "$framework_path/Testing.framework" ]]; then
        framework_path="$developer_path/Platforms/MacOSX.platform/Developer/Library/Frameworks"
    fi
    # Command Line Tools ships Testing but SwiftPM may omit its framework path.
    swift test --disable-xctest -Xswiftc -F -Xswiftc "$framework_path" \
        -Xlinker -rpath -Xlinker "$framework_path" \
        -Xlinker -rpath -Xlinker "$framework_path/../usr/lib"
}

shellcheck scripts/*.sh
uv run pytest
test_swift
