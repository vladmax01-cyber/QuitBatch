#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
test_dir="$(mktemp -d /private/tmp/QuitBatchDriveTest.XXXXXX)"
volume_name="QuitBatchTest${RANDOM}"
image="$test_dir/test.dmg"
blocker_pid=""
mount_path=""
cleanup() {
  if [[ -n "$blocker_pid" ]]; then kill "$blocker_pid" 2>/dev/null || true; fi
  if [[ -n "$mount_path" && -d "$mount_path" ]]; then hdiutil detach "$mount_path" >/dev/null 2>&1 || true; fi
  rm -rf "$test_dir"
}
trap cleanup EXIT

xcrun swiftc -target arm64-apple-macosx14.0 -framework AppKit -framework Combine \
  "$project_dir/Sources/Models.swift" "$project_dir/Sources/Symbols.swift" \
  "$project_dir/Sources/Drives.swift" "$project_dir/Tests/DriveTestHarness.swift" \
  -o "$test_dir/DriveTestHarness"
hdiutil create -quiet -size 32m -fs HFS+ -volname "$volume_name" "$image"
diskutil image attach --nobrowse "$image" > "$test_dir/attach.txt"
mount_path="/Volumes/$volume_name"
test -d "$mount_path"
"$test_dir/DriveTestHarness" "$volume_name"
/bin/sh -c 'cd "$1" && exec /bin/sleep 30' sh "$mount_path" &
blocker_pid=$!
/bin/sleep 1
"$test_dir/DriveTestHarness" "$volume_name" --blockers
"$test_dir/DriveTestHarness" "$volume_name" --expect-busy
kill "$blocker_pid"
wait "$blocker_pid" 2>/dev/null || true
blocker_pid=""
"$test_dir/DriveTestHarness" "$volume_name" --eject
if mount | rg -F "$mount_path" >/dev/null; then
  echo "Test image is still mounted" >&2
  exit 1
fi
diskutil image attach --nobrowse "$image" > "$test_dir/attach-force.txt"
/bin/sh -c 'cd "$1" && exec /bin/sleep 30' sh "$mount_path" &
blocker_pid=$!
/bin/sleep 1
"$test_dir/DriveTestHarness" "$volume_name" --force-eject
kill "$blocker_pid" 2>/dev/null || true
wait "$blocker_pid" 2>/dev/null || true
blocker_pid=""
if mount | rg -F "$mount_path" >/dev/null; then
  echo "Force-ejected test image is still mounted" >&2
  exit 1
fi
apfs_name="QuitBatchAPFSTest${RANDOM}"
apfs_image="$test_dir/apfs.dmg"
mount_path="/Volumes/$apfs_name"
hdiutil create -quiet -size 128m -fs APFS -volname "$apfs_name" "$apfs_image"
diskutil image attach --nobrowse "$apfs_image" > "$test_dir/attach-apfs.txt"
test -d "$mount_path"
"$test_dir/DriveTestHarness" "$apfs_name"
"$test_dir/DriveTestHarness" "$apfs_name" --eject
if mount | rg -F "$mount_path" >/dev/null; then
  echo "APFS test image is still mounted" >&2
  exit 1
fi
echo "HFS+ and APFS image discovery, open-file detection, busy failure, retry, and force eject passed"
