#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
app_dir="$repo_dir/build/Refill.app"
binary="$app_dir/Contents/MacOS/Refill"

if [[ ! -x "$binary" ]]; then
  echo "Build is missing. Run ./build.sh first." >&2
  exit 1
fi

for provider in claude codex grok; do
  if [[ ! -f "$app_dir/Contents/Resources/ProviderLogos/$provider.svg" ]]; then
    echo "The $provider provider logo is missing from the app bundle." >&2
    exit 1
  fi
done

/usr/bin/plutil -lint "$app_dir/Contents/Info.plist" >/dev/null
/usr/bin/codesign --verify --strict --verbose=2 "$app_dir" >/dev/null

plist_minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app_dir/Contents/Info.plist")"
if [[ "$plist_minimum" != "13.0" ]]; then
  echo "Expected LSMinimumSystemVersion 13.0, found ${plist_minimum:-none}." >&2
  exit 1
fi

architectures="$(/usr/bin/lipo -archs "$binary")"
for architecture in ${(z)architectures}; do
  minimum_version="$(/usr/bin/otool -arch "$architecture" -l "$binary" | /usr/bin/awk '/LC_BUILD_VERSION/{found=1} found&&/minos/{print $2; exit}')"
  if [[ "$minimum_version" != "13.0" ]]; then
    echo "Expected macOS 13.0 for $architecture, found ${minimum_version:-none}." >&2
    exit 1
  fi
done

signature_details="$(/usr/bin/codesign -dvv "$app_dir" 2>&1)"
if [[ "$signature_details" != *"runtime"* ]]; then
  echo "The app signature is missing hardened runtime." >&2
  exit 1
fi

if [[ "${REFILL_EXPECT_UNIVERSAL:-0}" == "1" ]]; then
  if [[ "$architectures" != *"arm64"* || "$architectures" != *"x86_64"* ]]; then
    echo "Expected arm64 and x86_64, found: $architectures" >&2
    exit 1
  fi
fi

echo "Verified Refill.app: macOS 13.0+, $architectures, hardened runtime."
