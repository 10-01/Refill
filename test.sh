#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h}"
test_binary="$repo_dir/build/refill-tests"
/bin/mkdir -p "$repo_dir/build"
xcrun swiftc \
  -target "$(/usr/bin/uname -m)-apple-macosx13.0" \
  -swift-version 5 \
  -framework AppKit \
  "$repo_dir/Sources/Models.swift" \
  "$repo_dir/Sources/UsageAPI.swift" \
  "$repo_dir/Sources/AccountStore.swift" \
  "$repo_dir/Tests/main.swift" \
  -o "$test_binary"
"$test_binary"
