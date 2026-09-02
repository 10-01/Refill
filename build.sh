#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h}"
build_dir="$repo_dir/build"
app_dir="$build_dir/Refill.app"
contents="$app_dir/Contents"
deployment_target="13.0"
build_mode="${1:-native}"
signing_identity="${REFILL_SIGNING_IDENTITY:--}"

if [[ "$(/usr/bin/uname -s)" != "Darwin" ]]; then
  echo "Refill can only be built on macOS." >&2
  exit 1
fi
if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
  echo "Install Apple's Command Line Tools with: xcode-select --install" >&2
  exit 1
fi
if [[ "$build_mode" != "native" && "$build_mode" != "--universal" ]]; then
  echo "Usage: ./build.sh [--universal]" >&2
  exit 2
fi

if [[ -d "$app_dir" ]]; then
  /bin/rm -rf "$app_dir"
fi
/bin/mkdir -p "$contents/MacOS" "$contents/Resources/Fonts" "$contents/Resources/ProviderLogos"

compile_binary() {
  local architecture="$1"
  local output="$2"
  /usr/bin/xcrun swiftc \
    -target "${architecture}-apple-macosx${deployment_target}" \
    -swift-version 5 \
    -O \
    -framework AppKit \
    -framework SwiftUI \
    -framework ServiceManagement \
    -framework CoreText \
    "$repo_dir"/Sources/*.swift \
    -o "$output"
}

if [[ "$build_mode" == "--universal" ]]; then
  universal_dir="$build_dir/universal"
  /bin/mkdir -p "$universal_dir"
  compile_binary arm64 "$universal_dir/Refill-arm64"
  compile_binary x86_64 "$universal_dir/Refill-x86_64"
  /usr/bin/lipo -create \
    "$universal_dir/Refill-arm64" \
    "$universal_dir/Refill-x86_64" \
    -output "$contents/MacOS/Refill"
else
  compile_binary "$(/usr/bin/uname -m)" "$contents/MacOS/Refill"
fi

/bin/cp "$repo_dir/Resources/Info.plist" "$contents/Info.plist"
/bin/cp "$repo_dir/Resources/Fonts/Geist.ttf" "$contents/Resources/Fonts/Geist.ttf"
/bin/cp "$repo_dir/Resources/Fonts/GeistMono.ttf" "$contents/Resources/Fonts/GeistMono.ttf"
/bin/cp "$repo_dir/Resources/Fonts/OFL.txt" "$contents/Resources/Fonts/OFL.txt"
/bin/cp "$repo_dir"/Resources/ProviderLogos/* "$contents/Resources/ProviderLogos/"

icon_work="$build_dir/AppIcon.iconset"
if [[ -d "$icon_work" ]]; then
  /bin/rm -rf "$icon_work"
fi
/bin/mkdir -p "$icon_work"
/usr/bin/xcrun swift "$repo_dir/Scripts/make-icon.swift" "$build_dir/AppIcon-1024.png"
for spec in "16 16" "16 32" "32 32" "32 64" "128 128" "128 256" "256 256" "256 512" "512 512" "512 1024"; do
  set -- ${(z)spec}
  point_size="$1"
  pixel_size="$2"
  if [[ "$point_size" == "$pixel_size" ]]; then
    filename="icon_${point_size}x${point_size}.png"
  else
    filename="icon_${point_size}x${point_size}@2x.png"
  fi
  /usr/bin/sips -z "$pixel_size" "$pixel_size" "$build_dir/AppIcon-1024.png" --out "$icon_work/$filename" >/dev/null
done
/usr/bin/iconutil -c icns "$icon_work" -o "$contents/Resources/AppIcon.icns"

sign_arguments=(--force --options runtime --entitlements "$repo_dir/Resources/Refill.entitlements" --sign "$signing_identity")
if [[ "$signing_identity" != "-" ]]; then
  sign_arguments+=(--timestamp)
fi
/usr/bin/codesign $sign_arguments "$app_dir" >/dev/null
echo "$app_dir"
