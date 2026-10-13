#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
test_binary="${TMPDIR:-/private/tmp/}AppCloserPolicyTests"
xcrun swiftc -target arm64-apple-macosx14.0 -framework AppKit -framework ServiceManagement \
  "$project_dir/Sources/AccentTone.swift" "$project_dir/Sources/Models.swift" \
  "$project_dir/Sources/Symbols.swift" "$project_dir/Sources/AppModel.swift" \
  "$project_dir/Tests/PolicyTests.swift" -o "$test_binary"
"$test_binary"
