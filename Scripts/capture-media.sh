#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
binary="$repo_dir/build/Refill.app/Contents/MacOS/Refill"

if [[ ! -x "$binary" ]]; then
  "$repo_dir/build.sh" >/dev/null
fi

/bin/mkdir -p "$repo_dir/Proof" "$repo_dir/Media"
"$binary" --screenshot-light "$repo_dir/Proof/refill-light.png"
"$binary" --screenshot-dark "$repo_dir/Proof/refill-dark.png"
"$binary" --screenshot-settings-light "$repo_dir/Proof/settings-light.png"
"$binary" --screenshot-settings-dark "$repo_dir/Proof/settings-dark.png"
"$binary" --screenshot-reauth-light "$repo_dir/Proof/reauth-light.png"
"$binary" --screenshot-reauth-dark "$repo_dir/Proof/reauth-dark.png"

/usr/bin/xcrun swift \
  -framework AppKit \
  -framework CoreText \
  "$repo_dir/Scripts/make-media.swift" \
  "$repo_dir"

echo "$repo_dir/Media"
