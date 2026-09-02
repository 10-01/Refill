#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h}"
source_app="$repo_dir/build/Refill.app"
install_root="$HOME/Applications"
target_app="$install_root/Refill.app"
leftbar_app="$install_root/Leftbar.app"
quota_app="$install_root/Quota.app"

if [[ "$(/usr/bin/uname -s)" != "Darwin" ]]; then
  echo "Refill requires macOS 13 or newer." >&2
  exit 1
fi
if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
  echo "Apple's Command Line Tools are required." >&2
  echo "Install them with: xcode-select --install" >&2
  exit 1
fi

macos_major="$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)"
if (( macos_major < 13 )); then
  echo "Refill requires macOS 13 or newer." >&2
  exit 1
fi

echo "Building Refill for this Mac..."
"$repo_dir/build.sh" >/dev/null
"$repo_dir/Scripts/verify-build.sh" >/dev/null

/bin/mkdir -p "$install_root"
/usr/bin/pkill -x Refill 2>/dev/null || true
/usr/bin/pkill -x Leftbar 2>/dev/null || true
/usr/bin/pkill -x Quota 2>/dev/null || true

if [[ -d "$target_app" ]]; then
  backup="$HOME/.Trash/Refill previous $(/bin/date +%Y%m%d-%H%M%S).app"
  /bin/mv "$target_app" "$backup"
  echo "Moved the previous app to Trash."
fi

if [[ -d "$leftbar_app" ]]; then
  leftbar_backup="$HOME/.Trash/Leftbar before Refill $(/bin/date +%Y%m%d-%H%M%S).app"
  /bin/mv "$leftbar_app" "$leftbar_backup"
  echo "Moved Leftbar.app to Trash after migrating to Refill."
fi

if [[ -d "$quota_app" ]]; then
  quota_backup="$HOME/.Trash/Quota before Refill $(/bin/date +%Y%m%d-%H%M%S).app"
  /bin/mv "$quota_app" "$quota_backup"
  echo "Moved the former Quota.app to Trash."
fi

/usr/bin/ditto "$source_app" "$target_app"
/usr/bin/open "$target_app"
echo "Installed and opened $target_app"
